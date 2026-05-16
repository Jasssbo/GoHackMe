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
  static const _kTurnTimeout = Duration(seconds: 15);

  // Configurable – host sets this when creating the room
  int maxPlayers;

  // Host IP geolocation — populated asynchronously after first join.
  double? hostLat;
  double? hostLon;
  String? hostCity;
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
  int get playerCount => _players.length;
  List<Player> get players => List.unmodifiable(_players);

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
    if (isFull && !isStarted) _startGame();

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
        // playing or hijackedVictimPlacement — auto-pass
        result = GameEngine.pass(_state!, playerId);
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
    ));
  }

  void _broadcastGameOver() {
    final scores = Scorer.areaScore(_state!.board);
    _log('room:$id', 'game OVER — scores: ${scores.map((k, v) => MapEntry(k.name, v))}');
    _broadcast(GameMessage(
      type: MessageType.gameOver,
      roomId: id,
      payload: {
        'scores': scores.map((k, v) => MapEntry(k.name, v)),
        'state': _state!.toJson(),
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
