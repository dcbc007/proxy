import 'dart:io';
import '../lib/models/proxy_node.dart';
import '../lib/services/singbox_config_builder.dart';

void main(List<String> args) {
  final node = ProxyNode(
    id: 'bootstrap', name: 'Bootstrap TLS test',
    protocol: ProxyProtocol.hysteria2, server: 'hy2.aurum.test',
    port: int.parse(args[1]), password: 'bootstrap-test-password',
  );
  File(args[0]).writeAsStringSync(SingBoxConfigBuilder.fromNode(
    node, mode: '全局模式', transportProxyOnly: true,
    systemCaBundlePath: args[2],
  ));
}
