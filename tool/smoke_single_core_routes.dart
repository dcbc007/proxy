import 'dart:io';

import 'package:aurum_proxy/services/singbox_config_router.dart';

void main(List<String> args) {
  final prefix = args.isEmpty ? '/tmp/aurum-single-core' : args.first;
  final geoDir = '${Directory.current.path}/assets/geo';
  const raw = r'''
{
  "log": {"level": "warn"},
  "inbounds": [
    {"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": 10808}
  ],
  "outbounds": [
    {
      "type": "socks",
      "tag": "proxy",
      "server": "127.0.0.1",
      "server_port": 2080,
      "version": "5"
    }
  ]
}
''';

  for (final entry in const {
    'smart': '智能模式',
    'global': '全局模式',
    'direct': '直连模式',
  }.entries) {
    final json = SingBoxConfigRouter.apply(
      raw,
      mode: entry.value,
      geoDir: entry.key == 'smart' ? geoDir : '',
    );
    File('$prefix-${entry.key}.json').writeAsStringSync(json);
  }
}
