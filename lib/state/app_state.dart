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
  String appVersion = '1.1.0';
  String mode = '智能模式';
  String downloadSpeed = '0 B/s';
  String uploadSpeed = '0 B/s';
  Duration connectedDuration = Duration.zero;
  DateTime? geoUpdatedAt;
  bool updatingGeo = false;

  StreamSubscription? _statusSub;
  StreamSubscription? _statsSub;
  StreamSubscription? _logsSub;
  StreamSubscription? _alertsSub;
  Timer? _timer;
  Timer? _latencyTimer;
  bool _latencyBusy = false;
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
    if (selectedNodeId != null && !nodes.any((n) => n.id == selectedNodeId)) {
      selectedNodeId = nodes.isEmpty ? null : nodes.first.id;
    }
    try {
      await _geo.bootstrap();
      await _vpn.initialize();
      final detectedVersion = await _vpn.appVersion();
      if (detectedVersion.isNotEmpty) appVersion = detectedVersion;
      coreReady = true;
      final info = await _vpn.coreInfo();
      coreVersion = info['version']?.toString() ?? '';
      _wireStreams();
      _log('代理核心已初始化${coreVersion.isEmpty ? '' : ' · $coreVersion'}');
    } catch (e) {
      coreReady = false;
      _log('核心初始化失败：$e');
    }
    notifyListeners();
  }

  void _wireStreams() {
    _statusSub?.cancel();
    _statsSub?.cancel();
    _logsSub?.cancel();
    _alertsSub?.cancel();

    _statusSub = _vpn.watchStatus().listen((status) {
      final name = status.name;
      connecting = name == 'starting' || name == 'stopping';
      final nowConnected = name == 'started';
      final wasConnected = connected;
      connected = nowConnected;
      if (nowConnected && !wasConnected) {
        _connectedAt = DateTime.now();
        _startTimer();
        _startLatencyTimer();
      }
      if (!nowConnected && name == 'stopped') {
        _connectedAt = null;
        connectedDuration = Duration.zero;
        downloadSpeed = '0 B/s';
        uploadSpeed = '0 B/s';
        _timer?.cancel();
        _latencyTimer?.cancel();
      }
      notifyListeners();
    }, onError: (Object e) => _logAndNotify('状态流错误：$e'));

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
      if (connected) {
        connected = false;
        _connectedAt = null;
        connectedDuration = Duration.zero;
        downloadSpeed = '0 B/s';
        uploadSpeed = '0 B/s';
        _timer?.cancel();
        _latencyTimer?.cancel();
      }
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
    if (selectedNodeId != null) await _store.saveSelectedNodeId(selectedNodeId!);
    _log('新增节点：${node.name}');
    notifyListeners();
  }

  Future<void> updateNode(ProxyNode updated) async {
    final index = nodes.indexWhere((n) => n.id == updated.id);
    if (index < 0) return;
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
    if (selectedNodeId == id) selectedNodeId = nodes.isEmpty ? null : nodes.first.id;
    await _store.saveNodes(nodes);
    if (selectedNodeId != null) await _store.saveSelectedNodeId(selectedNodeId!);
    notifyListeners();
  }

  Future<void> toggleFavorite(ProxyNode node) async {
    node.favorite = !node.favorite;
    await _store.saveNodes(nodes);
    notifyListeners();
  }

  Future<void> testLatency(
    ProxyNode node, {
    bool logResult = true,
  }) async {
    if (!coreReady || _latencyBusy) return;
    _latencyBusy = true;
    try {
      final latency = await _vpn.ping(
        node,
        allowTunnelFallback: connected && selectedNodeId == node.id,
      );
      node.latencyMs = latency > 0 ? latency : null;
      await _store.saveNodes(nodes);
      if (logResult) {
        _log(latency > 0
            ? '延迟测试：${node.name} $latency ms'
            : '延迟测试失败：${node.name}');
      }
    } catch (e) {
      node.latencyMs = null;
      if (logResult) _log('延迟测试失败：${node.name} · $e');
    } finally {
      _latencyBusy = false;
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

  Future<void> toggleConnection() async {
    if (connecting) return;
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
    notifyListeners();
    try {
      if (connected) {
        await _vpn.disconnect();
        _log('正在断开代理');
      } else {
        _log('正在连接：${node.name} · ${node.protocol.label}');
        final granted = await _vpn.hasVpnPermission();
        if (!granted) {
          _log('等待系统 VPN 授权：请在系统弹窗中选择“允许”');
        }
        _log('VPN 授权窗口已结束，正在启动 VPN 服务');
        notifyListeners();
        final ok = await _vpn.connect(node, mode: mode);
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
    if (mode == value) return;
    mode = value;
    _log('切换模式：$value');
    notifyListeners();

    final node = selectedNode;
    if (!coreReady || !connected || node == null) return;

    try {
      connecting = true;
      notifyListeners();
      await _vpn.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final ok = await _vpn.connect(node, mode: mode);
      _log(ok
          ? '路由模式已生效：$value'
          : '路由模式切换失败：VPN 未重新启动');
    } catch (e) {
      _log('路由模式切换失败：$e');
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
      await _store.saveGeoUpdatedAt(updated);
      _log('GeoIP / GeoSite 地址库更新完成');

      final node = selectedNode;
      if (connected && mode == '智能模式' && node != null) {
        _log('正在重新加载智能分流规则');
        await _vpn.disconnect();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await _vpn.connect(node, mode: mode);
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
    final t = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
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
    super.dispose();
  }
}
