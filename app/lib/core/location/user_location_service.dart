import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Country data entry with ISO code, name, geographic centroid, and IP prefix.
class CountryData {
  final String code;
  final String name;
  final double lat;
  final double lon;
  final String ipPrefix;

  const CountryData({
    required this.code,
    required this.name,
    required this.lat,
    required this.lon,
    required this.ipPrefix,
  });
}

/// Known country list with ISO 3166-1 alpha-2 codes, names, centroids, and IP prefixes.
const List<CountryData> kCountryDatabase = [
  CountryData(code: 'US', name: 'United States', lat: 38.0, lon: -97.0, ipPrefix: '172.56.'),
  CountryData(code: 'IT', name: 'Italy', lat: 42.5, lon: 12.5, ipPrefix: '82.112.'),
  CountryData(code: 'JP', name: 'Japan', lat: 36.2, lon: 138.3, ipPrefix: '133.242.'),
  CountryData(code: 'DE', name: 'Germany', lat: 51.5, lon: 10.5, ipPrefix: '85.214.'),
  CountryData(code: 'GB', name: 'United Kingdom', lat: 54.0, lon: -2.0, ipPrefix: '51.15.'),
  CountryData(code: 'FR', name: 'France', lat: 46.0, lon: 2.0, ipPrefix: '81.64.'),
  CountryData(code: 'CA', name: 'Canada', lat: 60.0, lon: -95.0, ipPrefix: '142.204.'),
  CountryData(code: 'AU', name: 'Australia', lat: -25.0, lon: 133.0, ipPrefix: '1.120.'),
  CountryData(code: 'BR', name: 'Brazil', lat: -10.0, lon: -53.0, ipPrefix: '177.12.'),
  CountryData(code: 'IN', name: 'India', lat: 20.6, lon: 78.9, ipPrefix: '103.21.'),
  CountryData(code: 'ES', name: 'Spain', lat: 40.0, lon: -3.7, ipPrefix: '83.32.'),
  CountryData(code: 'KR', name: 'South Korea', lat: 36.5, lon: 127.8, ipPrefix: '121.124.'),
  CountryData(code: 'NL', name: 'Netherlands', lat: 52.3, lon: 5.3, ipPrefix: '145.130.'),
  CountryData(code: 'SE', name: 'Sweden', lat: 60.1, lon: 18.6, ipPrefix: '192.121.'),
  CountryData(code: 'CH', name: 'Switzerland', lat: 47.0, lon: 8.3, ipPrefix: '193.134.'),
  CountryData(code: 'AT', name: 'Austria', lat: 47.5, lon: 14.5, ipPrefix: '194.24.'),
  CountryData(code: 'BE', name: 'Belgium', lat: 50.8, lon: 4.5, ipPrefix: '193.190.'),
  CountryData(code: 'NO', name: 'Norway', lat: 64.5, lon: 17.9, ipPrefix: '193.156.'),
  CountryData(code: 'FI', name: 'Finland', lat: 64.0, lon: 26.0, ipPrefix: '193.166.'),
  CountryData(code: 'DK', name: 'Denmark', lat: 56.0, lon: 10.0, ipPrefix: '192.38.'),
  CountryData(code: 'PL', name: 'Poland', lat: 52.0, lon: 19.4, ipPrefix: '212.191.'),
  CountryData(code: 'MX', name: 'Mexico', lat: 23.6, lon: -102.6, ipPrefix: '187.130.'),
  CountryData(code: 'AR', name: 'Argentina', lat: -34.0, lon: -64.0, ipPrefix: '181.16.'),
  CountryData(code: 'CL', name: 'Chile', lat: -30.0, lon: -71.0, ipPrefix: '190.160.'),
  CountryData(code: 'CN', name: 'China', lat: 35.0, lon: 105.0, ipPrefix: '202.108.'),
  CountryData(code: 'TW', name: 'Taiwan', lat: 23.7, lon: 121.0, ipPrefix: '140.112.'),
  CountryData(code: 'SG', name: 'Singapore', lat: 1.4, lon: 103.8, ipPrefix: '203.116.'),
  CountryData(code: 'NZ', name: 'New Zealand', lat: -41.3, lon: 174.8, ipPrefix: '202.48.'),
  CountryData(code: 'ZA', name: 'South Africa', lat: -29.0, lon: 25.0, ipPrefix: '196.25.'),
  CountryData(code: 'IE', name: 'Ireland', lat: 53.1, lon: -8.2, ipPrefix: '193.1.'),
  CountryData(code: 'PT', name: 'Portugal', lat: 39.6, lon: -8.0, ipPrefix: '193.136.'),
  CountryData(code: 'GR', name: 'Greece', lat: 39.0, lon: 22.0, ipPrefix: '194.177.'),
  CountryData(code: 'CZ', name: 'Czech Republic', lat: 49.8, lon: 15.5, ipPrefix: '195.113.'),
  CountryData(code: 'HU', name: 'Hungary', lat: 47.2, lon: 19.5, ipPrefix: '195.111.'),
  CountryData(code: 'RO', name: 'Romania', lat: 45.9, lon: 24.7, ipPrefix: '193.226.'),
  CountryData(code: 'UA', name: 'Ukraine', lat: 49.0, lon: 32.0, ipPrefix: '194.44.'),
  CountryData(code: 'TR', name: 'Turkey', lat: 39.0, lon: 35.0, ipPrefix: '193.140.'),
  CountryData(code: 'IL', name: 'Israel', lat: 31.5, lon: 35.0, ipPrefix: '192.114.'),
  CountryData(code: 'AE', name: 'United Arab Emirates', lat: 24.0, lon: 54.0, ipPrefix: '194.170.'),
  CountryData(code: 'SA', name: 'Saudi Arabia', lat: 24.0, lon: 45.0, ipPrefix: '212.26.'),
  CountryData(code: 'TH', name: 'Thailand', lat: 13.0, lon: 101.0, ipPrefix: '202.28.'),
  CountryData(code: 'ID', name: 'Indonesia', lat: -0.8, lon: 113.9, ipPrefix: '202.158.'),
  CountryData(code: 'MY', name: 'Malaysia', lat: 2.5, lon: 112.5, ipPrefix: '202.184.'),
  CountryData(code: 'PH', name: 'Philippines', lat: 12.9, lon: 121.8, ipPrefix: '202.90.'),
  CountryData(code: 'VN', name: 'Vietnam', lat: 14.1, lon: 108.3, ipPrefix: '203.162.'),
  CountryData(code: 'EG', name: 'Egypt', lat: 26.0, lon: 30.0, ipPrefix: '193.227.'),
  CountryData(code: 'CO', name: 'Colombia', lat: 4.0, lon: -72.0, ipPrefix: '190.25.'),
  CountryData(code: 'PE', name: 'Peru', lat: -10.0, lon: -76.0, ipPrefix: '200.48.'),
];

