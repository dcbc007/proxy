import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:aurum_proxy/models/proxy_node.dart';
import 'package:aurum_proxy/services/singbox_config_builder.dart';

void main() {
  test('Snell v5 client config maps to sing-box outbound v4', () {
    final node = ProxyNode(
      id: 'test',
      name: 'Snell v5',
      protocol: ProxyProtocol.snell,
      server: '127.0.0.1',
      port: 6333,
      password: 'test-password',
      sourceLink: 'snell://test-password@127.0.0.1:6333?version=5#Snell%20v5',
    );

    final config = jsonDecode(SingBoxConfigBuilder.fromNode(node))
        as Map<String, dynamic>;
    final outbounds = config['outbounds'] as List<dynamic>;
    final outbound = outbounds.first as Map<String, dynamic>;

    expect(outbound['type'], 'snell');
    expect(outbound['version'], 4);
    expect(outbound['psk'], 'test-password');
  });
}
