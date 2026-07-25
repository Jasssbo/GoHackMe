import 'dart:async';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_engine/go_engine.dart';

// ── Local game log ────────────────────────────────────────────────────────

class LocalGameLogNotifier extends Notifier<List<String>> {
  static const _maxLines = 10;

  @override
  List<String> build() => [];

  void append(String line) {
    final next = [...state, line];
    state = next.length > _maxLines ? next.sublist(next.length - _maxLines) : next;
  }

  void clear() => state = [];
}

final localGameLogProvider =
    NotifierProvider<LocalGameLogNotifier, List<String>>(
  LocalGameLogNotifier.new,
);

// ── Local game notifier ───────────────────────────────────────────────────

/// Holds the entire state of a local solo game against 1 or 3 bots.
///
/// The human player always plays first (index 0).
/// Bots fill the remaining slots.
///
/// After the human completes their turn (placement → optionally attacks →
/// end attack phase), each bot move is computed and applied automatically
/// with a short UI delay so the board has time to repaint.
class LocalGameNotifier extends Notifier<GameState?> {
  static const _humanId = 'human_player';
  static const _kTurnTimeout = Duration(seconds: 15);

  // Prevent concurrent bot turns being queued.
  bool _botTurnPending = false;
  BotDifficulty _difficulty = BotDifficulty.intermediate;
  Timer? _turnTimer;

  // ── Event stream ──────────────────────────────────────────────────────────

  /// Broadcast stream of typed [GameEvent]s.
  ///
  /// Consumers (terminal renderer, tutorial narration) listen here instead of
  /// diffing [GameState] snapshots.  The stream is closed when the provider
  /// is disposed.
  final StreamController<GameEvent> _eventController =
      StreamController<GameEvent>.broadcast();

  /// The public event stream.  Use [localGameEventProvider] to watch it via
  /// Riverpod, or call this getter directly from a notifier.
  Stream<GameEvent> get events => _eventController.stream;

  /// IDs of all bot players in the current game.
  List<String> _botIds = ['bot_1'];

  /// Undo history: states saved before each human placement or pass.
  /// Capped at 10 entries so the user can undo up to 10 moves back.
  final List<GameState> _undoHistory = [];

  bool _isBot(String playerId) => _botIds.contains(playerId);

  @override
  GameState? build() {
    ref.onDispose(() {
      _turnTimer?.cancel();
      _eventController.close();
    });
    return null;
  }

  // ── Start game ────────────────────────────────────────────────────────────

  void startGame({
    int boardSize = 9,
    BotDifficulty difficulty = BotDifficulty.intermediate,
    String humanName = 'PLAYER_1',
    /// Number of bot opponents.  Supported values: 1 (1v1) or 3 (1v3).
    int botCount = 1,
  }) {
    if (botCount < 1 || botCount > 3) {
      throw ArgumentError('botCount must be 1–3, got $botCount');
    }
    _botTurnPending = false;
    _difficulty = difficulty;
    _botIds = List.generate(botCount, (i) => 'bot_${i + 1}');
    _undoHistory.clear();

    final botLabels = _makeBotLabels(difficulty, botCount);
    final players = [
      Player(id: _humanId, displayName: humanName),
      ...List.generate(
        botCount,
        (i) => Player(id: _botIds[i], displayName: botLabels[i]),
      ),
    ];

    final gameState = GameState.newGame(
      players: players,
      boardSize: boardSize,
    );

    state = gameState;

    ref
        .read(localGameLogProvider.notifier)
        .append('>> LOCAL GAME STARTED ${boardSize}x$boardSize  [1v$botCount]');
    ref
        .read(localGameLogProvider.notifier)
        .append('>> YOU are $humanName. OPPONENTS: ${botLabels.join(', ')}.');
    _resetTurnTimer();
  }

  /// Generates display names for [botCount] bots at [difficulty].
  static List<String> _makeBotLabels(BotDifficulty difficulty, int botCount) {
    final ver = difficulty == BotDifficulty.beginner ? 'v0.1' : 'v0.5';
    if (botCount == 1) return ['BOT_$ver'];
    const suffixes = ['A', 'B', 'C'];
    return List.generate(botCount, (i) => 'BOT_${suffixes[i]}_$ver');
  }

  // Expose constants so the screen can reference them.
  String get humanId => _humanId;

  // ── Restore from save ─────────────────────────────────────────────────────

