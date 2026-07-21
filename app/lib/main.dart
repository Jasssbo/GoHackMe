import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/cyberpunk_theme.dart';
import 'core/theme/ui_scale.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // ── 1-1: Fire startup sound before any UI frame renders ──────────────────
  _playStartupSound();
  runApp(const ProviderScope(child: GoHackMeApp()));
}

/// Plays `1-1-startup.mp3` using a standalone [AudioPlayer] that lives
/// entirely outside the Riverpod tree — so it fires before the first widget
/// is built and disposes itself automatically on completion.
void _playStartupSound() {
  try {
    final player = AudioPlayer();
    player
        .play(AssetSource('audio/boot-sequence/1-1-startup.mp3'))
        .ignore();
    player.onPlayerComplete.listen((_) => player.dispose());
  } catch (_) {
    // Audio errors must never crash the app.
  }
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
