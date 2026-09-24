import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:v2ray_box/v2ray_box.dart';

import '../models/proxy_node.dart';
import 'singbox_config_builder.dart';

class VpnEngineService {
  static const MethodChannel _vpnPermissionChannel =
      MethodChannel('aurum_proxy/vpn_permission');

  final V2rayBox box = V2rayBox();

  Future<void> initialize() async {
    await box.initialize(notificationStopButtonText: '断开');
    await box.setCoreEngine('xray');
    await box.setServiceMode(VpnMode.vpn);
  }

  Stream<dynamic> watchStatus() => box.watchStatus();
  Stream<dynamic> watchStats() => box.watchStats();
  Stream<Map<String, dynamic>> watchLogs() => box.watchLogs();
  Stream<Map<String, dynamic>> watchAlerts() => box.watchAlerts();

  Future<bool> connect(ProxyNode node) async {
    if (!await ensureVpnPermission()) return false;

    await box.setCoreEngine('singbox');
    await box.setServiceMode(VpnMode.vpn);

    if (node.protocol == ProxyProtocol.snell) {
      // v2ray_box's share-link parser does not parse snell:// links. Build the
      // sing-box config explicitly so the protocol-version compatibility
      // mapping is deterministic and validated before startup.
      return box
          .connectWithJson(SingBoxConfigBuilder.fromNode(node), name: node.name)
          .timeout(const Duration(seconds: 12), onTimeout: () => false);
    }
    return box
        .connect(node.connectionLink, name: node.name, notificationTitle: 'Aurum Proxy')
        .timeout(const Duration(seconds: 12), onTimeout: () => false);
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

  Future<int> ping(ProxyNode node) async {
    if (node.protocol == ProxyProtocol.snell) return -1;
    return box.ping(node.connectionLink, timeout: 7000);
  }

  Future<void> setRoutingMode(String mode) async {
    final coreMode = switch (mode) {
      '全局模式' => 'global',
      '直连模式' => 'direct',
      _ => 'rule',
    };
    await box.setClashMode(coreMode);
  }

  Future<Map<String, dynamic>> parseSubscription(String url) => box.parseSubscription(url);
  Future<Map<String, dynamic>> coreInfo() => box.getCoreInfo();
}
