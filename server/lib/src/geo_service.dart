import 'dart:io';

/// Result of player location data.
///
/// [lat] and [lon] are the geographic coordinates of the player's self-reported
/// country with jitter offset, ensuring no external IP pings are made.
class GeoResult {
  final double lat;
  final double lon;
  final String country;

  const GeoResult({
    required this.lat,
    required this.lon,
    required this.country,
  });
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
  if (ip.isEmpty || ip == '0.0.0.0' || ip == '::1' || ip == '::') return true;
  if (ip.startsWith('127.')) return true;
  if (ip.startsWith('10.')) return true;
  if (ip.startsWith('192.168.')) return true;
  if (ip.startsWith('fc') || ip.startsWith('fd')) return true; // fc00::/7 ULA
  if (ip.toLowerCase().startsWith('fe80')) return true; // fe80::/10 link-local
  // 172.16.0.0 – 172.31.255.255
  final parts = ip.split('.');
  if (parts.length == 4) {
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == 172 && b != null && b >= 16 && b <= 31) return true;
  }
  return false;
}
