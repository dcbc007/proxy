import 'dart:convert';

import 'singbox_config_router.dart';

class SingBoxChainConfig {
  static String merge(
    String primaryRaw,
    String preProxyRaw, {
    String mode = '智能模式',
    String geoDir = '',
  }) {
    final primary = _firstProxyOutbound(primaryRaw, 'proxy');
    final preProxy = _firstProxyOutbound(preProxyRaw, 'preproxy');
    primary['detour'] = 'preproxy';

    final root = <String, dynamic>{
      'log': {'level': 'warn'},
      'inbounds': [
        {
          'type': 'mixed',
          'tag': 'mixed-in',
          'listen': '127.0.0.1',
          'listen_port': 10808,
        },
      ],
      'outbounds': [
        primary,
        preProxy,
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {'final': 'proxy'},
    };

    return SingBoxConfigRouter.apply(
      jsonEncode(root),
      mode: mode,
      geoDir: geoDir,
    );
  }

  static Map<String, dynamic> _firstProxyOutbound(
    String raw,
    String tag,
  ) {
    final root = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final list = (root['outbounds'] as List?) ?? const [];
    for (final item in list) {
      if (item is! Map) continue;
      final outbound = Map<String, dynamic>.from(item);
      final type = outbound['type']?.toString().toLowerCase() ?? '';
      if (type == 'direct' ||
          type == 'block' ||
          type == 'dns' ||
          type == 'selector' ||
          type == 'urltest') {
        continue;
      }
      outbound['tag'] = tag;
      outbound.remove('domain_resolver');
      outbound.remove('detour');
      return outbound;
    }
    throw StateError('未找到可用代理出站');
  }
}
