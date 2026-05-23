import 'dart:async';
import 'dart:io';

import 'package:go_engine/go_engine.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'game_room.dart';
import 'geo_service.dart';
import 'room_manager.dart';

/// Shelf handler that upgrades HTTP connections to WebSockets and routes
/// incoming [GameMessage]s to the appropriate [GameRoom].
/// Max bytes accepted per message to prevent memory exhaustion.
const _kMaxMessageBytes = 4096;

/// Max messages per second per connection before the connection is dropped.
const _kRateLimitPerSecond = 20;

/// How often the server sends a ping frame to the client.
const _kPingInterval = Duration(seconds: 30);

/// How many consecutive missed pongs trigger a forced disconnect.
const _kMaxMissedPongs = 2;

/// UUID v4 pattern – the only format the Flutter client generates.
final _kUuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Room ID: 4–64 alphanumeric / dash characters (client generates 8-char hex).
final _kRoomIdPattern = RegExp(r'^[A-Za-z0-9\-]{4,64}$');

/// Returns an error reason string if playerId/roomId fail format validation,
/// null if both are valid.
String? _validatePlayerAndRoom(String playerId, String roomId) {
  if (!_kUuidPattern.hasMatch(playerId)) return 'INVALID_PLAYER_ID_FORMAT';
  if (!_kRoomIdPattern.hasMatch(roomId)) return 'INVALID_ROOM_ID_FORMAT';
  return null;
}

/// Hard cap on concurrent WebSocket connections.
/// Prevents file-descriptor exhaustion and memory DoS on Render.com free tier.
const _kMaxConnections = 200;

void _log(String tag, String msg) {
  final ts = DateTime.now().toUtc().toIso8601String();
  print('[$ts][$tag] $msg');
}

