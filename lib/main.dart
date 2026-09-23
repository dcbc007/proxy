import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'screens/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.initialize();
  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: const AurumProxyApp(),
    ),
  );
}

class AurumProxyApp extends StatelessWidget {
  const AurumProxyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Aurum Proxy',
      theme: AppTheme.dark,
      home: const AppShell(),
    );
  }
}
