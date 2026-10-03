import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/proxy_node.dart';
import '../models/subscription.dart';
import '../services/local_store.dart';
import '../services/qr_payload_parser.dart';
import '../services/subscription_fetcher.dart';
import '../services/vpn_engine_service.dart';
import '../services/geo_asset_service.dart';

class AppState extends ChangeNotifier {
  final LocalStore _store = LocalStore();
  final VpnEngineService _vpn = VpnEngineService();
  final GeoAssetService _geo = GeoAssetService();

  List<ProxyNode> nodes = [];
  List<ProxySubscription> subscriptions = [];
  final List<String> logs = [];
  String? selectedNodeId;
  bool connected = false;
  bool connecting = false;
  bool coreReady = false;
  String coreVersion = '';
  String appVersion = '1.2.6';
  String mode = '智能模式';
  String downloadSpeed = '0 B/s';
  String uploadSpeed = '0 B/s';
  Duration connectedDuration = Duration.zero;
  DateTime? geoUpdatedAt;
  bool updatingGeo = false;
  bool geoAssetsReady = false;
  bool autoConnect = false;

  StreamSubscription? _statusSub;
  StreamSubscription? _statsSub;
  StreamSubscription? _logsSub;
  StreamSubscription? _alertsSub;
  Timer? _timer;
  Timer? _latencyTimer;
  Timer? _connectionWatchdog;
  DateTime? _connectionOpStartedAt;
  final Set<String> testingNodeIds = {};
  final Set<String> failedLatencyNodeIds = {};
  bool testingAllNodes = false;

  String latencyLabel(ProxyNode? node) {
    if (node == null) return '未选择';
    if (testingNodeIds.contains(node.id)) return '测试中';
    if (failedLatencyNodeIds.contains(node.id)) return '超时/失败';
    return node.latencyMs == null ? '待测试' : '${node.latencyMs} ms';
  }

  Future<void> testAllNodeLatencies() async {
    if (testingAllNodes) return;
    testingAllNodes = true;
    notifyListeners();
    try {
      for (final node in List<ProxyNode>.of(nodes)) {
        await testLatency(node);
      }
    } finally {
      testingAllNodes = false;
      notifyListeners();
    }
  }

  DateTime? _connectedAt;

  ProxyNode? get selectedNode {
    if (nodes.isEmpty) return null;
    for (final n in nodes) {
      if (n.id == selectedNodeId) return n;
    }
    return nodes.first;
  }

