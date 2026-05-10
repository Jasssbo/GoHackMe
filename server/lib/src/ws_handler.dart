import 'package:go_engine/go_engine.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'game_room.dart';
import 'room_manager.dart';

/// Shelf handler that upgrades HTTP connections to WebSockets and routes
/// incoming [GameMessage]s to the appropriate [GameRoom].
/// Max bytes accepted per message to prevent memory exhaustion.
const _kMaxMessageBytes = 4096;

/// Max messages per second per connection before the connection is dropped.
const _kRateLimitPerSecond = 20;

/// UUID v4 pattern – the only format the Flutter client generates.
final _kUuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Room ID: 4–64 alphanumeric / dash characters (client generates 8-char hex).
final _kRoomIdPattern = RegExp(r'^[A-Za-z0-9\-]{4,64}$');

Handler buildWsHandler(RoomManager roomManager) {
  return webSocketHandler((WebSocketChannel channel, String? protocol) {
    String? connectedPlayerId;
    String? connectedRoomId;

    // Rate limiting state
    var msgCount = 0;
    var windowStart = DateTime.now();

    channel.stream.listen(
      (raw) {
        if (raw is! String) return;

        // ── Size guard ─────────────────────────────────────────────────────
        if (raw.length > _kMaxMessageBytes) {
          channel.sink.add(
            GameMessage.error(reason: 'MESSAGE_TOO_LARGE').toJsonString(),
          );
          channel.sink.close();
          return;
        }

        // ── Rate limit ─────────────────────────────────────────────────────
        final now = DateTime.now();
        if (now.difference(windowStart).inSeconds >= 1) {
          msgCount = 0;
          windowStart = now;
        }
        msgCount++;
        if (msgCount > _kRateLimitPerSecond) {
          channel.sink.add(
            GameMessage.error(reason: 'RATE_LIMITED').toJsonString(),
          );
          channel.sink.close();
          return;
        }

        GameMessage message;
        try {
          message = GameMessage.fromJsonString(raw);
        } catch (_) {
          channel.sink.add(
            GameMessage.error(reason: 'INVALID_JSON').toJsonString(),
          );
          return;
        }

        // ── Ping / pong ────────────────────────────────────────────────────
        if (message.type == MessageType.ping) {
          channel.sink.add(GameMessage.pong().toJsonString());
          return;
        }

        // ── Join room ──────────────────────────────────────────────────────
        if (message.type == MessageType.joinRoom) {
          final playerId = message.playerId;
          final roomId = message.roomId;
          final displayName =
              message.payload['displayName'] as String? ?? 'Unknown';
          // Clamp to safe ranges (VULN 6)
          final boardSize =
              ((message.payload['boardSize'] as int?) ?? 19).clamp(9, 19);
          final maxPlayers =
              ((message.payload['maxPlayers'] as int?) ?? 2).clamp(2, 4);

          if (playerId == null || roomId == null) {
            channel.sink.add(
              GameMessage.error(reason: 'MISSING_PLAYER_ID_OR_ROOM_ID')
                  .toJsonString(),
            );
            return;
          }

          // VULN-A01: Validate playerId format (UUID v4) and roomId format
          // (hex/alnum, 4–64 chars) to prevent log injection and identity
          // spoofing via crafted strings.
          if (!_kUuidPattern.hasMatch(playerId)) {
            channel.sink.add(
              GameMessage.error(reason: 'INVALID_PLAYER_ID_FORMAT')
                  .toJsonString(),
            );
            return;
          }
          if (!_kRoomIdPattern.hasMatch(roomId)) {
            channel.sink.add(
              GameMessage.error(reason: 'INVALID_ROOM_ID_FORMAT')
                  .toJsonString(),
            );
            return;
          }

          // Sanitise displayName
          final sanitisedName = displayName.length > 32
              ? displayName.substring(0, 32)
              : displayName;

          final room = roomManager.getOrCreate(roomId, boardSize: boardSize);
          // VULN 4: server at max capacity → reject gracefully
          if (room == null) {
            channel.sink.add(
              GameMessage.error(reason: 'SERVER_FULL').toJsonString(),
            );
            return;
          }
          // VULN 2: only set maxPlayers before the game has started
          if (!room.isStarted) room.maxPlayers = maxPlayers;
          final error = room.addPlayer(
            Player(id: playerId, displayName: sanitisedName),
            channel,
          );

          if (error != null) {
            channel.sink.add(
              GameMessage.error(
                reason: error,
                roomId: roomId,
                playerId: playerId,
              ).toJsonString(),
            );
            return;
          }

          connectedPlayerId = playerId;
          connectedRoomId = roomId;
          return;
        }

        // ── All other messages require an established room connection ──────
        if (connectedRoomId == null || connectedPlayerId == null) {
          channel.sink.add(
            GameMessage.error(reason: 'JOIN_ROOM_FIRST').toJsonString(),
          );
          return;
        }

        final room = roomManager.getRoom(connectedRoomId!);
        if (room == null) {
          channel.sink.add(
            GameMessage.error(reason: 'ROOM_NOT_FOUND').toJsonString(),
          );
          return;
        }

        // VULN 5: override playerId with the server-verified identity,
        // ignoring whatever the client claims in the message body.
        room.handleAction(message, verifiedPlayerId: connectedPlayerId!);
      },
      onDone: () {
        if (connectedRoomId != null && connectedPlayerId != null) {
          roomManager
              .getRoom(connectedRoomId!)
              ?.removePlayer(connectedPlayerId!);
        }
      },
      onError: (_) {
        if (connectedRoomId != null && connectedPlayerId != null) {
          roomManager
              .getRoom(connectedRoomId!)
              ?.removePlayer(connectedPlayerId!);
        }
      },
      cancelOnError: true,
    );
  });
}
