import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_engine/go_engine.dart';

import '../../../core/theme/cyberpunk_colors.dart';
import '../../../core/theme/ui_scale.dart';
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

  /// Called when the player taps the PASS button.
  final VoidCallback? onPass;

  /// Called when the player taps the EXIT button.
  final VoidCallback? onExit;

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
    this.onPass,
    this.onExit,
    this.attackBurst,
  });

  @override
  State<GameLayout> createState() => _GameLayoutState();
}

class _GameLayoutState extends State<GameLayout> {
  /// Non-null while the player has selected a position-based attack
  /// (worm/honeypot) and needs to tap the board to complete it.
  AttackAction? _pendingPositionAttack;

  // ── Timebomb countdown ────────────────────────────────────────────────────
  Timer? _timebombTimer;
  int _timebombSecondsLeft = 5;

  bool get _isUnderTimebomb =>
      widget.state.currentPlayerId == widget.localPlayerId &&
      widget.state.hasEffect(widget.localPlayerId, AttackType.psyche);

  void _startTimebombIfNeeded() {
    if (!_isUnderTimebomb) return;
    if (_timebombTimer != null && _timebombTimer!.isActive) return;
    _timebombSecondsLeft = 5;
    _timebombTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _timebombSecondsLeft--);
      if (_timebombSecondsLeft <= 0) {
        t.cancel();
        _timebombTimer = null;
        // Cancel any pending position-pick and auto-pass.
        _pendingPositionAttack = null;
        widget.onPass?.call();
      }
    });
  }

  void _cancelTimebomb() {
    _timebombTimer?.cancel();
    _timebombTimer = null;
  }

  // ── Turn countdown (15 s) ─────────────────────────────────────────────────
  static const _kTurnSeconds = 15;
  Timer? _turnCountdownTimer;
  int _turnSecondsLeft = _kTurnSeconds;

  void _resetTurnCountdown() {
    _turnCountdownTimer?.cancel();
    _turnSecondsLeft = _kTurnSeconds;
    _turnCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _turnSecondsLeft--;
        if (_turnSecondsLeft <= 0) { t.cancel(); _turnSecondsLeft = 0; }
      });
    });
  }

  void _cancelTurnCountdown() {
    _turnCountdownTimer?.cancel();
    _turnCountdownTimer = null;
    _turnSecondsLeft = _kTurnSeconds;
  }

  @override
  void dispose() {
    _cancelTimebomb();
    _cancelTurnCountdown();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _startTimebombIfNeeded();
    _resetTurnCountdown();
  }

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
    // Manage timebomb countdown.
    if (_isUnderTimebomb) {
      // If the turn just changed to the local player, reset the countdown.
      if (oldWidget.state.currentPlayerId != widget.state.currentPlayerId) {
        _cancelTimebomb();
        _startTimebombIfNeeded();
      } else {
        _startTimebombIfNeeded(); // idempotent if already running
      }
    } else {
      _cancelTimebomb();
    }
    // Reset turn countdown whenever the active player changes.
    if (oldWidget.state.currentPlayerId != widget.state.currentPlayerId ||
        oldWidget.state.phase != widget.state.phase) {
      _resetTurnCountdown();
    }
  }

  void _onPickPosition(AttackAction partial) {
    setState(() => _pendingPositionAttack = partial);
  }

  void _onBoardTap(Position pos) {
    final pending = _pendingPositionAttack;
    if (pending != null) {
      // For WORM, derive the target player from whoever owns the tapped stone.
      if (pending.type == AttackType.worm) {
        final stoneColor = widget.state.board.at(pos);
        if (stoneColor == null) return; // tapped empty cell
        final attackerColor =
            widget.state.currentPlayerColor(pending.attackerPlayerId);
        if (stoneColor == attackerColor) return; // tapped own stone
        final owner = widget.state.players.firstWhere(
          (p) => widget.state.currentPlayerColor(p.id) == stoneColor,
          orElse: () => Player(id: '', displayName: ''),
        );
        if (owner.id.isEmpty) return;
        setState(() => _pendingPositionAttack = null);
        widget.onAttack(AttackAction(
          type: pending.type,
          attackerPlayerId: pending.attackerPlayerId,
          targetPlayerId: owner.id,
          targetPosition: pos,
        ));
        return;
      }
      // For all other position-based attacks (HONEYPOT), use the stored target.
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
            onPass: widget.onPass,
            onExit: widget.onExit,
            turnSecondsLeft: _turnSecondsLeft,
          ),

          // ── Position-pick hint banner ────────────────────────
          if (isPicking)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: CyberpunkColors.amber.withValues(alpha: 0.07),
                border: Border(
                  bottom: BorderSide(
                    color: CyberpunkColors.amber.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '>> ${_pendingPositionAttack!.type.name.toUpperCase()}  ·  TAP_TARGET_NODE',
                    style: TextStyle(
                      color: CyberpunkColors.amber.withValues(alpha: 0.95),
                      fontSize: 9,
                      letterSpacing: 1.2,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => setState(() => _pendingPositionAttack = null),
                    child: Text(
                      '[ABORT]',
                      style: TextStyle(
                        color: CyberpunkColors.textSecondary.withValues(alpha: 0.80),
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: CyberpunkColors.error.withValues(alpha: 0.07),
                border: Border(
                  left: BorderSide(
                    color: CyberpunkColors.error.withValues(alpha: 0.55),
                    width: 2,
                  ),
                ),
              ),
              child: const Text(
                '>> BACKDOOR  ·  HIJACK_ACTIVE  ·  TAP TO PLACE ENEMY NODE',
                style: TextStyle(
                  color: CyberpunkColors.error,
                  fontSize: 9,
                  letterSpacing: 1.2,
                  fontFamily: 'monospace',
                ),
              ),
            ),

          // ── Timebomb countdown banner ─────────────────────────
          if (_isUnderTimebomb)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: CyberpunkColors.error.withValues(alpha: 0.10),
                border: Border(
                  bottom: BorderSide(
                    color: CyberpunkColors.error.withValues(alpha: 0.55),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '>> PSYCHE  ·  ACT_OR_SKIP',
                    style: TextStyle(
                      color: CyberpunkColors.error.withValues(alpha: 0.95),
                      fontSize: 9,
                      letterSpacing: 1.2,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '[$_timebombSecondsLeft]',
                    style: const TextStyle(
                      color: CyberpunkColors.error,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
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
                    activePlayerColor: widget.state.currentPlayerColor(
                        widget.state.currentPlayerId),
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
                Container(width: 1, color: const Color(0xFF0C1814)),
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

class GameStatusStrip extends StatelessWidget {
  final GameState state;
  final String localPlayerId;
  final VoidCallback? onPass;
  final VoidCallback? onExit;
  final int turnSecondsLeft;

  const GameStatusStrip({
    super.key,
    required this.state,
    required this.localPlayerId,
    this.onPass,
    this.onExit,
    this.turnSecondsLeft = 15,
  });

  @override
  Widget build(BuildContext context) {
    final isMyTurn = state.currentPlayerId == localPlayerId;
    // The active playing phase is always `attack` (placement + optional attacks).
    final canPass  = isMyTurn && state.phase == GamePhase.attack;
    final isActive = state.phase != GamePhase.scoring;
    final urgentSeconds = turnSecondsLeft <= 5;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF040709),
        border: Border(
          bottom: BorderSide(color: Color(0xFF0D1A18), width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        children: [
          if (canPass && onPass != null) ...[
            _StripButton(
              label: 'PASS',
              color: CyberpunkColors.amber,
              onTap: onPass!,
            ),
            const SizedBox(width: 8),
          ],
          Text(
            isMyTurn
                ? '◉ ${state.currentPlayer.displayName}'
                : '○  SIGNAL WAIT',
            style: TextStyle(
              color: isMyTurn
                  ? CyberpunkColors.cyan.withValues(alpha: 0.95)
                  : CyberpunkColors.textSecondary.withValues(alpha: 0.75),
              fontSize: 9.5,
              letterSpacing: 1.2,
              fontFamily: 'monospace',
            ),
          ),
          const Spacer(),
          // ── Turn countdown ───────────────────────
          if (isActive)
            Text(
              '${turnSecondsLeft}s',
              style: TextStyle(
                color: urgentSeconds
                    ? CyberpunkColors.magenta
                    : Colors.white.withValues(alpha: 0.90),
                fontSize: 9,
                letterSpacing: 1,
                fontFamily: 'monospace',
                fontWeight: urgentSeconds ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          const SizedBox(width: 8),
          if (onExit != null)
            _StripButton(
              label: 'EXIT',
              color: CyberpunkColors.textSecondary,
              onTap: onExit!,
            ),
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

// ── _StripButton ──────────────────────────────────────────────────────────

/// Small tappable ASCII-styled button used in the status strip.
class _StripButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _StripButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.70), width: 1),
          color: color.withValues(alpha: 0.10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            letterSpacing: 1.2,
            fontFamily: 'monospace',
          ),
        ),
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
      width: context.s(180),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: isCurrent
            ? BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: color.withValues(alpha: 0.85),
                    width: 2,
                  ),
                ),
                color: color.withValues(alpha: 0.10),
              )
            : const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Colors.transparent, width: 2),
                ),
              ),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(right: 6),
              color: color.withValues(alpha: isCurrent ? 1.0 : 0.45),
            ),
            Expanded(
              child: Text(
                '${p.displayName}${isLocal ? ' [YOU]' : ''}',
                style: TextStyle(
                  color: color.withValues(alpha: isCurrent ? 1.0 : 0.65),
                  fontSize: 9.5,
                  letterSpacing: 0.8,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              'SN:${state.subnetsOf(p.id)}',
              style: TextStyle(
                color: CyberpunkColors.amber
                    .withValues(alpha: isCurrent ? 0.95 : 0.65),
                fontSize: 8.5,
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
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
      child: Row(
        children: [
          Text(
            '◈  ',
            style: TextStyle(
              color: CyberpunkColors.cyanDim.withValues(alpha: 0.80),
              fontSize: 7,
            ),
          ),
          Text(
            text,
            style: TextStyle(
              color: CyberpunkColors.cyanDim.withValues(alpha: 0.95),
              fontSize: 8.5,
              letterSpacing: 2,
              fontFamily: 'monospace',
            ),
          ),
        ],
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
      color: const Color(0xFF0C1814),
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
                                  color: CyberpunkColors.textDim,
                                  fontSize: 14,
                                  letterSpacing: 1,
                                  fontFamily: 'monospace',
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
    return InkWell(
      onTap: () => _openFullscreen(context),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
        child: Row(
          children: [
            const Text(
              '// ATTACK_CODEX',
              style: TextStyle(
                color: CyberpunkColors.cyanDim,
                fontSize: 9,
                letterSpacing: 2,
                fontFamily: 'monospace',
              ),
            ),
            const Spacer(),
            const Text(
              '[+]',
              style: TextStyle(
                color: CyberpunkColors.textDim,
                fontSize: 9,
                letterSpacing: 1,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── AttackCardsPanel ──────────────────────────────────────────────────────

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

    // HONEYPOT: board-targeted, no player selection.
    // The trap fires against whoever captures it – targetPlayerId is the owner.
    if (card.type == AttackType.knightseye) {
      onPickPosition(AttackAction(
        type: card.type,
        attackerPlayerId: localPlayerId,
        targetPlayerId: localPlayerId,
      ));
      return;
    }

    // WORM: board-targeted – target player is derived from the tapped stone
    // in _onBoardTap, so no player selection dialog is needed here.
    if (card.type == AttackType.worm) {
      onPickPosition(AttackAction(
        type: card.type,
        attackerPlayerId: localPlayerId,
        targetPlayerId: localPlayerId, // placeholder; overwritten in _onBoardTap
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

    // DDOS: auto-targets the next player in turn order – no dialog needed.
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

    // TIMEBOMB: broadcast – targets all opponents simultaneously, no dialog.
    if (card.type == AttackType.psyche) {
      onAttack(AttackAction(
        type: card.type,
        attackerPlayerId: localPlayerId,
        targetPlayerId: localPlayerId, // engine uses attackerPlayerId to exclude self
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
        builder: (_) => AsciiTargetDialog(card: card, targets: targets),
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
                : const Color(0xFF6B2030); // desaturated red when locked
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
            ...targets.map(
              (p) => InkWell(
                onTap: () => Navigator.pop(context, p),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(
                    '  [>>]  ${p.displayName}',
                    style: TextStyle(
                      color: CyberpunkColors.amber.withValues(alpha: 0.95),
                      fontSize: 10,
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
              child: Text(
                '  [X]  ABORT',
                style: TextStyle(
                  color: CyberpunkColors.textSecondary.withValues(alpha: 0.75),
                  fontSize: 9,
                  letterSpacing: 1.2,
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
          final isRecent = i == 0;
          return Text(
            line,
            style: TextStyle(
              color: isError
                  ? CyberpunkColors.error
                  : CyberpunkColors.green.withValues(
                      alpha:
                          isRecent ? 0.95 : (0.95 - i * 0.04).clamp(0.45, 0.95),
                    ),
              fontSize: 8.5,
              letterSpacing: 0.3,
              fontFamily: 'monospace',
              height: 1.55,
            ),
          );
        },
      ),
    );
  }
}
