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
    this.network = '',
    this.tlsInsecure = false,
    this.alpn = '',
    this.host = '',
    this.packetEncoding = '',
    this.plugin = '',
    this.pluginOpts = '',
    this.vmessSecurity = 'auto',
    this.alterId = 0,
    this.hy2UpMbps = 0,
    this.hy2DownMbps = 0,
    this.hy2Obfs = '',
    this.hy2ObfsPassword = '',
    this.hy2ServerPorts = '',
    this.hy2HopInterval = '',
    this.hy2HopIntervalMax = '',
    this.hy2BbrProfile = '',
    this.hy2DisableChromeParrot = false,
    this.snellReuse = true,
    this.snellUserKey = '',
    this.snellObfsMode = 'none',
    this.snellObfsHost = '',
    this.snellMode = 'default',
    this.sourceLink = '',
    this.remark = '',
    this.favorite = false,
    this.latencyMs,
    this.snellVersion = 5,
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
  String network;
  bool tlsInsecure;
  String alpn;
  String host;
  String packetEncoding;
  String plugin;
  String pluginOpts;
  String vmessSecurity;
  int alterId;
  int hy2UpMbps;
  int hy2DownMbps;
  String hy2Obfs;
  String hy2ObfsPassword;
  String hy2ServerPorts;
  String hy2HopInterval;
  String hy2HopIntervalMax;
  String hy2BbrProfile;
  bool hy2DisableChromeParrot;
  bool snellReuse;
  String snellUserKey;
  String snellObfsMode;
  String snellObfsHost;
  String snellMode;
  String sourceLink;
  String remark;
  bool favorite;
  int? latencyMs;
  int snellVersion;

  String get connectionLink => sourceLink.trim().isNotEmpty ? sourceLink.trim() : _buildLink();

  String _buildLink() {
    final fragment = Uri.encodeComponent(name);
    switch (protocol) {
      case ProxyProtocol.shadowsocks:
        final auth = base64Url.encode(utf8.encode('$method:$password')).replaceAll('=', '');
        final pluginValue = plugin.isEmpty
            ? ''
            : (pluginOpts.isEmpty ? plugin : '$plugin;$pluginOpts');
        final q = <String, String>{
          if (pluginValue.isNotEmpty) 'plugin': pluginValue,
          if (network.isNotEmpty) 'network': network,
        };
        return Uri(
          scheme: 'ss',
          userInfo: auth,
          host: server,
          port: port,
          queryParameters: q.isEmpty ? null : q,
          fragment: name,
        ).toString();
      case ProxyProtocol.vless:
        final q = <String, String>{
          if (transport.isNotEmpty && transport != 'tcp') 'type': transport,
          if (security.isNotEmpty) 'security': security,
          if (sni.isNotEmpty) 'sni': sni,
          if (tlsInsecure) 'allowInsecure': '1',
          if (alpn.isNotEmpty) 'alpn': alpn,
          if (host.isNotEmpty) 'host': host,
          if (transport == 'grpc' && path.isNotEmpty) 'serviceName': path,
          if (transport != 'grpc' && path.isNotEmpty) 'path': path,
          if (publicKey.isNotEmpty) 'pbk': publicKey,
          if (shortId.isNotEmpty) 'sid': shortId,
          if (flow.isNotEmpty) 'flow': flow,
          if (fingerprint.isNotEmpty && security.isNotEmpty) 'fp': fingerprint,
          if (packetEncoding.isNotEmpty) 'packetEncoding': packetEncoding,
          if (network.isNotEmpty) 'network': network,
        };
        return Uri(scheme: 'vless', userInfo: uuid, host: server, port: port, queryParameters: q.isEmpty ? null : q, fragment: name).toString();
      case ProxyProtocol.trojan:
        final q = <String, String>{
          if (transport.isNotEmpty && transport != 'tcp') 'type': transport,
          if (security.isNotEmpty) 'security': security,
          if (sni.isNotEmpty) 'sni': sni,
          if (tlsInsecure) 'allowInsecure': '1',
          if (alpn.isNotEmpty) 'alpn': alpn,
          if (fingerprint.isNotEmpty && security.isNotEmpty) 'fp': fingerprint,
          if (host.isNotEmpty) 'host': host,
          if (transport == 'grpc' && path.isNotEmpty) 'serviceName': path,
          if (transport != 'grpc' && path.isNotEmpty) 'path': path,
          if (network.isNotEmpty) 'network': network,
        };
        return Uri(scheme: 'trojan', userInfo: password, host: server, port: port, queryParameters: q.isEmpty ? null : q, fragment: name).toString();
      case ProxyProtocol.hysteria2:
        final q = <String, String>{
          if (sni.isNotEmpty) 'sni': sni,
          if (tlsInsecure) 'insecure': '1',
          if (alpn.isNotEmpty) 'alpn': alpn,
          if (hy2Obfs.isNotEmpty) 'obfs': hy2Obfs,
          if (hy2ObfsPassword.isNotEmpty) 'obfs-password': hy2ObfsPassword,
          if (hy2UpMbps > 0) 'upmbps': hy2UpMbps.toString(),
          if (hy2DownMbps > 0) 'downmbps': hy2DownMbps.toString(),
          if (hy2ServerPorts.isNotEmpty) 'mport': hy2ServerPorts,
          if (hy2HopInterval.isNotEmpty) 'hop-interval': hy2HopInterval,
          if (hy2HopIntervalMax.isNotEmpty) 'hop-interval-max': hy2HopIntervalMax,
          if (hy2BbrProfile.isNotEmpty) 'bbr-profile': hy2BbrProfile,
          if (hy2DisableChromeParrot) 'disable-chrome-parrot': '1',
          if (network.isNotEmpty) 'network': network,
        };
        return Uri(scheme: 'hy2', userInfo: password, host: server, port: port, queryParameters: q.isEmpty ? null : q, fragment: name).toString();
      case ProxyProtocol.vmess:
        final payload = <String, dynamic>{
          'v': '2',
          'ps': name,
          'add': server,
          'port': port.toString(),
          'id': uuid,
          'aid': alterId.toString(),
          'scy': vmessSecurity.isEmpty ? 'auto' : vmessSecurity,
          'net': transport.isEmpty ? 'tcp' : transport,
          'type': 'none',
          'host': host,
          'path': path,
          'tls': security.toLowerCase() == 'tls' ? 'tls' : '',
          'sni': sni,
          'alpn': alpn,
          'fp': fingerprint,
          'allowInsecure': tlsInsecure ? 1 : 0,
          'packetEncoding': packetEncoding,
        };
        return 'vmess://${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}';
      case ProxyProtocol.snell:
        final q = <String, String>{
          'version': snellVersion.toString(),
          if (snellReuse) 'reuse': '1',
          if (snellUserKey.isNotEmpty) 'userkey': snellUserKey,
          if (network.isNotEmpty) 'network': network,
          if (snellVersion == 6 && snellMode.isNotEmpty) 'mode': snellMode,
          if (snellVersion != 6 && snellObfsMode.isNotEmpty) 'obfs_mode': snellObfsMode,
          if (snellVersion != 6 && snellObfsHost.isNotEmpty) 'obfs_host': snellObfsHost,
        };
        return Uri(
          scheme: 'snell',
          userInfo: password,
          host: server,
          port: port,
          queryParameters: q,
          fragment: name,
        ).toString();
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
        'network': network,
        'tlsInsecure': tlsInsecure,
        'alpn': alpn,
        'host': host,
        'packetEncoding': packetEncoding,
        'plugin': plugin,
        'pluginOpts': pluginOpts,
        'vmessSecurity': vmessSecurity,
        'alterId': alterId,
        'hy2UpMbps': hy2UpMbps,
        'hy2DownMbps': hy2DownMbps,
        'hy2Obfs': hy2Obfs,
        'hy2ObfsPassword': hy2ObfsPassword,
        'hy2ServerPorts': hy2ServerPorts,
        'hy2HopInterval': hy2HopInterval,
        'hy2HopIntervalMax': hy2HopIntervalMax,
        'hy2BbrProfile': hy2BbrProfile,
        'hy2DisableChromeParrot': hy2DisableChromeParrot,
        'snellReuse': snellReuse,
        'snellUserKey': snellUserKey,
        'snellObfsMode': snellObfsMode,
        'snellObfsHost': snellObfsHost,
        'snellMode': snellMode,
        'sourceLink': sourceLink,
        'remark': remark,
        'favorite': favorite,
        'latencyMs': latencyMs,
        'snellVersion': snellVersion,
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
        network: j['network']?.toString() ?? '',
        tlsInsecure: j['tlsInsecure'] == true,
        alpn: j['alpn']?.toString() ?? '',
        host: j['host']?.toString() ?? '',
        packetEncoding: j['packetEncoding']?.toString() ?? '',
        plugin: j['plugin']?.toString() ?? '',
        pluginOpts: j['pluginOpts']?.toString() ?? '',
        vmessSecurity: j['vmessSecurity']?.toString() ?? 'auto',
        alterId: (j['alterId'] as num?)?.toInt() ??
            int.tryParse(j['alterId']?.toString() ?? '') ??
            0,
        hy2UpMbps: (j['hy2UpMbps'] as num?)?.toInt() ??
            int.tryParse(j['hy2UpMbps']?.toString() ?? '') ??
            0,
        hy2DownMbps: (j['hy2DownMbps'] as num?)?.toInt() ??
            int.tryParse(j['hy2DownMbps']?.toString() ?? '') ??
            0,
        hy2Obfs: j['hy2Obfs']?.toString() ?? '',
        hy2ObfsPassword: j['hy2ObfsPassword']?.toString() ?? '',
        hy2ServerPorts: j['hy2ServerPorts']?.toString() ?? '',
        hy2HopInterval: j['hy2HopInterval']?.toString() ?? '',
        hy2HopIntervalMax: j['hy2HopIntervalMax']?.toString() ?? '',
        hy2BbrProfile: j['hy2BbrProfile']?.toString() ?? '',
        hy2DisableChromeParrot: j['hy2DisableChromeParrot'] == true,
        snellReuse: j['snellReuse'] != false,
        snellUserKey: j['snellUserKey']?.toString() ?? '',
        snellObfsMode: j['snellObfsMode']?.toString() ?? 'none',
        snellObfsHost: j['snellObfsHost']?.toString() ?? '',
        snellMode: j['snellMode']?.toString() ?? 'default',
        sourceLink: j['sourceLink']?.toString() ?? '',
        remark: j['remark']?.toString() ?? '',
        favorite: j['favorite'] == true,
        latencyMs: (j['latencyMs'] as num?)?.toInt(),
        snellVersion: (j['snellVersion'] as num?)?.toInt() ??
            int.tryParse(j['snellVersion']?.toString() ?? '') ??
            5,
      );

  static String encodeList(List<ProxyNode> nodes) => jsonEncode(nodes.map((e) => e.toJson()).toList());

  static List<ProxyNode> decodeList(String raw) =>
      (jsonDecode(raw) as List).map((e) => ProxyNode.fromJson(Map<String, dynamic>.from(e as Map))).toList();
}
