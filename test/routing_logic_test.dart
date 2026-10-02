import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:aurum_proxy/models/proxy_node.dart';
import 'package:aurum_proxy/services/singbox_config_builder.dart';
import 'package:aurum_proxy/services/singbox_chain_config.dart';
import 'package:aurum_proxy/services/xray_config_router.dart';

void main() {
  ProxyNode snell(int version) => ProxyNode(
        id: 's$version',
        name: 'Snell $version',
        protocol: ProxyProtocol.snell,
        server: '2001:db8::1',
        port: 31289,
        password: 'psk',
        snellVersion: version,
      );

  test('desktop Snell compatibility maps v5 to v4 and keeps v6', () {
    final v5 = jsonDecode(SingBoxConfigBuilder.fromNode(snell(5)))
        as Map<String, dynamic>;
    final v5Out = (v5['outbounds'] as List).first as Map<String, dynamic>;
    expect(v5Out['version'], 4);

    final v6 = jsonDecode(SingBoxConfigBuilder.fromNode(snell(6)))
        as Map<String, dynamic>;
    final v6Out = (v6['outbounds'] as List).first as Map<String, dynamic>;
    expect(v6Out['version'], 6);
  });

  test('smart sing-box routing sends CN/private direct and others proxy', () {
    final config = jsonDecode(
      SingBoxConfigBuilder.fromNode(
        snell(5),
        mode: '智能模式',
        geoDir: '/data/user/0/aurum/files',
      ),
    ) as Map<String, dynamic>;
    final route = config['route'] as Map<String, dynamic>;
    expect(route['final'], 'proxy');
    final rules = route['rules'] as List;
    expect(rules.length, 4);
    expect((rules[2] as Map)['domain_suffix'], ['.cn']);
    final ruleSets = route['rule_set'] as List;
    expect(ruleSets.length, 2);
    expect((ruleSets.first as Map)['type'], 'local');
  });

  test('global and direct sing-box modes change final outbound', () {
    final global = jsonDecode(
      SingBoxConfigBuilder.fromNode(snell(5), mode: '全局模式'),
    ) as Map<String, dynamic>;
    expect((global['route'] as Map)['final'], 'proxy');

    final direct = jsonDecode(
      SingBoxConfigBuilder.fromNode(snell(5), mode: '直连模式'),
    ) as Map<String, dynamic>;
    expect((direct['route'] as Map)['final'], 'direct');
  });

  test('Hysteria2 raw config always enables TLS', () {
    final node = ProxyNode(
      id: 'hy2',
      name: 'HY2',
      protocol: ProxyProtocol.hysteria2,
      server: 'example.com',
      port: 443,
      password: 'pw',
      sni: 'example.com',
    );
    final config =
        jsonDecode(SingBoxConfigBuilder.fromNode(node)) as Map<String, dynamic>;
    final outbound = (config['outbounds'] as List).first as Map<String, dynamic>;
    expect((outbound['tls'] as Map)['enabled'], true);
    expect((outbound['tls'] as Map)['server_name'], 'example.com');
  });



  test('sing-box pre-proxy chain preserves detour across route modes', () {
    const primary = '''
{"outbounds":[{"type":"vless","tag":"old-main","server":"main.example","server_port":443,"uuid":"11111111-1111-1111-1111-111111111111"}]}
''';
    const pre = '''
{"outbounds":[{"type":"shadowsocks","tag":"old-pre","server":"pre.example","server_port":8388,"method":"aes-256-gcm","password":"secret"}]}
''';

    for (final mode in ['智能模式', '全局模式', '直连模式']) {
      final config = jsonDecode(
        SingBoxChainConfig.merge(
          primary,
          pre,
          mode: mode,
          geoDir: mode == '智能模式' ? '/tmp/geo' : '',
        ),
      ) as Map<String, dynamic>;
      final outbounds = config['outbounds'] as List;
      final main = outbounds.first as Map<String, dynamic>;
      final front = outbounds[1] as Map<String, dynamic>;
      expect(main['tag'], 'proxy');
      expect(main['detour'], 'preproxy');
      expect(front['tag'], 'preproxy');
      final route = config['route'] as Map<String, dynamic>;
      expect(
        route['final'],
        mode == '直连模式' ? 'direct' : 'proxy',
      );
    }
  });


  test('pre-proxy selection survives node persistence', () {
    final node = ProxyNode(
      id: 'main',
      name: 'Main',
      protocol: ProxyProtocol.vless,
      server: 'example.com',
      port: 443,
      uuid: '11111111-1111-1111-1111-111111111111',
      preProxyNodeId: 'front',
    );
    final restored = ProxyNode.fromJson(node.toJson());
    expect(restored.preProxyNodeId, 'front');
  });

  test('Xray smart global direct modes compile routing rules', () {
    const base = '{"outbounds":[{"protocol":"vless","tag":"proxy","settings":{}}]}';

    final smart = jsonDecode(XrayConfigRouter.apply(base, '智能模式'))
        as Map<String, dynamic>;
    final smartRouting = smart['routing'] as Map;
    final smartRules = smartRouting['rules'] as List;
    expect(smartRouting['domainStrategy'], 'IPIfNonMatch');
    expect(smartRules.length, 4);
    expect((smartRules.last as Map)['outboundTag'], 'proxy');
    final cnDomainRule = smartRules.cast<Map>().firstWhere(
      (r) => r['domain'] != null,
    );
    expect((cnDomainRule['domain'] as List).contains('domain:cn'), true);
    final smartOutbounds = smart['outbounds'] as List;
    final directOut = smartOutbounds.cast<Map>().firstWhere(
      (o) => o['tag'] == 'direct',
    );
    expect((directOut['settings'] as Map)['domainStrategy'], 'AsIs');

    final global = jsonDecode(XrayConfigRouter.apply(base, '全局模式'))
        as Map<String, dynamic>;
    expect((global['routing'] as Map)['domainStrategy'], 'AsIs');
    final globalRules = ((global['routing'] as Map)['rules'] as List);
    expect(globalRules.length, 1);
    expect((globalRules.first as Map)['outboundTag'], 'proxy');

    final direct = jsonDecode(XrayConfigRouter.apply(base, '直连模式'))
        as Map<String, dynamic>;
    expect((direct['routing'] as Map)['domainStrategy'], 'AsIs');
    final directRules = ((direct['routing'] as Map)['rules'] as List);
    expect(directRules.length, 1);
    expect((directRules.first as Map)['outboundTag'], 'direct');
  });
}