Handler buildWsHandler(RoomManager roomManager) {
  var activeConnections = 0;

  return (Request request) {
    // Extract client IP before upgrading to WebSocket.
    final clientIp = extractIp(
      request.headers,
      request.context['shelf.io.connection_info'] as HttpConnectionInfo?,
    );

    return webSocketHandler((WebSocketChannel channel, String? protocol) {
      // Reject the upgrade immediately if we are at capacity.
      if (activeConnections >= _kMaxConnections) {
        _log('ws', 'rejected connection — SERVER_FULL ($activeConnections/$_kMaxConnections)');
        channel.sink.add(
          GameMessage.error(reason: 'SERVER_FULL').toJsonString(),
        );
        channel.sink.close();
        return;
      }
      activeConnections++;
      _log('ws', 'client connected (active: $activeConnections) ip=$clientIp');

    String? connectedPlayerId;
    String? connectedRoomId;

    // Rate limiting state
    var msgCount = 0;
    var windowStart = DateTime.now();

    // Per-connection chat rate limit: max 100 messages in any 5-minute window.
    final chatTimestamps = <DateTime>[];
    const kMaxChatMsgs = 100;
    const kChatWindow = Duration(minutes: 5);

    // ── Proactive keep-alive ping ──────────────────────────────────────────
    // Detects dead connections (crashed clients that never emit onDone).
    // Sends a ping every [_kPingInterval]; if [_kMaxMissedPongs] consecutive
    // pings are unanswered the connection is forcibly closed.
    var missedPongs = 0;
    Timer? pingTimer;

    void cleanup() {
      pingTimer?.cancel();
      pingTimer = null;
      activeConnections--;
      if (connectedRoomId != null && connectedPlayerId != null) {
        _log('ws', 'disconnected: player=$connectedPlayerId room=$connectedRoomId (active: $activeConnections)');
        roomManager.getRoom(connectedRoomId!)?.removePlayer(connectedPlayerId!);
        connectedRoomId = null;
        connectedPlayerId = null;
      } else {
        _log('ws', 'anonymous client disconnected (active: $activeConnections)');
      }
    }

    pingTimer = Timer.periodic(_kPingInterval, (_) {
      missedPongs++;
      if (missedPongs > _kMaxMissedPongs) {
        _log('ws', 'no pong from ${connectedPlayerId ?? "unknown"} — closing stale connection');
        cleanup();
        channel.sink.close();
        return;
      }
      channel.sink.add(GameMessage.ping().toJsonString());
    });

    channel.stream.listen(
      (raw) {
        if (raw is! String) return;

        // ── Size guard ─────────────────────────────────────────────────────
        if (raw.length > _kMaxMessageBytes) {
          _log('ws', 'MESSAGE_TOO_LARGE from ${connectedPlayerId ?? "unknown"} (${raw.length} bytes) — closing');
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
          _log('ws', 'RATE_LIMITED ${connectedPlayerId ?? "unknown"} ($msgCount msg/s) — closing');
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
        if (message.type == MessageType.pong) {
          missedPongs = 0; // client is alive
          return;
        }

        // ── Join room ──────────────────────────────────────────────────────
        if (message.type == MessageType.joinRoom) {
          // Prevent a single WebSocket from joining more than one room, which
          // would leak the player's presence in the first room on disconnect.
          if (connectedPlayerId != null) {
            channel.sink.add(
              GameMessage.error(reason: 'ALREADY_CONNECTED').toJsonString(),
            );
            return;
          }

          final playerId = message.playerId;
          final roomId = message.roomId;
          final displayName =
              message.payload['displayName'] as String? ?? 'Unknown';
          // Clamp numeric fields to safe ranges to prevent oversized allocations.
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

          // Validate playerId (UUID v4) and roomId to prevent log injection / identity spoofing.
          final joinError = _validatePlayerAndRoom(playerId, roomId);
          if (joinError != null) {
            channel.sink.add(GameMessage.error(reason: joinError).toJsonString());
            return;
          }

          // Strip control characters (prevents log injection via \n, \x1b ANSI
          // codes, etc.) then enforce the 32-character visual length limit.
          final cleanName =
              displayName.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
          final sanitisedName =
              cleanName.length > 32 ? cleanName.substring(0, 32) : cleanName;

          final room = roomManager.getOrCreate(roomId, boardSize: boardSize);
          // Server at max room capacity — reject rather than allocate unbounded rooms.
          if (room == null) {
            channel.sink.add(
              GameMessage.error(reason: 'SERVER_FULL').toJsonString(),
            );
            return;
          }
          // Only the room creator (host = first joiner) may configure maxPlayers.
          // Subsequent players cannot override the host's room settings.
          if (!room.isStarted && room.playerCount == 0) room.maxPlayers = maxPlayers;
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
          _log('ws', 'joined: player=$playerId name="$sanitisedName" room=$roomId');

          // If this player is the first to join (becomes the host), kick off
          // an async IP geolocation so the lobby browser can show a globe pin.
          if (room.playerCount == 1) {
            geolocateIp(clientIp).then((geo) {
              if (geo != null) {
                roomManager.setRoomGeo(
                  roomId,
                  lat: geo.lat,
                  lon: geo.lon,
                  city: geo.city,
                  country: geo.country,
                );
              }
            });
          }
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

        // ── Host early-start ───────────────────────────────────────────────
        if (message.type == MessageType.startGame) {
          // Only the room host (first player to join) may trigger an early start.
          _log('ws', 'forceStart requested by player=$connectedPlayerId room=$connectedRoomId');
          final err = room.forceStart(requesterId: connectedPlayerId!);
          if (err != null) {
            _log('ws', 'forceStart denied: $err');
            channel.sink.add(
              GameMessage.error(
                reason: err,
                roomId: connectedRoomId,
                playerId: connectedPlayerId,
              ).toJsonString(),
            );
          }
          return;
        }

        // Use the server-verified identity rather than trusting the client's playerId field.
        // ── Chat ──────────────────────────────────────────────────────────────
        if (message.type == MessageType.chat) {
          // Only allowed while a game is in progress.
          if (!room.isStarted) {
            channel.sink.add(
              GameMessage.error(reason: 'GAME_NOT_STARTED').toJsonString(),
            );
            return;
          }
          // Per-connection chat rate limit (100 messages / 5 minutes).
          final now2 = DateTime.now();
          chatTimestamps.removeWhere(
              (t) => now2.difference(t) > kChatWindow);
          if (chatTimestamps.length >= kMaxChatMsgs) {
            channel.sink.add(
              GameMessage.error(reason: 'CHAT_RATE_LIMITED').toJsonString(),
            );
            return;
          }
          chatTimestamps.add(now2);

          final rawText = message.payload['text'] as String? ?? '';
          // Strip control characters and enforce 200-char cap.
          final cleanText =
              rawText.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
          if (cleanText.isEmpty) return;
          final text = cleanText.length > 200
              ? cleanText.substring(0, 200)
              : cleanText;

          final senderName = room.playerDisplayName(connectedPlayerId!);
          room.broadcastChat(connectedPlayerId!, senderName, text);
          return;
        }

        room.handleAction(message, verifiedPlayerId: connectedPlayerId!);
      },
      onDone: cleanup,
      onError: (_) => cleanup(),
      cancelOnError: true,
    );
    })(request); // invoke the webSocketHandler with the current request
  }; // close (Request request) lambda
}
