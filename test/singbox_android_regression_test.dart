import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:aurum_proxy/services/singbox_config_router.dart';
import 'package:aurum_proxy/services/singbox_config_builder.dart';
import 'package:aurum_proxy/models/proxy_node.dart';
import 'package:aurum_proxy/services/qr_payload_parser.dart';

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
  test('DNS is intercepted in sing-box and mode-specific DNS stays correct', () {
    final direct = routed('直连模式');
    expect(direct['dns']['final'], 'dns-cn');
    expect(direct['dns']['servers'][0]['type'], 'udp');
    expect(direct['dns']['servers'][0]['server'], '223.5.5.5');
    expect(direct['dns']['servers'][0]['server_port'], 53);
    expect(direct['route']['final'], 'direct');
    final directRules = direct['route']['rules'] as List;
    expect(directRules.length, 1);
    expect((directRules.first as Map)['type'], 'logical');
    expect((directRules.first as Map)['action'], 'hijack-dns');

    final global = routed('全局模式');
    expect(global['dns']['final'], 'dns-remote');
    expect(global['dns']['servers'][1]['detour'], 'proxy');
    expect(global['route']['final'], 'proxy');
    final globalRules = global['route']['rules'] as List;
    expect((globalRules.first as Map)['action'], 'sniff');
    expect((globalRules[1] as Map)['action'], 'hijack-dns');
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

  test('Android transport-only configs never use sing-box direct routing', () {
    for (final mode in ['智能模式', '全局模式', '直连模式']) {
      final config = jsonDecode(
        SingBoxConfigRouter.apply(
          jsonEncode({
            'inbounds': [
              {'type': 'mixed', 'listen': '127.0.0.1', 'listen_port': 10808},
            ],
            'outbounds': [outbound],
            'route': {'final': 'proxy'},
          }),
          mode: mode,
          geoDir: '/tmp/geo',
          transportProxyOnly: true,
        ),
      ) as Map<String, dynamic>;

      final route = config['route'] as Map<String, dynamic>;
      expect(route['final'], 'proxy');
      expect((route['rules'] as List), isEmpty);
      expect(config['dns'], isNull);

      final tags = (config['outbounds'] as List)
          .map((e) => (e as Map)['tag']?.toString())
          .whereType<String>()
          .toSet();
      final expectedMarker = switch (mode) {
        '直连模式' => 'aurum-mode-direct',
        '全局模式' => 'aurum-mode-global',
        _ => 'aurum-mode-smart',
      };
      expect(tags, contains(expectedMarker));
    }
  });


  test('Android verified TLS uses exported system CA and preserves insecure nodes', () {
    final secure = jsonDecode(
      SingBoxConfigRouter.apply(
        jsonEncode({
          'inbounds': [
            {'type': 'mixed', 'listen_port': 10808},
          ],
          'outbounds': [
            {
              'type': 'hysteria2',
              'tag': 'proxy',
              'server': 'hy.example.com',
              'server_port': 443,
              'password': 'pw',
              'tls': {'enabled': true},
            },
          ],
          'route': {'final': 'proxy'},
        }),
        mode: '全局模式',
        transportProxyOnly: true,
        systemCaBundlePath: '/data/user/0/app/files/aurum-system-ca.pem',
      ),
    ) as Map<String, dynamic>;
    final secureTls =
        ((secure['outbounds'] as List).first as Map)['tls'] as Map;
    expect(secureTls['insecure'], isNull);
    expect(secureTls['server_name'], 'hy.example.com');
    expect(
      secureTls['certificate_path'],
      '/data/user/0/app/files/aurum-system-ca.pem',
    );

    final insecure = jsonDecode(
      SingBoxConfigRouter.apply(
        jsonEncode({
          'inbounds': [
            {'type': 'mixed', 'listen_port': 10808},
          ],
          'outbounds': [
            {
              'type': 'hysteria2',
              'tag': 'proxy',
              'server': 'hy.example.com',
              'server_port': 443,
              'password': 'pw',
              'tls': {'enabled': true, 'insecure': true},
            },
          ],
          'route': {'final': 'proxy'},
        }),
        mode: '全局模式',
        transportProxyOnly: true,
        systemCaBundlePath: '/data/user/0/app/files/aurum-system-ca.pem',
      ),
    ) as Map<String, dynamic>;
    final insecureTls =
        ((insecure['outbounds'] as List).first as Map)['tls'] as Map;
    expect(insecureTls['insecure'], true);
    expect(insecureTls['certificate_path'], isNull);
  });

  test('Bare IPv6 Snell uses Xray protected transport dialer on Android', () {
    final node = ProxyNode(
      id: 's6',
      name: 'Snell IPv6',
      protocol: ProxyProtocol.snell,
      server: '2001:db8::1234',
      port: 443,
      password: 'test-password',
    );
    final config = jsonDecode(
      SingBoxConfigBuilder.fromNode(
        node,
        mode: '全局模式',
        transportProxyOnly: true,
        protectedIpv6Transport: true,
      ),
    ) as Map<String, dynamic>;

    final outbounds = (config['outbounds'] as List).cast<Map>();
    final snell = outbounds.firstWhere((e) => e['tag'] == 'proxy');
    expect(snell['detour'], 'aurum-protected-direct');

    final protected = outbounds.firstWhere(
      (e) => e['tag'] == 'aurum-protected-direct',
    );
    expect(protected['type'], 'socks');
    expect(protected['server'], '127.0.0.1');
    expect(protected['server_port'], 10809);
    expect(protected['version'], '5');
  });


  test('HY2 peer alias survives import and strict TLS config generation', () {
    final node = QrPayloadParser.parse(
      'hy2://test-password@203.0.113.10:443?peer=hy2.example.com&skip-cert-verify=0&alpn=h3#HY2',
    );
    expect(node.protocol, ProxyProtocol.hysteria2);
    expect(node.server, '203.0.113.10');
    expect(node.sni, 'hy2.example.com');
    expect(node.tlsInsecure, false);

    final config = jsonDecode(
      SingBoxConfigBuilder.fromNode(
        node,
        mode: '全局模式',
        transportProxyOnly: true,
        systemCaBundlePath: '/data/user/0/app/files/aurum-system-ca.pem',
      ),
    ) as Map<String, dynamic>;
    final proxy = (config['outbounds'] as List)
        .cast<Map>()
        .firstWhere((e) => e['tag'] == 'proxy');
    final tls = proxy['tls'] as Map;
    expect(tls['server_name'], 'hy2.example.com');
    expect(tls['insecure'], isNull);
    expect(
      tls['certificate_path'],
      '/data/user/0/app/files/aurum-system-ca.pem',
    );
    expect(tls['alpn'], ['h3']);
  });

  test('HY2 allowInsecure aliases are normalized by Aurum parser', () {
    for (final key in ['insecure', 'allowInsecure', 'skip-cert-verify']) {
      final node = QrPayloadParser.parse(
        'hy2://pw@hy.example.com:443?$key=1#HY2',
      );
      expect(node.tlsInsecure, true, reason: key);
    }
  });

}
