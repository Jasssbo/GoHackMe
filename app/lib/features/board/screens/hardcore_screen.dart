import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_engine/go_engine.dart';

import '../../../core/theme/cyberpunk_colors.dart';
import '../../../services/audio_service.dart';
import '../providers/local_game_provider.dart';

// ── HardcoreScreen ────────────────────────────────────────────────────────

/// Terminal-only game screen — play Go entirely by typing commands.
///
/// No board widget is mounted.  All game output is rendered as terminal
/// text lines driven by [localGameEventProvider].  Input is a command-line
/// parser that accepts:
///
///   place `<col><row>`   — place stone, e.g. "place a1", "p Q10"
///   pass               — pass turn
///   undo               — undo last move (solo mode)
///   attack `<type>` [`player`] — launch attack, e.g. "attack ddos bot_1"
///   status             — print board size + current player
///   help               — print command reference
///   quit               — return to lobby
///
/// The screen listens to [localGameEventProvider] and prints a formatted
/// terminal line for each [GameEvent].
class HardcoreScreen extends ConsumerStatefulWidget {
  final int boardSize;
  final BotDifficulty difficulty;

  const HardcoreScreen({
    super.key,
    this.boardSize = 9,
    this.difficulty = BotDifficulty.intermediate,
  });

  @override
  ConsumerState<HardcoreScreen> createState() => _HardcoreScreenState();
}

class _HardcoreScreenState extends ConsumerState<HardcoreScreen> {
  // ── Terminal state ────────────────────────────────────────────────────────
  final List<_TermLine> _lines = [];
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _inputCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _inputEnabled = false;
  String _prevInputText = '';

  // ── Event subscription ────────────────────────────────────────────────────
  StreamSubscription<GameEvent>? _eventSub;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _inputCtrl.addListener(_onInputChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _inputCtrl.removeListener(_onInputChanged);
    _eventSub?.cancel();
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    final current = _inputCtrl.text;
    if (current == _prevInputText) return;
    final audio = ref.read(audioServiceProvider);
    if (current.length < _prevInputText.length) {
      audio.playDeleteTypingSound();
    } else if (current.length > _prevInputText.length) {
      audio.playRandomTypingSound();
    }
    _prevInputText = current;
  }

  void _requestFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  // ── Boot sequence ─────────────────────────────────────────────────────────

  Future<void> _boot() async {
    await _typeLines([
      '> HARDCORE_MODE.sh — INITIALISING...',
      '> BOARD: ${widget.boardSize}x${widget.boardSize}',
      '> DIFFICULTY: ${widget.difficulty.name.toUpperCase()}',
      '> NO GUI. NO MERCY.',
      '',
    ]);

    // Start the game engine.
    ref.read(localGameProvider.notifier).startGame(
          boardSize: widget.boardSize,
          difficulty: widget.difficulty,
          humanName: 'OPERATOR',
        );

    // Subscribe to typed events AFTER starting the game.
    _eventSub = ref.read(localGameProvider.notifier).events.listen(_onEvent);

    await _typeLines([
      '> SESSION OPEN.',
      '> Type [help] for commands.',
      '',
    ]);

    if (mounted) {
      setState(() => _inputEnabled = true);
      _requestFocus();
    }
  }

  // ── Event → terminal line ─────────────────────────────────────────────────

  void _onEvent(GameEvent event) {
    final state = ref.read(localGameProvider);
    final line = switch (event) {
      StonePlacedEvent(:final playerId, :final pos, :final isHijacked) =>
        isHijacked
            ? '  >> HIJACK_STONE  ${_coordLabel(pos)}  [${_name(state, playerId)}]'
            : '  >> NODE_PLACED   ${_coordLabel(pos)}  [${_name(state, playerId)}]',
      StonesCapturedEvent(:final capturedByPlayerId, :final captured) =>
        '  >> CAPTURE  ${captured.length} stone${captured.length == 1 ? '' : 's'}'
        '  [${_name(state, capturedByPlayerId)}]',
      PlayerPassedEvent(:final playerId) =>
        '  >> PASS  [${_name(state, playerId)}]',
      TurnAdvancedEvent(:final newCurrentPlayerId, :final turnNumber) =>
        '  T:$turnNumber  AWAITING  [${_name(state, newCurrentPlayerId)}]',
      AttackLaunchedEvent(:final type, :final attackerPlayerId,
        :final targetPlayerId, :final wasBlocked) =>
        wasBlocked
            ? '  >> ${type.name.toUpperCase()}.sh  BLOCKED  [${_name(state, targetPlayerId)} used PATCH]'
            : '  >> ${type.name.toUpperCase()}.sh  LAUNCHED  '
              '${_name(state, attackerPlayerId)} → ${_name(state, targetPlayerId)}',
      DdosSkipEvent(:final skippedPlayerId) =>
        '  >> DDoS  SKIP  [${_name(state, skippedPlayerId)}]',
      HijackActivatedEvent(:final hijackerPlayerId, :final victimPlayerId) =>
        '  >> MITM  ${_name(state, hijackerPlayerId)} HIJACKED ${_name(state, victimPlayerId)}',
      GameOverEvent(:final scores) => _buildScoreLine(state, scores),
    };
    _appendLine(line, kind: _LineKind.event);
  }

