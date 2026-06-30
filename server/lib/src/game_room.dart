import 'dart:async';

import 'package:go_engine/go_engine.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef OnEmpty = void Function();

void _log(String tag, String msg) {
  final ts = DateTime.now().toUtc().toIso8601String();
  print('[$ts][$tag] $msg');
}

/// A single game room managing up to 4 connected players.
///
/// [GameRoom] holds the authoritative [GameState] and fans out every state
/// update to all connected clients.
class GameRoom {
  final String id;
  final int boardSize;
  final OnEmpty onEmpty;

  GameState? _state;
  final _connections = <String, WebSocketChannel>{}; // playerId → channel
  final _players = <Player>[];

  /// The player who created the room (first to join).
  /// Only the host may trigger a force-start before the room fills.
  String? _hostPlayerId;

  /// Players that disconnected mid-game and are waiting within the 30-second
  /// reconnect window.  The room stays alive until their timers expire.
  final _disconnectedPlayerIds = <String>{};
  final _reconnectTimers = <String, Timer>{};
  static const _kReconnectGrace = Duration(seconds: 30);

  // ── Turn timer ────────────────────────────────────────────────────────────
  Timer? _turnTimer;
  DateTime? _turnStartedAt; // wall-clock time when the current turn began
  static const _kTurnTimeout = Duration(seconds: 15);

  // Configurable – host sets this when creating the room
  int maxPlayers;

  // Country-centroid pin — populated asynchronously after the first player joins.
  // Stores the geographic centre of the host's country, not their real location.
  double? hostLat;
  double? hostLon;
  String? hostCountry;

  GameRoom({
    required this.id,
    required this.boardSize,
    required this.onEmpty,
    this.maxPlayers = 2,
  });

  bool get isEmpty => _connections.isEmpty && _reconnectTimers.isEmpty;
  bool get isFull => _players.length >= maxPlayers;
  bool get isStarted => _state != null;
  bool get hasReconnectSlots => _reconnectTimers.isNotEmpty;
  int get playerCount => _players.length;
  List<Player> get players => List.unmodifiable(_players);

  // ── Restore-from-save state ───────────────────────────────────────────────

  /// Non-null when this room was created via [restoreFromSave].
  GameState? _savedState;

  /// maps new playerId → slot index in the saved state.
  final Map<String, int> _claimedSlots = {};

  // ── Join / leave ──────────────────────────────────────────────────────────

  /// Adds [player] to the room and registers their [channel].
  ///
  /// Returns an error string if the room is full or already started.
  String? addPlayer(Player player, WebSocketChannel channel) {
    // Reconnect: player was in the game but temporarily disconnected.
    if (_disconnectedPlayerIds.contains(player.id)) {
      _disconnectedPlayerIds.remove(player.id);
      _reconnectTimers[player.id]?.cancel();
      _reconnectTimers.remove(player.id);
      _connections[player.id] = channel;
      _log('room:$id', 'player RECONNECTED: ${player.id} (${player.displayName})');
      // Immediately sync the returning player.
      channel.sink.add(GameMessage(
        type: MessageType.gameStateUpdate,
        roomId: id,
        payload: {'state': _state!.toJson(), 'log': 'RECONNECTED'},
      ).toJsonString());
      _broadcast(GameMessage(
        type: MessageType.playerJoined,
        roomId: id,
        payload: {'player': player.toJson()},
      ));
      return null;
    }

    if (isFull) return 'ROOM_FULL';
    if (_players.any((p) => p.id == player.id)) return 'ALREADY_IN_ROOM';

    _players.add(player);
    _connections[player.id] = channel;
    // First to join is the room host.
    _hostPlayerId ??= player.id;
    _log('room:$id', 'player joined: ${player.id} (${player.displayName}) [${_players.length}/$maxPlayers]');

    _broadcast(GameMessage(
      type: MessageType.playerJoined,
      roomId: id,
      payload: {'player': player.toJson(), 'playerCount': _players.length},
    ));

    // Auto-start when room is full
    if (isFull && !isStarted) {
      if (_savedState != null) {
        // Restore mode: for 2-player games auto-assign the second joiner to
        // the only remaining unclaimed slot, then start.  For ≥3 players each
        // joiner must explicitly claim their slot via [claimSlot].
        if (_savedState!.players.length == 2) {
          // Find the one slot the host didn't claim.
          final unclaimedSlot = List.generate(_savedState!.players.length, (i) => i)
              .firstWhere((i) => !_claimedSlots.containsValue(i), orElse: () => -1);
          if (unclaimedSlot >= 0) {
            _claimedSlots[player.id] = unclaimedSlot;
          }
          _tryStartRestored();
        }
        // ≥3 players: do nothing — wait for explicit claimSlot messages.
      } else {
        _startGame();
      }
    }

    return null;
  }