  /// Restores a previously saved game state.
  ///
  /// [savedState] must have been produced by a local game (the player at
  /// [humanSlotIndex] is treated as the human; all others become bots).
  /// Bot IDs and difficulty are re-derived so the engine loop works correctly.
  void restoreGame({
    required GameState savedState,
    required int humanSlotIndex,
    BotDifficulty difficulty = BotDifficulty.intermediate,
  }) {
    _botTurnPending = false;
    _difficulty = difficulty;
    _undoHistory.clear();
    _turnTimer?.cancel();

    // Identify bot slots: every player that is NOT the human.
    final botSlots = <int>[];
    for (var i = 0; i < savedState.players.length; i++) {
      if (i != humanSlotIndex) botSlots.add(i);
    }
    _botIds = botSlots.map((i) => savedState.players[i].id).toList();

    state = savedState;

    ref
        .read(localGameLogProvider.notifier)
        .append('>> SESSION_RESTORED  T${savedState.turnNumber}');
    _resetTurnTimer();
    // If it is a bot's turn right away, kick off bot logic.
    if (state != null && _isBot(state!.currentPlayerId)) {
      _scheduleBotTurn();
    }
  }

  // ── Human actions ─────────────────────────────────────────────────────────

  void placeStone(Position pos) {
    final current = state;
    if (current == null) return;
    if (current.currentPlayerId != _humanId) return;

    _undoHistory.add(current);
    if (_undoHistory.length > 10) _undoHistory.removeAt(0);
    final result = GameEngine.placeStone(current, _humanId, pos);
    _applyResult(result);
  }

  void pass() {
    final current = state;
    if (current == null) return;
    if (current.currentPlayerId != _humanId) return;

    _undoHistory.add(current);
    if (_undoHistory.length > 10) _undoHistory.removeAt(0);
    final result = GameEngine.pass(current, _humanId);
    _applyResult(result);
  }

  void launchAttack(AttackAction action) {
    final current = state;
    if (current == null) return;

    final result = GameEngine.launchAttack(current, action);
    _applyResult(result);
  }

  // ── Undo ──────────────────────────────────────────────────────────────────

  /// Whether there is a move to undo. True only on the human's attack turn.
  bool get canUndo =>
      _undoHistory.isNotEmpty &&
      state != null &&
      state!.phase == GamePhase.attack &&
      state!.currentPlayerId == _humanId;

