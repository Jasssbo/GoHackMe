import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_engine/go_engine.dart';

// ── Local game log ────────────────────────────────────────────────────────

class LocalGameLogNotifier extends Notifier<List<String>> {
  static const _maxLines = 50;

  @override
  List<String> build() => [];

  void append(String line) {
    final next = [...state, line];
    state = next.length > _maxLines ? next.sublist(next.length - _maxLines) : next;
  }
}

final localGameLogProvider =
    NotifierProvider<LocalGameLogNotifier, List<String>>(
  LocalGameLogNotifier.new,
);

// ── Local game notifier ───────────────────────────────────────────────────

/// Holds the entire state of a local 1v1 game against the bot.
///
/// The human player always plays first (index 0, black stones).
/// The bot plays second (index 1, white stones).
///
/// After the human completes their turn (placement → optionally attacks →
/// end attack phase), the bot move is computed and applied automatically
/// with a short UI delay so the board has time to repaint.
class LocalGameNotifier extends Notifier<GameState?> {
  static const _humanId = 'human_player';
  static const _botId = 'bot_player';

  // Prevent concurrent bot turns being queued.
  bool _botTurnPending = false;
  BotDifficulty _difficulty = BotDifficulty.intermediate;

  @override
  GameState? build() => null;

  // ── Start game ────────────────────────────────────────────────────────────

  void startGame({
    int boardSize = 9,
    BotDifficulty difficulty = BotDifficulty.intermediate,
    String humanName = 'PLAYER_1',
    String botName = 'BOT',
  }) {
    _botTurnPending = false;
    _difficulty = difficulty;

    final players = [
      Player(id: _humanId, displayName: humanName),
      Player(id: _botId, displayName: botName),
    ];

    final gameState = GameState.newGame(
      players: players,
      boardSize: boardSize,
    );

    state = gameState;

    ref
        .read(localGameLogProvider.notifier)
        .append('>> LOCAL GAME STARTED ${boardSize}x$boardSize');
    ref
        .read(localGameLogProvider.notifier)
        .append('>> YOU are $humanName (BLACK). BOT is $botName (WHITE).');
  }

  // Expose constants so the screen can reference them.
  String get humanId => _humanId;
  String get botId => _botId;

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

  void _applyResult(ActionResult result) {
    switch (result) {
      case ActionSuccess(:final newState, :final logMessage):
        state = newState;
        if (logMessage != null) {
          ref.read(localGameLogProvider.notifier).append(logMessage);
        }

        if (GameEngine.isGameOver(newState)) {
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
            if (skipState.currentPlayerId == _botId) {
              _scheduleBotTurn();
              return;
            }
          } else {
            break;
          }
        }

        // Schedule bot turn when it becomes the bot's turn.
        if (newState.currentPlayerId == _botId &&
            newState.phase == GamePhase.attack) {
          _scheduleBotTurn();
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
    if (current.currentPlayerId != _botId) return;
    if (current.phase != GamePhase.attack) return;
    if (GameEngine.isGameOver(current)) return;

    // Bot may choose to attack first (attacks are valid in placement phase).
    final attack = BotPlayer.pickAttack(current, _botId, _humanId, _difficulty);
    GameState afterAttack = current;
    if (attack != null) {
      final ar = GameEngine.launchAttack(current, attack);
      if (ar case ActionSuccess(:final newState, :final logMessage)) {
        afterAttack = newState;
        if (logMessage != null) {
          ref.read(localGameLogProvider.notifier).append('BOT >> $logMessage');
        }
        state = afterAttack;
      }
    }

    // Bot places stone or passes.
    final move = BotPlayer.pickMove(afterAttack, _botId, _difficulty);
    if (move == null) {
      ref.read(localGameLogProvider.notifier).append('BOT >> PASS');
      _applyResult(GameEngine.pass(afterAttack, _botId));
    } else {
      ref
          .read(localGameLogProvider.notifier)
          .append('BOT >> PLACE (${move.x},${move.y})');
      _applyResult(GameEngine.placeStone(afterAttack, _botId, move));
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