  String get durationText {
    final h = connectedDuration.inHours.toString().padLeft(2, '0');
    final m = (connectedDuration.inMinutes % 60).toString().padLeft(2, '0');
    final s = (connectedDuration.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> initialize() async {
    nodes = await _store.loadNodes();
    subscriptions = await _store.loadSubscriptions();
    selectedNodeId = await _store.loadSelectedNodeId();
    geoUpdatedAt = await _store.loadGeoUpdatedAt();
    mode = await _store.loadMode();
    autoConnect = await _store.loadAutoConnect();
    if (selectedNodeId == null || !nodes.any((n) => n.id == selectedNodeId)) {
      selectedNodeId = nodes.isEmpty ? null : nodes.first.id;
    }
    try {
      await _geo.bootstrap();
      geoAssetsReady = await _geo.hasSmartRuleAssets();
      await _vpn.initialize();
      final detectedVersion = await _vpn.appVersion();
      if (detectedVersion.isNotEmpty) appVersion = detectedVersion;

      // Core initialization is the readiness gate. Reading the optional
      // version/info payload must never disable the Connect button.
      coreReady = true;
      _wireStreams();
      try {
        final info = await _vpn
            .coreInfo()
            .timeout(const Duration(seconds: 4));
        coreVersion = info['version']?.toString() ?? '';
      } catch (e) {
        coreVersion = '';
        _log('核心信息读取失败（不影响连接）：$e');
      }
      _log('代理核心已初始化${coreVersion.isEmpty ? '' : ' · $coreVersion'}');
    } catch (e) {
      coreReady = false;
      _log('核心初始化失败：$e');
    }
    notifyListeners();
    if (autoConnect && coreReady && selectedNode != null) {
      unawaited(toggleConnection());
    }
  }

  ProxyNode? preProxyFor(ProxyNode node) {
    final id = node.preProxyNodeId.trim();
    if (id.isEmpty || id == node.id) return null;
    for (final candidate in nodes) {
      if (candidate.id != id) continue;
      if (candidate.preProxyNodeId == node.id) return null;
      return candidate;
    }
    return null;
  }

  void _wireStreams() {
    _statusSub?.cancel();
    _statsSub?.cancel();
    _logsSub?.cancel();
    _alertsSub?.cancel();

    _statusSub = _vpn.watchStatus().listen((status) {
      final name = status.name;

      // Do not let a stale native STARTING/STOPPING event lock the UI.
      // Local commands own the transient "connecting" flag; terminal native
      // states only clear it and synchronize the actual connection state.
      if (name == 'started') {
        final wasConnected = connected;
        connected = true;
        connecting = false;
        _clearConnectionWatchdog();
        if (!wasConnected) {
          _connectedAt = DateTime.now();
          _startTimer();
          _startLatencyTimer();
        }
      } else if (name == 'stopped') {
        connected = false;
        connecting = false;
        _clearConnectionWatchdog();
        _connectedAt = null;
        connectedDuration = Duration.zero;
        downloadSpeed = '0 B/s';
        uploadSpeed = '0 B/s';
        _timer?.cancel();
        _latencyTimer?.cancel();
      }
      notifyListeners();
    }, onError: (Object e) {
      connecting = false;
      _clearConnectionWatchdog();
      _logAndNotify('状态流错误：$e');
    });

    _statsSub = _vpn.watchStats().listen((stats) {
      uploadSpeed = stats.formattedUplink;
      downloadSpeed = stats.formattedDownlink;
      notifyListeners();
    });

    _logsSub = _vpn.watchLogs().listen((event) {
      final line = event['message'] ?? event['log'] ?? event.toString();
      final text = line.toString();
      _log(text);
      _applyConnectionStateFromLog(text);
      notifyListeners();
    });

    _alertsSub = _vpn.watchAlerts().listen((event) {
      _log('提示：${event['message'] ?? event.toString()}');
      notifyListeners();
    });
  }

  void _applyConnectionStateFromLog(String line) {
    final lower = line.toLowerCase();
    if (lower.contains('service connected')) {
      if (!connected) {
        connected = true;
        connecting = false;
        _connectedAt ??= DateTime.now();
        _startTimer();
        _startLatencyTimer();
      }
      return;
    }

    if (lower.contains('service stopped') ||
        lower.contains('stopping service with alert')) {
      connecting = false;
      _clearConnectionWatchdog();
      connected = false;
      _connectedAt = null;
      connectedDuration = Duration.zero;
      downloadSpeed = '0 B/s';
      uploadSpeed = '0 B/s';
      _timer?.cancel();
      _latencyTimer?.cancel();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_connectedAt != null) {
        connectedDuration = DateTime.now().difference(_connectedAt!);
        notifyListeners();
      }
    });
  }

  Future<void> selectNode(String id) async {
    if (connected) await _vpn.disconnect();
    selectedNodeId = id;
    await _store.saveSelectedNodeId(id);
    _log('选择节点：${selectedNode?.name ?? id}');
    notifyListeners();
    final node = selectedNode;
    if (node != null) {
      unawaited(testLatency(node, logResult: false));
    }
  }

  Future<void> addNode(ProxyNode node) async {
    final duplicate = nodes.any((n) => n.connectionLink == node.connectionLink);
    if (duplicate) {
      _log('节点已存在：${node.name}');
      notifyListeners();
      return;
    }
    nodes.insert(0, node);
    selectedNodeId ??= node.id;
    await _store.saveNodes(nodes);
    if (selectedNodeId != null)
      await _store.saveSelectedNodeId(selectedNodeId!);
    _log('新增节点：${node.name}');
    notifyListeners();
    unawaited(testLatency(node, logResult: false));
  }

