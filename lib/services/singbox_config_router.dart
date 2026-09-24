import 'dart:convert';

class SingBoxConfigRouter {
  static String apply(
    String raw, {
    String mode = '智能模式',
    String geoDir = '',
  }) {
    final root = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final outbounds = ((root['outbounds'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (!outbounds.any((o) => o['tag']?.toString() == 'direct')) {
      outbounds.add({'type': 'direct', 'tag': 'direct'});
    }
    root['outbounds'] = outbounds;

    final route = <String, dynamic>{};
    switch (mode) {
      case '直连模式':
        route['final'] = 'direct';
        break;
      case '全局模式':
        route['final'] = _proxyTag(outbounds);
        break;
      default:
        final proxy = _proxyTag(outbounds);
        route['final'] = proxy;
        route['rules'] = [
          {
            'ip_is_private': true,
            'action': 'route',
            'outbound': 'direct',
          },
          {
            'rule_set': ['geosite-cn', 'geoip-cn'],
            'action': 'route',
            'outbound': 'direct',
          },
        ];
        route['rule_set'] = geoDir.isNotEmpty
            ? [
                {
                  'type': 'local',
                  'tag': 'geosite-cn',
                  'format': 'binary',
                  'path': '$geoDir/geosite-geolocation-cn.srs',
                },
                {
                  'type': 'local',
                  'tag': 'geoip-cn',
                  'format': 'binary',
                  'path': '$geoDir/geoip-cn.srs',
                },
              ]
            : [
                {
                  'type': 'remote',
                  'tag': 'geosite-cn',
                  'format': 'binary',
                  'url':
                      'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs',
                  'download_detour': 'direct',
                  'update_interval': '1d',
                },
                {
                  'type': 'remote',
                  'tag': 'geoip-cn',
                  'format': 'binary',
                  'url':
                      'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs',
                  'download_detour': 'direct',
                  'update_interval': '1d',
                },
              ];
        break;
    }

    final oldRoute = root['route'];
    if (oldRoute is Map) {
      for (final e in oldRoute.entries) {
        final key = e.key.toString();
        if (!route.containsKey(key) &&
            key != 'rules' &&
            key != 'rule_set' &&
            key != 'final' &&
            key != 'auto_detect_interface') {
          route[key] = e.value;
        }
      }
    }
    root['route'] = route;
    return jsonEncode(root);
  }

  static String _proxyTag(List<Map<String, dynamic>> outbounds) {
    for (final o in outbounds) {
      final tag = o['tag']?.toString() ?? '';
      final type = o['type']?.toString().toLowerCase() ?? '';
      if (tag != 'direct' && type != 'direct' && tag.isNotEmpty) return tag;
    }
    if (outbounds.isNotEmpty) {
      outbounds.first['tag'] = 'proxy';
      return 'proxy';
    }
    return 'proxy';
  }
}
