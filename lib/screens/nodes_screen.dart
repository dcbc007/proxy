import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/proxy_node.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'add_node_screen.dart';

class NodesScreen extends StatefulWidget {
  const NodesScreen({super.key});

  @override
  State<NodesScreen> createState() => _NodesScreenState();
}

class _NodesScreenState extends State<NodesScreen> {
  String query = '';
  String filter = '全部';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    var list = s.nodes.where((n) => n.name.toLowerCase().contains(query.toLowerCase()) || n.server.toLowerCase().contains(query.toLowerCase())).toList();
    if (filter == '收藏') list = list.where((e) => e.favorite).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
          child: Row(
            children: [
              const Expanded(child: Text('节点列表', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
              IconButton(icon: const Icon(Icons.search, color: AppColors.gold), onPressed: () {}),
              IconButton(
                icon: const Icon(Icons.add, color: AppColors.gold),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddNodeScreen())),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜索国家、节点名称或地址...'),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: ['全部', '推荐', '手动', '订阅', '收藏'].map((e) {
              final on = filter == e;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  selected: on,
                  label: Text(e),
                  onSelected: (_) => setState(() => filter = e),
                  selectedColor: AppColors.gold.withOpacity(.15),
                  side: BorderSide(color: on ? AppColors.gold : AppColors.line),
                  labelStyle: TextStyle(color: on ? AppColors.goldBright : AppColors.text2),
                  backgroundColor: AppColors.card,
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 5),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final n = list[i];
              final selected = s.selectedNodeId == n.id;
              return Dismissible(
                key: ValueKey(n.id),
                direction: DismissDirection.endToStart,
                background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 24), color: AppColors.red.withOpacity(.18), child: const Icon(Icons.delete_outline, color: AppColors.red)),
                onDismissed: (_) => s.deleteNode(n.id),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  onTap: () => s.selectNode(n.id),
                  leading: Container(
                    width: 38,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: selected ? AppColors.gold.withOpacity(.15) : AppColors.card2, borderRadius: BorderRadius.circular(7), border: Border.all(color: selected ? AppColors.gold : AppColors.line)),
                    child: Text(_countryCode(n.name), style: TextStyle(color: selected ? AppColors.goldBright : AppColors.text, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(n.name, style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
                  subtitle: Text('${n.protocol.label}  ·  ${n.server}', style: const TextStyle(color: AppColors.text2, fontSize: 11), overflow: TextOverflow.ellipsis),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => s.testLatency(n),
                        child: Text('${n.latencyMs ?? '--'} ms', style: TextStyle(color: _latencyColor(n.latencyMs), fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => s.toggleFavorite(n),
                        icon: Icon(n.favorite ? Icons.star_rounded : Icons.star_border_rounded, color: n.favorite ? AppColors.gold : AppColors.text2),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Color _latencyColor(int? v) {
    if (v == null) return AppColors.text2;
    if (v < 80) return AppColors.green;
    if (v < 140) return AppColors.amber;
    return AppColors.red;
  }

  String _countryCode(String name) {
    if (name.contains('新加坡')) return 'SG';
    if (name.contains('日本')) return 'JP';
    if (name.contains('美国')) return 'US';
    if (name.contains('英国')) return 'UK';
    if (name.contains('德国')) return 'DE';
    if (name.contains('香港')) return 'HK';
    if (name.contains('台湾')) return 'TW';
    if (name.contains('韩国')) return 'KR';
    return 'N';
  }
}
