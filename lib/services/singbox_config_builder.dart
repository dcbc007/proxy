import 'dart:convert';
import '../models/proxy_node.dart';

/// Fallback raw sing-box config, primarily used for Snell v5.
/// On Android v2ray_box runs sing-box behind its VpnService TUN bridge and
/// expects a local SOCKS/mixed listener on 127.0.0.1:10808.
class SingBoxConfigBuilder {
  static String fromNode(ProxyNode n) {
    final outbound = <String, dynamic>{
      'tag': 'proxy',
      'server': n.server,
      'server_port': n.port,
    };

    switch (n.protocol) {
      case ProxyProtocol.shadowsocks:
        outbound.addAll({'type': 'shadowsocks', 'method': n.method, 'password': n.password});
        break;
      case ProxyProtocol.vless:
        outbound.addAll({'type': 'vless', 'uuid': n.uuid, if (n.flow.isNotEmpty) 'flow': n.flow});
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
        outbound.addAll({'type': 'hysteria2', 'password': n.password});
        _tlsAndTransport(outbound, n);
        break;
      case ProxyProtocol.snell:
        outbound.addAll({'type': 'snell', 'psk': n.password, 'version': 5});
        break;
    }

    return jsonEncode({
      'log': {'level': 'info', 'timestamp': true},
      'inbounds': [
        {'type': 'mixed', 'tag': 'mixed-in', 'listen': '127.0.0.1', 'listen_port': 10808}
      ],
      'outbounds': [
        outbound,
        {'type': 'direct', 'tag': 'direct'}
      ],
      'route': {'auto_detect_interface': true, 'final': 'proxy'},
      'experimental': {
        'clash_api': {'external_controller': '127.0.0.1:9090'}
      }
    });
  }

  static void _tlsAndTransport(Map<String, dynamic> outbound, ProxyNode n) {
    final sec = n.security.toLowerCase();
    if (sec == 'tls' || sec == 'reality') {
      outbound['tls'] = {
        'enabled': true,
        if (n.sni.isNotEmpty) 'server_name': n.sni,
        if (n.fingerprint.isNotEmpty) 'utls': {'enabled': true, 'fingerprint': n.fingerprint},
        if (sec == 'reality')
          'reality': {
            'enabled': true,
            if (n.publicKey.isNotEmpty) 'public_key': n.publicKey,
            if (n.shortId.isNotEmpty) 'short_id': n.shortId,
          }
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
