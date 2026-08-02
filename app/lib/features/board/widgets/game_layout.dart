import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_engine/go_engine.dart';

import '../../../core/lifecycle/app_lifecycle_provider.dart';
import '../../../core/theme/cyberpunk_colors.dart';
import '../../../services/audio_service.dart';
import 'board_widget.dart';
import 'codex/attack_codex_dialog.dart';
import 'layout/attack_deck_widget.dart';
import 'layout/terminal_hud_widget.dart';

// ── GameLayout ────────────────────────────────────────────────────────────

/// Full game UI: board on top, terminal + attacks side-by-side on bottom.
///
/// Used by both [GameScreen] (online) and [LocalGameScreen] (single-player).
/// Provide [logLines] from whichever provider the caller watches.
class GameLayout extends ConsumerStatefulWidget {
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

  /// Called when the player taps the SAVE button to snapshot the game.
  final VoidCallback? onSave;

  /// Called when the player taps the EXIT button.
  final VoidCallback? onExit;

  /// Increment this to fire a glitch burst on the parent [GlitchOverlay].
  final ValueNotifier<int>? attackBurst;

  /// Optional: called when the player sends a chat message.
  /// When null the chat input is hidden (e.g. local / LAN games).
  final void Function(String)? onChatSend;

  /// Optional: called to undo the last move (solo mode only).
  /// When null the UNDO button is hidden.
  final VoidCallback? onUndo;

  /// When non-null, the client seeds the turn countdown from the server's
  /// authoritative start time rather than always resetting to 15 s.
  /// This keeps the display correct after reconnects.
  final DateTime? serverTurnStartedAt;

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
    this.onSave,
    this.onExit,
    this.attackBurst,
    this.onChatSend,
    this.onUndo,
    this.serverTurnStartedAt,
  });

  @override
  ConsumerState<GameLayout> createState() => _GameLayoutState();
}

class _GameLayoutState extends ConsumerState<GameLayout> {
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
      final lifecycle = ref.read(appLifecycleProvider);
      if (lifecycle == AppLifecycleState.paused || lifecycle == AppLifecycleState.inactive) {
        return; // Pause timebomb countdown while app is backgrounded
      }
      ref.read(audioServiceProvider).playTimebombTick();
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
  /// Wall-clock reference point for the current turn, used to recompute the
  /// display value on every tick without accumulating Timer.periodic drift.
  DateTime? _turnStartedAtLocal;

  /// Recomputes the remaining seconds from the wall clock.
  /// Uses ceiling division so the display reads "1s" until the last millisecond
  /// instead of jumping to "0s" a full second early.
  int _computeTurnSecondsLeft() {
    final ref = _turnStartedAtLocal;
    if (ref == null) return _kTurnSeconds;
    final elapsedMs = DateTime.now().toUtc().difference(ref).inMilliseconds;
    final remainingMs = _kTurnSeconds * 1000 - elapsedMs;
    if (remainingMs <= 0) return 0;
    // Ceiling integer division: (remainingMs + 999) ~/ 1000
    return ((remainingMs + 999) ~/ 1000).clamp(0, _kTurnSeconds);
  }

