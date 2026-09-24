import 'dart:convert';

import '../models/proxy_node.dart';
import 'singbox_config_router.dart';

/// Fallback raw sing-box config, primarily used for Snell v5.
/// On Android v2ray_box runs sing-box behind its VpnService TUN bridge and
/// expects a local SOCKS/mixed listener on 127.0.0.1:10808.
class SingBoxConfigBuilder {
  static String fromNode(
    ProxyNode n, {
    String mode = '智能模式',
    String geoDir = '',
  }) {
    final outbound = <String, dynamic>{
      'tag': 'proxy',
      'server': n.server,
      'server_port': n.port,
    };

    switch (n.protocol) {
      case ProxyProtocol.shadowsocks:
        outbound.addAll({
          'type': 'shadowsocks',
          'method': n.method,
          'password': n.password,
          if (n.plugin.isNotEmpty) 'plugin': n.plugin,
          if (n.pluginOpts.isNotEmpty) 'plugin_opts': n.pluginOpts,
          if (n.network.isNotEmpty) 'network': n.network,
        });
        break;
      case ProxyProtocol.vless:
        outbound.addAll({
          'type': 'vless',
          'uuid': n.uuid,
          if (n.flow.isNotEmpty) 'flow': n.flow,
          if (n.network.isNotEmpty) 'network': n.network,
          if (n.packetEncoding.isNotEmpty) 'packet_encoding': n.packetEncoding,
        });
        _tlsAndTransport(outbound, n);
        break;
      case ProxyProtocol.vmess:
        outbound.addAll({
          'type': 'vmess',
          'uuid': n.uuid,
          'security': n.vmessSecurity.isEmpty ? 'auto' : n.vmessSecurity,
          if (n.alterId > 0) 'alter_id': n.alterId,
          if (n.network.isNotEmpty) 'network': n.network,
          if (n.packetEncoding.isNotEmpty) 'packet_encoding': n.packetEncoding,
        });
        _tlsAndTransport(outbound, n);
        break;
      case ProxyProtocol.trojan:
        outbound.addAll({
          'type': 'trojan',
          'password': n.password,
          if (n.network.isNotEmpty) 'network': n.network,
        });
        _tlsAndTransport(outbound, n);
        break;
      case ProxyProtocol.hysteria2:
        outbound.addAll({
          'type': 'hysteria2',
          'password': n.password,
          if (n.hy2ServerPorts.isNotEmpty)
            'server_ports': _parseServerPorts(n.hy2ServerPorts),
          if (n.hy2HopInterval.isNotEmpty) 'hop_interval': n.hy2HopInterval,
          if (n.hy2HopIntervalMax.isNotEmpty)
            'hop_interval_max': n.hy2HopIntervalMax,
          if (n.hy2UpMbps > 0) 'up_mbps': n.hy2UpMbps,
          if (n.hy2DownMbps > 0) 'down_mbps': n.hy2DownMbps,
          if (n.hy2Obfs.isNotEmpty)
            'obfs': {
              'type': n.hy2Obfs,
              if (n.hy2ObfsPassword.isNotEmpty)
                'password': n.hy2ObfsPassword,
            },
          if (n.network.isNotEmpty) 'network': n.network,
          if (n.hy2BbrProfile.isNotEmpty) 'bbr_profile': n.hy2BbrProfile,
          if (n.hy2DisableChromeParrot) 'disable_chrome_parrot': true,
          'tls': {
            'enabled': true,
            if (n.sni.isNotEmpty) 'server_name': n.sni,
            if (n.tlsInsecure) 'insecure': true,
            if (n.alpn.trim().isNotEmpty) 'alpn': _splitList(n.alpn),
          },
        });
        break;
      case ProxyProtocol.snell:
        // Desktop v0.7.x compatibility logic:
        // v4 -> 4, plain v5 -> 4 (wire compatible), v6 -> 6.
        // Snell v5 QUIC proxy mode is not implemented by sing-box.
        final runtimeVersion = n.snellVersion == 6 ? 6 : 4;
        outbound.addAll({
          'type': 'snell',
          'psk': n.password,
          'version': runtimeVersion,
          'reuse': n.snellReuse,
          if (n.snellUserKey.isNotEmpty) 'userkey': n.snellUserKey,
          if (n.network.isNotEmpty) 'network': n.network,
          if (runtimeVersion == 4 && n.snellObfsMode.isNotEmpty)
            'obfs_mode': n.snellObfsMode,
          if (runtimeVersion == 4 && n.snellObfsHost.isNotEmpty)
            'obfs_host': n.snellObfsHost,
          if (runtimeVersion == 6 && n.snellMode.isNotEmpty)
            'mode': n.snellMode,
        });
        break;
    }

    final route = <String, dynamic>{};
    switch (mode) {
      case '直连模式':
        route['final'] = 'direct';
        break;
      case '全局模式':
        route['final'] = 'proxy';
        break;
      default:
        route['final'] = 'proxy';
        route['rules'] = [
          {'ip_is_private': true, 'action': 'route', 'outbound': 'direct'},
          {
            'rule_set': ['geosite-cn', 'geoip-cn'],
            'action': 'route',
            'outbound': 'direct',
          },
        ];
        if (geoDir.isNotEmpty) {
          route['rule_set'] = [
            {
              'type': 'local',
              'tag': 'geosite-cn',
              'format': 'binary',
              'path': '$geoDir/geosite-geolocation-cn.srs',
            },
            {
              'type': 'local',
              'tag': 'geoip-cn',
              'format': 'binary',
              'path': '$geoDir/geoip-cn.srs',
            },
          ];
        } else {
          route['rule_set'] = [
            {
              'type': 'remote',
              'tag': 'geosite-cn',
              'format': 'binary',
              'url': 'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs',
              'download_detour': 'direct',
              'update_interval': '1d',
            },
            {
              'type': 'remote',
              'tag': 'geoip-cn',
              'format': 'binary',
              'url': 'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs',
              'download_detour': 'direct',
              'update_interval': '1d',
            },
          ];
        }
        break;
    }

    return SingBoxConfigRouter.apply(
      jsonEncode({
        'log': {'level': 'info', 'timestamp': true},
        'inbounds': [
          {
            'type': 'mixed',
            'tag': 'mixed-in',
            'listen': '127.0.0.1',
            'listen_port': 10808,
          },
        ],
        'outbounds': [
          outbound,
          {'type': 'direct', 'tag': 'direct'},
        ],
        'route': route,
        'experimental': {
          'clash_api': {'external_controller': '127.0.0.1:9090'},
        },
      }),
      mode: mode,
      geoDir: geoDir,
    );
  }

