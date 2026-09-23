import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/subscription.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/gold_card.dart';

class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
          child: Row(
            children: [
              const Expanded(child: Text('订阅管理', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
              IconButton(onPressed: () => _add(context), icon: const Icon(Icons.add, color: AppColors.gold)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Expanded(child: _Action(icon: Icons.content_paste_rounded, title: '从剪贴板导入', onTap: () {})),
              const SizedBox(width: 10),
              Expanded(child: _Action(icon: Icons.qr_code_scanner_rounded, title: '扫描二维码', onTap: () {})),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: s.subscriptions.isEmpty
              ? const Center(child: Text('还没有订阅，点击右上角 + 添加', style: TextStyle(color: AppColors.text2)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                  itemCount: s.subscriptions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final sub = s.subscriptions[i];
                    return GoldCard(
                      child: Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined, color: AppColors.gold),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(sub.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 4),
                              Text(sub.url, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.text2, fontSize: 11)),
                              const SizedBox(height: 7),
                              Text('${sub.nodeCount} 个节点 · 上次更新 ${_date(sub.updatedAt)}', style: const TextStyle(color: AppColors.text2, fontSize: 11)),
                            ]),
                          ),
                          IconButton(tooltip: '更新订阅', onPressed: () => s.updateSubscription(sub), icon: const Icon(Icons.refresh_rounded, color: AppColors.gold)),
                          Switch(value: sub.enabled, activeColor: AppColors.gold, onChanged: (_) => s.toggleSubscription(sub)),
                        ],
                      ),
                    );
                  },
                ),
        )
      ],
    );
  }

  static String _date(DateTime d) => '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  void _add(BuildContext context) {
    final name = TextEditingController();
    final url = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('添加订阅', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(controller: name, decoration: const InputDecoration(labelText: '订阅名称')),
          const SizedBox(height: 12),
          TextField(controller: url, decoration: const InputDecoration(labelText: '订阅地址')),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              if (url.text.trim().isEmpty) return;
              await context.read<AppState>().addSubscription(ProxySubscription(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    name: name.text.trim().isEmpty ? '我的订阅' : name.text.trim(),
                    url: url.text.trim(),
                  ));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(50)),
            child: const Text('保存'),
          ),
        ]),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.title, required this.onTap});
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GoldCard(
        onTap: onTap,
        child: Column(children: [Icon(icon, color: AppColors.gold), const SizedBox(height: 8), Text(title, style: const TextStyle(fontSize: 12))]),
      );
}
