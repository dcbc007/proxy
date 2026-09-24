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
      path: query['path'] ?? '',
      publicKey: query['pbk'] ?? query['publicKey'] ?? '',
      shortId: query['sid'] ?? query['shortId'] ?? '',
      flow: query['flow'] ?? '',
      fingerprint: query['fp'] ?? 'chrome',
      snellVersion: protocol == ProxyProtocol.snell
          ? (int.tryParse(query['version'] ?? '') ?? 5)
          : 5,
      sourceLink: raw,
    );
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

    return ProxyNode(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      protocol: ProxyProtocol.shadowsocks,
      server: uri.host,
      port: uri.port,
      method: method,
      password: password,
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
      sourceLink: raw,
    );
  }
}
