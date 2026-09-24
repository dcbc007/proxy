import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../models/proxy_node.dart';
import '../services/qr_payload_parser.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

class AddNodeScreen extends StatefulWidget {
  const AddNodeScreen({super.key, this.node});

  final ProxyNode? node;

  @override
  State<AddNodeScreen> createState() => _AddNodeScreenState();
}

class _AddNodeScreenState extends State<AddNodeScreen> with SingleTickerProviderStateMixin {
  late final TabController tab = TabController(length: 3, vsync: this);
  ProxyProtocol protocol = ProxyProtocol.shadowsocks;
  String transport = 'tcp';
  String security = 'none';
  String network = '';
  String plugin = '';
  String packetEncoding = '';
  String vmessSecurity = 'auto';
  String hy2Obfs = '';
  String hy2BbrProfile = '';
  String snellObfsMode = 'none';
  String snellMode = 'default';

  final name = TextEditingController();
  final server = TextEditingController();
  final port = TextEditingController(text: '443');
  final credential = TextEditingController();
  final method = TextEditingController(text: 'aes-256-gcm');
  final sni = TextEditingController();
  final alpn = TextEditingController();
  final path = TextEditingController();
  final host = TextEditingController();
  final publicKey = TextEditingController();
  final shortId = TextEditingController();
  final flow = TextEditingController();
  final fingerprint = TextEditingController(text: 'chrome');
  final pluginOpts = TextEditingController();
  final alterId = TextEditingController(text: '0');
  final hy2UpMbps = TextEditingController();
  final hy2DownMbps = TextEditingController();
  final hy2ObfsPassword = TextEditingController();
  final hy2ServerPorts = TextEditingController();
  final hy2HopInterval = TextEditingController();
  final hy2HopIntervalMax = TextEditingController();
  final snellUserKey = TextEditingController();
  final snellObfsHost = TextEditingController();
  bool tlsInsecure = false;
  bool hy2DisableChromeParrot = false;
  bool snellReuse = true;
  bool scanned = false;
  int snellVersion = 5;

  bool get editing => widget.node != null;

  @override
  void initState() {
    super.initState();
    final n = widget.node;
    if (n == null) return;
    protocol = n.protocol;
    name.text = n.name;
    server.text = n.server;
    port.text = n.port.toString();
    credential.text = [ProxyProtocol.vless, ProxyProtocol.vmess].contains(n.protocol)
        ? n.uuid
        : n.password;
    method.text = n.method.isEmpty ? 'aes-256-gcm' : n.method;
    transport = n.transport.isEmpty ? 'tcp' : n.transport;
    security = n.security.isEmpty ? 'none' : n.security;
    network = n.network;
    plugin = n.plugin;
    packetEncoding = n.packetEncoding;
    vmessSecurity = n.vmessSecurity.isEmpty ? 'auto' : n.vmessSecurity;
    hy2Obfs = n.hy2Obfs;
    hy2BbrProfile = n.hy2BbrProfile;
    snellObfsMode = n.snellObfsMode.isEmpty ? 'none' : n.snellObfsMode;
    snellMode = n.snellMode.isEmpty ? 'default' : n.snellMode;
    sni.text = n.sni;
    alpn.text = n.alpn;
    path.text = n.path;
    host.text = n.host;
    publicKey.text = n.publicKey;
    shortId.text = n.shortId;
    flow.text = n.flow;
    fingerprint.text = n.fingerprint.isEmpty ? 'chrome' : n.fingerprint;
    pluginOpts.text = n.pluginOpts;
    alterId.text = n.alterId.toString();
    hy2UpMbps.text = n.hy2UpMbps > 0 ? n.hy2UpMbps.toString() : '';
    hy2DownMbps.text = n.hy2DownMbps > 0 ? n.hy2DownMbps.toString() : '';
    hy2ObfsPassword.text = n.hy2ObfsPassword;
    hy2ServerPorts.text = n.hy2ServerPorts;
    hy2HopInterval.text = n.hy2HopInterval;
    hy2HopIntervalMax.text = n.hy2HopIntervalMax;
    snellUserKey.text = n.snellUserKey;
    snellObfsHost.text = n.snellObfsHost;
    tlsInsecure = n.tlsInsecure;
    hy2DisableChromeParrot = n.hy2DisableChromeParrot;
    snellReuse = n.snellReuse;
    snellVersion = n.snellVersion;
  }

