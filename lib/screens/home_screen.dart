import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/gold_card.dart';
import '../widgets/power_button.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final node = s.selectedNode;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '首页',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.card.withOpacity(.85),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Text(
                      'v${s.appVersion}',
                      style: const TextStyle(
                        color: AppColors.goldBright,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(
                      Icons.workspace_premium_outlined,
                      color: AppColors.gold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GoldCard(
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDD3C45),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        'SG',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            node?.name ?? '未选择节点',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            node == null
                                ? '请选择一个节点'
                                : '${node.protocol.label} · ${node.server}:${node.port}',
                            style: const TextStyle(
                              color: AppColors.text2,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (s.connected)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.green.withOpacity(.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '已连接',
                          style: TextStyle(
                            color: AppColors.green,
                            fontSize: 12,
                          ),
                        ),
                      )
                    else
                      const Icon(Icons.chevron_right, color: AppColors.text2),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: PowerButton(
                  connected: s.connected,
                  onTap: s.toggleConnection,
                ),
              ),
              Center(
                child: Column(
                  children: [
                    Text(
                      s.durationText,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.connected ? '已连接' : '未连接',
                      style: TextStyle(
                        color: s.connected ? AppColors.green : AppColors.text2,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: ['智能模式', '全局模式', '直连模式'].map((m) {
                  final active = s.mode == m;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: OutlinedButton(
                        onPressed: () => s.setMode(m),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: active
                              ? AppColors.goldBright
                              : AppColors.text,
                          backgroundColor: active
                              ? AppColors.gold.withOpacity(.1)
                              : AppColors.card.withOpacity(.8),
                          side: BorderSide(
                            color: active ? AppColors.gold : AppColors.line,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(m, style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              GoldCard(
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: node == null ? null : () => s.testLatency(node),
                        child: _Metric(
                          title: '延迟 · 点击测试',
                          value: s.latencyLabel(node),
                          color: node?.latencyMs == null
                              ? AppColors.text2
                              : AppColors.green,
                        ),
                      ),
                    ),
                    const _Divider(),
                    Expanded(
                      child: _Metric(
                        title: '↓ 下载速度',
                        value: s.connected ? s.downloadSpeed : '0 B/s',
                        color: AppColors.green,
                      ),
                    ),
                    const _Divider(),
                    Expanded(
                      child: _Metric(
                        title: '↑ 上传速度',
                        value: s.connected ? s.uploadSpeed : '0 B/s',
                        color: AppColors.green,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GoldCard(
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: AppColors.gold),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.coreReady
                            ? '代理核心已就绪${s.coreVersion.isEmpty ? '' : ' · ${s.coreVersion}'}'
                            : '正在检查代理核心',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.text2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!s.coreReady) ...[
                const SizedBox(height: 14),
                const GoldCard(
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: AppColors.amber),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '代理核心未就绪。请按源码包中的构建说明编译 sing-box 核心后重新安装。',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.text2,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ]),
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.title,
    required this.value,
    required this.color,
  });
  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(title, style: const TextStyle(color: AppColors.text2, fontSize: 11)),
      const SizedBox(height: 7),
      Text(
        value,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    ],
  );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 38, color: AppColors.line);
}
