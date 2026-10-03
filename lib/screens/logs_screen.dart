import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  String filter = '全部';

  List<String> _filtered(List<String> logs) {
    if (filter == '全部') return logs;
    final f = filter;
    return logs.where((line) {
      final lower = line.toLowerCase();
      switch (f) {
        case '连接':
          return lower.contains('连接') ||
              lower.contains('connected') ||
              lower.contains('starting service') ||
              lower.contains('vpn data path active');
        case '断开':
          return lower.contains('断开') ||
              lower.contains('stopped') ||
              lower.contains('stopping service');
        case '错误':
          return lower.contains('失败') ||
              lower.contains('错误') ||
              lower.contains('超时') ||
              lower.contains('failed') ||
              lower.contains('error');
        case '测试':
          return lower.contains('测试') ||
              lower.contains('自检') ||
              lower.contains('握手') ||
              lower.contains('延迟');
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final logs = _filtered(state.logs);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '连接日志',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: '清空日志',
                onPressed: state.clearLogs,
                icon: const Icon(Icons.delete_outline, color: AppColors.gold),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: ['全部', '连接', '断开', '错误', '测试']
                .map(
                  (e) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: OutlinedButton(
                        onPressed: () => setState(() => filter = e),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: e == filter ? AppColors.gold : AppColors.line,
                          ),
                          foregroundColor: e == filter
                              ? AppColors.goldBright
                              : AppColors.text2,
                        ),
                        child: Text(
                          e,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: logs.isEmpty
              ? const Center(
                  child: Text(
                    '当前筛选没有日志',
                    style: TextStyle(color: AppColors.text2),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                  itemCount: logs.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(top: 5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _dotColor(logs[i]),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            logs[i],
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                              color: Color(0xFFCDD0D4),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
          child: FilledButton.icon(
            onPressed: state.runDiagnostics,
            icon: const Icon(Icons.hub_outlined),
            label: const Text('开始路由自检'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
      ],
    );
  }

  Color _dotColor(String line) {
    final lower = line.toLowerCase();
    if (lower.contains('失败') ||
        lower.contains('错误') ||
        lower.contains('超时') ||
        lower.contains('failed') ||
        lower.contains('error')) {
      return AppColors.red;
    }
    if (lower.contains('断开') ||
        lower.contains('stopped') ||
        lower.contains('stopping service')) {
      return AppColors.amber;
    }
    return AppColors.green;
  }
}
