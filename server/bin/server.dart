import 'dart:convert';
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
        ))
    // Wired lobby browser: returns all open (not-started) rooms.
    ..get('/rooms', (_) => Response.ok(
          jsonEncode(roomManager.openRooms),
          headers: {'content-type': 'application/json'},
        ));

  final handler = Pipeline()
      // Verbose request logging is off by default (lobby browsers poll /rooms
      // every 4 s which would flood logs).  Enable with LOG_REQUESTS=1.
      .addMiddleware(
        Platform.environment['LOG_REQUESTS'] == '1' ? logRequests() : const Pipeline().middleware,
      )
      .addMiddleware(_corsMiddleware())
      .addMiddleware(_securityHeaders())
      .addMiddleware(_httpRateLimit())
      .addHandler(router.call);

  final server = await shelf_io.serve(handler, '0.0.0.0', port);
  print('[GoHackMe Server] listening on :${server.port}  (ws /ws  |  lobby /rooms)');

  // Graceful shutdown: finish in-flight requests before exiting.
  // Render.com (and Docker) send SIGTERM before killing the process.
  ProcessSignal.sigterm.watch().listen((_) async {
    print('[GoHackMe Server] SIGTERM received — shutting down gracefully');
    await server.close(force: false);
    exit(0);
  });

  // Start UDP LAN auto-discovery so LAN clients can find this server
  // without typing an IP address.  Fails silently on Render.com (expected —
  // UDP broadcasts do not work over the internet).
  await startDiscoveryService(server.port);
}

/// CORS middleware that accepts any origin.
///
/// The server is public-facing (Render.com) so requests arrive from any
/// network.  Security is enforced at the application layer (room codes,
/// input validation, rate limiting) — not at the HTTP origin level.
Middleware _corsMiddleware() => (innerHandler) => (request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders());
      }
      final response = await innerHandler(request);
      return response.change(headers: _corsHeaders());
    };

Map<String, String> _corsHeaders() => const {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Origin, Content-Type',
    };

/// Security headers applied to every HTTP response.
///
/// These protect the JSON API endpoints (/health, /stats, /rooms) against
/// MIME-sniffing and caching of live game data by intermediate proxies.
Middleware _securityHeaders() => (innerHandler) => (request) async {
      final response = await innerHandler(request);
      return response.change(headers: {
        'X-Content-Type-Options': 'nosniff',
        'Cache-Control': 'no-store',
        // HSTS: instruct clients to always use HTTPS for the next year.
        'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
        // Remove stack fingerprint — no need to advertise the framework.
        'X-Powered-By': '',
      });
    };

/// Per-IP rate limiter for HTTP endpoints (OWASP A04 — Resource Exhaustion).
///
/// Allows up to [_kHttpRateLimit] requests per [_kHttpRateWindow] per unique
/// IP address.  WebSocket upgrades are excluded (they have their own limit in
/// ws_handler.dart).
///
/// The /rooms endpoint is polled by every lobby client every ~4 s, so the
/// window is deliberately generous — this only blocks aggressive scrapers.
const _kHttpRateLimit = 60; // requests
const _kHttpRateWindow = Duration(minutes: 1);

Middleware _httpRateLimit() {
  // ip → list of request timestamps within the current window
  final counters = <String, List<DateTime>>{};

  return (innerHandler) => (request) async {
        // Only rate-limit non-WebSocket HTTP requests.
        if (request.headers['upgrade']?.toLowerCase() == 'websocket') {
          return innerHandler(request);
        }

        final ip = request.headers['cf-connecting-ip'] ??
            (request.headers['x-forwarded-for']?.split(',').last.trim()) ??
            (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)
                ?.remoteAddress
                .address ??
            'unknown';

        final now = DateTime.now();
        final timestamps = counters.putIfAbsent(ip, () => []);
        // Evict entries outside the current window.
        timestamps.removeWhere((t) => now.difference(t) > _kHttpRateWindow);

        if (timestamps.length >= _kHttpRateLimit) {
          return Response(429,
              body: '{"error":"RATE_LIMITED"}',
              headers: {
                'content-type': 'application/json',
                'Retry-After': '60',
              });
        }

        timestamps.add(now);
        return innerHandler(request);
      };
}
