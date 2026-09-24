import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:v2ray_box/v2ray_box.dart';

import '../models/proxy_node.dart';
import 'singbox_config_builder.dart';
import 'geo_asset_service.dart';
import 'xray_config_router.dart';

class VpnEngineService {
  static const MethodChannel _vpnPermissionChannel =
      MethodChannel('aurum_proxy/vpn_permission');

  final V2rayBox box = V2rayBox();
  final GeoAssetService _geo = GeoAssetService();

  Future<void> initialize() async {
    await box.initialize(notificationStopButtonText: '断开');
    await box.setCoreEngine('xray');
    await box.setServiceMode(VpnMode.vpn);
  }

  Stream<dynamic> watchStatus() => box.watchStatus();
  Stream<dynamic> watchStats() => box.watchStats();
  Stream<Map<String, dynamic>> watchLogs() => box.watchLogs();
  Stream<Map<String, dynamic>> watchAlerts() => box.watchAlerts();

  Future<bool> connect(
    ProxyNode node, {
    String mode = '智能模式',
  }) async {
    if (!await ensureVpnPermission()) return false;

    final useSingBox = node.protocol == ProxyProtocol.snell ||
        node.protocol == ProxyProtocol.hysteria2;
    await box.setCoreEngine(useSingBox ? 'singbox' : 'xray');
    await box.setServiceMode(VpnMode.vpn);

    if (useSingBox) {
      final geoDir = await _geo.filesDir;
      final json = SingBoxConfigBuilder.fromNode(
        node,
        mode: mode,
        geoDir: geoDir,
      );
      return box
          .connectWithJson(json, name: node.name)
          .timeout(const Duration(seconds: 15), onTimeout: () => false);
    }

    final generated = await box.generateConfig(node.connectionLink);
    if (generated.trim().isEmpty) return false;
    final routed = XrayConfigRouter.apply(generated, mode);
    return box
        .connectWithJson(routed, name: node.name)
        .timeout(const Duration(seconds: 15), onTimeout: () => false);
  }

  Future<bool> disconnect() => box.disconnect();

  Future<bool> hasVpnPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _vpnPermissionChannel.invokeMethod<bool>('check') ?? false;
    } on PlatformException {
      return box.checkVpnPermission();
    }
  }

  Future<bool> ensureVpnPermission() async {
    if (!Platform.isAndroid) return true;
    if (await hasVpnPermission()) return true;

    try {
      // Wait for the system VPN dialog to close, but do not trust OEM result
      // codes as the final permission authority. The native v2ray_box start
      // path performs VpnService.prepare() again and either starts directly
      // or requests VPN permission itself.
      await _vpnPermissionChannel
          .invokeMethod<bool>('request')
          .timeout(const Duration(seconds: 20), onTimeout: () => true);
      return true;
    } on PlatformException {
      // Still continue to v2ray_box; its native start path owns the final
      // VpnService.prepare() decision and can request permission again.
      return true;
    }
  }

  Future<String> appVersion() async {
    if (!Platform.isAndroid) return '';
    try {
      return await _vpnPermissionChannel.invokeMethod<String>('version') ?? '';
    } on PlatformException {
      return '';
    }
  }

  Future<int> ping(
    ProxyNode node, {
    bool allowTunnelFallback = false,
  }) async {
    if (node.protocol == ProxyProtocol.snell) return -1;
    final value = await box.ping(node.connectionLink, timeout: 7000);
    if (value > 0) return value;

    // libXray's standalone URL tester does not understand every sing-box-only
    // protocol (notably Hysteria2). When that node is already connected, time
    // a small HTTPS request through the active Android VPN as the effective
    // tunnel latency shown on Home.
    if (allowTunnelFallback && node.protocol == ProxyProtocol.hysteria2) {
      return _measureActiveTunnelLatency();
    }
    return -1;
  }

  Future<int> _measureActiveTunnelLatency() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    final sw = Stopwatch()..start();
    try {
      final request = await client.getUrl(
        Uri.parse('https://www.gstatic.com/generate_204'),
      );
      request.followRedirects = false;
      final response = await request.close().timeout(const Duration(seconds: 7));
      await response.drain<void>();
      sw.stop();
      if (response.statusCode >= 200 && response.statusCode < 500) {
        return sw.elapsedMilliseconds.clamp(1, 60000);
      }
    } catch (_) {
      // Fall through to -1.
    } finally {
      client.close(force: true);
    }
    return -1;
  }

  Future<void> setRoutingMode(String mode) async {
    // Routing is compiled into the active core configuration. The caller
    // reconnects the current node after switching mode.
  }

  Future<Map<String, dynamic>> parseSubscription(String url) => box.parseSubscription(url);
  Future<Map<String, dynamic>> coreInfo() => box.getCoreInfo();
}
