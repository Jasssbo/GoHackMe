import 'package:flutter/material.dart';
import 'package:go_engine/go_engine.dart';

import '../../../../core/theme/cyberpunk_colors.dart';

/// Collapsible reference panel listing all attack payloads and their effects.
/// Sits below the SIGNAL_LOG so the player can look up mechanics mid-game.
class AttackCodex extends StatefulWidget {
  const AttackCodex({super.key});

  @override
  State<AttackCodex> createState() => _AttackCodexState();
}

class _AttackCodexState extends State<AttackCodex> {
  void _openFullscreen(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close ATTACK_CODEX',
      barrierColor: Colors.black.withValues(alpha: 0.88),
      transitionDuration: const Duration(milliseconds: 180),
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1.0).animate(anim),
          child: child,
        ),
      ),
      pageBuilder: (ctx, _, __) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF020810),
                  border: Border.all(color: CyberpunkColors.cyanDim, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header row with close button
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: CyberpunkColors.cyanDim, width: 1),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Text(
                            '// ATTACK_CODEX',
                            style: TextStyle(
                              color: CyberpunkColors.cyanDim,
                              fontSize: 15,
                              letterSpacing: 3,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          InkWell(
                            onTap: () => Navigator.of(ctx).pop(),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Text(
                                '[X]',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  letterSpacing: 1,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Entries list
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: AttackCard.all.map((card) {
                            return Container(
                              margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: CyberpunkColors.magenta.withValues(alpha: 0.45),
                                    width: 2,
                                  ),
                                ),
                                color: CyberpunkColors.magenta.withValues(alpha: 0.03),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        card.terminalName,
                                        style: const TextStyle(
                                          color: CyberpunkColors.magenta,
                                          fontSize: 16,
                                          letterSpacing: 1.5,
                                          fontFamily: 'monospace',
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Text(
                                        '${card.subnetCost} SN',
                                        style: const TextStyle(
                                          color: CyberpunkColors.amber,
                                          fontSize: 14,
                                          letterSpacing: 1,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    card.description,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      letterSpacing: 0.3,
                                      height: 1.6,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: CyberpunkColors.cyan.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: CyberpunkColors.cyan.withValues(alpha: 0.85),
          width: 1.2,
        ),
        boxShadow: CyberpunkColors.glowFor(CyberpunkColors.cyan, intensity: 1.2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openFullscreen(context),
          borderRadius: BorderRadius.circular(4),
          splashColor: CyberpunkColors.cyan.withValues(alpha: 0.3),
          highlightColor: CyberpunkColors.cyan.withValues(alpha: 0.2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.menu_book_rounded,
                  size: 13,
                  color: CyberpunkColors.cyan,
                ),
                const SizedBox(width: 6),
                const Text(
                  '// ATTACK_CODEX',
                  style: TextStyle(
                    color: CyberpunkColors.cyan,
                    fontSize: 9.5,
                    letterSpacing: 1.5,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color: CyberpunkColors.cyan,
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
