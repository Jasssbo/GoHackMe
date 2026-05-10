import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:gohackme_server/src/discovery_service.dart';
import 'package:gohackme_server/src/room_manager.dart';
import 'package:gohackme_server/src/ws_handler.dart';

void main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final roomManager = RoomManager();

  final router = Router()
    ..get('/ws', buildWsHandler(roomManager))
    ..get('/health', (_) => Response.ok('{"status":"ok"}',
        headers: {'content-type': 'application/json'}))
    ..get('/stats', (_) => Response.ok(
          '{"activeRooms":${roomManager.activeRoomCount}}',
          headers: {'content-type': 'application/json'},
        ));

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsMiddleware())
      .addHandler(router.call);

  final server = await shelf_io.serve(handler, '0.0.0.0', port);
  print('[GoHackMe Server] listening on ws://0.0.0.0:${server.port}/ws');

  // Start UDP LAN auto-discovery so mobile clients can find this server
  // without the user having to type the IP address manually.
  await startDiscoveryService(server.port);
}

Middleware _corsMiddleware() => (innerHandler) => (request) async {
      // Accept localhost, 127.0.0.1, and RFC-1918 LAN addresses so that
      // mobile/tablet clients on the same network can connect.
      final origin = request.headers['origin'] ?? '';
      final allowed = origin.isEmpty ||
          origin.startsWith('http://localhost') ||
          origin.startsWith('http://127.0.0.1') ||
          // RFC-1918: 10.x.x.x
          RegExp(r'^https?://10\.\d+\.\d+\.\d+').hasMatch(origin) ||
          // RFC-1918: 172.16-31.x.x
          RegExp(r'^https?://172\.(1[6-9]|2[0-9]|3[01])\.\d+\.\d+').hasMatch(origin) ||
          // RFC-1918: 192.168.x.x
          RegExp(r'^https?://192\.168\.\d+\.\d+').hasMatch(origin);

      if (!allowed) {
        return Response.forbidden('Forbidden');
      }

      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders(origin));
      }
      final response = await innerHandler(request);
      return response.change(headers: _corsHeaders(origin));
    };

Map<String, String> _corsHeaders(String origin) => {
      'Access-Control-Allow-Origin': origin.isEmpty ? 'http://localhost' : origin,
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Origin, Content-Type',
    };
