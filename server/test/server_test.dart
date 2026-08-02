import 'dart:convert';
import 'dart:io';

import 'package:go_engine/go_engine.dart';
import 'package:http/http.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  // Use a non-standard port to avoid conflicts with a running dev server.
  const port = '18082';
  // 127.0.0.1 is safer than 0.0.0.0 as a client address across all platforms.
  const host = 'http://127.0.0.1:$port';
  const wsUrl = 'ws://127.0.0.1:$port/ws';
  late Process p;

  setUp(() async {
    p = await Process.start(
      'dart',
      ['run', 'bin/server.dart'],
      // Inherit the full parent environment so the child dart process has
      // access to HOME, PATH, PUB_CACHE, etc. (required in CI).
      // Only PORT is overridden.
      environment: {...Platform.environment, 'PORT': port},
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

      // _kMaxMessageBytes on the server is 65536. Send well above that.
      final padding = 'a' * 70000;
      ws.sink.add('{"type":"ping","payload":{"x":"$padding"}}');

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

      // _kRateLimitPerSecond is 20; send 40 pings to reliably exceed it even
      // under CI scheduler jitter.
      for (var i = 0; i < 40; i++) {
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

    test('pre-game host disconnect closes room immediately and removes it from /rooms',
        () async {
      const playerId = '550e8400-e29b-41d4-a716-446655440099';
      const roomId = 'ROOM-PRE-HOST';

      final ws = WebSocketChannel.connect(Uri.parse(wsUrl));
      await ws.ready;
      ws.sink.add(GameMessage.joinRoom(
        playerId: playerId,
        roomId: roomId,
        displayName: 'HostPlayer',
      ).toJsonString());

      await ws.stream.first.timeout(const Duration(seconds: 3));

      // Host leaves before game starts.
      await ws.sink.close();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final response = await get(Uri.parse('$host/rooms'));
      expect(response.statusCode, 200);
      final rooms = jsonDecode(response.body) as List<dynamic>;
      expect(rooms.any((r) => (r as Map)['code'] == roomId), isFalse);
    });

    test('pre-game host disconnect notifies connected guests with ROOM_CLOSED',
        () async {
      const hostId = '550e8400-e29b-41d4-a716-446655440088';
      const guestId = '550e8400-e29b-41d4-a716-446655440077';
      const roomId = 'ROOM-PRE-GUEST';

      final hostWs = WebSocketChannel.connect(Uri.parse(wsUrl));
      addTearDown(hostWs.sink.close);
      await hostWs.ready;
      hostWs.sink.add(GameMessage.joinRoom(
        playerId: hostId,
        roomId: roomId,
        displayName: 'Host',
        maxPlayers: 3,
      ).toJsonString());
      await hostWs.stream.first.timeout(const Duration(seconds: 3));

      final guestWs = WebSocketChannel.connect(Uri.parse(wsUrl));
      addTearDown(guestWs.sink.close);
      await guestWs.ready;

      final guestMsgs = <GameMessage>[];
      final sub = guestWs.stream
          .map((raw) => GameMessage.fromJsonString(raw as String))
          .listen(guestMsgs.add);
      addTearDown(sub.cancel);

      guestWs.sink.add(GameMessage.joinRoom(
        playerId: guestId,
        roomId: roomId,
        displayName: 'Guest',
      ).toJsonString());

      // Wait until guest receives initial message
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (guestMsgs.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(guestMsgs.isNotEmpty, isTrue);
      expect(
        guestMsgs.first.type,
        MessageType.playerJoined,
        reason: 'Received error instead: ${guestMsgs.first.payload['reason']}',
      );

      // Host closes connection
      await hostWs.sink.close();

      // Guest should receive ROOM_CLOSED error
      final errDeadline = DateTime.now().add(const Duration(seconds: 3));
      while (guestMsgs.length < 2 && DateTime.now().isBefore(errDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(guestMsgs.length, 2);
      expect(guestMsgs[1].type, MessageType.error);
      expect(guestMsgs[1].payload['reason'], 'ROOM_CLOSED');
    });
  });
}
