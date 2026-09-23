import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final logs = context.watch<AppState>().logs;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
          child: Row(
            children: [
              const Expanded(child: Text('连接日志', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
              IconButton(onPressed: () => context.read<AppState>().clearLogs(), icon: const Icon(Icons.delete_outline, color: AppColors.gold)),
              IconButton(onPressed: () {}, icon: const Icon(Icons.more_horiz, color: AppColors.gold)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: ['全部', '连接', '断开', '错误', '测试'].map((e) => Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(side: BorderSide(color: e == '全部' ? AppColors.gold : AppColors.line), foregroundColor: e == '全部' ? AppColors.goldBright : AppColors.text2),
                child: Text(e, style: const TextStyle(fontSize: 11)),
              ),
            ))).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
            itemCount: logs.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 7, height: 7, margin: const EdgeInsets.only(top: 5), decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.green)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(logs[i], style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: Color(0xFFCDD0D4), height: 1.4))),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
          child: FilledButton.icon(
            onPressed: () => context.read<AppState>().addLog('开始路由测试'),
            icon: const Icon(Icons.hub_outlined),
            label: const Text('开始路由测试'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(48)),
          ),
        )
      ],
    );
  }
}
