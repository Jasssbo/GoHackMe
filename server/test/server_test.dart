import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:test/test.dart';

void main() {
  // Use a non-standard port to avoid conflicts with a running dev server.
  const port = '18082';
  const host = 'http://0.0.0.0:$port';
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
}