  /// Host-triggered early start.  Requires ≥ 2 players.
  /// Only the room host (first joiner) is authorised to call this.
  /// Returns an error string on failure, null on success.
  String? forceStart({required String requesterId}) {
    if (requesterId != _hostPlayerId) return 'NOT_HOST';
    if (_state != null) return 'GAME_ALREADY_STARTED';
    if (_players.length < 2) return 'NOT_ENOUGH_PLAYERS';
    _startGame();
    return null;
  }

  void removePlayer(String playerId) {
    _connections.remove(playerId);

    // Mid-game disconnect: keep slot alive for the reconnect grace period.
    if (_state != null && _players.any((p) => p.id == playerId)) {
      _log('room:$id', 'player DISCONNECTED (mid-game): $playerId — grace ${_kReconnectGrace.inSeconds}s');
      _disconnectedPlayerIds.add(playerId);
      _reconnectTimers[playerId]?.cancel();
      _reconnectTimers[playerId] = Timer(_kReconnectGrace, () {
        _disconnectedPlayerIds.remove(playerId);
        _reconnectTimers.remove(playerId);
        _players.removeWhere((p) => p.id == playerId);
        // Also remove the timed-out player from the live GameState so their
        // turn slot does not become an infinitely-stalling ghost.
        // Adjust currentPlayerIndex if the removed player was earlier in the
        // list — otherwise every remaining player's index shifts by -1 and
        // the wrong player gets the next turn.
        if (_state != null) {
          final removedIdx =
              _state!.players.indexWhere((p) => p.id == playerId);
          final newPlayers =
              _state!.players.where((p) => p.id != playerId).toList();
          int newCurrentIdx = _state!.currentPlayerIndex;
          if (removedIdx != -1 && removedIdx < newCurrentIdx) {
            newCurrentIdx--;
          }
          if (newPlayers.isNotEmpty) {
            newCurrentIdx = newCurrentIdx.clamp(0, newPlayers.length - 1);
          }
          _state = _state!.copyWith(
            players: newPlayers,
            currentPlayerIndex: newCurrentIdx,
          );
        }
        _log('room:$id', 'player TIMED OUT after ${_kReconnectGrace.inSeconds}s: $playerId');
        _broadcast(GameMessage(
          type: MessageType.playerLeft,
          roomId: id,
          payload: {'playerId': playerId, 'reason': 'TIMED_OUT'},
        ));
        if (isEmpty) onEmpty();
      });
      _broadcast(GameMessage(
        type: MessageType.playerLeft,
        roomId: id,
        payload: {'playerId': playerId},
      ));
      // If only one player remains active, end the game immediately — no need
      // to wait for the 15-second turn timer.
      final activeCount = _players.length - _disconnectedPlayerIds.length;
      if (activeCount <= 1 && _players.length > 1) {
        _log('room:$id', 'LAST_ENTITY_STANDING (on disconnect) — game ends by forfeit');
        _turnTimer?.cancel();
        _broadcastGameOver();
      }
      return;
    }

    // Pre-game or player not found: immediate removal.
    _log('room:$id', 'player left (pre-game): $playerId');
    _players.removeWhere((p) => p.id == playerId);
    _broadcast(GameMessage(
      type: MessageType.playerLeft,
      roomId: id,
      payload: {'playerId': playerId},
    ));
    if (isEmpty) onEmpty();
  }