  void _resetTurnCountdown() {
    _turnCountdownTimer?.cancel();
    // Use the server's authoritative start time when available; fall back to
    // now() for local / LAN games that don't supply a clock-sync timestamp.
    _turnStartedAtLocal = widget.serverTurnStartedAt ?? DateTime.now().toUtc();
    // Compute the first value immediately — no blank frame before the timer fires.
    _turnSecondsLeft = _computeTurnSecondsLeft();
    // Poll every 500 ms and recompute from the wall clock each tick.
    // This eliminates Timer.periodic drift AND the 1-second inaccuracy that the
    // old decrement approach had (inSeconds truncates, so 14.9 s elapsed → 14,
    // showing 1 s more than reality).
    _turnCountdownTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (!mounted) { t.cancel(); return; }
      final remaining = _computeTurnSecondsLeft();
      if (remaining != _turnSecondsLeft) {
        setState(() => _turnSecondsLeft = remaining);
      }
      if (remaining <= 0) t.cancel();
    });
  }

  void _cancelTurnCountdown() {
    _turnCountdownTimer?.cancel();
    _turnCountdownTimer = null;
    _turnStartedAtLocal = null;
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
    // Reset turn countdown whenever the active player changes, the phase
    // changes, OR the server sends a fresh start timestamp (e.g. after a
    // reconnect where the same player is still active).
    if (oldWidget.state.currentPlayerId != widget.state.currentPlayerId ||
        oldWidget.state.phase != widget.state.phase ||
        oldWidget.serverTurnStartedAt != widget.serverTurnStartedAt) {
      _resetTurnCountdown();
    }
    // Sound: turn start (only when the turn flips to the local player).
    if (oldWidget.state.currentPlayerId != widget.state.currentPlayerId &&
        widget.state.currentPlayerId == widget.localPlayerId) {
      ref.read(audioServiceProvider).playTurnStart();
    }
    // Sound + haptic: capture events.
    final prevCaptures = oldWidget.state.captureCount.values
        .fold(0, (s, v) => s + v);
    final nextCaptures = widget.state.captureCount.values
        .fold(0, (s, v) => s + v);
    if (nextCaptures > prevCaptures) {
      HapticFeedback.heavyImpact();
      ref.read(audioServiceProvider).playCapture();
    }
    // Sound: game finished.
    if (oldWidget.state.phase != GamePhase.finished &&
        widget.state.phase == GamePhase.finished) {
      final myColor =
          widget.state.currentPlayerColor(widget.localPlayerId);
      final scores = Scorer.areaScore(widget.state.board);
      final myScore = scores[myColor] ?? 0;
      final maxScore =
          scores.values.isEmpty ? 0 : scores.values.reduce((a, b) => a > b ? a : b);
      if (myScore >= maxScore) {
        ref.read(audioServiceProvider).playGameWin();
      } else {
        ref.read(audioServiceProvider).playGameOver();
      }
    }
  }

  void _onPickPosition(AttackAction partial) {
    setState(() => _pendingPositionAttack = partial);
  }

  /// Plays the attack-type sound then forwards to the parent callback.
  void _handleAttack(AttackAction action) {
    ref.read(audioServiceProvider).playAttack(action.type);
    widget.onAttack(action);
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
        HapticFeedback.lightImpact();
        _handleAttack(AttackAction(
          type: pending.type,
          attackerPlayerId: pending.attackerPlayerId,
          targetPlayerId: owner.id,
          targetPosition: pos,
        ));
        return;
      }
      // For all other position-based attacks (HONEYPOT), use the stored target.
      setState(() => _pendingPositionAttack = null);
      HapticFeedback.lightImpact();
      _handleAttack(AttackAction(
        type: pending.type,
        attackerPlayerId: pending.attackerPlayerId,
        targetPlayerId: pending.targetPlayerId,
        targetPosition: pos,
      ));
    } else {
      ref.read(audioServiceProvider).playPlaceNode();
      HapticFeedback.mediumImpact();
      widget.onPlace(pos);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMyTurn = widget.state.currentPlayerId == widget.localPlayerId;
    final inAttack = isMyTurn && widget.state.phase == GamePhase.attack;
    final isPicking = _pendingPositionAttack != null;
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height * 1.2;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RepaintBoundary(
            child: GameStatusStrip(
              state: widget.state,
              localPlayerId: widget.localPlayerId,
              onPass: widget.onPass == null
                  ? null
                  : () {
                      ref.read(audioServiceProvider).playPass();
                      widget.onPass!();
                    },
              onSave: widget.onSave,
              onExit: widget.onExit,
              onUndo: widget.onUndo,
              turnSecondsLeft: _turnSecondsLeft,
            ),
          ),
          Expanded(
            child: isLandscape
                ? _buildLandscapeBody(isMyTurn, inAttack, isPicking)
                : _buildPortraitBody(isMyTurn, inAttack, isPicking),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBanners(bool isMyTurn) {
    final isPicking = _pendingPositionAttack != null;
    return [
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
                    color: CyberpunkColors.error,
                    fontSize: 9,
                    letterSpacing: 1,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      if (widget.state.phase == GamePhase.hijackedVictimPlacement && isMyTurn)
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
    ];
  }

  Widget _buildBoardWidget(bool isMyTurn) {
    final myColorEnum = widget.state.currentPlayerColor(widget.localPlayerId);
    Color turnColor;
    switch (myColorEnum) {
      case StoneColor.p1:
        turnColor = CyberpunkColors.cyan;
        break;
      case StoneColor.p2:
        turnColor = CyberpunkColors.magenta;
        break;
      case StoneColor.p3:
        turnColor = CyberpunkColors.green;
        break;
      case StoneColor.p4:
        turnColor = CyberpunkColors.amber;
        break;
    }

    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: RepaintBoundary(
            child: _GlowingBoardBorder(
              isMyTurn: isMyTurn,
              turnColor: turnColor,
              child: BoardWidget(
                board: widget.state.board,
                boardSize: widget.state.board.size,
                lastPlaced: widget.lastPlaced,
                activePlayerColor: widget.state.currentPlayerColor(
                    widget.state.currentPlayerId),
                scoringTerritory: (widget.state.phase == GamePhase.scoring ||
                        widget.state.phase == GamePhase.finished)
                    ? Scorer.territoryRegions(widget.state.board)
                    : null,
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
    );
  }

  Widget _buildAttackPanel(bool inAttack, bool isPicking) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (inAttack && !isPicking) ...[
          const PanelHeader('// ATTACK_VECTOR'),
          Expanded(
            child: SingleChildScrollView(
              child: AttackDeckWidget(
                subnets: widget.state.subnetsOf(widget.localPlayerId),
                players: widget.state.players,
                localPlayerId: widget.localPlayerId,
                onAttack: _handleAttack,
                onPickPosition: _onPickPosition,
              ),
            ),
          ),
        ] else ...[
          const PanelHeader('// LAYER_STATUS'),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
            child: Text(
              widget.state.phase == GamePhase.attack
                  ? (widget.state.currentPlayerId == widget.localPlayerId
                      ? '> YOUR_TURN.exe'
                      : '> AWAITING_ENTITY_UPLINK')
                  : '> LAYER::${widget.state.phase.name.toUpperCase()}',
              style: const TextStyle(
                color: CyberpunkColors.green,
                fontSize: 10,
                letterSpacing: 1,
                fontFamily: 'monospace',
              ),
            ),
          ),
          if (widget.state.phase == GamePhase.attack &&
              widget.state.currentPlayerId != widget.localPlayerId)
            const Padding(
              padding: EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Text(
                '> Tip: Access ATTACK_CODEX below to inspect payload specs while waiting.',
                style: TextStyle(
                  color: CyberpunkColors.textSecondary,
                  fontSize: 9,
                  letterSpacing: 0.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          const Spacer(),
        ],
        const PanelDivider(),
        const AttackCodex(),
      ],
    );
  }

  Widget _buildPortraitBody(bool isMyTurn, bool inAttack, bool isPicking) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._buildBanners(isMyTurn),
        Expanded(flex: 3, child: _buildBoardWidget(isMyTurn)),
        const PanelDivider(),
        Expanded(
          flex: 2,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: RepaintBoundary(
                  child: _buildAttackPanel(inAttack, isPicking),
                ),
              ),
              Container(width: 1, color: const Color(0xFF0C1814)),
              RepaintBoundary(
                child: TerminalHudWidget(
                  state: widget.state,
                  localPlayerId: widget.localPlayerId,
                  logLines: widget.logLines,
                  onChatSend: widget.onChatSend,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeBody(bool isMyTurn, bool inAttack, bool isPicking) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ..._buildBanners(isMyTurn),
              Expanded(child: _buildBoardWidget(isMyTurn)),
            ],
          ),
        ),
        Container(width: 1, color: const Color(0xFF0C1814)),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: RepaintBoundary(
                  child: _buildAttackPanel(inAttack, isPicking),
                ),
              ),
              const PanelDivider(),
              Expanded(
                flex: 2,
                child: RepaintBoundary(
                  child: TerminalHudWidget(
                    state: widget.state,
                    localPlayerId: widget.localPlayerId,
                    logLines: widget.logLines,
                    onChatSend: widget.onChatSend,
                    fillWidth: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── GameStatusStrip ───────────────────────────────────────────────────────

class GameStatusStrip extends StatelessWidget {
  final GameState state;
  final String localPlayerId;
  final VoidCallback? onPass;
  final VoidCallback? onSave;
  final VoidCallback? onExit;
  final VoidCallback? onUndo;
  final int turnSecondsLeft;

  const GameStatusStrip({
    super.key,
    required this.state,
    required this.localPlayerId,
    this.onPass,
    this.onSave,
    this.onExit,
    this.onUndo,
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
          if (isActive && onSave != null) ...[
            _StripButton(
              label: 'SAVE',
              color: CyberpunkColors.green,
              onTap: onSave!,
            ),
            const SizedBox(width: 8),
          ],
          if (onUndo != null) ...[
            _StripButton(
              label: 'UNDO',
              color: CyberpunkColors.magenta,
              onTap: onUndo!,
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
          // ── Move counter ─────────────────────────
          Text(
            'T:${state.turnNumber}',
            style: TextStyle(
              color: CyberpunkColors.cyanDim.withValues(alpha: 0.70),
              fontSize: 9,
              letterSpacing: 1,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
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
              color: Colors.white,
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
          border: Border.all(color: color, width: 1),
          color: color.withValues(alpha: 0.18),
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

// ── _GlowingBoardBorder ───────────────────────────────────────────────────

/// Animated border around the board widget that pulses with neon glow
/// when [isMyTurn] is true.
class _GlowingBoardBorder extends StatefulWidget {
  final bool isMyTurn;
  final Color turnColor;
  final Widget child;

  const _GlowingBoardBorder({
    required this.isMyTurn,
    required this.turnColor,
    required this.child,
  });

  @override
  State<_GlowingBoardBorder> createState() => _GlowingBoardBorderState();
}

class _GlowingBoardBorderState extends State<_GlowingBoardBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isMyTurn) {
      _pulseCtrl.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _GlowingBoardBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isMyTurn != oldWidget.isMyTurn) {
      if (widget.isMyTurn) {
        _pulseCtrl.repeat(reverse: true);
      } else {
        _pulseCtrl.stop();
        _pulseCtrl.value = 0.0;
      }
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, child) {
        final pulse = _pulseCtrl.value;
        final color = widget.turnColor;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: widget.isMyTurn
                  ? color.withValues(alpha: 0.4 + 0.5 * pulse)
                  : const Color(0xFF0D1A18),
              width: widget.isMyTurn ? 2.0 : 1.0,
            ),
            boxShadow: widget.isMyTurn
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35 + 0.35 * pulse),
                      blurRadius: 16 + 8 * pulse,
                      spreadRadius: 2 + 2 * pulse,
                    ),
                    BoxShadow(
                      color: color.withValues(alpha: 0.2 * pulse),
                      blurRadius: 32,
                      spreadRadius: 4,
                    ),
                  ]
                : [],
          ),
          child: Stack(
            children: [
              widget.child,
              if (widget.isMyTurn)
                Positioned(
                  top: 6,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF030506).withValues(alpha: 0.85),
                      border: Border.all(
                        color: color.withValues(alpha: 0.6 + 0.4 * pulse),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color.withValues(alpha: 0.5 + 0.5 * pulse),
                            boxShadow: [
                              BoxShadow(
                                color: color,
                                blurRadius: 4,
                              )
                            ],
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'YOUR TURN',
                          style: TextStyle(
                            color: color.withValues(alpha: 0.85 + 0.15 * pulse),
                            fontSize: 8.5,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
