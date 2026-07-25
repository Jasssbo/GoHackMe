import 'package:flutter/material.dart';

import '../../../core/theme/cyberpunk_colors.dart';

// ── DemoScreen ─────────────────────────────────────────────────────────────

/// Placeholder for the interactive Go tutorial / demo mode.
///
/// Will walk players through Go rules, attack mechanics, and strategy tips
/// using NAVI narration and a step-by-step board interaction sequence.
/// See [Routes.demo].
class DemoScreen extends StatelessWidget {
  const DemoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyberpunkColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: CyberpunkColors.cyan.withValues(alpha: 0.06),
                border: Border(
                  bottom: BorderSide(
                    color: CyberpunkColors.cyan.withValues(alpha: 0.30),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    'NAVI://demo',
                    style: TextStyle(
                      color: CyberpunkColors.cyan.withValues(alpha: 0.90),
                      fontSize: 9.5,
                      letterSpacing: 2.5,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Text(
                      '[×]',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        letterSpacing: 1,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Content ─────────────────────────────────────────────────
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '> DEMO MODE',
                      style: TextStyle(
                        color: CyberpunkColors.cyan,
                        fontSize: 14,
                        letterSpacing: 3,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      '  Interactive Go tutorial — under construction.',
                      style: TextStyle(
                        color: CyberpunkColors.textSecondary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '  Will teach placement, capture, territory, and attacks.',
                      style: TextStyle(
                        color: CyberpunkColors.textSecondary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
