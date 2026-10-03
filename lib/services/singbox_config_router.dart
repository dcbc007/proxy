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

    // Android owns the TUN. The native Xray edge performs the first
    // Smart/Global/Direct split; proxy-bound traffic and DNS arrive here.
    root['inbounds'] = [
      {
        'type': 'mixed',
        'tag': 'mixed-in',
        'listen': '127.0.0.1',
        'listen_port': 10808,
      },
    ];
    root['log'] = {'level': 'warn', 'timestamp': false};

    final proxyTag = _proxyTag(outbounds);
    final smartMode = mode == '智能模式';
    final directMode = mode == '直连模式';

    // Stable China-client DNS pattern:
    // - known CN domains use AliDNS directly;
    // - known non-CN domains use Cloudflare through the selected proxy;
    // - unknown domains fall back to the proxied resolver without a blocking
    //   evaluate/respond probe.
    root['dns'] = {
      'servers': [
        {
          'type': 'https',
          'tag': 'dns-cn',
          'server': '223.5.5.5',
          'server_port': 443,
          'path': '/dns-query',
          'tls': {
            'enabled': true,
            'server_name': 'dns.alidns.com',
          },
        },
        {
          'type': 'https',
          'tag': 'dns-remote',
          'server': '1.1.1.1',
          'server_port': 443,
          'path': '/dns-query',
          'detour': proxyTag,
        },
      ],
      'final': directMode ? 'dns-cn' : 'dns-remote',
      'strategy': 'prefer_ipv4',
      if (smartMode)
        'rules': [
          {
            'domain_suffix': ['.cn'],
            'action': 'route',
            'server': 'dns-cn',
          },
          {
            'rule_set': ['geosite-cn'],
            'action': 'route',
            'server': 'dns-cn',
          },
          {
            'rule_set': ['geosite-geolocation-!cn'],
            'action': 'route',
            'server': 'dns-remote',
          },
        ],
    };

    final route = <String, dynamic>{
      'default_domain_resolver': 'dns-cn',
    };

    switch (mode) {
      case '直连模式':
        route['rules'] = [
          {
            'type': 'logical',
            'mode': 'or',
            'rules': [
              {'protocol': 'dns'},
              {'port': 53},
            ],
            'action': 'hijack-dns',
          },
        ];
        route['final'] = 'direct';
        break;

      case '全局模式':
        route['rules'] = [
          {'action': 'sniff'},
          {
            'type': 'logical',
            'mode': 'or',
            'rules': [
              {'protocol': 'dns'},
              {'port': 53},
            ],
            'action': 'hijack-dns',
          },
        ];
        route['final'] = proxyTag;
        break;

      default:
        route['rules'] = [
          // Required when the upstream TUN bridge hands sing-box an IP
          // destination. This restores the TLS/HTTP domain before geosite
          // matching and is part of sing-box's official China-client example.
          {'action': 'sniff'},
          {
            'type': 'logical',
            'mode': 'or',
            'rules': [
              {'protocol': 'dns'},
              {'port': 53},
            ],
            'action': 'hijack-dns',
          },
          {
            'ip_is_private': true,
            'action': 'route',
            'outbound': 'direct',
          },
          {
            'domain_suffix': ['.cn'],
            'action': 'route',
            'outbound': 'direct',
          },
          {
            'rule_set': ['geosite-cn'],
            'action': 'route',
            'outbound': 'direct',
          },
          {
            'rule_set': ['geoip-cn'],
            'action': 'route',
            'outbound': 'direct',
          },
        ];
        route['rule_set'] = _smartRuleSets(geoDir);
        route['final'] = proxyTag;
        break;
    }

    // Preserve unrelated parser-generated route options, but never preserve
    // another set of rules/final/rule-sets that could override our mode.
    final oldRoute = root['route'];
    if (oldRoute is Map) {
      for (final e in oldRoute.entries) {
        final key = e.key.toString();
        if (!route.containsKey(key) &&
            key != 'rules' &&
            key != 'rule_set' &&
            key != 'final' &&
            key != 'auto_detect_interface' &&
            key != 'default_domain_resolver') {
          route[key] = e.value;
        }
      }
    }

    root['route'] = route;
    root['experimental'] = {
      'cache_file': {'enabled': true},
      'clash_api': {'external_controller': '127.0.0.1:9090'},
    };
    return jsonEncode(root);
  }

  static List<Map<String, dynamic>> _smartRuleSets(String geoDir) {
    if (geoDir.isNotEmpty) {
      return [
        {
          'type': 'local',
          'tag': 'geoip-cn',
          'format': 'binary',
          'path': '$geoDir/geoip-cn.srs',
        },
        {
          'type': 'local',
          'tag': 'geosite-cn',
          'format': 'binary',
          'path': '$geoDir/geosite-cn.srs',
        },
        {
          'type': 'local',
          'tag': 'geosite-geolocation-!cn',
          'format': 'binary',
          'path': '$geoDir/geosite-geolocation-!cn.srs',
        },
      ];
    }

    return [
      {
        'type': 'remote',
        'tag': 'geoip-cn',
        'format': 'binary',
        'url':
            'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs',
        'update_interval': '1d',
      },
      {
        'type': 'remote',
        'tag': 'geosite-cn',
        'format': 'binary',
        'url':
            'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs',
        'update_interval': '1d',
      },
      {
        'type': 'remote',
        'tag': 'geosite-geolocation-!cn',
        'format': 'binary',
        'url':
            'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-!cn.srs',
        'update_interval': '1d',
      },
    ];
  }

  static String _proxyTag(List<Map<String, dynamic>> outbounds) {
    for (final o in outbounds) {
      final tag = o['tag']?.toString() ?? '';
      final type = o['type']?.toString().toLowerCase() ?? '';
      if (tag != 'direct' &&
          type != 'direct' &&
          type != 'block' &&
          type != 'dns' &&
          tag.isNotEmpty) {
        return tag;
      }
    }
    if (outbounds.isNotEmpty) {
      outbounds.first['tag'] = 'proxy';
      return 'proxy';
    }
    return 'proxy';
  }
}
