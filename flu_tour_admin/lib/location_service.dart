// lib/location_service.dart — FluTour Admin App
// Admin reads live driver locations from Firebase Realtime DB (read-only).

import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';

class LatLngPoint {
  final double lat;
  final double lng;
  const LatLngPoint(this.lat, this.lng);
}

// ── Live driver entry shown on the admin map ───────────────────────────────
class LiveDriverInfo {
  final String driverId;
  final String driverName;
  final double lat;
  final double lng;
  final bool isOnTrip;
  final DateTime updatedAt;

  const LiveDriverInfo({
    required this.driverId,
    required this.driverName,
    required this.lat,
    required this.lng,
    required this.isOnTrip,
    required this.updatedAt,
  });
}

// ── Admin Location Service ─────────────────────────────────────────────────
class AdminLocationService {
  // ── Admin's own position (for map centering) ──────────────────────────────

  static Future<LatLngPoint?> getAdminLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low, // admin map doesn't need high precision
          timeLimit: Duration(seconds: 8),
        ),
      );
      return LatLngPoint(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  // ── Live driver stream ────────────────────────────────────────────────────

  /// Returns a stream that emits the full list of online drivers from Realtime DB.
  static Stream<List<LiveDriverInfo>> watchOnlineDrivers() {
    return FirebaseDatabase.instance
        .ref('drivers_location')
        .onValue
        .map((event) {
      final data =
          event.snapshot.value as Map<dynamic, dynamic>? ?? {};
      return data.entries.map((e) {
        final v = Map<String, dynamic>.from(e.value as Map);
        return LiveDriverInfo(
          driverId: e.key,
          driverName: v['name'] ?? 'Driver',
          lat: (v['lat'] as num).toDouble(),
          lng: (v['lng'] as num).toDouble(),
          isOnTrip: v['isOnTrip'] ?? false,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
              v['timestamp'] as int? ?? 0),
        );
      }).toList();
    });
  }

  // ── Luxor center fallback ─────────────────────────────────────────────────
  static const LatLngPoint luxorCenter = LatLngPoint(25.6872, 32.6370);
}
