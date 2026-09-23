import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/gold_background.dart';
import 'home_screen.dart';
import 'nodes_screen.dart';
import 'subscriptions_screen.dart';
import 'logs_screen.dart';
import 'settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;

  final pages = const [
    HomeScreen(),
    NodesScreen(),
    SubscriptionsScreen(),
    LogsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return GoldBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(child: IndexedStack(index: index, children: pages)),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
          child: NavigationBar(
            height: 66,
            selectedIndex: index,
            onDestinationSelected: (v) => setState(() => index = v),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: '首页'),
              NavigationDestination(icon: Icon(Icons.public_outlined), selectedIcon: Icon(Icons.public), label: '节点'),
              NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: '订阅'),
              NavigationDestination(icon: Icon(Icons.article_outlined), selectedIcon: Icon(Icons.article), label: '日志'),
              NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
            ],
          ),
        ),
      ),
    );
  }
}