  Future<void> updateNode(ProxyNode updated) async {
    final index = nodes.indexWhere((n) => n.id == updated.id);
    if (index < 0) return;
    if (updated.preProxyNodeId == updated.id) {
      updated.preProxyNodeId = '';
    }
    final proposedPre = nodes.where(
      (n) => n.id == updated.preProxyNodeId,
    );
    if (proposedPre.isNotEmpty &&
        proposedPre.first.preProxyNodeId == updated.id) {
      updated.preProxyNodeId = '';
      _log('已阻止前置代理循环：${updated.name}');
    }
    final wasSelected = selectedNodeId == updated.id;
    if (wasSelected && connected) {
      await _vpn.disconnect();
    }
    nodes[index] = updated;
    await _store.saveNodes(nodes);
    _log('更新节点：${updated.name}');
    notifyListeners();
    if (wasSelected) {
      unawaited(testLatency(updated, logResult: false));
    }
  }

  Future<void> duplicateNode(ProxyNode node) async {
    final copy = ProxyNode.fromJson(node.toJson())
      ..id = DateTime.now().microsecondsSinceEpoch.toString()
      ..name = '${node.name} 副本';
    nodes.insert(0, copy);
    await _store.saveNodes(nodes);
    _log('复制节点：${copy.name}');
    notifyListeners();
  }

  Future<void> deleteNode(String id) async {
    if (selectedNodeId == id && connected) await _vpn.disconnect();
    nodes.removeWhere((n) => n.id == id);
    for (final node in nodes) {
      if (node.preProxyNodeId == id) {
        node.preProxyNodeId = '';
      }
    }
    if (selectedNodeId == id)
      selectedNodeId = nodes.isEmpty ? null : nodes.first.id;
    await _store.saveNodes(nodes);
    if (selectedNodeId != null)
      await _store.saveSelectedNodeId(selectedNodeId!);
    notifyListeners();
  }

  Future<void> toggleFavorite(ProxyNode node) async {
    node.favorite = !node.favorite;
    await _store.saveNodes(nodes);
    notifyListeners();
  }

  Future<void> testLatency(ProxyNode node, {bool logResult = true}) async {
    if (!coreReady ||
        testingNodeIds.contains(node.id) ||
        testingNodeIds.length >= 2)
      return;
    testingNodeIds.add(node.id);
    failedLatencyNodeIds.remove(node.id);
    final originalLink = node.connectionLink;
    notifyListeners();
    try {
      final latency = await _vpn.ping(
        node,
        preProxy: preProxyFor(node),
        allowTunnelFallback: connected && selectedNodeId == node.id,
      );
      if (!nodes.contains(node) || originalLink != node.connectionLink) return;
      node.latencyMs = latency > 0 ? latency : null;
      if (latency <= 0) failedLatencyNodeIds.add(node.id);
      if (logResult) {
        _log(
          latency > 0 ? '延迟测试：${node.name} $latency ms' : '延迟测试失败：${node.name}',
        );
      }
    } catch (e) {
      node.latencyMs = null;
      failedLatencyNodeIds.add(node.id);
      if (logResult) _log('延迟测试失败：${node.name} · $e');
    } finally {
      testingNodeIds.remove(node.id);
      notifyListeners();
    }
    notifyListeners();
  }