  static void _tlsAndTransport(Map<String, dynamic> outbound, ProxyNode n) {
    final sec = n.security.toLowerCase();
    if (sec == 'tls' || sec == 'reality') {
      outbound['tls'] = {
        'enabled': true,
        if (n.sni.isNotEmpty) 'server_name': n.sni,
        if (n.tlsInsecure) 'insecure': true,
        if (n.alpn.trim().isNotEmpty) 'alpn': _splitList(n.alpn),
        if (n.fingerprint.isNotEmpty)
          'utls': {'enabled': true, 'fingerprint': n.fingerprint},
        if (sec == 'reality')
          'reality': {
            'enabled': true,
            if (n.publicKey.isNotEmpty) 'public_key': n.publicKey,
            if (n.shortId.isNotEmpty) 'short_id': n.shortId,
          },
      };
    }
    if (n.transport != 'tcp' && n.transport.isNotEmpty) {
      outbound['transport'] = {
        'type': n.transport,
        if (n.transport == 'grpc' && n.path.isNotEmpty)
          'service_name': n.path,
        if (n.transport != 'grpc' && n.path.isNotEmpty) 'path': n.path,
        if (n.host.isNotEmpty && n.transport == 'http') 'host': [n.host],
        if (n.host.isNotEmpty &&
            (n.transport == 'ws' || n.transport == 'httpupgrade'))
          'headers': {'Host': n.host},
      };
    }
  }

  static List<String> _splitList(String value) => value
      .split(RegExp(r'[,\\s]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  static List<String> _parseServerPorts(String value) => value
      .split(RegExp(r'[,\\s]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}
