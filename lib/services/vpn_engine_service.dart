import 'dart:async';
import 'package:v2ray_box/v2ray_box.dart';

import '../models/proxy_node.dart';
import 'singbox_config_builder.dart';

class VpnEngineService {
  final V2rayBox box = V2rayBox();

  Future<void> initialize() async {
    await box.initialize(notificationStopButtonText: '断开');
    await box.setCoreEngine('singbox');
    await box.setServiceMode(VpnMode.vpn);
  }

  Stream<dynamic> watchStatus() => box.watchStatus();
  Stream<dynamic> watchStats() => box.watchStats();
  Stream<Map<String, dynamic>> watchLogs() => box.watchLogs();
  Stream<Map<String, dynamic>> watchAlerts() => box.watchAlerts();

  Future<bool> connect(ProxyNode node) async {
    if (!await box.checkVpnPermission()) {
      final granted = await box.requestVpnPermission();
      if (!granted) return false;
    }
    await box.setCoreEngine('singbox');
    await box.setServiceMode(VpnMode.vpn);

    if (node.protocol == ProxyProtocol.snell) {
      try {
        final ok = await box.connect(node.connectionLink, name: node.name, notificationTitle: 'Aurum Proxy');
        if (ok) return true;
      } catch (_) {}
      return box.connectWithJson(SingBoxConfigBuilder.fromNode(node), name: node.name);
    }
    return box.connect(node.connectionLink, name: node.name, notificationTitle: 'Aurum Proxy');
  }

  Future<bool> disconnect() => box.disconnect();

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