  // ── Game actions ──────────────────────────────────────────────────────────

  void handleAction(GameMessage message, {required String verifiedPlayerId}) {
    if (_state == null) {
      _sendError(verifiedPlayerId, 'GAME_NOT_STARTED');
      return;
    }

    ActionResult result;

    switch (message.type) {
      case MessageType.placeStone:
        // Reject non-integer or out-of-range coordinates before passing to engine.
        final x = message.payload['x'];
        final y = message.payload['y'];
        if (x is! int || y is! int) {
          _sendError(verifiedPlayerId, 'INVALID_COORDINATES');
          return;
        }
        if (!_state!.board.isInBounds(Position(x, y))) {
          _sendError(verifiedPlayerId, 'POSITION_OUT_OF_BOUNDS');
          return;
        }
        _log('room:$id', 'placeStone: player=$verifiedPlayerId pos=($x,$y)');
        result = GameEngine.placeStone(
          _state!,
          verifiedPlayerId, // use server-verified id, not client-supplied
          Position(x, y),
        );

      case MessageType.pass:
        _log('room:$id', 'pass: player=$verifiedPlayerId');
        result = GameEngine.pass(_state!, verifiedPlayerId);

      case MessageType.endAttackPhase:
        _log('room:$id', 'endAttackPhase: player=$verifiedPlayerId');
        result = GameEngine.endAttackPhase(_state!, verifiedPlayerId);

      case MessageType.performAttack:
        // Enforce server-side attacker id
        final rawAction = Map<String, dynamic>.from(message.payload)
          ..['attackerPlayerId'] = verifiedPlayerId;
        // AttackAction.fromJson throws on unknown enum names or malformed
        // targetPosition — catch to avoid crashing the whole room.
        AttackAction action;
        try {
          action = AttackAction.fromJson(rawAction);
        } catch (_) {
          _sendError(verifiedPlayerId, 'INVALID_ATTACK_PAYLOAD');
          return;
        }
        _log('room:$id', 'attack: player=$verifiedPlayerId type=${action.type.name} target=${action.targetPlayerId}');
        result = GameEngine.launchAttack(_state!, action);

      default:
        _sendError(verifiedPlayerId, 'UNKNOWN_ACTION: ${message.type.name}');
        return;
    }

    if (result is ActionSuccess) {
      _state = result.newState;
      _broadcastState(logMessage: result.logMessage);

      if (GameEngine.isGameOver(_state!)) {
        _turnTimer?.cancel();
        _broadcastGameOver();
      } else {
        _resetTurnTimer();
      }
    } else if (result is ActionFailure) {
      _log('room:$id', 'action rejected: player=$verifiedPlayerId reason=${(result).reason}');
      _sendError(verifiedPlayerId, (result).reason);
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  /// Resets (or starts) the 15-second turn clock for the current player.
  /// When it fires the server auto-acts on behalf of the inactive player.
  void _resetTurnTimer() {
    _turnTimer?.cancel();
    _turnStartedAt = DateTime.now().toUtc();
    if (_state == null || _state!.phase == GamePhase.scoring) return;
    final playerId = _state!.currentPlayerId;
    _turnTimer = Timer(_kTurnTimeout, () {
      if (_state == null) return;
      if (_state!.currentPlayerId != playerId) return; // already advanced
      _log('room:$id', 'TURN_TIMEOUT: auto-acting for player=$playerId phase=${_state!.phase.name}');
      final ActionResult result;
      if (_state!.phase == GamePhase.attack) {
        result = GameEngine.endAttackPhase(_state!, playerId);
      } else {
        // hijackedVictimPlacement: auto-pass is not valid in this phase;
        // the turn timer cannot resolve it. Log and wait for the next tick.
        _log('room:$id', 'TURN_TIMEOUT: cannot auto-resolve phase=${_state!.phase.name} for player=$playerId');
        _resetTurnTimer(); // keep the clock running
        return;
      }
      if (result is ActionSuccess) {
        _state = result.newState;
        _broadcastState(logMessage: 'TURN_TIMEOUT');
        if (GameEngine.isGameOver(_state!)) {
          _broadcastGameOver();
          return;
        }
        // If only one entity remains connected, award them the win.
        final activeCount = _players.length - _disconnectedPlayerIds.length;
        if (activeCount <= 1 && _players.length > 1) {
          _log('room:$id', 'LAST_ENTITY_STANDING — game ends by forfeit');
          _broadcastGameOver();
          _turnTimer?.cancel();
          return;
        }
        _resetTurnTimer();
      }
    });
  }

  // ── Restore-from-save API ─────────────────────────────────────────────────

  /// Seeds this room with [savedState] from a previously saved game.
  ///
  /// Must be called by the host (first joiner) before any other player joins.
  /// [hostSlotIndex] is the 0-based slot the host occupied in the original game.
  /// Returns an error string on failure, null on success.
  String? restoreFromSave({
    required GameState savedState,
    required int hostSlotIndex,
    required String hostPlayerId,
  }) {
    if (_state != null) return 'GAME_ALREADY_STARTED';
    if (hostSlotIndex < 0 || hostSlotIndex >= savedState.players.length) {
      return 'INVALID_HOST_SLOT';
    }
    _savedState = savedState;
    maxPlayers = savedState.players.length;
    _claimedSlots[hostPlayerId] = hostSlotIndex;
    _log('room:$id',
        'restore seeded: host=$hostPlayerId slot=$hostSlotIndex players=${savedState.players.length}');
    return null;
  }

  /// Assigns [playerId] to a slot in the saved game.
  ///
  /// For 2-player restores the second slot is auto-assigned when the room
  /// fills; this method is only needed for ≥ 3-player saves.
  /// Returns an error string on failure, null on success.
  String? claimSlot({
    required String playerId,
    required int slotIndex,
  }) {
    final saved = _savedState;
    if (saved == null) return 'NOT_A_RESTORE_ROOM';
    if (slotIndex < 0 || slotIndex >= saved.players.length) return 'INVALID_SLOT';
    if (_claimedSlots.containsValue(slotIndex)) return 'SLOT_ALREADY_CLAIMED';
    if (_claimedSlots.containsKey(playerId)) return 'ALREADY_CLAIMED_SLOT';
    _claimedSlots[playerId] = slotIndex;
    _log('room:$id', 'slot claimed: player=$playerId slot=$slotIndex');
    _tryStartRestored();
    return null;
  }

  /// Starts the restored game if every slot has been claimed.
  void _tryStartRestored() {
    final saved = _savedState;
    if (saved == null) return;
    if (_claimedSlots.length < saved.players.length) return;
    _startRestored(saved);
  }

  /// Builds a remapped [GameState] using the new player IDs and broadcasts it.
  void _startRestored(GameState saved) {
    // Build old-id → new-id mapping from the claimed slots.
    final idRemap = <String, String>{};
    for (final entry in _claimedSlots.entries) {
      final newId = entry.key;
      final slotIdx = entry.value;
      final oldId = saved.players[slotIdx].id;
      idRemap[oldId] = newId;
    }

    String remap(String id) => idRemap[id] ?? id;
    String? remapNullable(String? id) => id == null ? null : remap(id);

    // Rebuild ordered player list preserving slot order.
    final newPlayers = List.generate(saved.players.length, (i) {
      final oldPlayer = saved.players[i];
      final newId = idRemap[oldPlayer.id] ?? oldPlayer.id;
      return Player(id: newId, displayName: oldPlayer.displayName);
    });

    _state = saved.copyWith(
      players: newPlayers,
      subnets: {for (final e in saved.subnets.entries) remap(e.key): e.value},
      captureCount: {for (final e in saved.captureCount.entries) remap(e.key): e.value},
      patchShields: {for (final e in saved.patchShields.entries) remap(e.key): e.value},
      backdoorBy: {
        for (final e in saved.backdoorBy.entries)
          remap(e.key): remapNullable(e.value)
      },
      activeEffects: saved.activeEffects.map((ef) => ActiveEffect(
        type: ef.type,
        targetPlayerId: remap(ef.targetPlayerId),
        turnsRemaining: ef.turnsRemaining,
        anchorPosition: ef.anchorPosition,
        hijackedByPlayerId: remapNullable(ef.hijackedByPlayerId),
      )).toList(),
    );

    _log('room:$id', 'game RESTORED — ${newPlayers.length} players from save');
    _broadcastState(logMessage: 'GAME_RESTORED');
    _resetTurnTimer();
  }

  // ── Normal game start ─────────────────────────────────────────────────────

  void _startGame() {
    _state = GameState.newGame(players: _players, boardSize: boardSize);
    _log('room:$id', 'game STARTED — ${_players.length} players, ${boardSize}x$boardSize board');
    _broadcastState(logMessage: 'GAME_START');
    _resetTurnTimer();
  }

  void _broadcastState({String? logMessage}) {
    _broadcast(GameMessage.gameStateUpdate(
      roomId: id,
      state: _state!,
      logMessage: logMessage,
      turnStartedAt: _turnStartedAt,
    ));
  }

  void _broadcastGameOver() {
    final scores = Scorer.areaScore(_state!.board);
    _log('room:$id', 'game OVER — scores: ${scores.map((k, v) => MapEntry(k.name, v))}');
    // Force the state to the scoring phase so clients whose game-over detection
    // relies on GamePhase (wired_game_provider._onGameState) correctly
    // transition their UI to the game-over screen.
    _state = _state!.copyWith(phase: GamePhase.scoring);
    _broadcastState(logMessage: 'GAME_OVER');
    _broadcast(GameMessage(
      type: MessageType.gameOver,
      roomId: id,
      payload: {
        'scores': scores.map((k, v) => MapEntry(k.name, v)),
      },
    ));
  }

  void _broadcast(GameMessage message) {
    final json = message.toJsonString();
    for (final channel in _connections.values) {
      try {
        channel.sink.add(json);
      } catch (e) {
        _log('room:$id', 'broadcast error (stale sink): $e');
      }
    }
  }

  /// Returns the display name of [playerId], or '?' if not found.
  String playerDisplayName(String playerId) {
    return _players
        .firstWhere(
          (p) => p.id == playerId,
          orElse: () => Player(id: '', displayName: '?'),
        )
        .displayName;
  }

  /// Broadcasts a chat message from [senderId] to all currently-connected
  /// players.  Only active connections receive it — late joiners see nothing.
  void broadcastChat(String senderId, String senderName, String text) {
    // Strip '>' from senderName so the CHAT> log format stays unambiguous.
    final safeName = senderName.replaceAll('>', '');
    _broadcast(GameMessage(
      type: MessageType.chat,
      roomId: id,
      payload: {'senderId': senderId, 'senderName': safeName, 'text': text},
    ));
  }

  /// Cancels all pending timers.  Called by [RoomManager] when the room is reaped.
  void dispose() {
    _turnTimer?.cancel();
    for (final t in _reconnectTimers.values) {
      t.cancel();
    }
    _reconnectTimers.clear();
    _disconnectedPlayerIds.clear();
  }

  void _sendError(String? playerId, String reason) {
    if (playerId == null) return;
    final channel = _connections[playerId];
    channel?.sink.add(
      GameMessage.error(reason: reason, roomId: id, playerId: playerId)
          .toJsonString(),
    );
  }
}
