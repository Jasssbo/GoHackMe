import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/cyberpunk_theme.dart';
import 'core/theme/ui_scale.dart';

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
      // ── Responsive scaling ────────────────────────────────────────────────
      // Scales all Text widgets automatically via textScaler, and injects
      // UiScale so individual widgets can scale non-text dimensions with
      // context.s() / context.sp().
      builder: (context, child) {
        final scale = UiScale.fromContext(context);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: UiScale(scale: scale, child: child!),
        );
      },
    );
  }
}
