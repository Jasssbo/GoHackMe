import 'dart:async';

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

  /// IDs of all bot players in the current game.
  List<String> _botIds = ['bot_1'];

  bool _isBot(String playerId) => _botIds.contains(playerId);

  @override
  GameState? build() {
    ref.onDispose(() => _turnTimer?.cancel());
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
    assert(botCount >= 1 && botCount <= 3, 'botCount must be 1, 2 or 3');
    _botTurnPending = false;
    _difficulty = difficulty;
    _botIds = List.generate(botCount, (i) => 'bot_${i + 1}');

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

  // ── Human actions ─────────────────────────────────────────────────────────

  void placeStone(Position pos) {
    final current = state;
    if (current == null) return;
    if (current.currentPlayerId != _humanId) return;

    final result = GameEngine.placeStone(current, _humanId, pos);
    _applyResult(result);
  }

  void pass() {
    final current = state;
    if (current == null) return;
    if (current.currentPlayerId != _humanId) return;

    final result = GameEngine.pass(current, _humanId);
    _applyResult(result);
  }

  void launchAttack(AttackAction action) {
    final current = state;
    if (current == null) return;

    final result = GameEngine.launchAttack(current, action);
    _applyResult(result);
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
      case ActionSuccess(:final newState, :final logMessage):
        state = newState;
        if (logMessage != null) {
          ref.read(localGameLogProvider.notifier).append(logMessage);
        }

        if (GameEngine.isGameOver(newState)) {
          _turnTimer?.cancel();
          _handleGameOver(newState);
          return;
        }

        // Auto-skip loop: advance past every consecutive DDOS-blocked player.
        int skipGuard = 0;
        while (
          skipGuard < newState.players.length &&
          state!.phase == GamePhase.attack &&
          state!.hasEffect(state!.currentPlayerId, AttackType.ddos)
        ) {
          skipGuard++;
          final skipResult = GameEngine.skipDdosVictim(state!);
          if (skipResult case ActionSuccess(
            newState: final skipState,
            logMessage: final skipLog,
          )) {
            state = skipState;
            if (skipLog != null) {
              ref.read(localGameLogProvider.notifier).append('DDOS >> $skipLog');
            }
            if (skipState.currentPlayerId == _humanId) {
              // Human's turn after DDOS skip – restart their timer.
              _resetTurnTimer();
              return;
            }
            if (_isBot(skipState.currentPlayerId)) {
              _scheduleBotTurn();
              return;
            }
          } else {
            break;
          }
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

  void _runBotTurn() {
    final current = state;
    if (current == null) return;
    if (!_isBot(current.currentPlayerId)) return;
    if (current.phase != GamePhase.attack) return;
    if (GameEngine.isGameOver(current)) return;

    final botId = current.currentPlayerId;
    final botLabel = current.players
        .firstWhere((p) => p.id == botId)
        .displayName;

    // Bot may choose to attack first (attacks are valid in placement phase).
    final attack = BotPlayer.pickAttack(current, botId, _humanId, _difficulty);
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

    // Bot places stone or passes.
    final move = BotPlayer.pickMove(afterAttack, botId, _difficulty);
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
  }
}

final localGameProvider =
    NotifierProvider<LocalGameNotifier, GameState?>(LocalGameNotifier.new);
