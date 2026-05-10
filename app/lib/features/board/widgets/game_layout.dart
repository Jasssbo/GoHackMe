import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_engine/go_engine.dart';

import '../../../core/theme/cyberpunk_colors.dart';
import 'board_widget.dart';

// ── GameLayout ────────────────────────────────────────────────────────────

/// Full game UI: board on top, terminal + attacks side-by-side on bottom.
///
/// Used by both [GameScreen] (online) and [LocalGameScreen] (single-player).
/// Provide [logLines] from whichever provider the caller watches.
class GameLayout extends StatefulWidget {
  final GameState state;
  final String localPlayerId;

  /// Short label shown in the top-right chip, e.g. "ROOM:XXXX" or "LOCAL".
  final String statusLabel;

  final List<String> logLines;
  final Position? lastPlaced;
  final void Function(Position) onPlace;
  final void Function(AttackAction) onAttack;

  /// Increment this to fire a glitch burst on the parent [GlitchOverlay].
  final ValueNotifier<int>? attackBurst;

  const GameLayout({
    super.key,
    required this.state,
    required this.localPlayerId,
    required this.statusLabel,
    required this.logLines,
    required this.lastPlaced,
    required this.onPlace,
    required this.onAttack,
    this.attackBurst,
  });

  @override
  State<GameLayout> createState() => _GameLayoutState();
}

class _GameLayoutState extends State<GameLayout> {
  /// Non-null while the player has selected a position-based attack
  /// (worm/honeypot) and needs to tap the board to complete it.
  AttackAction? _pendingPositionAttack;

  @override
  void didUpdateWidget(GameLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Cancel pending attack if it's no longer the player's turn.
    if (_pendingPositionAttack != null) {
      final isMyTurn = widget.state.currentPlayerId == widget.localPlayerId;
      if (!isMyTurn || widget.state.phase != GamePhase.attack) {
        setState(() => _pendingPositionAttack = null);
      }
    }
  }

  void _onPickPosition(AttackAction partial) {
    setState(() => _pendingPositionAttack = partial);
  }

