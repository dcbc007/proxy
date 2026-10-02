import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/gold_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      children: [
        const Text(
          '设置',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        GoldCard(
          child: Column(
            children: [
              _row(
                Icons.route_outlined,
                '路由模式',
                state.mode,
                onTap: () => _pickRouteMode(context, state),
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: state.autoConnect,
                activeColor: AppColors.gold,
                onChanged: state.setAutoConnect,
                secondary: const Icon(
                  Icons.power_settings_new_rounded,
                  color: AppColors.gold,
                ),
                title: const Text('自动连接'),
                subtitle: const Text(
                  '启动 App 后自动连接上次选择的节点',
                  style: TextStyle(color: AppColors.text2, fontSize: 11),
                ),
              ),
              const Divider(),
              _row(
                Icons.public_rounded,
                'GeoIP / GeoSite 地址库',
                state.updatingGeo
                    ? '更新中…'
                    : (state.geoAssetsReady
                        ? state.geoUpdatedText
                        : '缺失 / 不完整'),
                onTap: state.updatingGeo
                    ? null
                    : () => _updateGeo(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GoldCard(
          child: Column(
            children: [
              _row(
                Icons.article_outlined,
                '清空运行日志',
                '${state.logs.length} 条',
                onTap: () {
                  state.clearLogs();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('运行日志已清空')),
                  );
                },
              ),
              const Divider(),
              _row(
                Icons.memory_rounded,
                '代理核心',
                state.coreReady
                    ? (state.coreVersion.isEmpty ? '已就绪' : state.coreVersion)
                    : '未就绪',
                onTap: () => _showCoreInfo(context, state),
              ),
              const Divider(),
              _row(
                Icons.info_outline,
                '关于应用',
                'v${state.appVersion}',
                onTap: () => _showAbout(context, state),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '本页只保留已经接入实际功能的设置。路由模式会在切换后重新建立 VPN；Geo 数据更新完成后，智能模式会自动重新加载规则。',
            style: TextStyle(
              color: AppColors.text2,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickRouteMode(BuildContext context, AppState state) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '选择路由模式',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              for (final mode in const ['智能模式', '全局模式', '直连模式'])
                RadioListTile<String>(
                  value: mode,
                  groupValue: state.mode,
                  activeColor: AppColors.gold,
                  title: Text(mode),
                  subtitle: Text(
                    mode == '智能模式'
                        ? '中国大陆与局域网直连，其他流量走代理'
                        : mode == '全局模式'
                            ? '所有 TCP / UDP 流量走代理'
                            : '所有 TCP / UDP 流量直连',
                    style: const TextStyle(
                      color: AppColors.text2,
                      fontSize: 11,
                    ),
                  ),
                  onChanged: (v) => Navigator.pop(context, v),
                ),
            ],
          ),
        ),
      ),
    );
    if (value != null && context.mounted) {
      await context.read<AppState>().setMode(value);
    }
  }

  Future<void> _updateGeo(BuildContext context) async {
    try {
      await context.read<AppState>().updateGeoAssets();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GeoIP / GeoSite 更新完成并已校验')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Geo 数据更新失败：$e')),
        );
      }
    }
  }

  void _showCoreInfo(BuildContext context, AppState state) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('代理核心'),
        content: Text(
          state.coreReady
              ? '核心已就绪${state.coreVersion.isEmpty ? '' : ' · ${state.coreVersion}'}\n\n'
                  'Xray 用于普通单节点连接；sing-box 用于 Hysteria2、Snell 和启用前置代理的链式连接。'
              : '代理核心未就绪，请查看运行日志。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context, AppState state) {
    showAboutDialog(
      context: context,
      applicationName: 'AurumProxy',
      applicationVersion: state.appVersion,
      applicationLegalese: 'Android ARM64 · Xray + sing-box',
    );
  }

  Widget _row(
    IconData icon,
    String title,
    String trailing, {
    required VoidCallback? onTap,
  }) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: AppColors.gold),
        title: Text(title),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trailing.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Text(
                  trailing,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text2,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            if (onTap != null)
              const Icon(Icons.chevron_right, color: AppColors.text2),
          ],
        ),
        onTap: onTap,
      );
}