  /// Reverts the game to the state before the last human placement or pass.
  void undo() {
    if (_undoHistory.isEmpty) return;
    _turnTimer?.cancel();
    _turnTimer = null;
    _botTurnPending = false;
    state = _undoHistory.removeLast();
    ref.read(localGameLogProvider.notifier).append('>> UNDO :: MOVE_REVERTED');
    _resetTurnTimer();
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  void _resetTurnTimer() {
    _turnTimer?.cancel();
    _turnTimer = null;
    final current = state;
    if (current == null) return;
    if (current.phase == GamePhase.scoring) return;
    if (GameEngine.isGameOver(current)) return;
    // Only enforce for the human — the bot schedules itself.
    if (current.currentPlayerId != _humanId) return;

    _turnTimer = Timer(_kTurnTimeout, () {
      final s = state;
      if (s == null) return;
      if (s.currentPlayerId != _humanId) return;
      ref.read(localGameLogProvider.notifier).append('TURN_TIMEOUT >> AUTO_SKIP');
      if (s.phase == GamePhase.hijackedVictimPlacement) {
        // pass() is invalid in this phase; keep the clock running so the
        // game does not stall while waiting for the human hijacker to act.
        ref.read(localGameLogProvider.notifier).append('TURN_TIMEOUT >> AWAITING_HIJACK_PLACEMENT');
        _resetTurnTimer();
        return;
      }
      final ActionResult result;
      if (s.phase == GamePhase.attack) {
        result = GameEngine.endAttackPhase(s, _humanId);
      } else {
        result = GameEngine.pass(s, _humanId);
      }
      _applyResult(result);
    });
  }

  void _applyResult(ActionResult result) {
    switch (result) {
      case ActionSuccess(:final newState, :final logMessage, :final event):
        state = newState;
        if (logMessage != null) {
          ref.read(localGameLogProvider.notifier).append(logMessage);
        }
        // Emit the typed event to all stream listeners.
        if (event != null && !_eventController.isClosed) {
          _eventController.add(event);
        }

        if (GameEngine.isGameOver(newState)) {
          _turnTimer?.cancel();
          _handleGameOver(newState);
          return;
        }

        // Schedule bot turn when it becomes any bot's turn.
        if (_isBot(newState.currentPlayerId)) {
          _scheduleBotTurn();
        } else {
          _resetTurnTimer();
        }

      case ActionFailure(:final reason):
        ref.read(localGameLogProvider.notifier).append('ERR: $reason');
    }
  }

  void _scheduleBotTurn({
    Duration delay = const Duration(milliseconds: 500),
  }) {
    if (_botTurnPending) return;
    _botTurnPending = true;

    Future.delayed(delay, () {
      _botTurnPending = false;
      _runBotTurn();
    });
  }

  Future<void> _runBotTurn() async {
    final current = state;
    if (current == null) return;
    if (!_isBot(current.currentPlayerId)) return;
    if (GameEngine.isGameOver(current)) return;

    final botId = current.currentPlayerId;
    final difficulty = _difficulty;
    final botLabel =
        current.players.firstWhere((p) => p.id == botId).displayName;

    // In hijackedVictimPlacement the bot (hijacker) must place a stone in
    // the victim's colour. Pick any legal position and place it.
    if (current.phase == GamePhase.hijackedVictimPlacement) {
      final move = await Isolate.run(() => BotPlayer.pickMove(current, botId, difficulty));
      if (state != current) return; // Discard if state changed (e.g. user undo/exit)
      if (move != null) {
        ref
            .read(localGameLogProvider.notifier)
            .append('$botLabel >> HIJACK_PLACE (${move.x},${move.y})');
        _applyResult(GameEngine.placeStone(current, botId, move));
      } else {
        // Board full — pass as a fallback; engine will reject and log.
        ref
            .read(localGameLogProvider.notifier)
            .append('$botLabel >> HIJACK_PASS (board full)');
        _applyResult(GameEngine.pass(current, botId));
      }
      return;
    }

    if (current.phase != GamePhase.attack) return;

    // Bot may choose to attack first (attacks are valid in placement phase).
    final attack = await Isolate.run(() => BotPlayer.pickAttack(current, botId, _humanId, difficulty));
    if (state != current) return;

    GameState afterAttack = current;
    if (attack != null) {
      final ar = GameEngine.launchAttack(current, attack);
      if (ar case ActionSuccess(:final newState, :final logMessage)) {
        afterAttack = newState;
        if (logMessage != null) {
          ref.read(localGameLogProvider.notifier).append('$botLabel >> $logMessage');
        }
        state = afterAttack;
      }
    }

    // Bot places stone or passes (computed in background isolate).
    final move = await Isolate.run(() => BotPlayer.pickMove(afterAttack, botId, difficulty));
    if (state != afterAttack) return;

    if (move == null) {
      ref.read(localGameLogProvider.notifier).append('$botLabel >> PASS');
      _applyResult(GameEngine.pass(afterAttack, botId));
    } else {
      ref
          .read(localGameLogProvider.notifier)
          .append('$botLabel >> PLACE (${move.x},${move.y})');
      _applyResult(GameEngine.placeStone(afterAttack, botId, move));
    }
  }

  void _handleGameOver(GameState finalState) {
    final scores = Scorer.areaScore(finalState.board);
    ref.read(localGameLogProvider.notifier).append('>> GAME OVER');
    for (final entry in scores.entries) {
      final color = entry.key;
      final playerIdx = color.index;
      if (playerIdx < finalState.players.length) {
        final player = finalState.players[playerIdx];
        ref
            .read(localGameLogProvider.notifier)
            .append('   ${player.displayName}: ${entry.value} pts');
      }
    }
    // Emit final scores event.
    if (!_eventController.isClosed) {
      _eventController.add(GameOverEvent(scores: scores));
    }
  }
}

final localGameProvider =
    NotifierProvider<LocalGameNotifier, GameState?>(LocalGameNotifier.new);

/// Exposes the typed [GameEvent] stream from [LocalGameNotifier] as a
/// Riverpod [StreamProvider].
///
/// Use this to drive the terminal renderer or tutorial narration:
/// ```dart
/// ref.listen(localGameEventProvider, (_, next) {
///   if (next case AsyncData(:final value)) _handleEvent(value);
/// });
/// ```
final localGameEventProvider = StreamProvider<GameEvent>((ref) {
  return ref.watch(localGameProvider.notifier).events;
});