  void _onBoardTap(Position pos) {
    final pending = _pendingPositionAttack;
    if (pending != null) {
      // Complete the position-based attack.
      setState(() => _pendingPositionAttack = null);
      widget.onAttack(AttackAction(
        type: pending.type,
        attackerPlayerId: pending.attackerPlayerId,
        targetPlayerId: pending.targetPlayerId,
        targetPosition: pos,
      ));
    } else {
      widget.onPlace(pos);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMyTurn = widget.state.currentPlayerId == widget.localPlayerId;
    // Show attacks whenever it's my turn – player decides attack before placing.
    final inAttack = isMyTurn && widget.state.phase == GamePhase.attack;
    final isPicking = _pendingPositionAttack != null;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Status strip ────────────────────────────────────────
          GameStatusStrip(
            state: widget.state,
            localPlayerId: widget.localPlayerId,
            statusLabel: widget.statusLabel,
          ),

          // ── Position-pick hint banner ────────────────────────
          if (isPicking)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              color: CyberpunkColors.magenta.withValues(alpha: 0.12),
              child: Row(
                children: [
                  Text(
                    '>> ${_pendingPositionAttack!.type.name.toUpperCase()}_MODE :: TAP_TARGET_NODE',
                    style: const TextStyle(
                      color: CyberpunkColors.magenta,
                      fontSize: 9,
                      letterSpacing: 1.2,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => setState(() => _pendingPositionAttack = null),
                    child: const Text(
                      '[ABORT]',
                      style: TextStyle(
                        color: CyberpunkColors.textDim,
                        fontSize: 9,
                        letterSpacing: 1,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Backdoor hint banner ──────────────────────────────
          if (widget.state.phase == GamePhase.hijackedVictimPlacement &&
              isMyTurn)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              color: CyberpunkColors.error.withValues(alpha: 0.10),
              child: const Text(
                '>> BACKDOOR :: HIJACK_ACTIVE :: TAP TO PLACE ENEMY NODE',
                style: TextStyle(
                  color: CyberpunkColors.error,
                  fontSize: 9,
                  letterSpacing: 1.2,
                  fontFamily: 'monospace',
                ),
              ),
            ),

          // ── Board (top, ~60% of remaining space) ─────────────
          Expanded(
            flex: 3,
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: BoardWidget(
                    board: widget.state.board,
                    boardSize: widget.state.board.size,
                    lastPlaced: widget.lastPlaced,
                    onTap: isMyTurn &&
                            (widget.state.phase == GamePhase.attack ||
                                widget.state.phase ==
                                    GamePhase.hijackedVictimPlacement)
                        ? _onBoardTap
                        : null,
                  ),
                ),
              ),
            ),
          ),

          const PanelDivider(),

          // ── Bottom half: terminal (left) | attacks/status (right) ──
          Expanded(
            flex: 2,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Terminal log + attack codex
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const PanelHeader('// SIGNAL_LOG'),
                      const PanelDivider(),
                      Expanded(child: GameTerminalLog(lines: widget.logLines)),
                      const PanelDivider(),
                      const AttackCodex(),
                    ],
                  ),
                ),
                // Vertical separator
                Container(width: 1, color: const Color(0xFF0D2035)),
                // Attacks / status + player list
                GameSidePanel(
                  state: widget.state,
                  localPlayerId: widget.localPlayerId,
                  inAttack: inAttack && !isPicking,
                  onAttack: widget.onAttack,
                  onPickPosition: _onPickPosition,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── GameStatusStrip ───────────────────────────────────────────────────────

class GameStatusStrip extends StatefulWidget {
  final GameState state;
  final String localPlayerId;
  final String statusLabel;

  const GameStatusStrip({
    super.key,
    required this.state,
    required this.localPlayerId,
    required this.statusLabel,
  });

  @override
  State<GameStatusStrip> createState() => _GameStatusStripState();
}

class _GameStatusStripState extends State<GameStatusStrip> {
  late Timer _clockTimer;
  late String _clock;

  @override
  void initState() {
    super.initState();
    _clock = _formatNow();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _clock = _formatNow());
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  static String _formatNow() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final localPlayerId = widget.localPlayerId;
    final isMyTurn = state.currentPlayerId == localPlayerId;
    final phase = state.phase.name.toUpperCase();
    final turn = state.turnNumber.toString().padLeft(3, '0');
    final nodeCount = state.board.stones.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      color: const Color(0xFF050D15),
      child: Row(
        children: [
          AsciiChip(
            isMyTurn ? '▶ ${state.currentPlayer.displayName}' : '◌ WAIT',
            color: isMyTurn ? CyberpunkColors.cyan : CyberpunkColors.textDim,
          ),
          const SizedBox(width: 6),
          AsciiChip('T:$turn', color: CyberpunkColors.yellow),
          const SizedBox(width: 6),
          AsciiChip('N:$nodeCount',
              color: CyberpunkColors.green.withValues(alpha: 0.8)),
          const SizedBox(width: 6),
          AsciiChip('LAYER::$phase',
              color: CyberpunkColors.green.withValues(alpha: 0.5)),
          const Spacer(),
          AsciiChip(
            'SN:${state.subnetsOf(localPlayerId)}',
            color: CyberpunkColors.yellow,
          ),
          const SizedBox(width: 6),
          AsciiChip(_clock,
              color: CyberpunkColors.textDim),
          const SizedBox(width: 6),
          AsciiChip(widget.statusLabel, color: CyberpunkColors.textDim),
        ],
      ),
    );
  }
}

// ── AsciiChip ─────────────────────────────────────────────────────────────

class AsciiChip extends StatelessWidget {
  final String text;
  final Color color;

  const AsciiChip(this.text, {super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      '[$text]',
      style: TextStyle(
        color: color,
        fontSize: 10,
        letterSpacing: 1.0,
        fontFamily: 'monospace',
      ),
    );
  }
}

// ── GameSidePanel ─────────────────────────────────────────────────────────

class GameSidePanel extends StatelessWidget {
  final GameState state;
  final String localPlayerId;
  final bool inAttack;
  final void Function(AttackAction) onAttack;
  final void Function(AttackAction partial) onPickPosition;

  const GameSidePanel({
    super.key,
    required this.state,
    required this.localPlayerId,
    required this.inAttack,
    required this.onAttack,
    required this.onPickPosition,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      decoration: const BoxDecoration(
        color: Color(0xFF050D15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Players ──────────────────────────────────────────────
          const PanelHeader('// ENTITIES'),
          ..._playerRows(),
          const PanelDivider(),

          // ── Attack or status ──────────────────────────────────────
          if (inAttack) ...[
            const PanelHeader('// ATTACK_VECTOR'),
            Expanded(
              child: SingleChildScrollView(
                child: AttackCardsPanel(
                  subnets: state.subnetsOf(localPlayerId),
                  players: state.players,
                  localPlayerId: localPlayerId,
                  onAttack: onAttack,                  onPickPosition: onPickPosition,                ),
              ),
            ),
          ] else ...[
            const PanelHeader('// LAYER_STATUS'),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              child: Text(
                state.phase == GamePhase.attack
                    ? (state.currentPlayerId == localPlayerId
                        ? '> YOUR_TURN.exe'
                        : '> AWAITING_ENTITY_UPLINK')
                    : '> LAYER::${state.phase.name.toUpperCase()}',
                style: const TextStyle(
                  color: CyberpunkColors.green,
                  fontSize: 10,
                  letterSpacing: 1,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const Spacer(),
          ],
        ],
      ),
    );
  }

  List<Widget> _playerRows() {
    const colors = [
      CyberpunkColors.stoneP1,
      CyberpunkColors.stoneP2,
      CyberpunkColors.stoneP3,
      CyberpunkColors.stoneP4,
    ];
    return state.players.map((p) {
      final isCurrent = state.currentPlayerId == p.id;
      final isLocal = p.id == localPlayerId;
      final idx = state.players.indexOf(p);
      final color = colors[idx % colors.length];
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        color:
            isCurrent ? color.withValues(alpha: 0.06) : Colors.transparent,
        child: Row(
          children: [
            Text(
              isCurrent ? '▶' : '  ',
              style: TextStyle(color: color, fontSize: 9),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${p.displayName}${isLocal ? ' [YOU]' : ''}',
                style: TextStyle(
                  color: color.withValues(alpha: 0.85),
                  fontSize: 10,
                  letterSpacing: 0.8,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              'SN:${state.subnetsOf(p.id)}',
              style: TextStyle(
                color: CyberpunkColors.yellow.withValues(alpha: 0.6),
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}

// ── PanelHeader / PanelDivider ────────────────────────────────────────────

class PanelHeader extends StatelessWidget {
  final String text;
  const PanelHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      child: Text(
        text,
        style: const TextStyle(
          color: CyberpunkColors.cyanDim,
          fontSize: 9,
          letterSpacing: 2,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class PanelDivider extends StatelessWidget {
  const PanelDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: const Color(0xFF0D2035),
    );
  }
}

// ── AttackCodex ───────────────────────────────────────────────────────────

/// Collapsible reference panel listing all attack payloads and their effects.
/// Sits below the SIGNAL_LOG so the player can look up mechanics mid-game.
class AttackCodex extends StatefulWidget {
  const AttackCodex({super.key});

  @override
  State<AttackCodex> createState() => _AttackCodexState();
}

class _AttackCodexState extends State<AttackCodex> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Header / toggle ─────────────────────────────────────
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
            child: Row(
              children: [
                Text(
                  '// ATTACK_CODEX',
                  style: const TextStyle(
                    color: CyberpunkColors.cyanDim,
                    fontSize: 9,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                Text(
                  _expanded ? '[-]' : '[+]',
                  style: const TextStyle(
                    color: CyberpunkColors.textDim,
                    fontSize: 9,
                    letterSpacing: 1,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ),
        // ── Entries ─────────────────────────────────────────────
        if (_expanded)
          Container(
            color: const Color(0xFF030A11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: AttackCard.all.map((card) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: card.terminalName.padRight(14),
                          style: const TextStyle(
                            color: CyberpunkColors.magenta,
                            fontSize: 8,
                            letterSpacing: 0.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                        TextSpan(
                          text: '${card.subnetCost}SN  ',
                          style: const TextStyle(
                            color: CyberpunkColors.yellow,
                            fontSize: 8,
                            fontFamily: 'monospace',
                          ),
                        ),
                        TextSpan(
                          text: card.description,
                          style: const TextStyle(
                            color: CyberpunkColors.textDim,
                            fontSize: 8,
                            letterSpacing: 0.2,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

// ── AttackCardsPanel ──────────────────────────────────────────────────────

/// Whether this attack type requires the player to tap a board position.
bool _requiresPosition(AttackType type) =>
    type == AttackType.worm || type == AttackType.honeypot;

class AttackCardsPanel extends StatelessWidget {
  final int subnets;
  final List<Player> players;
  final String localPlayerId;
  final void Function(AttackAction) onAttack;
  final void Function(AttackAction partial) onPickPosition;

  const AttackCardsPanel({
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

    final targets = players.where((p) => p.id != localPlayerId).toList();
    if (targets.isEmpty) return;

    // Resolve target: auto-select when only one opponent, else show dialog.
    final Player target;
    if (targets.length == 1) {
      target = targets.first;
    } else {
      final selected = await showDialog<Player>(
        context: context,
        builder: (_) => AsciiTargetDialog(card: card, targets: targets),
      );
      if (selected == null) return;
      target = selected;
    }

    final partial = AttackAction(
      type: card.type,
      attackerPlayerId: localPlayerId,
      targetPlayerId: target.id,
    );

    if (_requiresPosition(card.type)) {
      // Enter board pick-position mode; the board tap will complete the action.
      onPickPosition(partial);
    } else {
      onAttack(partial);
    }
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
            final color =
                enabled ? CyberpunkColors.magenta : CyberpunkColors.textDim;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: InkWell(
                onTap: enabled ? () => _pick(context, card) : null,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: color.withValues(alpha: enabled ? 0.6 : 0.2),
                    ),
                    color: color.withValues(alpha: enabled ? 0.04 : 0.0),
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
                              color: CyberpunkColors.yellow
                                  .withValues(alpha: enabled ? 0.8 : 0.3),
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
                          color: color.withValues(alpha: enabled ? 0.45 : 0.25),
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
          const SizedBox(height: 2),
          // SKIP button removed: turn advances automatically after placing a stone.
        ],
      ),
    );
  }
}

// ── AsciiTargetDialog ─────────────────────────────────────────────────────

class AsciiTargetDialog extends StatelessWidget {
  final AttackCard card;
  final List<Player> targets;

  const AsciiTargetDialog({
    super.key,
    required this.card,
    required this.targets,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: CyberpunkColors.surface,
      shape: const RoundedRectangleBorder(),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: CyberpunkColors.cyanDim, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '╔══ ${card.terminalName} ══╗',
              style: const TextStyle(
                color: CyberpunkColors.cyan,
                fontSize: 11,
                letterSpacing: 1.5,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              card.description,
              style: const TextStyle(
                color: CyberpunkColors.textSecondary,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '> SELECT_TARGET:',
              style: TextStyle(
                color: CyberpunkColors.green,
                fontSize: 10,
                letterSpacing: 1,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            ...targets.map(
              (p) => InkWell(
                onTap: () => Navigator.pop(context, p),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '  [>>] ${p.displayName}',
                    style: const TextStyle(
                      color: CyberpunkColors.magenta,
                      fontSize: 11,
                      letterSpacing: 1,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => Navigator.pop(context),
              child: const Text(
                '  [X]  ABORT',
                style: TextStyle(
                  color: CyberpunkColors.textDim,
                  fontSize: 10,
                  letterSpacing: 1,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── GameTerminalLog ───────────────────────────────────────────────────────

class GameTerminalLog extends StatelessWidget {
  final List<String> lines;
  const GameTerminalLog({super.key, required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF030810),
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      child: ListView.builder(
        reverse: true,
        itemCount: lines.length,
        itemBuilder: (_, i) {
          final line = lines[lines.length - 1 - i];
          final isError = line.contains('ERROR');
          return Text(
            line,
            style: TextStyle(
              color: isError
                  ? CyberpunkColors.error
                  : CyberpunkColors.green.withValues(alpha: 0.75),
              fontSize: 8.5,
              letterSpacing: 0.3,
              fontFamily: 'monospace',
              height: 1.5,
            ),
          );
        },
      ),
    );
  }
}
