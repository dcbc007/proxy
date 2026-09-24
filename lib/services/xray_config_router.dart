import 'dart:convert';

class XrayConfigRouter {
  static String apply(String raw, String mode) {
    final root = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final outbounds = ((root['outbounds'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (outbounds.isEmpty) return raw;

    final proxyTag = (outbounds.first['tag']?.toString().trim().isNotEmpty ?? false)
        ? outbounds.first['tag'].toString()
        : 'proxy';
    outbounds.first['tag'] = proxyTag;

    var hasDirect = false;
    for (final o in outbounds) {
      final protocol = o['protocol']?.toString().toLowerCase();
      final tag = o['tag']?.toString();
      if (protocol == 'freedom' || tag == 'direct') {
        o['tag'] = 'direct';
        hasDirect = true;
      }
    }
    if (!hasDirect) {
      outbounds.add({
        'tag': 'direct',
        'protocol': 'freedom',
        'settings': <String, dynamic>{},
      });
    }
    root['outbounds'] = outbounds;

    final rules = <Map<String, dynamic>>[];
    switch (mode) {
      case '直连模式':
        rules.add({
          'type': 'field',
          'network': 'tcp,udp',
          'outboundTag': 'direct',
        });
        break;
      case '全局模式':
        // First outbound is the selected proxy. No routing rule means all
        // unmatched traffic uses it.
        break;
      default:
        rules.addAll([
          {
            'type': 'field',
            'ip': ['geoip:private'],
            'outboundTag': 'direct',
          },
          {
            'type': 'field',
            'domain': ['geosite:cn'],
            'outboundTag': 'direct',
          },
          {
            'type': 'field',
            'ip': ['geoip:cn'],
            'outboundTag': 'direct',
          },
        ]);
        break;
    }

    root['routing'] = {
      'domainStrategy': 'IPIfNonMatch',
      'rules': rules,
    };
    return jsonEncode(root);
  }
}
