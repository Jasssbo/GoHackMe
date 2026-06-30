import 'dart:convert';
import 'dart:io';

import 'package:go_engine/go_engine.dart';
import 'package:http/http.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  // Use a non-standard port to avoid conflicts with a running dev server.
  const port = '18082';
  const host = 'http://0.0.0.0:$port';
  const wsUrl = 'ws://0.0.0.0:$port/ws';
  late Process p;

  setUp(() async {
    p = await Process.start(
      'dart',
      ['run', 'bin/server.dart'],
      environment: {'PORT': port},
    );
    // Wait for the server's startup banner, then give it a moment to bind.
    await p.stdout.first;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });

  tearDown(() async {
    p.kill();
    await p.exitCode;
  });

  // ── HTTP endpoints ──────────────────────────────────────────────────────
  group('HTTP endpoints', () {
    test('/health returns 200 with status:ok', () async {
      final response = await get(Uri.parse('$host/health'));
      expect(response.statusCode, 200);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['status'], 'ok');
    });

    test('/rooms returns 200 with a JSON array', () async {
      final response = await get(Uri.parse('$host/rooms'));
      expect(response.statusCode, 200);
      expect(jsonDecode(response.body), isA<List>());
    });

    test('/stats returns 200 with activeRooms', () async {
      final response = await get(Uri.parse('$host/stats'));
      expect(response.statusCode, 200);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['activeRooms'], isA<int>());
    });

    test('unknown route returns 404', () async {
      final response = await get(Uri.parse('$host/nonexistent'));
      expect(response.statusCode, 404);
    });

    test('responses include security headers', () async {
      final response = await get(Uri.parse('$host/health'));
      expect(response.headers['x-content-type-options'], 'nosniff');
      expect(response.headers['cache-control'], 'no-store');
    });
  });

  // ── WebSocket ───────────────────────────────────────────────────────────
  group('WebSocket', () {
    test('valid joinRoom is accepted and broadcasts playerJoined', () async {
      final ws = WebSocketChannel.connect(Uri.parse(wsUrl));
      addTearDown(ws.sink.close);
      await ws.ready;

      const playerId = '550e8400-e29b-41d4-a716-446655440000';
      ws.sink.add(GameMessage.joinRoom(
        playerId: playerId,
        roomId: 'ROOM0001',
        displayName: 'Alice',
      ).toJsonString());

      final raw =
          await ws.stream.first.timeout(const Duration(seconds: 3));
      final msg = GameMessage.fromJsonString(raw as String);
      expect(msg.type, MessageType.playerJoined);
      expect((msg.payload['player'] as Map?)!['id'], playerId);
    });

    test('invalid playerId format is rejected with INVALID_PLAYER_ID_FORMAT',
        () async {
      final ws = WebSocketChannel.connect(Uri.parse(wsUrl));
      addTearDown(ws.sink.close);
      await ws.ready;

      ws.sink.add(GameMessage.joinRoom(
        playerId: 'not-a-valid-uuid',
        roomId: 'ROOM0002',
        displayName: 'Hacker',
      ).toJsonString());

      final raw =
          await ws.stream.first.timeout(const Duration(seconds: 3));
      final msg = GameMessage.fromJsonString(raw as String);
      expect(msg.type, MessageType.error);
      expect(msg.payload['reason'], 'INVALID_PLAYER_ID_FORMAT');
    });

    test('duplicate playerId in same room is rejected with ALREADY_IN_ROOM',
        () async {
      const playerId = '550e8400-e29b-41d4-a716-446655440001';
      const roomId = 'ROOM0003';

      final ws1 = WebSocketChannel.connect(Uri.parse(wsUrl));
      addTearDown(ws1.sink.close);
      await ws1.ready;
      ws1.sink.add(GameMessage.joinRoom(
        playerId: playerId,
        roomId: roomId,
        displayName: 'Original',
      ).toJsonString());
      // Consume the playerJoined broadcast so ws1's stream stays open.
      await ws1.stream.first.timeout(const Duration(seconds: 3));

      final ws2 = WebSocketChannel.connect(Uri.parse(wsUrl));
      addTearDown(ws2.sink.close);
      await ws2.ready;
      ws2.sink.add(GameMessage.joinRoom(
        playerId: playerId,
        roomId: roomId,
        displayName: 'Impersonator',
      ).toJsonString());

      final raw =
          await ws2.stream.first.timeout(const Duration(seconds: 3));
      final msg = GameMessage.fromJsonString(raw as String);
      expect(msg.type, MessageType.error);
      expect(msg.payload['reason'], 'ALREADY_IN_ROOM');
    });

    test('oversized message is rejected with MESSAGE_TOO_LARGE and connection closed',
        () async {
      final ws = WebSocketChannel.connect(Uri.parse(wsUrl));
      addTearDown(ws.sink.close);
      await ws.ready;

      // 5000-char payload exceeds _kMaxMessageBytes (4096).
      final padding = 'a' * 5000;
      ws.sink.add('{"type":"pass","payload":{"x":"$padding"}}');

      // Server sends the error then closes — collect until stream ends.
      final msgs = await ws.stream
          .timeout(const Duration(seconds: 3))
          .map((raw) => GameMessage.fromJsonString(raw as String))
          .toList();
      expect(
        msgs.any((m) =>
            m.type == MessageType.error &&
            m.payload['reason'] == 'MESSAGE_TOO_LARGE'),
        isTrue,
      );
    });

    test('message burst triggers RATE_LIMITED and connection closed', () async {
      final ws = WebSocketChannel.connect(Uri.parse(wsUrl));
      addTearDown(ws.sink.close);
      await ws.ready;

      // Send 25 pings in a burst; the 21st in a 1-second window hits the
      // 20 msg/s hard cap and triggers RATE_LIMITED.
      for (var i = 0; i < 25; i++) {
        ws.sink.add(GameMessage.ping().toJsonString());
      }

      // Server sends RATE_LIMITED then closes — collect until stream ends.
      final msgs = await ws.stream
          .timeout(const Duration(seconds: 3))
          .map((raw) => GameMessage.fromJsonString(raw as String))
          .toList();
      expect(
        msgs.any((m) =>
            m.type == MessageType.error &&
            m.payload['reason'] == 'RATE_LIMITED'),
        isTrue,
      );
    });
  });
}
