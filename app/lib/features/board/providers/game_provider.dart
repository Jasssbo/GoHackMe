import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_engine/go_engine.dart';

import '../../../services/game_sync_service.dart';

// ── WebSocket service provider ────────────────────────────────────────────

final gameSyncServiceProvider = Provider<GameSyncService>((ref) {
  final service = GameSyncService();
  ref.onDispose(service.dispose);
  return service;
});

// ── Game state provider ───────────────────────────────────────────────────

class GameStateNotifier extends AsyncNotifier<GameState?> {
  StreamSubscription? _stateSub;
  StreamSubscription? _errorSub;

  @override
  Future<GameState?> build() async {
    ref.onDispose(() {
      _stateSub?.cancel();
      _errorSub?.cancel();
    });
    return null;
  }

  /// Connects to the server room and starts receiving state updates.
  Future<void> connect({
    required String serverUrl,
    required String playerId,
    required String roomId,
    required String displayName,
    int boardSize = 19,
    int maxPlayers = 2,
  }) async {
    state = const AsyncLoading();

    final service = ref.read(gameSyncServiceProvider);
    try {
      await service.connect(
        serverUrl: serverUrl,
        playerId: playerId,
        roomId: roomId,
        displayName: displayName,
        boardSize: boardSize,
        maxPlayers: maxPlayers,
      );
    } catch (e, st) {
      state = AsyncError(e, st);
      return;
    }

    // Connected – waiting for all players. Show waiting screen.
    state = const AsyncData(null);

    // Cancel any subscriptions from a previous connect() call.
    await _stateSub?.cancel();
    await _errorSub?.cancel();

    // Forward game state updates to this notifier.
    _stateSub = service.gameStateStream.listen(
      (gameState) => state = AsyncData(gameState),
      onError: (e) => state = AsyncError(e, StackTrace.current),
    );

    // Surface server-side errors as state errors too.
    _errorSub = service.errorStream.listen(
      (msg) => state = AsyncError(msg, StackTrace.current),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void placeStone(String playerId, String roomId, Position pos) {
    ref.read(gameSyncServiceProvider).send(
          GameMessage.placeStone(playerId: playerId, roomId: roomId, pos: pos),
        );
  }

  void pass(String playerId, String roomId) {
    ref.read(gameSyncServiceProvider).send(
          GameMessage.pass(playerId: playerId, roomId: roomId),
        );
  }

  void launchAttack(String roomId, AttackAction action) {
    ref.read(gameSyncServiceProvider).send(
          GameMessage.performAttack(roomId: roomId, action: action),
        );
  }
}

final gameStateProvider =
    AsyncNotifierProvider<GameStateNotifier, GameState?>(
  GameStateNotifier.new,
);

// ── Connection log provider ───────────────────────────────────────────────

/// Stores the last N terminal-style log lines for display in the HUD.
class GameLogNotifier extends Notifier<List<String>> {
  static const _maxLines = 10;

  @override
  List<String> build() => const [];

  void addLine(String line) {
    final ts = DateTime.now();
    final stamp =
        '[${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}]';
    final next = [...state, '$stamp $line'];
    state = next.length > _maxLines ? next.sublist(next.length - _maxLines) : next;
  }

  void clear() => state = const [];
}

final gameLogProvider =
    NotifierProvider<GameLogNotifier, List<String>>(GameLogNotifier.new);
