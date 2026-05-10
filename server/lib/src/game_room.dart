import 'package:go_engine/go_engine.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef OnEmpty = void Function();

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

  // Configurable – host sets this when creating the room
  int maxPlayers;

  GameRoom({
    required this.id,
    required this.boardSize,
    required this.onEmpty,
    this.maxPlayers = 2,
  });

  bool get isEmpty => _connections.isEmpty;
  bool get isFull => _players.length >= maxPlayers;
  bool get isStarted => _state != null;
  List<Player> get players => List.unmodifiable(_players);

  // ── Join / leave ──────────────────────────────────────────────────────────

  /// Adds [player] to the room and registers their [channel].
  ///
  /// Returns an error string if the room is full or already started.
  String? addPlayer(Player player, WebSocketChannel channel) {
    if (isFull) return 'ROOM_FULL';
    if (_players.any((p) => p.id == player.id)) return 'ALREADY_IN_ROOM';

    _players.add(player);
    _connections[player.id] = channel;

    _broadcast(GameMessage(
      type: MessageType.playerJoined,
      roomId: id,
      payload: {'player': player.toJson(), 'playerCount': _players.length},
    ));

    // Auto-start when room is full
    if (isFull && !isStarted) _startGame();

    return null;
  }

  void removePlayer(String playerId) {
    _players.removeWhere((p) => p.id == playerId);
    _connections.remove(playerId);

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
        // VULN 1: safe int parsing – reject if missing or out of bounds
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
        result = GameEngine.placeStone(
          _state!,
          verifiedPlayerId, // VULN 5: use server-verified id
          Position(x, y),
        );

      case MessageType.pass:
        result = GameEngine.pass(_state!, verifiedPlayerId);

      case MessageType.endAttackPhase:
        result = GameEngine.endAttackPhase(_state!, verifiedPlayerId);

      case MessageType.performAttack:
        // Enforce server-side attacker id
        final rawAction = Map<String, dynamic>.from(message.payload)
          ..['attackerPlayerId'] = verifiedPlayerId;
        // VULN-A03: AttackAction.fromJson throws on unknown enum names or
        // malformed targetPosition — catch to prevent crashing the room stream.
        AttackAction action;
        try {
          action = AttackAction.fromJson(rawAction);
        } catch (_) {
          _sendError(verifiedPlayerId, 'INVALID_ATTACK_PAYLOAD');
          return;
        }
        result = GameEngine.launchAttack(_state!, action);

      default:
        _sendError(verifiedPlayerId, 'UNKNOWN_ACTION: ${message.type.name}');
        return;
    }

    if (result is ActionSuccess) {
      _state = result.newState;
      _broadcastState(logMessage: result.logMessage);

      if (GameEngine.isGameOver(_state!)) {
        _broadcastGameOver();
      }
    } else if (result is ActionFailure) {
      _sendError(verifiedPlayerId, (result).reason);
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  void _startGame() {
    _state = GameState.newGame(players: _players, boardSize: boardSize);
    print('[GameRoom $id] game started with ${_players.length} players');
    _broadcastState(logMessage: 'GAME_START');
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
      channel.sink.add(json);
    }
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
