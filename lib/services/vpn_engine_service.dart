import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:v2ray_box/v2ray_box.dart';

import '../models/proxy_node.dart';
import 'singbox_config_builder.dart';
import 'geo_asset_service.dart';
import 'singbox_config_router.dart';
import 'singbox_chain_config.dart';

class VpnEngineService {
  static const MethodChannel _vpnPermissionChannel = MethodChannel(
    'aurum_proxy/vpn_permission',
  );

  final V2rayBox box = V2rayBox();
  final GeoAssetService _geo = GeoAssetService();

  Future<void> initialize() async {
    await box.initialize(notificationStopButtonText: '断开');
    await box.setCoreEngine('singbox');
    await box.setServiceMode(VpnMode.vpn);
  }

  Stream<dynamic> watchStatus() => box.watchStatus();
  Stream<dynamic> watchStats() => box.watchStats();
  Stream<Map<String, dynamic>> watchLogs() => box.watchLogs();
  Stream<Map<String, dynamic>> watchAlerts() => box.watchAlerts();

  Future<bool> connect(
    ProxyNode node, {
    String mode = '智能模式',
    ProxyNode? preProxy,
  }) async {
    if (!await ensureVpnPermission()) return false;

    if (mode == '智能模式') {
      await _geo.bootstrap();
      if (!await _geo.hasSmartRuleAssets()) {
        throw StateError('智能分流 Geo 数据缺失或不完整，请在设置中更新 GeoIP / GeoSite');
      }
    }

    final useChain = preProxy != null;

    // 1.2.0: one routing engine only. Android's Xray TUN layer is a pure
    // transport bridge; sing-box owns Smart/Global/Direct, DNS and Geo rules.
    // This avoids the previous double-routing/double-DNS behavior.
    await box.setCoreEngine('singbox');
    await box.setServiceMode(VpnMode.vpn);

    {
      final geoDir = mode == '智能模式' && await _geo.hasSmartRuleAssets()
          ? await _geo.filesDir
          : '';

      if (useChain) {
        final json = await _buildSingBoxChain(
          node,
          preProxy,
          mode: mode,
          geoDir: geoDir,
        );
        return box
            .connectWithJson(json, name: node.name)
            .timeout(const Duration(seconds: 15), onTimeout: () => false);
      }

      if (node.protocol == ProxyProtocol.snell) {
        final json = SingBoxConfigBuilder.fromNode(
          node,
          mode: mode,
          geoDir: geoDir,
        );
        return box
            .connectWithJson(json, name: node.name)
            .timeout(const Duration(seconds: 15), onTimeout: () => false);
      }

      // All supported share links are parsed by sing-box in 1.2.0. This keeps
      // routing, DNS, Geo matching and protocol transport in one core.
      final generated = await box.generateConfig(node.connectionLink);
      if (generated.trim().isEmpty) return false;
      final routed = SingBoxConfigRouter.apply(
        generated,
        mode: mode,
        geoDir: geoDir,
      );
      return box
          .connectWithJson(routed, name: node.name)
          .timeout(const Duration(seconds: 15), onTimeout: () => false);
    }
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
    ProxyNode? preProxy,
  }) async {
    if (!Platform.isAndroid) return -1;
    await box.setCoreEngine('singbox');
    final raw = preProxy != null
        ? await _buildSingBoxChain(node, preProxy, mode: '全局模式')
        : (node.protocol == ProxyProtocol.snell
            ? SingBoxConfigBuilder.fromNode(node, mode: '全局模式')
            : await box.generateConfig(node.connectionLink));
    if (raw.trim().isEmpty) return -1;
    final config = SingBoxConfigRouter.apply(raw, mode: '全局模式');
    final decoded = jsonDecode(config) as Map<String, dynamic>;
    final tag = (decoded['route'] as Map)['final'] as String;
    return await _vpnPermissionChannel
            .invokeMethod<int>('measureNodeDelay', {
              // Reuse the running core for Home; independent temporary cores allow
              // testing other nodes without disconnecting the current VPN.
              if (!allowTunnelFallback) 'config': config,
              'tag': tag,
            })
            .timeout(const Duration(seconds: 13), onTimeout: () => -1) ??
        -1;
  }

  Future<String> _rawSingBoxForNode(ProxyNode node) async {
    if (node.protocol == ProxyProtocol.snell) {
      return SingBoxConfigBuilder.fromNode(node, mode: '全局模式');
    }
    final raw = await box.generateConfig(node.connectionLink);
    if (raw.trim().isEmpty) {
      throw StateError('无法生成 ${node.name} 的 sing-box 配置');
    }
    return raw;
  }

  Future<String> _buildSingBoxChain(
    ProxyNode node,
    ProxyNode preProxy, {
    required String mode,
    String geoDir = '',
  }) async {
    final primaryRaw = await _rawSingBoxForNode(node);
    final preRaw = await _rawSingBoxForNode(preProxy);
    return SingBoxChainConfig.merge(
      primaryRaw,
      preRaw,
      mode: mode,
      geoDir: geoDir,
    );
  }

  Future<void> setRoutingMode(String mode) async {
    // Routing is compiled into the active core configuration. The caller
    // reconnects the current node after switching mode.
  }

  Future<Map<String, dynamic>> parseSubscription(String url) =>
      box.parseSubscription(url);
  Future<Map<String, dynamic>> coreInfo() => box.getCoreInfo();
}
