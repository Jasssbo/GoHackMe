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
    final uri = Uri.parse(
        'http://ip-api.com/json/$ip?fields=status,lat,lon,city,country');
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
/// Prefers X-Forwarded-For (set by Render.com / reverse proxies).
String extractIp(Map<String, String> headers, HttpConnectionInfo? conn) {
  final forwarded = headers['x-forwarded-for'];
  if (forwarded != null && forwarded.isNotEmpty) {
    return forwarded.split(',').first.trim();
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
