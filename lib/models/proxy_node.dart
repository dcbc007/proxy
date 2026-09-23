import 'dart:convert';

enum ProxyProtocol {
  shadowsocks('Shadowsocks'),
  vless('VLESS'),
  vmess('VMess'),
  trojan('Trojan'),
  hysteria2('Hysteria2'),
  snell('Snell');

  const ProxyProtocol(this.label);
  final String label;

  static ProxyProtocol fromString(String value) {
    final v = value.toLowerCase();
    if (v == 'ss' || v == 'shadowsocks') return shadowsocks;
    if (v == 'vless') return vless;
    if (v == 'vmess') return vmess;
    if (v == 'trojan') return trojan;
    if (v == 'hysteria2' || v == 'hy2') return hysteria2;
    if (v == 'snell') return snell;
    return shadowsocks;
  }
}

class ProxyNode {
  ProxyNode({
    required this.id,
    required this.name,
    required this.protocol,
    required this.server,
    required this.port,
    this.username = '',
    this.password = '',
    this.uuid = '',
    this.method = '',
    this.transport = 'tcp',
    this.security = '',
    this.sni = '',
    this.path = '',
    this.publicKey = '',
    this.shortId = '',
    this.flow = '',
    this.fingerprint = 'chrome',
    this.sourceLink = '',
    this.remark = '',
    this.favorite = false,
    this.latencyMs,
  });

  String id;
  String name;
  ProxyProtocol protocol;
  String server;
  int port;
  String username;
  String password;
  String uuid;
  String method;
  String transport;
  String security;
  String sni;
  String path;
  String publicKey;
  String shortId;
  String flow;
  String fingerprint;
  String sourceLink;
  String remark;
  bool favorite;
  int? latencyMs;

  String get connectionLink => sourceLink.trim().isNotEmpty ? sourceLink.trim() : _buildLink();

  String _buildLink() {
    final fragment = Uri.encodeComponent(name);
    switch (protocol) {
      case ProxyProtocol.shadowsocks:
        final auth = base64Url.encode(utf8.encode('$method:$password')).replaceAll('=', '');
        return 'ss://$auth@${_host(server)}:$port#$fragment';
      case ProxyProtocol.vless:
        final q = <String, String>{
          if (transport.isNotEmpty && transport != 'tcp') 'type': transport,
          if (security.isNotEmpty) 'security': security,
          if (sni.isNotEmpty) 'sni': sni,
          if (path.isNotEmpty) 'path': path,
          if (publicKey.isNotEmpty) 'pbk': publicKey,
          if (shortId.isNotEmpty) 'sid': shortId,
          if (flow.isNotEmpty) 'flow': flow,
          if (fingerprint.isNotEmpty && security.toLowerCase() == 'reality') 'fp': fingerprint,
        };
        return Uri(scheme: 'vless', userInfo: uuid, host: server, port: port, queryParameters: q.isEmpty ? null : q, fragment: name).toString();
      case ProxyProtocol.trojan:
        final q = <String, String>{
          if (transport.isNotEmpty && transport != 'tcp') 'type': transport,
          if (security.isNotEmpty) 'security': security,
          if (sni.isNotEmpty) 'sni': sni,
          if (path.isNotEmpty) 'path': path,
        };
        return Uri(scheme: 'trojan', userInfo: password, host: server, port: port, queryParameters: q.isEmpty ? null : q, fragment: name).toString();
      case ProxyProtocol.hysteria2:
        final q = <String, String>{if (sni.isNotEmpty) 'sni': sni};
        return Uri(scheme: 'hy2', userInfo: password, host: server, port: port, queryParameters: q.isEmpty ? null : q, fragment: name).toString();
      case ProxyProtocol.vmess:
        final payload = <String, dynamic>{
          'v': '2',
          'ps': name,
          'add': server,
          'port': port.toString(),
          'id': uuid,
          'aid': '0',
          'scy': 'auto',
          'net': transport.isEmpty ? 'tcp' : transport,
          'type': 'none',
          'host': '',
          'path': path,
          'tls': security.toLowerCase() == 'tls' ? 'tls' : '',
          'sni': sni,
        };
        return 'vmess://${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}';
      case ProxyProtocol.snell:
        return Uri(scheme: 'snell', userInfo: password, host: server, port: port, queryParameters: const {'version': '5'}, fragment: name).toString();
    }
  }

  static String _host(String value) => value.contains(':') && !value.startsWith('[') ? '[$value]' : value;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'protocol': protocol.name,
        'server': server,
        'port': port,
        'username': username,
        'password': password,
        'uuid': uuid,
        'method': method,
        'transport': transport,
        'security': security,
        'sni': sni,
        'path': path,
        'publicKey': publicKey,
        'shortId': shortId,
        'flow': flow,
        'fingerprint': fingerprint,
        'sourceLink': sourceLink,
        'remark': remark,
        'favorite': favorite,
        'latencyMs': latencyMs,
      };

  factory ProxyNode.fromJson(Map<String, dynamic> j) => ProxyNode(
        id: j['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: j['name']?.toString() ?? '未命名节点',
        protocol: ProxyProtocol.fromString(j['protocol']?.toString() ?? 'shadowsocks'),
        server: j['server']?.toString() ?? '',
        port: (j['port'] as num?)?.toInt() ?? int.tryParse(j['port']?.toString() ?? '') ?? 0,
        username: j['username']?.toString() ?? '',
        password: j['password']?.toString() ?? '',
        uuid: j['uuid']?.toString() ?? '',
        method: j['method']?.toString() ?? '',
        transport: j['transport']?.toString() ?? 'tcp',
        security: j['security']?.toString() ?? '',
        sni: j['sni']?.toString() ?? '',
        path: j['path']?.toString() ?? '',
        publicKey: j['publicKey']?.toString() ?? '',
        shortId: j['shortId']?.toString() ?? '',
        flow: j['flow']?.toString() ?? '',
        fingerprint: j['fingerprint']?.toString() ?? 'chrome',
        sourceLink: j['sourceLink']?.toString() ?? '',
        remark: j['remark']?.toString() ?? '',
        favorite: j['favorite'] == true,
        latencyMs: (j['latencyMs'] as num?)?.toInt(),
      );

  static String encodeList(List<ProxyNode> nodes) => jsonEncode(nodes.map((e) => e.toJson()).toList());

  static List<ProxyNode> decodeList(String raw) =>
      (jsonDecode(raw) as List).map((e) => ProxyNode.fromJson(Map<String, dynamic>.from(e as Map))).toList();
}