  void _startLatencyTimer() {
    _latencyTimer?.cancel();
    final node = selectedNode;
    if (node != null) {
      unawaited(testLatency(node, logResult: false));
    }
    _latencyTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final current = selectedNode;
      if (connected && current != null) {
        unawaited(testLatency(current, logResult: false));
      }
    });
  }

  void _armConnectionWatchdog() {
    _connectionWatchdog?.cancel();
    _connectionOpStartedAt = DateTime.now();
    _connectionWatchdog = Timer(const Duration(seconds: 30), () {
      if (!connecting) return;
      connecting = false;
      _connectionOpStartedAt = null;
      _log('连接状态等待超时，已自动解除按钮锁定');
      notifyListeners();
    });
  }

  void _clearConnectionWatchdog() {
    _connectionWatchdog?.cancel();
    _connectionWatchdog = null;
    _connectionOpStartedAt = null;
  }

  Future<void> toggleConnection() async {
    if (connecting) {
      final startedAt = _connectionOpStartedAt;
      if (startedAt != null &&
          DateTime.now().difference(startedAt) < const Duration(seconds: 30)) {
        _logAndNotify(connected ? '正在断开，请稍候' : '正在连接，请稍候');
        return;
      }
      connecting = false;
      _clearConnectionWatchdog();
      _log('检测到残留连接状态，已解除按钮锁定');
    }
    final node = selectedNode;
    if (node == null) {
      _logAndNotify('请先添加并选择节点');
      return;
    }
    if (!coreReady) {
      _logAndNotify('代理核心未就绪，请检查平台核心文件是否已正确编译');
      return;
    }
    connecting = true;
    _armConnectionWatchdog();
    notifyListeners();
    try {
      if (connected) {
        await _vpn.disconnect();
        _log('正在断开代理');
      } else {
        final preProxy = preProxyFor(node);
        _log(
          preProxy == null
              ? '正在连接：${node.name} · ${node.protocol.label}'
              : '正在连接：前置 ${preProxy.name} → ${node.name}',
        );
        final granted = await _vpn.hasVpnPermission();
        if (!granted) {
          _log('等待系统 VPN 授权：请在系统弹窗中选择“允许”');
        }
        _log('VPN 授权窗口已结束，正在启动 VPN 服务');
        notifyListeners();
        final ok = await _vpn.connect(
          node,
          mode: mode,
          preProxy: preProxy,
        );
        if (!ok) {
          _log('VPN 服务启动请求超时或失败');
        } else {
          _log('VPN 启动命令已提交，等待核心连接');
        }
      }
    } catch (e) {
      _log('连接失败：$e');
    } finally {
      connecting = false;
      _clearConnectionWatchdog();
      notifyListeners();
    }
  }

  Future<void> addSubscription(ProxySubscription sub) async {
    subscriptions.add(sub);
    await _store.saveSubscriptions(subscriptions);
    notifyListeners();
    await updateSubscription(sub);
  }

  Future<void> updateSubscription(ProxySubscription sub) async {
    if (!coreReady) return;
    _log('更新订阅：${sub.name}');
    try {
      final links = <String>{};
      try {
        final result = await _vpn.parseSubscription(sub.url);
        _collectLinks(result, links);
      } catch (_) {}
      try {
        links.addAll(await SubscriptionFetcher.fetchLinks(sub.url));
      } catch (_) {}
      if (links.isEmpty) throw const FormatException('订阅中没有识别到受支持的节点链接');
      var added = 0;
      for (final link in links) {
        try {
          final node = QrPayloadParser.parse(link);
          if (!nodes.any((n) => n.connectionLink == node.connectionLink)) {
            nodes.add(node);
            added++;
          }
        } catch (_) {}
      }
      sub.nodeCount = links.length;
      sub.updatedAt = DateTime.now();
      await _store.saveNodes(nodes);
      await _store.saveSubscriptions(subscriptions);
      _log('订阅更新完成：识别 ${links.length} 个节点，新增 $added 个');
    } catch (e) {
      _log('订阅更新失败：$e');
    }
    notifyListeners();
  }

  void _collectLinks(Object? value, Set<String> out) {
    if (value is String) {
      final v = value.trim();
      if (QrPayloadParser.looksLikeNode(v)) out.add(v);
      for (final line in v.split(RegExp(r'[\r\n]+'))) {
        final t = line.trim();
        if (QrPayloadParser.looksLikeNode(t)) out.add(t);
      }
    } else if (value is Map) {
      for (final v in value.values) _collectLinks(v, out);
    } else if (value is Iterable) {
      for (final v in value) _collectLinks(v, out);
    }
  }

  Future<void> toggleSubscription(ProxySubscription sub) async {
    sub.enabled = !sub.enabled;
    await _store.saveSubscriptions(subscriptions);
    notifyListeners();
  }

  Future<void> setMode(String value) async {
    if (!const ['智能模式', '全局模式', '直连模式'].contains(value)) return;
    if (mode == value) return;
    mode = value;
    await _store.saveMode(value);
    _log('切换模式：$value');
    notifyListeners();

    if (coreReady && connected && selectedNode != null) {
      await _reconnectSelected('路由模式已生效：$value');
    }
  }

  Future<void> setAutoConnect(bool value) async {
    autoConnect = value;
    await _store.saveAutoConnect(value);
    _log(value ? '已开启自动连接' : '已关闭自动连接');
    notifyListeners();
  }

  Future<bool> _disconnectAndWait() async {
    await _vpn.disconnect();
    for (var i = 0; i < 40; i++) {
      if (!connected) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return !connected;
  }

  Future<void> _reconnectSelected(String successMessage) async {
    final node = selectedNode;
    if (node == null) return;
    if (connecting) return;
    connecting = true;
    notifyListeners();
    try {
      final stopped = await _disconnectAndWait();
      if (!stopped) {
        _log('重新连接失败：旧 VPN 服务未完全停止');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final ok = await _vpn.connect(
        node,
        mode: mode,
        preProxy: preProxyFor(node),
      );
      _log(ok ? successMessage : '重新连接失败：VPN 未启动');
    } catch (e) {
      _log('重新连接失败：$e');
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  Future<void> updateGeoAssets() async {
    if (updatingGeo) return;
    updatingGeo = true;
    _log('开始更新 GeoIP / GeoSite 地址库');
    notifyListeners();
    try {
      final updated = await _geo.updateAll();
      geoUpdatedAt = updated;
      geoAssetsReady = await _geo.hasSmartRuleAssets();
      await _store.saveGeoUpdatedAt(updated);
      _log('GeoIP / GeoSite 地址库更新完成');

      if (connected && mode == '智能模式' && selectedNode != null) {
        _log('正在重新加载智能分流规则');
        await _reconnectSelected('智能分流规则已重新加载');
      }
    } catch (e) {
      _log('GeoIP / GeoSite 更新失败：$e');
      rethrow;
    } finally {
      updatingGeo = false;
      notifyListeners();
    }
  }

  String get geoUpdatedText {
    final value = geoUpdatedAt;
    if (value == null) return '内置数据库';
    final y = value.year.toString();
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Future<void> runDiagnostics() async {
    _log('========== 路由自检开始 ==========');
    _log('架构：Android TUN → Xray 纯传输桥 → sing-box');
    _log('模式：$mode');
    _log('核心状态：${coreReady ? '已就绪' : '未就绪'}${coreVersion.isEmpty ? '' : ' · $coreVersion'}');
    _log('当前连接：${connected ? '已连接' : (connecting ? '连接中' : '未连接')}');

    final node = selectedNode;
    if (node == null) {
      _log('自检失败：未选择节点');
    } else {
      _log('节点：${node.name} · ${node.protocol.label} · ${node.server}:${node.port}');
      final pre = preProxyFor(node);
      if (pre != null) {
        _log('前置代理：${pre.name} → ${node.name}');
      }
    }

    try {
      final permission = await _vpn.hasVpnPermission();
      _log('VPN 权限：${permission ? '已授权' : '未授权'}');
    } catch (e) {
      _log('VPN 权限检查失败：$e');
    }

    try {
      geoAssetsReady = await _geo.hasSmartRuleAssets();
      _log('Smart Geo：${geoAssetsReady ? '完整' : '缺失/不完整'}');
    } catch (e) {
      _log('Smart Geo 检查失败：$e');
    }

    if (node != null && coreReady) {
      try {
        final latency = await _vpn.ping(
          node,
          preProxy: preProxyFor(node),
          allowTunnelFallback: connected && selectedNodeId == node.id,
        );
        _log(latency > 0 ? '节点核心握手：正常 · $latency ms' : '节点核心握手：失败/超时');
      } catch (e) {
        _log('节点核心握手失败：$e');
      }
    }

    if (mode == '智能模式') {
      _log('Smart DNS：中国 223.5.5.5:53 UDP 直连；国外 1.1.1.1 DoH 经代理');
      _log('Smart 路由：中国域名/CN IP → direct；其余 → proxy');
    } else if (mode == '全局模式') {
      _log('全局路由：业务流量与国外 DNS → proxy');
    } else {
      _log('直连路由：业务流量 → direct；DNS → 223.5.5.5');
    }

    _log('========== 路由自检结束 ==========');
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  void _logAndNotify(String value) {
    _log(value);
    notifyListeners();
  }

  void _log(String value) {
    final now = DateTime.now();
    final t =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    logs.insert(0, '$t  $value');
    if (logs.length > 500) logs.removeLast();
  }

  void addLog(String value) => _logAndNotify(value);

  @override
  void dispose() {
    _statusSub?.cancel();
    _statsSub?.cancel();
    _logsSub?.cancel();
    _alertsSub?.cancel();
    _timer?.cancel();
    _latencyTimer?.cancel();
    _connectionWatchdog?.cancel();
    super.dispose();
  }
}
