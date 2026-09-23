import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/gold_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool autoConnect = false;
  bool notify = true;
  String dns = '系统默认';

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      children: [
        const Text('设置', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        GoldCard(
          child: Column(children: [
            _row(Icons.route_outlined, '路由模式', '智能分流'),
            const Divider(),
            _row(Icons.dns_outlined, 'DNS 设置', dns),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: autoConnect,
              activeColor: AppColors.gold,
              onChanged: (v) => setState(() => autoConnect = v),
              secondary: const Icon(Icons.power_settings_new_rounded, color: AppColors.gold),
              title: const Text('自动连接'),
              subtitle: const Text('启动 App 后自动连接上次节点', style: TextStyle(color: AppColors.text2, fontSize: 11)),
            ),
            const Divider(),
            _row(Icons.data_usage_rounded, '流量统计单位', 'GB'),
          ]),
        ),
        const SizedBox(height: 12),
        GoldCard(
          child: Column(children: [
            _row(Icons.dark_mode_outlined, '主题模式', '暗金主题'),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: notify,
              activeColor: AppColors.gold,
              onChanged: (v) => setState(() => notify = v),
              secondary: const Icon(Icons.notifications_none, color: AppColors.gold),
              title: const Text('通知提醒'),
              subtitle: const Text('连接状态、节点切换', style: TextStyle(color: AppColors.text2, fontSize: 11)),
            ),
            const Divider(),
            _row(Icons.language, '语言', '简体中文'),
            const Divider(),
            _row(Icons.palette_outlined, '外观与显示', ''),
          ]),
        ),
        const SizedBox(height: 12),
        GoldCard(
          child: Column(children: [
            _row(Icons.update_rounded, '检查更新', 'v1.0.0'),
            const Divider(),
            _row(Icons.info_outline, '关于应用', ''),
            const Divider(),
            _row(Icons.help_outline, '帮助与反馈', ''),
          ]),
        ),
      ],
    );
  }

  Widget _row(IconData icon, String title, String trailing) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: AppColors.gold),
        title: Text(title),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (trailing.isNotEmpty) Text(trailing, style: const TextStyle(color: AppColors.text2, fontSize: 12)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: AppColors.text2),
        ]),
        onTap: () {},
      );
}
