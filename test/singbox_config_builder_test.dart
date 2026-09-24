import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:aurum_proxy/models/proxy_node.dart';
import 'package:aurum_proxy/services/singbox_config_builder.dart';
import 'package:aurum_proxy/services/qr_payload_parser.dart';

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

    final route = config['route'] as Map<String, dynamic>;
    expect(route['final'], 'proxy');
    expect(route.containsKey('auto_detect_interface'), isFalse);
  });

  test('Hysteria2 advanced TLS and transport options are emitted', () {
    final node = ProxyNode(
      id: 'hy2',
      name: 'HY2',
      protocol: ProxyProtocol.hysteria2,
      server: 'hy2.example.com',
      port: 443,
      password: 'secret',
      sni: 'cdn.example.com',
      tlsInsecure: true,
      alpn: 'h3,h2',
      network: 'udp',
      hy2UpMbps: 100,
      hy2DownMbps: 500,
      hy2Obfs: 'salamander',
      hy2ObfsPassword: 'obfs-secret',
      hy2ServerPorts: '20000:30000,443',
      hy2HopInterval: '30s',
      hy2HopIntervalMax: '60s',
      hy2BbrProfile: 'aggressive',
      hy2DisableChromeParrot: true,
    );

    final config = jsonDecode(
      SingBoxConfigBuilder.fromNode(node, mode: '全局模式'),
    ) as Map<String, dynamic>;
    final outbound = (config['outbounds'] as List).first as Map<String, dynamic>;
    final tls = outbound['tls'] as Map<String, dynamic>;

    expect(outbound['type'], 'hysteria2');
    expect(outbound['up_mbps'], 100);
    expect(outbound['down_mbps'], 500);
    expect(outbound['network'], 'udp');
    expect(outbound['server_ports'], ['20000:30000', '443']);
    expect(outbound['hop_interval'], '30s');
    expect(outbound['hop_interval_max'], '60s');
    expect(outbound['bbr_profile'], 'aggressive');
    expect(outbound['disable_chrome_parrot'], true);
    expect(outbound['obfs'], {
      'type': 'salamander',
      'password': 'obfs-secret',
    });
    expect(tls['server_name'], 'cdn.example.com');
    expect(tls['insecure'], true);
    expect(tls['alpn'], ['h3', 'h2']);
  });

  test('Snell advanced client fields are emitted', () {
    final node = ProxyNode(
      id: 'snell-advanced',
      name: 'Snell v6',
      protocol: ProxyProtocol.snell,
      server: 'snell.example.com',
      port: 443,
      password: '123456789012',
      snellVersion: 6,
      snellReuse: false,
      snellUserKey: 'user-secret',
      snellMode: 'unshaped',
      network: 'tcp',
    );

    final config = jsonDecode(
      SingBoxConfigBuilder.fromNode(node, mode: '全局模式'),
    ) as Map<String, dynamic>;
    final outbound = (config['outbounds'] as List).first as Map<String, dynamic>;

    expect(outbound['type'], 'snell');
    expect(outbound['version'], 6);
    expect(outbound['reuse'], false);
    expect(outbound['userkey'], 'user-secret');
    expect(outbound['mode'], 'unshaped');
    expect(outbound['network'], 'tcp');
  });


  test('HY2 share link imports skip-certificate and advanced options', () {
    final node = QrPayloadParser.parse(
      'hy2://secret@hy2.example.com:443?sni=cdn.example.com&insecure=1&alpn=h3&obfs=salamander&obfs-password=mask&upmbps=120&downmbps=600&mport=20000%3A30000&hop-interval=30s#HY2',
    );

    expect(node.protocol, ProxyProtocol.hysteria2);
    expect(node.tlsInsecure, true);
    expect(node.sni, 'cdn.example.com');
    expect(node.alpn, 'h3');
    expect(node.hy2Obfs, 'salamander');
    expect(node.hy2ObfsPassword, 'mask');
    expect(node.hy2UpMbps, 120);
    expect(node.hy2DownMbps, 600);
    expect(node.hy2ServerPorts, '20000:30000');
    expect(node.hy2HopInterval, '30s');
  });

}
