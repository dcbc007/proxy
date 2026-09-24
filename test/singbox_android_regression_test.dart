import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:aurum_proxy/services/singbox_config_router.dart';
import 'package:aurum_proxy/services/singbox_config_builder.dart';
import 'package:aurum_proxy/models/proxy_node.dart';

void main() {
  final outbound = {
    'type': 'hysteria2',
    'tag': 'proxy',
    'server': 'example.com',
    'server_port': 443,
    'password': 'test',
    'tls': {'enabled': true, 'insecure': true, 'server_name': 'test.example'},
    'obfs': {'type': 'salamander', 'password': 'test-obfs'},
    'up_mbps': 100,
    'down_mbps': 500,
  };
  Map<String, dynamic> routed(String mode) => jsonDecode(
    SingBoxConfigRouter.apply(
      jsonEncode({
        'inbounds': [
          {'type': 'tun', 'auto_route': true, 'interface_name': 'tun0'},
          {'type': 'mixed', 'listen_port': 10808},
        ],
        'outbounds': [outbound],
        'route': {'auto_detect_interface': true},
        'experimental': {
          'cache_file': {'enabled': true, 'path': 'cache.db'},
        },
      }),
      mode: mode,
      geoDir: '/tmp/geo',
    ),
  ) as Map<String, dynamic>;

  test('HY2 uses only Android bridge listener, no privileged TUN', () {
    for (final mode in ['智能模式', '全局模式', '直连模式']) {
      final config = routed(mode);
      final inbounds = config['inbounds'] as List;
      expect(inbounds.length, 1);
      expect(inbounds.single['type'], 'mixed');
      expect(inbounds.single['listen'], '127.0.0.1');
      expect(inbounds.single['listen_port'], 10808);
      expect(config['route']['auto_detect_interface'], isNull);
      // Never lose auth, TLS, obfuscation or user's bandwidth during routing.
      expect(config['outbounds'][0], outbound);
    }
  });
  test('DNS is intercepted before routing and direct mode uses direct DNS', () {
    final direct = routed('直连模式');
    expect(direct['dns']['final'], 'dns-direct');
    expect(direct['route']['final'], 'direct');
    expect(direct['route']['rules'][0], {'port': 53, 'action': 'hijack-dns'});
    final global = routed('全局模式');
    expect(global['dns']['final'], 'dns-remote');
    expect(global['dns']['servers'][1]['detour'], 'proxy');
    expect(global['route']['final'], 'proxy');
    expect(global['dns']['disable_expire'], isNull);
  });
  test('Snell reuses connections without bandwidth caps', () {
    final node = ProxyNode(
      id: 's',
      name: 'Snell',
      protocol: ProxyProtocol.snell,
      server: 'example.com',
      port: 443,
      password: 'test-password',
    );
    final config = jsonDecode(
      SingBoxConfigBuilder.fromNode(node, mode: '全局模式'),
    );
    expect(config['outbounds'][0]['reuse'], true);
    expect(config['outbounds'][0]['up_mbps'], isNull);
    expect(config['outbounds'][0]['down_mbps'], isNull);
    expect(
      config['experimental']['clash_api']['external_controller'],
      '127.0.0.1:9090',
    );
  });
}