  String _name(GameState? state, String id) {
    if (state == null) return id;
    return state.players
        .firstWhere((p) => p.id == id, orElse: () => Player(id: id, displayName: id))
        .displayName;
  }

  String _coordLabel(Position pos) {
    // Column letters: A-H then J-T (skip I, standard Go convention).
    final colCode = pos.x < 8 ? 65 + pos.x : 66 + pos.x;
    final col = String.fromCharCode(colCode);
    final row = pos.y + 1;
    return '$col$row';
  }

  String _buildScoreLine(GameState? state, Map<StoneColor, int> scores) {
    final buf = StringBuffer('  >> GAME OVER\n');
    for (final entry in scores.entries) {
      final idx = entry.key.index;
      final name = (state != null && idx < state.players.length)
          ? state.players[idx].displayName
          : entry.key.name;
      buf.write('     $name : ${entry.value} pts\n');
    }
    return buf.toString().trimRight();
  }

  // ── Input handling ────────────────────────────────────────────────────────

  void _submit() {
    final raw = _inputCtrl.text.trim();
    if (raw.isEmpty) return;
    _inputCtrl.clear();
    _appendLine('> $raw', kind: _LineKind.user);
    _parseCommand(raw.toLowerCase());
  }

  void _parseCommand(String cmd) {
    final parts = cmd.split(RegExp(r'\s+'));
    final verb = parts.first;

    switch (verb) {
      case 'help' || 'h':
        _appendLine(_kHelpText, kind: _LineKind.system);

      case 'quit' || 'exit' || 'q':
        _appendLine('  Jacking out.', kind: _LineKind.system);
        setState(() => _inputEnabled = false);
        Future<void>.delayed(const Duration(milliseconds: 600), () {
          if (mounted) Navigator.of(context).pop();
        });

      case 'status' || 's':
        final state = ref.read(localGameProvider);
        if (state == null) {
          _appendLine('  No active session.', kind: _LineKind.system);
          return;
        }
        _appendLine(
          '  T:${state.turnNumber}  '
          'BOARD:${state.board.size}x${state.board.size}  '
          'CURRENT:[${_name(state, state.currentPlayerId)}]',
          kind: _LineKind.system,
        );

      case 'undo' || 'u':
        final notifier = ref.read(localGameProvider.notifier);
        if (notifier.canUndo) {
          notifier.undo();
          _appendLine('  >> UNDO executed.', kind: _LineKind.system);
        } else {
          _appendLine('  ERR: nothing to undo.', kind: _LineKind.system);
        }

      case 'pass' || 'p' when parts.length == 1:
        ref.read(localGameProvider.notifier).pass();

      case 'place' || 'pl':
        if (parts.length < 2) {
          _appendLine('  ERR: usage: place <coord>  e.g. place A1', kind: _LineKind.system);
          return;
        }
        _doPlace(parts[1]);

      // Shorthand: a single coord token like "a1" or "q10"
      case final c when _isCoord(c):
        _doPlace(c);

      case 'attack' || 'atk':
        if (parts.length < 2) {
          _appendLine('  ERR: usage: attack <type> [target]  e.g. attack ddos bot_1',
              kind: _LineKind.system);
          return;
        }
        _doAttack(parts.sublist(1));

      default:
        _appendLine(
          '  Unknown command "$verb".  Type [help] for reference.',
          kind: _LineKind.system,
        );
    }
  }

  bool _isCoord(String s) {
    if (s.length < 2 || s.length > 3) return false;
    final letter = s[0];
    final digits = s.substring(1);
    return RegExp(r'^[a-t]$').hasMatch(letter) &&
        RegExp(r'^\d{1,2}$').hasMatch(digits);
  }

