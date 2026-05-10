import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/cyberpunk_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: GoHackMeApp()));
}

class GoHackMeApp extends StatelessWidget {
  const GoHackMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'GoHackMe',
      debugShowCheckedModeBanner: false,
      theme: CyberpunkTheme.dark,
      routerConfig: appRouter,
    );
  }
}
