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

/// Geographic centroids for ~90 countries (ISO 3166-1 alpha-2 keys).
const _countryCentroids = <String, (double, double)>{
  'AD': (42.5, 1.5),    'AE': (24.0, 54.0),   'AF': (33.0, 65.0),
  'AL': (41.0, 20.0),   'AM': (40.0, 45.0),   'AO': (-12.5, 18.5),
  'AR': (-34.0, -64.0), 'AT': (47.5, 14.5),   'AU': (-25.0, 133.0),
  'AZ': (40.5, 47.5),   'BA': (44.0, 17.5),   'BD': (23.7, 90.4),
  'BE': (50.8, 4.5),    'BG': (42.8, 25.3),   'BH': (26.0, 50.5),
  'BO': (-16.5, -64.5), 'BR': (-10.0, -53.0), 'BY': (53.7, 27.9),
  'CA': (60.0, -95.0),  'CH': (47.0, 8.3),    'CL': (-30.0, -71.0),
  'CM': (4.0, 12.5),    'CN': (35.0, 105.0),  'CO': (4.0, -72.0),
  'CZ': (49.8, 15.5),   'DE': (51.5, 10.5),   'DK': (56.0, 10.0),
  'DZ': (28.0, 3.0),    'EC': (-1.5, -78.0),  'EG': (26.0, 30.0),
  'ES': (40.0, -3.7),   'ET': (8.0, 38.0),    'FI': (64.0, 26.0),
  'FR': (46.0, 2.0),    'GB': (54.0, -2.0),   'GE': (42.0, 43.5),
  'GH': (7.9, -1.0),    'GR': (39.0, 22.0),   'HR': (45.3, 16.0),
  'HU': (47.2, 19.5),   'ID': (-0.8, 113.9),  'IE': (53.1, -8.2),
  'IL': (31.5, 35.0),   'IN': (20.6, 78.9),   'IQ': (33.0, 44.0),
  'IR': (32.0, 53.7),   'IT': (42.5, 12.5),   'JO': (31.0, 36.0),
  'JP': (36.2, 138.3),  'KE': (0.0, 37.9),    'KG': (41.2, 74.8),
  'KR': (36.5, 127.8),  'KW': (29.3, 47.7),   'KZ': (48.0, 68.0),
  'LB': (33.9, 35.9),   'LT': (55.9, 23.9),   'LV': (57.0, 25.0),
  'LY': (27.0, 17.0),   'MA': (32.0, -5.0),   'MD': (47.0, 28.9),
  'MK': (41.6, 21.7),   'MM': (17.0, 96.0),   'MN': (46.9, 103.8),
  'MX': (23.6, -102.6), 'MY': (2.5, 112.5),   'MZ': (-18.0, 35.0),
  'NG': (9.1, 8.7),     'NL': (52.3, 5.3),    'NO': (64.5, 17.9),
  'NP': (28.4, 84.1),   'NZ': (-41.3, 174.8), 'OM': (21.5, 57.5),
  'PA': (9.0, -79.5),   'PE': (-10.0, -76.0), 'PH': (12.9, 121.8),
  'PK': (30.4, 69.3),   'PL': (52.0, 19.4),   'PT': (39.6, -8.0),
  'QA': (25.3, 51.2),   'RO': (45.9, 24.7),   'RS': (44.0, 21.0),
  'RU': (60.0, 100.0),  'SA': (24.0, 45.0),   'SE': (60.1, 18.6),
  'SG': (1.4, 103.8),   'SI': (46.1, 14.8),   'SK': (48.7, 19.7),
  'SN': (14.5, -14.5),  'SY': (35.0, 38.0),   'TH': (13.0, 101.0),
  'TR': (39.0, 35.0),   'TW': (23.7, 121.0),  'TZ': (-6.4, 34.9),
  'UA': (49.0, 32.0),   'UG': (1.4, 32.3),    'US': (38.0, -97.0),
  'UY': (-33.0, -56.0), 'UZ': (41.4, 64.6),   'VE': (8.0, -66.0),
  'VN': (14.1, 108.3),  'YE': (15.6, 47.8),   'ZA': (-29.0, 25.0),
  'ZW': (-20.0, 30.0),
};

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

/// Strict IPv4 / IPv6 format check — rejects anything that is not a bare IP
/// address, preventing path-traversal injection into the geolocation URL.
bool _isValidPublicIp(String ip) {
  // IPv4: four decimal octets
  final ipv4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
  if (ipv4.hasMatch(ip)) {
    return ip.split('.').every((o) {
      final n = int.tryParse(o);
      return n != null && n >= 0 && n <= 255;
    });
  }
  // IPv6: only hex digits and colons (covers full and compressed forms)
  final ipv6 = RegExp(r'^[0-9a-fA-F:]+$');
  return ipv6.hasMatch(ip) && ip.contains(':');
}
