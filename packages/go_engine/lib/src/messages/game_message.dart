import 'dart:convert';

import '../models/attack.dart';
import '../models/game_state.dart';
import '../models/position.dart';

// ── Message type catalogue ────────────────────────────────────────────────

enum MessageType {
  // ── Client → Server ───────────────────────────────────────────────────
  /// Join or create a game room.
  joinRoom,

  /// Place a stone at (x, y).
  placeStone,

  /// Pass this turn.
  pass,

  /// Execute a hack/attack during the attack phase.
  performAttack,

  /// Signal end of attack phase (advance turn).
  endAttackPhase,

  // ── Server → Client ───────────────────────────────────────────────────
  /// Full game state snapshot (sent after every state change).
  gameStateUpdate,

  /// A player connected/joined the room.
  playerJoined,

  /// A player disconnected or left.
  playerLeft,

  /// The server rejected an action.
  error,

  /// Game has ended; payload contains final scores.
  gameOver,

  // ── Bidirectional ─────────────────────────────────────────────────────
  ping,
  pong,
}

// ── GameMessage ────────────────────────────────────────────────────────────

/// The single wire-format message exchanged over the WebSocket connection.
///
/// Every client action and every server broadcast is a [GameMessage].
/// The [payload] is type-specific; see [MessageType] for what each type
/// expects in its payload.
class GameMessage {
  final MessageType type;

  /// The player who sent this message (null for server-originated messages).
  final String? playerId;

  /// The room this message belongs to.
  final String? roomId;

  /// Type-specific data.
  final Map<String, dynamic> payload;

  const GameMessage({
    required this.type,
    this.playerId,
    this.roomId,
    this.payload = const {},
  });

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'type': type.name,
        if (playerId != null) 'playerId': playerId,
        if (roomId != null) 'roomId': roomId,
        'payload': payload,
      };

  String toJsonString() => jsonEncode(toJson());

  factory GameMessage.fromJson(Map<String, dynamic> json) => GameMessage(
        type: MessageType.values.byName(json['type'] as String),
        playerId: json['playerId'] as String?,
        roomId: json['roomId'] as String?,
        payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
      );

  factory GameMessage.fromJsonString(String raw) =>
      GameMessage.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  // ── Named constructors for common messages ─────────────────────────────────

  factory GameMessage.joinRoom({
    required String playerId,
    required String roomId,
    required String displayName,
    int boardSize = 19,
    int maxPlayers = 2,
  }) =>
      GameMessage(
        type: MessageType.joinRoom,
        playerId: playerId,
        roomId: roomId,
        payload: {
          'displayName': displayName,
          'boardSize': boardSize,
          'maxPlayers': maxPlayers,
        },
      );

  factory GameMessage.placeStone({
    required String playerId,
    required String roomId,
    required Position pos,
  }) =>
      GameMessage(
        type: MessageType.placeStone,
        playerId: playerId,
        roomId: roomId,
        payload: {'x': pos.x, 'y': pos.y},
      );

  factory GameMessage.pass({
    required String playerId,
    required String roomId,
  }) =>
      GameMessage(
        type: MessageType.pass,
        playerId: playerId,
        roomId: roomId,
      );

  factory GameMessage.performAttack({
    required String roomId,
    required AttackAction action,
  }) =>
      GameMessage(
        type: MessageType.performAttack,
        playerId: action.attackerPlayerId,
        roomId: roomId,
        payload: action.toJson(),
      );

  factory GameMessage.endAttackPhase({
    required String playerId,
    required String roomId,
  }) =>
      GameMessage(
        type: MessageType.endAttackPhase,
        playerId: playerId,
        roomId: roomId,
      );

  factory GameMessage.gameStateUpdate({
    required String roomId,
    required GameState state,
    String? logMessage,
  }) =>
      GameMessage(
        type: MessageType.gameStateUpdate,
        roomId: roomId,
        payload: {
          'state': state.toJson(),
          if (logMessage != null) 'log': logMessage,
        },
      );

  factory GameMessage.error({
    required String reason,
    String? roomId,
    String? playerId,
  }) =>
      GameMessage(
        type: MessageType.error,
        roomId: roomId,
        playerId: playerId,
        payload: {'reason': reason},
      );

  factory GameMessage.ping() => const GameMessage(type: MessageType.ping);
  factory GameMessage.pong() => const GameMessage(type: MessageType.pong);

  @override
  String toString() => 'GameMessage(${type.name}, room=$roomId, player=$playerId)';
}
