import 'dart:convert';
import 'dart:io';
import '../lib/services/singbox_config_router.dart';
void main(List<String> args) {
  final config = {
    'inbounds': [{'type': 'tun', 'auto_route': true}],
    'outbounds': [{
      'type': 'hysteria2', 'tag': 'proxy', 'server': '127.0.0.1',
      'server_port': int.parse(args[1]), 'password': 'test-password',
      'tls': {'enabled': true, 'insecure': true},
      'obfs': {'type': 'salamander', 'password': 'test-obfs'},
    }],
  };
  File(args[0]).writeAsStringSync(SingBoxConfigRouter.apply(
    jsonEncode(config), mode: '全局模式'));
}