  void _doPlace(String coord) {
    final pos = _parseCoord(coord);
    if (pos == null) {
      _appendLine('  ERR: invalid coordinate "$coord".  Example: A1, Q10',
          kind: _LineKind.system);
      return;
    }
    ref.read(localGameProvider.notifier).placeStone(pos);
  }

  /// Parses a Go coordinate string like "A1", "q10", "T19" into a [Position].
  /// Column letters skip I (standard Go): A-H → 0-7, J-T → 8-18.
  Position? _parseCoord(String raw) {
    if (raw.length < 2 || raw.length > 3) return null;
    final letter = raw[0].toUpperCase();
    final rowStr = raw.substring(1);
    final row = int.tryParse(rowStr);
    if (row == null || row < 1 || row > 25) return null;

    final colCode = letter.codeUnitAt(0);
    // A=65..H=72 → 0..7, skip I(73), J=74..T=84 → 8..18
    if (colCode < 65 || colCode > 84 || colCode == 73) return null;
    final x = colCode <= 72 ? colCode - 65 : colCode - 66;
    final y = row - 1;
    return Position(x, y);
  }

  void _doAttack(List<String> args) {
    final state = ref.read(localGameProvider);
    if (state == null) {
      _appendLine('  ERR: no active session.', kind: _LineKind.system);
      return;
    }
    final notifier = ref.read(localGameProvider.notifier);
    final typeName = args[0].toLowerCase();
    final AttackType? type = AttackType.values
        .where((t) => t.name.toLowerCase() == typeName)
        .firstOrNull;

    if (type == null) {
      _appendLine(
        '  ERR: unknown attack "$typeName".\n'
        '  Available: ${AttackType.values.map((t) => t.name).join(', ')}',
        kind: _LineKind.system,
      );
      return;
    }

    // Resolve target player: default to first non-human player.
    final attackerId = notifier.humanId;
    String targetId;
    if (args.length >= 2) {
      final raw = args[1];
      // Accept partial match on display name or ID.
      final match = state.players
          .where((p) => p.id != attackerId)
          .firstWhere(
            (p) =>
                p.id.toLowerCase().contains(raw) ||
                p.displayName.toLowerCase().contains(raw),
            orElse: () => Player(id: '', displayName: ''),
          );
      if (match.id.isEmpty) {
        _appendLine('  ERR: player "$raw" not found.', kind: _LineKind.system);
        return;
      }
      targetId = match.id;
    } else {
      // Default: first opponent.
      final opponent = state.players.firstWhere(
        (p) => p.id != attackerId,
        orElse: () => Player(id: '', displayName: ''),
      );
      if (opponent.id.isEmpty) {
        _appendLine('  ERR: no target player.', kind: _LineKind.system);
        return;
      }
      targetId = opponent.id;
    }

    // Position-based attacks (worm) require a coordinate argument.
    if (type == AttackType.worm) {
      if (args.length < 3) {
        _appendLine('  ERR: worm requires a target coordinate.  e.g. attack worm bot_1 B4',
            kind: _LineKind.system);
        return;
      }
      final pos = _parseCoord(args[2]);
      if (pos == null) {
        _appendLine('  ERR: invalid coordinate "${args[2]}".', kind: _LineKind.system);
        return;
      }
      notifier.launchAttack(AttackAction(
        type: type,
        attackerPlayerId: attackerId,
        targetPlayerId: targetId,
        targetPosition: pos,
      ));
      return;
    }

    notifier.launchAttack(AttackAction(
      type: type,
      attackerPlayerId: attackerId,
      targetPlayerId: targetId,
    ));
  }

  // ── Output helpers ────────────────────────────────────────────────────────

