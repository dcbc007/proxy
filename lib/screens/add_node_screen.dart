import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../models/proxy_node.dart';
import '../services/qr_payload_parser.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

class AddNodeScreen extends StatefulWidget {
  const AddNodeScreen({super.key});

  @override
  State<AddNodeScreen> createState() => _AddNodeScreenState();
}

class _AddNodeScreenState extends State<AddNodeScreen> with SingleTickerProviderStateMixin {
  late final TabController tab = TabController(length: 3, vsync: this);
  ProxyProtocol protocol = ProxyProtocol.shadowsocks;
  String transport = 'tcp';
  String security = 'none';

  final name = TextEditingController();
  final server = TextEditingController();
  final port = TextEditingController(text: '443');
  final credential = TextEditingController();
  final method = TextEditingController(text: 'aes-256-gcm');
  final sni = TextEditingController();
  final path = TextEditingController();
  final publicKey = TextEditingController();
  final shortId = TextEditingController();
  final flow = TextEditingController();
  final fingerprint = TextEditingController(text: 'chrome');
  bool scanned = false;

  @override
  void dispose() {
    tab.dispose();
    for (final c in [name, server, port, credential, method, sni, path, publicKey, shortId, flow, fingerprint]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('添加节点', style: TextStyle(fontWeight: FontWeight.w800)),
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
    final supportsTls = [ProxyProtocol.vless, ProxyProtocol.vmess, ProxyProtocol.trojan, ProxyProtocol.hysteria2].contains(protocol);
    final supportsTransport = [ProxyProtocol.vless, ProxyProtocol.vmess, ProxyProtocol.trojan].contains(protocol);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
      children: [
        _label('协议类型'),
        DropdownButtonFormField<ProxyProtocol>(
          value: protocol,
          items: ProxyProtocol.values.map((p) => DropdownMenuItem(value: p, child: Text(p.label))).toList(),
          onChanged: (v) => setState(() {
            protocol = v ?? protocol;
            if (protocol == ProxyProtocol.shadowsocks) port.text = '8388';
          }),
        ),
        _field('节点名称', name, '例如：新加坡 SG-01'),
        _field('服务器地址', server, 'example.com 或 IP 地址'),
        _field('端口', port, '443', keyboardType: TextInputType.number),
        _field(_credentialLabel, credential, _credentialHint, obscureText: true),
        if (protocol == ProxyProtocol.shadowsocks) _field('加密方式', method, 'aes-256-gcm'),
        if (protocol == ProxyProtocol.snell)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('Snell 手动节点按 v5 配置生成。', style: TextStyle(color: AppColors.text2, fontSize: 11)),
          ),
        if (supportsTransport) ...[
          const SizedBox(height: 14),
          _label('传输方式'),
          DropdownButtonFormField<String>(
            value: transport,
            items: const ['tcp', 'ws', 'grpc', 'http', 'h2', 'httpupgrade', 'xhttp', 'quic']
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) => setState(() => transport = v ?? 'tcp'),
          ),
          if (transport != 'tcp') _field('Path / Service Name', path, '可选'),
        ],
        if (supportsTls) ...[
          const SizedBox(height: 14),
          _label('安全层'),
          DropdownButtonFormField<String>(
            value: security,
            items: const [
              DropdownMenuItem(value: 'none', child: Text('无')),
              DropdownMenuItem(value: 'tls', child: Text('TLS')),
              DropdownMenuItem(value: 'reality', child: Text('Reality')),
            ],
            onChanged: (v) => setState(() => security = v ?? 'none'),
          ),
          if (security != 'none') _field('SNI / Server Name', sni, '例如：www.example.com'),
          if (security == 'reality') ...[
            _field('Reality Public Key', publicKey, 'Public Key'),
            _field('Reality Short ID', shortId, 'Short ID'),
            _field('uTLS 指纹', fingerprint, 'chrome'),
          ],
        ],
        if (protocol == ProxyProtocol.vless) _field('Flow', flow, '可选，例如 xtls-rprx-vision'),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _saveManual,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('保存节点', style: TextStyle(fontWeight: FontWeight.w800)),
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
    final n = ProxyNode(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.text.trim().isEmpty ? '${protocol.label} 节点' : name.text.trim(),
      protocol: protocol,
      server: server.text.trim(),
      port: parsedPort,
      password: [ProxyProtocol.shadowsocks, ProxyProtocol.trojan, ProxyProtocol.hysteria2, ProxyProtocol.snell].contains(protocol) ? credential.text.trim() : '',
      uuid: [ProxyProtocol.vless, ProxyProtocol.vmess].contains(protocol) ? credential.text.trim() : '',
      method: method.text.trim(),
      transport: transport,
      security: security == 'none' ? '' : security,
      sni: sni.text.trim(),
      path: path.text.trim(),
      publicKey: publicKey.text.trim(),
      shortId: shortId.text.trim(),
      flow: flow.text.trim(),
      fingerprint: fingerprint.text.trim(),
    );
    await context.read<AppState>().addNode(n);
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
