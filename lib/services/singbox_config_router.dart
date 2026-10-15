import 'dart:convert';

class SingBoxConfigRouter {
  static String apply(
    String raw, {
    String mode = '智能模式',
    String geoDir = '',
    bool transportProxyOnly = false,
    String systemCaBundlePath = '',
  }) {
    final root = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final outbounds = ((root['outbounds'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (!outbounds.any((o) => o['tag']?.toString() == 'direct')) {
      outbounds.add({'type': 'direct', 'tag': 'direct'});
    }
    root['outbounds'] = outbounds;

    // Android owns the TUN. Xray is transport-only and forwards every
    // TCP/UDP flow to this mixed inbound. sing-box is the only routing core.
    root['inbounds'] = [
      {
        'type': 'mixed',
        'tag': 'mixed-in',
        'listen': '127.0.0.1',
        'listen_port': 10808,
      },
    ];
    root['log'] = {'level': 'warn', 'timestamp': false, 'disabled': false};

    _applyAndroidSystemCa(root, outbounds, systemCaBundlePath);
    root['outbounds'] = outbounds;

    final proxyTag = _proxyTag(outbounds);
    final smartMode = mode == '智能模式';
    final directMode = mode == '直连模式';

    // Android 1.3.0 architecture: sing-box is transport-only.
    // Xray owns TUN, Direct, Smart Geo routing and DNS interception.
    // sing-box must never decide "direct" for application traffic on Android.
    if (transportProxyOnly) {
      final marker = switch (mode) {
        '直连模式' => 'aurum-mode-direct',
        '全局模式' => 'aurum-mode-global',
        _ => 'aurum-mode-smart',
      };

      if (!outbounds.any((o) => o['tag'] == marker)) {
        outbounds.add({'type': 'direct', 'tag': marker});
      }
      root['outbounds'] = outbounds;

      // App DNS routing remains owned by Xray. The standalone Android core
      // still needs bootstrap DNS to resolve the proxy SERVER before it can
      // establish any tunnel. Go's system resolver can fall back to [::1]:53
      // on Android, where no DNS listener exists. Use an IP-addressed resolver
      // independent of the selected proxy to avoid a bootstrap dependency loop.
      root['dns'] = {
        'servers': [
          {
            'type': 'udp',
            'tag': 'dns-bootstrap',
            'server': '223.5.5.5',
            'server_port': 53,
          },
        ],
        'final': 'dns-bootstrap',
        'strategy': 'prefer_ipv4',
      };
      for (final outbound in outbounds) {
        final server = outbound['server']?.toString().trim() ?? '';
        if (server.isNotEmpty && !_isIpLiteral(server)) {
          outbound['domain_resolver'] = 'dns-bootstrap';
        }
      }
      root['route'] = {
        'default_domain_resolver': 'dns-bootstrap',
        'rules': const <Map<String, dynamic>>[],
        'final': proxyTag,
      };
      root['experimental'] = {
        'cache_file': {'enabled': true},
        'clash_api': {'external_controller': '127.0.0.1:9090'},
      };
      return jsonEncode(root);
    }

    // Official sing-box China-client pattern:
    // - China DNS goes directly to AliDNS.
    // - Foreign DNS goes through the selected proxy.
    // - Unknown domains are probed with China DNS; a CN answer is accepted,
    //   otherwise they fall back to the proxied resolver.
    root['dns'] = {
      'servers': [
        {
          'type': 'udp',
          'tag': 'dns-cn',
          'server': '223.5.5.5',
          'server_port': 53,
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
            'rule_set': ['geosite-geolocation-cn'],
            'action': 'route',
            'server': 'dns-cn',
          },
          {
            'rule_set': ['geosite-geolocation-!cn'],
            'action': 'route',
            'server': 'dns-remote',
          },
          {
            'action': 'evaluate',
            'server': 'dns-cn',
            'tag': 'cn-probe',
          },
          {
            'match_response': 'cn-probe',
            'rule_set': ['geoip-cn'],
            'action': 'respond',
          },
          {
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
            'rule_set': ['geosite-geolocation-cn'],
            'action': 'route',
            'outbound': 'direct',
          },
          {
            'type': 'logical',
            'mode': 'and',
            'rules': [
              {'rule_set': ['geoip-cn']},
              {
                'rule_set': ['geosite-geolocation-!cn'],
                'invert': true,
              },
            ],
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

  static void _applyAndroidSystemCa(
    Map<String, dynamic> root,
    List<Map<String, dynamic>> outbounds,
    String systemCaBundlePath,
  ) {
    final caPath = systemCaBundlePath.trim();

    // Use sing-box's global certificate store instead of replacing RootCAs on
    // every outbound. The global store augments the platform/system pool with
    // the CA bundle exported by Android and is the intended 1.12+ mechanism.
    if (caPath.isNotEmpty) {
      root['certificate'] = {
        'store': 'system',
        'certificate_path': [caPath],
      };
    }

    for (final outbound in outbounds) {
      final rawTls = outbound['tls'];
      if (rawTls is! Map) continue;

      final tls = Map<String, dynamic>.from(rawTls);
      if (tls['enabled'] == false || tls['insecure'] == true) continue;

      final reality = tls['reality'];
      if (reality is Map && reality['enabled'] == true) continue;

      // Do not inject certificate_path here: outbound certificate_path
      // replaces the RootCA pool. Trust is configured globally above.
      final serverName = tls['server_name']?.toString().trim() ?? '';
      final server = outbound['server']?.toString().trim() ?? '';
      if (serverName.isEmpty && server.isNotEmpty && !_isIpLiteral(server)) {
        tls['server_name'] = server;
      }

      outbound['tls'] = tls;
    }
  }

  static bool _isIpLiteral(String value) {
    var v = _stripIpv6Brackets(value.trim());
    final zone = v.indexOf('%');
    if (zone >= 0) v = v.substring(0, zone);
    if (v.contains(':')) return true;
    final parts = v.split('.');
    return parts.length == 4 &&
        parts.every((p) {
          final n = int.tryParse(p);
          return n != null && n >= 0 && n <= 255;
        });
  }

  static String _stripIpv6Brackets(String value) {
    final v = value.trim();
    if (v.length >= 2 && v.startsWith('[') && v.endsWith(']')) {
      return v.substring(1, v.length - 1);
    }
    return v;
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
          'tag': 'geosite-geolocation-cn',
          'format': 'binary',
          'path': '$geoDir/geosite-geolocation-cn.srs',
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
        'tag': 'geosite-geolocation-cn',
        'format': 'binary',
        'url':
            'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs',
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