/// User location state holding country details, casual IP, and non-overlapping map coordinates.
class UserLocation {
  final String countryCode;
  final String countryName;
  final String casualIp;
  final double lat;
  final double lon;

  const UserLocation({
    required this.countryCode,
    required this.countryName,
    required this.casualIp,
    required this.lat,
    required this.lon,
  });

  Map<String, dynamic> toJson() => {
        'countryCode': countryCode,
        'countryName': countryName,
        'casualIp': casualIp,
        'lat': lat,
        'lon': lon,
      };

  factory UserLocation.fromJson(Map<String, dynamic> j) => UserLocation(
        countryCode: j['countryCode'] as String? ?? 'US',
        countryName: j['countryName'] as String? ?? 'United States',
        casualIp: j['casualIp'] as String? ?? '172.56.42.101',
        lat: (j['lat'] as num?)?.toDouble() ?? 38.0,
        lon: (j['lon'] as num?)?.toDouble() ?? -97.0,
      );
}

class UserLocationNotifier extends AsyncNotifier<UserLocation?> {
  static const _keyCountryCode = 'wired_user_country_code';
  static const _keyCountryName = 'wired_user_country_name';
  static const _keyCasualIp    = 'wired_user_casual_ip';
  static const _keyLat         = 'wired_user_lat';
  static const _keyLon         = 'wired_user_lon';

  @override
  Future<UserLocation?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_keyCountryCode);
    final name = prefs.getString(_keyCountryName);
    final ip   = prefs.getString(_keyCasualIp);
    final lat  = prefs.getDouble(_keyLat);
    final lon  = prefs.getDouble(_keyLon);

    if (code != null && name != null && ip != null && lat != null && lon != null) {
      return UserLocation(
        countryCode: code,
        countryName: name,
        casualIp: ip,
        lat: lat,
        lon: lon,
      );
    }
    return null;
  }

  /// Sets or updates the user's country, generates a country-specific casual IP,
  /// and derives jittered coordinates so players from the same country don't overlap pins.
  Future<UserLocation> setCountry(String query) async {
    final target = findCountry(query);
    final rng = math.Random();

    // Generate casual IP octets
    final c = 10 + rng.nextInt(230);
    final d = 10 + rng.nextInt(230);
    final casualIp = '${target.ipPrefix}$c.$d';

    // Jitter coordinates based on octets so points from the same state/country don't overlap
    final offsetLat = ((c % 60) - 30) * 0.08;
    final offsetLon = ((d % 60) - 30) * 0.08;

    final lat = (target.lat + offsetLat).clamp(-85.0, 85.0);
    final lon = (target.lon + offsetLon).clamp(-180.0, 180.0);

    final location = UserLocation(
      countryCode: target.code,
      countryName: target.name,
      casualIp: casualIp,
      lat: lat,
      lon: lon,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCountryCode, location.countryCode);
    await prefs.setString(_keyCountryName, location.countryName);
    await prefs.setString(_keyCasualIp, location.casualIp);
    await prefs.setDouble(_keyLat, location.lat);
    await prefs.setDouble(_keyLon, location.lon);

    state = AsyncData(location);
    return location;
  }

  /// Helper to lookup country by code or name (case-insensitive substring match).
  static CountryData findCountry(String query) {
    final q = query.trim().toUpperCase();
    if (q.isEmpty) return kCountryDatabase.first;

    // Direct match on ISO code
    for (final c in kCountryDatabase) {
      if (c.code == q) return c;
    }
    // Match name starts with or contains query
    for (final c in kCountryDatabase) {
      if (c.name.toUpperCase().startsWith(q)) return c;
    }
    for (final c in kCountryDatabase) {
      if (c.name.toUpperCase().contains(q)) return c;
    }
    // Fallback default (United States)
    return kCountryDatabase.first;
  }
}

final userLocationProvider =
    AsyncNotifierProvider<UserLocationNotifier, UserLocation?>(
  UserLocationNotifier.new,
);
