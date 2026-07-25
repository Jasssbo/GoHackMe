import 'package:flutter/material.dart';
import 'package:go_engine/go_engine.dart';

import '../../../../core/theme/cyberpunk_colors.dart';

/// Interactive deck of attack cards for launching cybersecurity actions.
class AttackDeckWidget extends StatelessWidget {
  final int subnets;
  final List<Player> players;
  final String localPlayerId;
  final void Function(AttackAction) onAttack;
  final void Function(AttackAction partial) onPickPosition;

  const AttackDeckWidget({
    super.key,
    required this.subnets,
    required this.players,
    required this.localPlayerId,
    required this.onAttack,
    required this.onPickPosition,
  });

  Future<void> _pick(BuildContext context, AttackCard card) async {
    // PATCH is a self-buff – no target selection needed.
    if (card.type == AttackType.patch) {
      onAttack(AttackAction(
        type: card.type,
        attackerPlayerId: localPlayerId,
        targetPlayerId: localPlayerId,
      ));
      return;
    }

    // HONEYPOT: board-targeted, no player selection.
    if (card.type == AttackType.knightseye) {
      onPickPosition(AttackAction(
        type: card.type,
        attackerPlayerId: localPlayerId,
        targetPlayerId: localPlayerId,
      ));
      return;
    }

    // WORM: board-targeted – target player derived from tapped stone.
    if (card.type == AttackType.worm) {
      onPickPosition(AttackAction(
        type: card.type,
        attackerPlayerId: localPlayerId,
        targetPlayerId: localPlayerId,
      ));
      return;
    }

    // BACKDOOR is self-applied – no target selection needed.
    if (card.type == AttackType.backdoor) {
      onAttack(AttackAction(
        type: card.type,
        attackerPlayerId: localPlayerId,
        targetPlayerId: localPlayerId,
      ));
      return;
    }

    final targets = players.where((p) => p.id != localPlayerId).toList();
    if (targets.isEmpty) return;

    // DDOS: auto-targets next player in turn order.
    if (card.type == AttackType.ddos) {
      final myIndex = players.indexWhere((p) => p.id == localPlayerId);
      final target = players[(myIndex + 1) % players.length];
      onAttack(AttackAction(
        type: card.type,
        attackerPlayerId: localPlayerId,
        targetPlayerId: target.id,
      ));
      return;
    }

    // TIMEBOMB: broadcast – targets all opponents simultaneously.
    if (card.type == AttackType.psyche) {
      onAttack(AttackAction(
        type: card.type,
        attackerPlayerId: localPlayerId,
        targetPlayerId: localPlayerId,
      ));
      return;
    }

    // TROJAN and MITM: require explicit target selection.
    final Player target;
    if (targets.length == 1) {
      target = targets.first;
    } else {
      final selected = await showDialog<Player>(
        context: context,
        builder: (_) => AsciiTargetDialog(
          card: card,
          targets: targets,
          allPlayers: players,
        ),
      );
      if (selected == null) return;
      target = selected;
    }

    onAttack(AttackAction(
      type: card.type,
      attackerPlayerId: localPlayerId,
      targetPlayerId: target.id,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ...AttackCard.all.map((card) {
            final enabled = subnets >= card.subnetCost;
            final color = enabled
                ? CyberpunkColors.green
                : const Color(0xFF6B2030);
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: InkWell(
                onTap: enabled ? () => _pick(context, card) : null,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: color.withValues(alpha: enabled ? 0.85 : 0.35),
                    ),
                    color: color.withValues(alpha: enabled ? 0.08 : 0.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            card.terminalName,
                            style: TextStyle(
                              color: color,
                              fontSize: 9,
                              letterSpacing: 1,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${card.subnetCost}SN',
                            style: TextStyle(
                              color: CyberpunkColors.amber
                                  .withValues(alpha: enabled ? 0.95 : 0.45),
                              fontSize: 9,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        card.description,
                        style: TextStyle(
                          color: color.withValues(alpha: enabled ? 0.75 : 0.40),
                          fontSize: 8,
                          letterSpacing: 0.3,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class AsciiTargetDialog extends StatelessWidget {
  final AttackCard card;
  final List<Player> targets;
  final List<Player> allPlayers;

  const AsciiTargetDialog({
    super.key,
    required this.card,
    required this.targets,
    required this.allPlayers,
  });

  static const _stoneColors = [
    CyberpunkColors.stoneP1,
    CyberpunkColors.stoneP2,
    CyberpunkColors.stoneP3,
    CyberpunkColors.stoneP4,
  ];

  Color _colorFor(Player p) {
    final idx = allPlayers.indexWhere((x) => x.id == p.id);
    return _stoneColors[(idx < 0 ? 0 : idx) % _stoneColors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF070C10),
      shape: const RoundedRectangleBorder(),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: CyberpunkColors.cyanDim.withValues(alpha: 0.70),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '// ${card.terminalName}',
              style: TextStyle(
                color: CyberpunkColors.cyan.withValues(alpha: 0.95),
                fontSize: 10,
                letterSpacing: 2,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 1,
              color: CyberpunkColors.cyanDim.withValues(alpha: 0.50),
            ),
            const SizedBox(height: 8),
            Text(
              card.description,
              style: TextStyle(
                color: CyberpunkColors.textSecondary.withValues(alpha: 0.90),
                fontSize: 9,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '> SELECT_TARGET',
              style: TextStyle(
                color: CyberpunkColors.green.withValues(alpha: 0.95),
                fontSize: 9,
                letterSpacing: 1.2,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            ...targets.map((p) {
              final col = _colorFor(p);
              return InkWell(
                onTap: () => Navigator.pop(context, p),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: col.withValues(alpha: 0.80), width: 2),
                    ),
                    color: col.withValues(alpha: 0.07),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: col,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(
                        p.displayName,
                        style: TextStyle(
                          color: col.withValues(alpha: 0.95),
                          fontSize: 10,
                          letterSpacing: 1,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '[>>]',
                        style: TextStyle(
                          color: col.withValues(alpha: 0.55),
                          fontSize: 9,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => Navigator.pop(context),
              child: const Text(
                '  [X]  ABORT',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  letterSpacing: 1.2,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