  @override
  void dispose() {
    tab.dispose();
    for (final c in [
      name,
      server,
      port,
      credential,
      method,
      sni,
      alpn,
      path,
      host,
      publicKey,
      shortId,
      flow,
      fingerprint,
      pluginOpts,
      alterId,
      hy2UpMbps,
      hy2DownMbps,
      hy2ObfsPassword,
      hy2ServerPorts,
      hy2HopInterval,
      hy2HopIntervalMax,
      snellUserKey,
      snellObfsHost,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(editing ? '编辑节点' : '添加节点', style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [TextButton(onPressed: _saveManual, child: const Text('保存'))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
            child: TabBar(
              controller: tab,
              indicatorColor: AppColors.gold,
              labelColor: AppColors.goldBright,
              unselectedLabelColor: AppColors.text2,
              tabs: const [Tab(text: '手动添加'), Tab(text: '剪贴板导入'), Tab(text: '扫码添加')],
            ),
          ),
          Expanded(child: TabBarView(controller: tab, children: [_manual(), _clipboard(), _scanner()])),
        ],
      ),
    );
  }

  Widget _manual() {
    final supportsTls = [
      ProxyProtocol.vless,
      ProxyProtocol.vmess,
      ProxyProtocol.trojan,
      ProxyProtocol.hysteria2,
    ].contains(protocol);
    final supportsTransport = [
      ProxyProtocol.vless,
      ProxyProtocol.vmess,
      ProxyProtocol.trojan,
    ].contains(protocol);
    final tlsEnabled =
        protocol == ProxyProtocol.hysteria2 || security != 'none';

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
      children: [
        _label('协议类型'),
        DropdownButtonFormField<ProxyProtocol>(
          value: protocol,
          items: ProxyProtocol.values
              .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
              .toList(),
          onChanged: (v) => setState(() {
            protocol = v ?? protocol;
            if (protocol == ProxyProtocol.shadowsocks) port.text = '8388';
            if (protocol == ProxyProtocol.hysteria2) security = 'tls';
          }),
        ),
        _field('节点名称', name, '例如：新加坡 SG-01'),
        _field('服务器地址', server, 'example.com 或 IP 地址'),
        _field('端口', port, '443', keyboardType: TextInputType.number),
        _field(_credentialLabel, credential, _credentialHint, obscureText: true),

        const SizedBox(height: 14),
        _label('网络类型'),
        DropdownButtonFormField<String>(
          value: network,
          items: const [
            DropdownMenuItem(value: '', child: Text('TCP + UDP（默认）')),
            DropdownMenuItem(value: 'tcp', child: Text('仅 TCP')),
            DropdownMenuItem(value: 'udp', child: Text('仅 UDP')),
          ],
          onChanged: (v) => setState(() => network = v ?? ''),
        ),

        if (protocol == ProxyProtocol.shadowsocks) ...[
          _field('加密方式', method, 'aes-256-gcm / 2022-blake3-aes-256-gcm'),
          const SizedBox(height: 14),
          _label('SIP003 插件'),
          DropdownButtonFormField<String>(
            value: plugin,
            items: const [
              DropdownMenuItem(value: '', child: Text('无')),
              DropdownMenuItem(value: 'obfs-local', child: Text('obfs-local')),
              DropdownMenuItem(value: 'v2ray-plugin', child: Text('v2ray-plugin')),
            ],
            onChanged: (v) => setState(() => plugin = v ?? ''),
          ),
          if (plugin.isNotEmpty)
            _field('插件参数', pluginOpts, '例如：tls;host=example.com;path=/ws'),
        ],

        if (protocol == ProxyProtocol.vmess) ...[
          const SizedBox(height: 14),
          _label('VMess 加密'),
          DropdownButtonFormField<String>(
            value: vmessSecurity,
            items: const ['auto', 'none', 'zero', 'aes-128-gcm', 'chacha20-poly1305']
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) => setState(() => vmessSecurity = v ?? 'auto'),
          ),
          _field('Alter ID', alterId, '0', keyboardType: TextInputType.number),
        ],

        if (protocol == ProxyProtocol.snell) ...[
          const SizedBox(height: 14),
          _label('Snell 版本'),
          DropdownButtonFormField<int>(
            value: snellVersion,
            items: const [
              DropdownMenuItem(value: 4, child: Text('Snell v4')),
              DropdownMenuItem(value: 5, child: Text('Snell v5（v4 线路兼容）')),
              DropdownMenuItem(value: 6, child: Text('Snell v6')),
            ],
            onChanged: (v) => setState(() => snellVersion = v ?? 5),
          ),
          _field('User Key', snellUserKey, '多用户服务器可选'),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('连接复用'),
            subtitle: const Text('减少重复握手，通常建议开启'),
            value: snellReuse,
            onChanged: (v) => setState(() => snellReuse = v),
          ),
          if (snellVersion == 6) ...[
            _label('流量整形模式'),
            DropdownButtonFormField<String>(
              value: snellMode,
              items: const ['default', 'unshaped', 'unsafe-raw']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) => setState(() => snellMode = v ?? 'default'),
            ),
          ] else ...[
            _label('HTTP 混淆'),
            DropdownButtonFormField<String>(
              value: snellObfsMode,
              items: const [
                DropdownMenuItem(value: 'none', child: Text('关闭')),
                DropdownMenuItem(value: 'http', child: Text('HTTP')),
              ],
              onChanged: (v) => setState(() => snellObfsMode = v ?? 'none'),
            ),
            if (snellObfsMode == 'http')
              _field('混淆 Host', snellObfsHost, '默认 bing.com'),
          ],
        ],

        if (supportsTransport) ...[
          const SizedBox(height: 14),
          _label('传输方式'),
          DropdownButtonFormField<String>(
            value: transport,
            items: const [
              'tcp',
              'ws',
              'grpc',
              'http',
              'h2',
              'httpupgrade',
              'xhttp',
              'quic',
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => transport = v ?? 'tcp'),
          ),
          if (['ws', 'http', 'h2', 'httpupgrade', 'xhttp'].contains(transport))
            _field('Host', host, '例如：cdn.example.com'),
          if (transport == 'grpc')
            _field('gRPC Service Name', path, '例如：TunService')
          else if (!['tcp', 'quic'].contains(transport))
            _field('Path', path, '例如：/ws'),
        ],

        if (supportsTls) ...[
          const SizedBox(height: 14),
          if (protocol != ProxyProtocol.hysteria2) ...[
            _label('安全层'),
            DropdownButtonFormField<String>(
              value: security,
              items: protocol == ProxyProtocol.vless
                  ? const [
                      DropdownMenuItem(value: 'none', child: Text('无')),
                      DropdownMenuItem(value: 'tls', child: Text('TLS')),
                      DropdownMenuItem(value: 'reality', child: Text('Reality')),
                    ]
                  : const [
                      DropdownMenuItem(value: 'none', child: Text('无')),
                      DropdownMenuItem(value: 'tls', child: Text('TLS')),
                    ],
              onChanged: (v) => setState(() => security = v ?? 'none'),
            ),
          ] else
            const Text(
              'TLS（Hysteria2 必需）',
              style: TextStyle(color: AppColors.text2, fontSize: 12),
            ),
          if (tlsEnabled) ...[
            _field('SNI / Server Name', sni, '例如：www.example.com'),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('跳过 TLS 证书验证'),
              subtitle: const Text('对应 insecure / allowInsecure；自签名证书节点常用'),
              value: tlsInsecure,
              onChanged: (v) => setState(() => tlsInsecure = v),
            ),
            _field('ALPN', alpn, '例如：h3 或 h2,http/1.1'),
            if (protocol != ProxyProtocol.hysteria2)
              _field('uTLS 指纹', fingerprint, 'chrome / firefox / edge / safari'),
          ],
          if (security == 'reality' && protocol == ProxyProtocol.vless) ...[
            _field('Reality Public Key', publicKey, 'Public Key'),
            _field('Reality Short ID', shortId, 'Short ID'),
          ],
        ],

        if (protocol == ProxyProtocol.vless) ...[
          _field('Flow', flow, '可选，例如 xtls-rprx-vision'),
          const SizedBox(height: 14),
          _label('UDP 包编码'),
          DropdownButtonFormField<String>(
            value: packetEncoding,
            items: const [
              DropdownMenuItem(value: '', child: Text('默认')),
              DropdownMenuItem(value: 'xudp', child: Text('xudp')),
              DropdownMenuItem(value: 'packetaddr', child: Text('packetaddr')),
            ],
            onChanged: (v) => setState(() => packetEncoding = v ?? ''),
          ),
        ],

        if (protocol == ProxyProtocol.vmess) ...[
          const SizedBox(height: 14),
          _label('UDP 包编码'),
          DropdownButtonFormField<String>(
            value: packetEncoding,
            items: const [
              DropdownMenuItem(value: '', child: Text('关闭/默认')),
              DropdownMenuItem(value: 'xudp', child: Text('xudp')),
              DropdownMenuItem(value: 'packetaddr', child: Text('packetaddr')),
            ],
            onChanged: (v) => setState(() => packetEncoding = v ?? ''),
          ),
        ],

        if (protocol == ProxyProtocol.hysteria2) ...[
          const SizedBox(height: 18),
          const Text(
            'Hysteria2 高级参数',
            style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.goldBright),
          ),
          _field('上传带宽 Mbps', hy2UpMbps, '留空使用 BBR', keyboardType: TextInputType.number),
          _field('下载带宽 Mbps', hy2DownMbps, '留空使用 BBR', keyboardType: TextInputType.number),
          const SizedBox(height: 14),
          _label('QUIC 混淆'),
          DropdownButtonFormField<String>(
            value: hy2Obfs,
            items: const [
              DropdownMenuItem(value: '', child: Text('关闭')),
              DropdownMenuItem(value: 'salamander', child: Text('salamander')),
              DropdownMenuItem(value: 'gecko', child: Text('gecko（sing-box 1.14+）')),
            ],
            onChanged: (v) => setState(() => hy2Obfs = v ?? ''),
          ),
          if (hy2Obfs.isNotEmpty)
            _field('混淆密码', hy2ObfsPassword, 'Obfs Password', obscureText: true),
          _field('端口跳跃范围', hy2ServerPorts, '例如：20000:30000 或 443,8443'),
          _field('跳跃间隔', hy2HopInterval, '例如：30s'),
          _field('最大跳跃间隔', hy2HopIntervalMax, '例如：60s'),
          const SizedBox(height: 14),
          _label('BBR Profile'),
          DropdownButtonFormField<String>(
            value: hy2BbrProfile,
            items: const [
              DropdownMenuItem(value: '', child: Text('默认 standard')),
              DropdownMenuItem(value: 'conservative', child: Text('conservative')),
              DropdownMenuItem(value: 'standard', child: Text('standard')),
              DropdownMenuItem(value: 'aggressive', child: Text('aggressive')),
            ],
            onChanged: (v) => setState(() => hy2BbrProfile = v ?? ''),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('禁用 Chrome QUIC 指纹模拟'),
            subtitle: const Text('仅在服务端兼容性需要时开启'),
            value: hy2DisableChromeParrot,
            onChanged: (v) => setState(() => hy2DisableChromeParrot = v),
          ),
        ],

        const SizedBox(height: 18),
        FilledButton(
          onPressed: _saveManual,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            editing ? '保存修改' : '保存节点',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  Widget _clipboard() => Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
              child: const Column(
                children: [
                  Icon(Icons.content_paste_go_rounded, size: 52, color: AppColors.gold),
                  SizedBox(height: 16),
                  Text('从剪贴板导入节点', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  SizedBox(height: 8),
                  Text('支持 ss、VLESS、VMess、Trojan、Hysteria2 与 Snell 节点链接；也可一次粘贴多行。', textAlign: TextAlign.center, style: TextStyle(color: AppColors.text2, fontSize: 12, height: 1.5)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _importClipboard,
              icon: const Icon(Icons.paste),
              label: const Text('读取剪贴板并添加'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(50)),
            ),
          ],
        ),
      );

  Widget _scanner() => Padding(
        padding: const EdgeInsets.all(18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                onDetect: (capture) async {
                  if (scanned) return;
                  String? raw;
                  for (final code in capture.barcodes) {
                    if (code.rawValue != null) {
                      raw = code.rawValue;
                      break;
                    }
                  }
                  if (raw == null) return;
                  scanned = true;
                  final ok = await _importRaw(raw);
                  if (!ok) scanned = false;
                },
              ),
              IgnorePointer(
                child: Center(
                  child: Container(
                    width: 230,
                    height: 230,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.gold, width: 2),
                      boxShadow: [BoxShadow(color: AppColors.gold.withOpacity(.25), blurRadius: 26, spreadRadius: 3)],
                    ),
                  ),
                ),
              ),
              const Positioned(left: 0, right: 0, bottom: 24, child: Text('将节点二维码放入取景框内', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
            ],
          ),
        ),
      );

  String get _credentialLabel {
    switch (protocol) {
      case ProxyProtocol.vless:
      case ProxyProtocol.vmess:
        return '用户 ID（UUID）';
      case ProxyProtocol.shadowsocks:
      case ProxyProtocol.trojan:
      case ProxyProtocol.hysteria2:
      case ProxyProtocol.snell:
        return '密码 / PSK';
    }
  }

  String get _credentialHint => protocol == ProxyProtocol.vless || protocol == ProxyProtocol.vmess ? '请输入 UUID' : '请输入密码';

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(text, style: const TextStyle(color: AppColors.text2, fontSize: 12)),
      );

  Widget _field(String label, TextEditingController c, String hint, {bool obscureText = false, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label(label),
        TextField(controller: c, obscureText: obscureText, keyboardType: keyboardType, decoration: InputDecoration(hintText: hint)),
      ]),
    );
  }

  Future<void> _saveManual() async {
    final parsedPort = int.tryParse(port.text.trim());
    if (server.text.trim().isEmpty || parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
      _toast('请填写有效的服务器地址和端口');
      return;
    }
    if (credential.text.trim().isEmpty) {
      _toast('认证信息不能为空');
      return;
    }
    final old = widget.node;
    final n = ProxyNode(
      id: old?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.text.trim().isEmpty ? '${protocol.label} 节点' : name.text.trim(),
      protocol: protocol,
      server: server.text.trim(),
      port: parsedPort,
      password: [ProxyProtocol.shadowsocks, ProxyProtocol.trojan, ProxyProtocol.hysteria2, ProxyProtocol.snell].contains(protocol) ? credential.text.trim() : '',
      uuid: [ProxyProtocol.vless, ProxyProtocol.vmess].contains(protocol) ? credential.text.trim() : '',
      method: method.text.trim(),
      transport: transport,
      security: protocol == ProxyProtocol.hysteria2
          ? 'tls'
          : (security == 'none' ? '' : security),
      sni: sni.text.trim(),
      path: path.text.trim(),
      publicKey: publicKey.text.trim(),
      shortId: shortId.text.trim(),
      flow: flow.text.trim(),
      fingerprint: fingerprint.text.trim(),
      network: network,
      tlsInsecure: tlsInsecure,
      alpn: alpn.text.trim(),
      host: host.text.trim(),
      packetEncoding: packetEncoding,
      plugin: plugin,
      pluginOpts: pluginOpts.text.trim(),
      vmessSecurity: vmessSecurity,
      alterId: int.tryParse(alterId.text.trim()) ?? 0,
      hy2UpMbps: int.tryParse(hy2UpMbps.text.trim()) ?? 0,
      hy2DownMbps: int.tryParse(hy2DownMbps.text.trim()) ?? 0,
      hy2Obfs: hy2Obfs,
      hy2ObfsPassword: hy2ObfsPassword.text.trim(),
      hy2ServerPorts: hy2ServerPorts.text.trim(),
      hy2HopInterval: hy2HopInterval.text.trim(),
      hy2HopIntervalMax: hy2HopIntervalMax.text.trim(),
      hy2BbrProfile: hy2BbrProfile,
      hy2DisableChromeParrot: hy2DisableChromeParrot,
      snellReuse: snellReuse,
      snellUserKey: snellUserKey.text.trim(),
      snellObfsMode: snellObfsMode,
      snellObfsHost: snellObfsHost.text.trim(),
      snellMode: snellMode,
      snellVersion: snellVersion,
      favorite: old?.favorite ?? false,
      latencyMs: old?.latencyMs,
      remark: old?.remark ?? '',
      sourceLink: '',
    );
    final state = context.read<AppState>();
    if (editing) {
      await state.updateNode(n);
    } else {
      await state.addNode(n);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _importClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text?.trim() ?? '';
    if (raw.isEmpty) {
      _toast('剪贴板为空');
      return;
    }
    final count = await _importMany(raw);
    if (count > 0) _toast('已添加 $count 个节点');
  }

  Future<int> _importMany(String raw) async {
    var count = 0;
    for (final line in raw.split(RegExp(r'[\r\n]+'))) {
      final v = line.trim();
      if (!QrPayloadParser.looksLikeNode(v)) continue;
      if (await _importRaw(v, showToast: false)) count++;
    }
    if (count == 0) _toast('未识别到支持的节点链接');
    return count;
  }

  Future<bool> _importRaw(String raw, {bool showToast = true}) async {
    try {
      final node = QrPayloadParser.parse(raw);
      await context.read<AppState>().addNode(node);
      if (showToast) _toast('节点已添加：${node.name}');
      return true;
    } catch (_) {
      if (showToast) _toast('无法识别该节点内容');
      return false;
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
