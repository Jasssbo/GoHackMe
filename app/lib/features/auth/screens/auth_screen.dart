import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/cyberpunk_colors.dart';
import '../providers/auth_provider.dart';

/// Auth screen – username / display name entry.
///
/// Full authentication (OAuth, magic link, etc.) would be added here.
/// For now it just sets a display name and moves to the lobby.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyberpunkColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Glitch title ───────────────────────────────────────────
                const Text(
                  'GOHACKME',
                  style: TextStyle(
                    color: CyberpunkColors.cyan,
                    fontSize: 36,
                    letterSpacing: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text(
                  'v0.1.0-alpha',
                  style: TextStyle(
                    color: CyberpunkColors.textDim,
                    fontSize: 10,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 48),

                // ── Login prompt ──────────────────────────────────────────
                const Text(
                  '> IDENTIFY YOURSELF',
                  style: TextStyle(
                    color: CyberpunkColors.green,
                    fontSize: 12,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  style: const TextStyle(
                    color: CyberpunkColors.textPrimary,
                    letterSpacing: 2,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'HANDLE',
                    prefixText: r'$ ',
                    prefixStyle: TextStyle(color: CyberpunkColors.cyan),
                  ),
                  onSubmitted: (_) => _enter(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _enter,
                    child: const Text('AUTHENTICATE >>'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _enter() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    ref.read(authProvider.notifier).setDisplayName(name);
    context.go(Routes.lobby);
  }
}
