import 'dart:convert';
import '../models/proxy_node.dart';

class QrPayloadParser {
  static const _schemes = ['ss://', 'vless://', 'vmess://', 'trojan://', 'hysteria2://', 'hy2://', 'snell://'];

  static bool looksLikeNode(String value) {
    final v = value.trim().toLowerCase();
    return _schemes.any(v.startsWith);
  }

  static ProxyNode parse(String input) {
    final raw = input.trim();
    if (raw.startsWith('ss://')) return _parseSs(raw);
    if (raw.startsWith('vless://')) return _parseUri(raw, ProxyProtocol.vless);
    if (raw.startsWith('trojan://')) return _parseUri(raw, ProxyProtocol.trojan);
    if (raw.startsWith('hysteria2://') || raw.startsWith('hy2://')) {
      return _parseUri(raw, ProxyProtocol.hysteria2);
    }
    if (raw.startsWith('snell://')) return _parseUri(raw, ProxyProtocol.snell);
    if (raw.startsWith('vmess://')) return _parseVmess(raw);
    throw const FormatException('不支持的节点二维码/链接');
  }

  static ProxyNode _parseUri(String raw, ProxyProtocol protocol) {
    final uri = Uri.parse(raw);
    final query = uri.queryParameters;
    final userInfo = Uri.decodeComponent(uri.userInfo);
    if (uri.host.isEmpty || uri.port <= 0) throw const FormatException('节点地址或端口无效');
    return ProxyNode(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: uri.fragment.isEmpty ? '${protocol.label} 节点' : Uri.decodeComponent(uri.fragment),
      protocol: protocol,
      server: uri.host,
      port: uri.port,
      password: protocol == ProxyProtocol.trojan || protocol == ProxyProtocol.hysteria2 || protocol == ProxyProtocol.snell ? userInfo : '',
      uuid: protocol == ProxyProtocol.vless ? userInfo : '',
      transport: query['type'] ?? query['transport'] ?? 'tcp',
      security: query['security'] ?? '',
      sni: query['sni'] ?? query['peer'] ?? '',
      path: query['serviceName'] ?? query['service_name'] ?? query['path'] ?? '',
      publicKey: query['pbk'] ?? query['publicKey'] ?? '',
      shortId: query['sid'] ?? query['shortId'] ?? '',
      flow: query['flow'] ?? '',
      fingerprint: query['fp'] ?? 'chrome',
      network: query['network'] ?? '',
      tlsInsecure: _truthy(query['insecure']) ||
          _truthy(query['allowInsecure']) ||
          _truthy(query['skip-cert-verify']),
      alpn: query['alpn'] ?? '',
      host: query['host'] ?? '',
      packetEncoding: query['packetEncoding'] ?? query['packet_encoding'] ?? '',
      hy2UpMbps: protocol == ProxyProtocol.hysteria2
          ? _intParam(query, ['upmbps', 'up_mbps'])
          : 0,
      hy2DownMbps: protocol == ProxyProtocol.hysteria2
          ? _intParam(query, ['downmbps', 'down_mbps'])
          : 0,
      hy2Obfs: protocol == ProxyProtocol.hysteria2 ? (query['obfs'] ?? '') : '',
      hy2ObfsPassword: protocol == ProxyProtocol.hysteria2
          ? (query['obfs-password'] ?? query['obfs_password'] ?? query['obfsPassword'] ?? '')
          : '',
      hy2ServerPorts: protocol == ProxyProtocol.hysteria2
          ? (query['mport'] ?? query['server_ports'] ?? '')
          : '',
      hy2HopInterval: protocol == ProxyProtocol.hysteria2
          ? (query['hop-interval'] ?? query['hop_interval'] ?? '')
          : '',
      hy2HopIntervalMax: protocol == ProxyProtocol.hysteria2
          ? (query['hop-interval-max'] ?? query['hop_interval_max'] ?? '')
          : '',
      hy2BbrProfile: protocol == ProxyProtocol.hysteria2
          ? (query['bbr-profile'] ?? query['bbr_profile'] ?? '')
          : '',
      hy2DisableChromeParrot: protocol == ProxyProtocol.hysteria2 &&
          (_truthy(query['disable-chrome-parrot']) ||
              _truthy(query['disable_chrome_parrot'])),
      snellVersion: protocol == ProxyProtocol.snell
          ? (int.tryParse(query['version'] ?? '') ?? 5)
          : 5,
      snellReuse: protocol != ProxyProtocol.snell || query['reuse'] == null
          ? true
          : _truthy(query['reuse']),
      snellUserKey: protocol == ProxyProtocol.snell ? (query['userkey'] ?? '') : '',
      snellObfsMode: protocol == ProxyProtocol.snell ? (query['obfs_mode'] ?? 'none') : 'none',
      snellObfsHost: protocol == ProxyProtocol.snell ? (query['obfs_host'] ?? '') : '',
      snellMode: protocol == ProxyProtocol.snell ? (query['mode'] ?? 'default') : 'default',
      sourceLink: raw,
    );
  }

