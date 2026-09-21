// lib/route_service.dart — OSRM routing + Nominatim geocoding (no API keys required)
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteResult {
  final List<LatLng> points;
  final double distanceKm;
  final int durationSeconds;

  RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationSeconds,
  });
}

class RouteService {
  /// Last successfully fetched route — reused instantly by the active ride screen
  static RouteResult? lastResult;

  static Future<RouteResult?> fetchRoute(LatLng from, LatLng to) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving'
        '/${from.longitude},${from.latitude}'
        ';${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if ((json['code'] as String?) != 'Ok') return null;
      final routes = json['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;
      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>;
      final coords = (geometry['coordinates'] as List)
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      if (coords.length < 2) return null;
      final distKm = (route['distance'] as num).toDouble() / 1000;
      final durSec = (route['duration'] as num).toInt();
      final result = RouteResult(points: coords, distanceKm: distKm, durationSeconds: durSec);
      lastResult = result;
      return result;
    } catch (_) {
      return null;
    }
  }

  static String etaLabel(int seconds) {
    if (seconds < 60) return '$seconds s';
    final mins = seconds ~/ 60;
    if (mins < 60) return '$mins min';
    return '${mins ~/ 60}h ${mins % 60}min';
  }
}

// ===== GEOCODING (Nominatim, Egypt-only) =====
class GeoSuggestion {
  final String name;
  final LatLng location;
  GeoSuggestion({required this.name, required this.location});
}

class GeocodingService {
  static Future<List<GeoSuggestion>> searchEgypt(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(q)}'
        '&format=json'
        '&limit=6',
      );
      final res = await http.get(url, headers: {
        'Accept-Language': 'en',
        'User-Agent': 'FluTour/1.0 flutour.dev@gmail.com',
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final list = jsonDecode(res.body) as List;
      return list.map((item) {
        final lat = double.parse(item['lat'] as String);
        final lon = double.parse(item['lon'] as String);
        // Trim to first 3 comma-parts for a readable short name
        final parts = (item['display_name'] as String).split(', ');
        final name = parts.take(3).join(', ');
        return GeoSuggestion(name: name, location: LatLng(lat, lon));
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
