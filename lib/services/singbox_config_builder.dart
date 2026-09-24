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
        });
        break;
      case ProxyProtocol.vless:
        outbound.addAll({
          'type': 'vless',
          'uuid': n.uuid,
          if (n.flow.isNotEmpty) 'flow': n.flow,
        });
        _tlsAndTransport(outbound, n);
        break;
      case ProxyProtocol.vmess:
        outbound.addAll({'type': 'vmess', 'uuid': n.uuid, 'security': 'auto'});
        _tlsAndTransport(outbound, n);
        break;
      case ProxyProtocol.trojan:
        outbound.addAll({'type': 'trojan', 'password': n.password});
        _tlsAndTransport(outbound, n);
        break;
      case ProxyProtocol.hysteria2:
        outbound.addAll({
          'type': 'hysteria2',
          'password': n.password,
          'tls': {'enabled': true, if (n.sni.isNotEmpty) 'server_name': n.sni},
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
          'reuse': true,
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
        if (n.path.isNotEmpty) 'path': n.path,
      };
    }
  }
}