  static bool _truthy(String? value) {
    if (value == null) return false;
    final v = value.trim().toLowerCase();
    return v == '1' || v == 'true' || v == 'yes' || v == 'on';
  }

  static int _intParam(Map<String, String> query, List<String> keys) {
    for (final key in keys) {
      final value = int.tryParse(query[key] ?? '');
      if (value != null) return value;
    }
    return 0;
  }

  static ProxyNode _parseSs(String raw) {
    final uri = Uri.parse(raw);
    final name = uri.fragment.isEmpty ? 'Shadowsocks 节点' : Uri.decodeComponent(uri.fragment);
    var userInfo = uri.userInfo;
    String method = '';
    String password = '';

    if (userInfo.contains(':')) {
      final split = userInfo.split(':');
      method = Uri.decodeComponent(split.first);
      password = Uri.decodeComponent(split.sublist(1).join(':'));
    } else if (userInfo.isNotEmpty) {
      final decoded = utf8.decode(base64Url.decode(base64Url.normalize(userInfo)));
      final idx = decoded.indexOf(':');
      if (idx <= 0) throw const FormatException('Shadowsocks 认证信息无效');
      method = decoded.substring(0, idx);
      password = decoded.substring(idx + 1);
    } else {
      // Legacy ss://BASE64(method:password@host:port)
      final body = raw.substring(5).split('#').first.split('?').first;
      final decoded = utf8.decode(base64Url.decode(base64Url.normalize(body)));
      final legacy = Uri.parse('ss://$decoded');
      final auth = legacy.userInfo.split(':');
      if (auth.length < 2) throw const FormatException('Shadowsocks 链接无效');
      return ProxyNode(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        protocol: ProxyProtocol.shadowsocks,
        server: legacy.host,
        port: legacy.port,
        method: auth.first,
        password: auth.sublist(1).join(':'),
        sourceLink: raw,
      );
    }

    final pluginRaw = uri.queryParameters['plugin'] ?? '';
    final pluginParts = pluginRaw.isEmpty ? <String>[] : pluginRaw.split(';');
    return ProxyNode(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      protocol: ProxyProtocol.shadowsocks,
      server: uri.host,
      port: uri.port,
      method: method,
      password: password,
      plugin: pluginParts.isEmpty ? '' : pluginParts.first,
      pluginOpts: pluginParts.length <= 1 ? '' : pluginParts.sublist(1).join(';'),
      network: uri.queryParameters['network'] ?? '',
      sourceLink: raw,
    );
  }

  static ProxyNode _parseVmess(String raw) {
    final b64 = raw.substring(8).trim();
    final json = utf8.decode(base64Url.decode(base64Url.normalize(b64)));
    final j = jsonDecode(json) as Map<String, dynamic>;
    return ProxyNode(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: j['ps']?.toString() ?? 'VMess 节点',
      protocol: ProxyProtocol.vmess,
      server: j['add']?.toString() ?? '',
      port: int.tryParse(j['port']?.toString() ?? '') ?? 0,
      uuid: j['id']?.toString() ?? '',
      transport: j['net']?.toString() ?? 'tcp',
      security: j['tls']?.toString() ?? '',
      sni: j['sni']?.toString() ?? '',
      path: j['path']?.toString() ?? '',
      host: j['host']?.toString() ?? '',
      alpn: j['alpn']?.toString() ?? '',
      fingerprint: j['fp']?.toString() ?? 'chrome',
      tlsInsecure: j['allowInsecure'] == true ||
          j['allowInsecure'] == 1 ||
          j['allowInsecure']?.toString() == '1',
      packetEncoding: j['packetEncoding']?.toString() ?? '',
      vmessSecurity: j['scy']?.toString() ?? 'auto',
      alterId: int.tryParse(j['aid']?.toString() ?? '') ?? 0,
      sourceLink: raw,
    );
  }
}
