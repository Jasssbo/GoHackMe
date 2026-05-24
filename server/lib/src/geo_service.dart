import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Result of a successful IP geolocation lookup.
class GeoResult {
  final double lat;
  final double lon;
  final String city;
  final String country;

  const GeoResult({
    required this.lat,
    required this.lon,
    required this.city,
    required this.country,
  });
}

/// Returns geolocation for [ip] using ip-api.com (free, no key, 45 req/min).
/// Returns null for private/loopback addresses or if the lookup fails.
Future<GeoResult?> geolocateIp(String ip) async {
  if (_isPrivateIp(ip)) return null;
  try {
    // HTTPS — prevents MITM from reading player IPs or injecting fake coordinates.
    final uri = Uri.parse(
        'https://ip-api.com/json/$ip?fields=status,lat,lon,city,country');
    final res = await http.get(uri).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['status'] != 'success') return null;
    return GeoResult(
      lat: (data['lat'] as num).toDouble(),
      lon: (data['lon'] as num).toDouble(),
      city: data['city'] as String? ?? '',
      country: data['country'] as String? ?? '',
    );
  } catch (_) {
    return null;
  }
}

/// Returns the best-effort client IP from [headers].
///
/// Priority:
/// 1. `CF-Connecting-IP` — set by Cloudflare to the real end-user IP.
///    Most reliable when the header is forwarded by the host (some Render
///    configurations strip it before reaching the app).
/// 2. `X-Real-IP` — sometimes set by Render.com or nginx upstreams.
/// 3. First non-private entry in `X-Forwarded-For` — Render.com places the
///    real client IP as the leftmost XFF entry, with internal/Cloudflare IPs
///    appended to the right.  Skipping private entries filters out load-
///    balancer addresses without requiring knowledge of the exact proxy chain.
/// 4. Raw TCP remote address (LAN / local dev fallback).
String extractIp(Map<String, String> headers, HttpConnectionInfo? conn) {
  // 1. Cloudflare's tamper-proof header (present when CF forwards it to origin).
  final cfIp = headers['cf-connecting-ip'];
  if (cfIp != null && cfIp.isNotEmpty && !_isPrivateIp(cfIp.trim())) {
    return cfIp.trim();
  }

  // 2. Render.com / nginx real-IP header.
  final realIp = headers['x-real-ip'];
  if (realIp != null && realIp.isNotEmpty && !_isPrivateIp(realIp.trim())) {
    return realIp.trim();
  }

  // 3. Walk XFF left-to-right and return the first routable (non-private) IP.
  //    Render.com puts the real client IP first; internal proxy IPs follow.
  final forwarded = headers['x-forwarded-for'];
  if (forwarded != null && forwarded.isNotEmpty) {
    for (final entry in forwarded.split(',')) {
      final ip = entry.trim();
      if (!_isPrivateIp(ip)) return ip;
    }
  }

  return conn?.remoteAddress.address ?? '';
}

bool _isPrivateIp(String ip) {
  if (ip.isEmpty || ip == '0.0.0.0' || ip == '::1') return true;
  if (ip.startsWith('127.')) return true;
  if (ip.startsWith('10.')) return true;
  if (ip.startsWith('192.168.')) return true;
  // 172.16.0.0 – 172.31.255.255
  final parts = ip.split('.');
  if (parts.length == 4) {
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == 172 && b != null && b >= 16 && b <= 31) return true;
  }
  return false;
}
