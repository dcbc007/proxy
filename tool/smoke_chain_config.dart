import 'dart:io';

import '../lib/services/singbox_chain_config.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    throw ArgumentError('output path required');
  }
  const primary = '''
{"outbounds":[{"type":"vless","tag":"main","server":"127.0.0.1","server_port":443,"uuid":"11111111-1111-1111-1111-111111111111"}]}
''';
  const preProxy = '''
{"outbounds":[{"type":"shadowsocks","tag":"front","server":"127.0.0.1","server_port":8388,"method":"aes-256-gcm","password":"0123456789abcdef"}]}
''';
  final config = SingBoxChainConfig.merge(
    primary,
    preProxy,
    mode: '全局模式',
  );
  File(args.first).writeAsStringSync(config);
}