  void _appendLine(String text, {required _LineKind kind}) {
    if (!mounted) return;
    // Multi-line strings (e.g. game over block) are split into separate lines.
    final split = text.split('\n');
    setState(() {
      for (final l in split) {
        _lines.add(_TermLine(text: l, kind: kind));
      }
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _typeLines(
    List<String> lines, {
    Duration lineDelay = const Duration(milliseconds: 45),
  }) async {
    for (final line in lines) {
      if (!mounted) return;
      _appendLine(line, kind: _LineKind.system);
      await Future<void>.delayed(lineDelay);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Watch game state to update input availability (disable during bot turn).
    final gameState = ref.watch(localGameProvider);
    final notifier = ref.read(localGameProvider.notifier);
    final isMyTurn = gameState != null &&
        gameState.currentPlayerId == notifier.humanId &&
        gameState.phase == GamePhase.attack;
    final isOver = gameState != null && GameEngine.isGameOver(gameState);
    final canInput = _inputEnabled && (isMyTurn || isOver);

    if (canInput) {
      _requestFocus();
    }

    return Scaffold(
      backgroundColor: CyberpunkColors.background,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _requestFocus,
        child: SafeArea(
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────────────────
              _HardcoreHeader(onClose: () => Navigator.of(context).pop()),
              // ── Output ──────────────────────────────────────────────────
              Expanded(
                child: ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  itemCount: _lines.length,
                  itemBuilder: (_, i) => _LineWidget(line: _lines[i]),
                ),
              ),
              // ── Input ───────────────────────────────────────────────────
              _InputRow(
                controller: _inputCtrl,
                focusNode: _focusNode,
                enabled: canInput,
                onSubmit: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Help text ─────────────────────────────────────────────────────────────

const _kHelpText = '''
> COMMAND REFERENCE:

  place <A1>        — place stone at coordinate  (e.g. place D4)
  <A1>              — shorthand place            (e.g. q10)
  pass              — pass your turn
  undo              — undo last move
  attack <type>     — launch attack  (types: backdoor patch worm trojan
                        knightseye ddos mitm psyche)
  attack worm <player> <A1>  — worm requires target coord
  status            — show turn / board info
  help              — this message
  quit              — jack out''';

// ── Sub-widgets ───────────────────────────────────────────────────────────

enum _LineKind { user, event, system, err }

class _TermLine {
  final String text;
  final _LineKind kind;
  const _TermLine({required this.text, required this.kind});
}

class _HardcoreHeader extends StatelessWidget {
  final VoidCallback onClose;
  const _HardcoreHeader({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: CyberpunkColors.magenta.withValues(alpha: 0.06),
        border: Border(
          bottom: BorderSide(
            color: CyberpunkColors.magenta.withValues(alpha: 0.30),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            'HARDCORE://terminal',
            style: TextStyle(
              color: CyberpunkColors.magenta.withValues(alpha: 0.90),
              fontSize: 9.5,
              letterSpacing: 2.5,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onClose,
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
    );
  }
}

class _LineWidget extends StatelessWidget {
  final _TermLine line;
  const _LineWidget({required this.line});

  @override
  Widget build(BuildContext context) {
    final color = switch (line.kind) {
      _LineKind.user => CyberpunkColors.cyan.withValues(alpha: 0.90),
      _LineKind.event => CyberpunkColors.green.withValues(alpha: 0.85),
      _LineKind.system => CyberpunkColors.magenta.withValues(alpha: 0.85),
      _LineKind.err => CyberpunkColors.error.withValues(alpha: 0.90),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: Text(
        line.text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontFamily: 'monospace',
          height: 1.65,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _InputRow extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onSubmit;

  const _InputRow({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: CyberpunkColors.magenta.withValues(alpha: 0.20),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            '> ',
            style: TextStyle(
              color: CyberpunkColors.magenta
                  .withValues(alpha: enabled ? 0.90 : 0.30),
              fontSize: 12,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: KeyboardListener(
              focusNode: FocusNode(),
              onKeyEvent: (event) {
                if (enabled &&
                    event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.enter) {
                  onSubmit();
                }
              },
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: true,
                autofocus: true,
                style: TextStyle(
                  color: CyberpunkColors.cyan.withValues(alpha: 0.90),
                  fontSize: 12,
                  fontFamily: 'monospace',
                  letterSpacing: 0.4,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: enabled ? 'enter command...' : 'waiting for opponent...',
                  hintStyle: TextStyle(
                    color: CyberpunkColors.magenta.withValues(alpha: 0.20),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                onSubmitted: (_) => enabled ? onSubmit() : null,
                cursorColor: CyberpunkColors.magenta,
                cursorWidth: 7,
                cursorHeight: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: enabled ? onSubmit : null,
            child: Text(
              '[RUN]',
              style: TextStyle(
                color: enabled
                    ? CyberpunkColors.magenta.withValues(alpha: 0.65)
                    : CyberpunkColors.magenta.withValues(alpha: 0.18),
                fontSize: 9,
                letterSpacing: 1.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
