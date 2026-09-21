// lib/location_service.dart — FluTour Passenger App
// Handles GPS, permissions, fare estimation, and ETA

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ── Luxor landmarks (fixed coordinates) ───────────────────────────────────
class LuxorSpots {
  static const Map<String, LatLngPoint> all = {
    'Luxor Temple':    LatLngPoint(25.6987, 32.6390),
    'Karnak Temple':   LatLngPoint(25.7188, 32.6571),
    'Nile Corniche':   LatLngPoint(25.6872, 32.6370),
    'Winter Palace':   LatLngPoint(25.6938, 32.6393),
    'Luxor Museum':    LatLngPoint(25.7010, 32.6390),
    'Luxor Airport':   LatLngPoint(25.6710, 32.7061),
    'Hatshepsut Temple': LatLngPoint(25.7379, 32.6073),
    'Valley of Kings': LatLngPoint(25.7402, 32.6014),
  };
}

class LatLngPoint {
  final double lat;
  final double lng;
  const LatLngPoint(this.lat, this.lng);
}

// ── Fare estimation ────────────────────────────────────────────────────────
class FareEstimator {
  // Surge multipliers — loaded from Firestore settings/surge at login
  static double feluccaSurge = 1.0;
  static double hantourSurge = 1.0;

  /// Call once at login / session load to pull the latest multipliers.
  static Future<void> loadSurge() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings').doc('surge').get();
      if (doc.exists) {
        feluccaSurge = (doc.data()?['felucca'] as num?)?.toDouble() ?? 1.0;
        hantourSurge = (doc.data()?['horseCarriage'] as num?)?.toDouble() ?? 1.0;
      }
    } catch (_) {
      // Network unavailable — keep defaults (1.0 = no surge)
    }
  }

  // Haversine distance between two GPS points (km)
  static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    final distMeters = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
    return distMeters / 1000;
  }

  /// Felucca: time-based pricing (Nile boat sessions).
  /// Horse carriage: distance-based pricing.
  /// [distanceKm] is always provided; [durationMinutes] is used for felucca.
  static FareBreakdown estimate(double distanceKm,
      {String vehicleType = 'felucca', double durationMinutes = 0}) {
    final surge = vehicleType == 'felucca' ? feluccaSurge : hantourSurge;

    double base;
    double variable = 0.0;
    String unit;
    String description;

    if (vehicleType == 'felucca') {
      // Time-based tiers for felucca (Nile boat)
      final mins = durationMinutes > 0
          ? durationMinutes
          : (distanceKm / 0.083); // ~5 km/h on water fallback
      if (mins <= 15) {
        base = 250.0; description = 'Up to 15 min';
      } else if (mins <= 30) {
        base = 350.0; description = 'Up to 30 min';
      } else if (mins <= 60) {
        base = 650.0; description = 'Up to 60 min';
      } else {
        base = 650.0;
        variable = (mins - 60) * 9.0; // 9 EGP per extra minute
        description = '${mins.round()} min';
      }
      unit = 'min';
    } else {
      // Distance-based tiers for horse carriage
      if (distanceKm <= 0.5) {
        base = 30.0; description = 'Up to 500 m';
      } else if (distanceKm <= 1.0) {
        base = 50.0; description = 'Up to 1 km';
      } else {
        base = 50.0;
        variable = (distanceKm - 1.0) * 40.0; // 40 EGP per extra km
        description = '${(distanceKm * 1000).round()} m';
      }
      unit = 'km';
    }

    final subtotal = (base + variable) * surge;
    final total = double.parse(subtotal.toStringAsFixed(0));
    return FareBreakdown(
      baseFare: base,
      variableFare: variable,
      surgeMultiplier: surge,
      total: total,
      unit: unit,
      description: description,
    );
  }

  // ETA string based on distance at city speed (~30 km/h)
  static String etaString(double distanceKm) {
    final minutes = (distanceKm / 0.5).round();
    if (minutes < 60) return '$minutes min';
    return '${(minutes / 60).floor()}h ${minutes % 60}min';
  }
}

class FareBreakdown {
  final double baseFare;
  final double variableFare;
  final double surgeMultiplier;
  final double total;
  final String unit;        // 'km' or 'min'
  final String description; // human-readable tier label

  FareBreakdown({
    required this.baseFare,
    required this.variableFare,
    required this.surgeMultiplier,
    required this.total,
    required this.unit,
    required this.description,
  });
}

// ── Location Service ───────────────────────────────────────────────────────
class LocationService {
  static Position? _lastPosition;
  static Position? get lastPosition => _lastPosition;

  // Request location permission and get current GPS position
  static Future<LocationResult> getCurrentLocation() async {
    // Check if location services are enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationResult.error(
          'Location services are disabled. Please enable GPS.');
    }

    // Check/request permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return LocationResult.error(
            'Location permission denied. Please allow location access.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationResult.error(
          'Location permission permanently denied. Please enable it in Settings.');
    }

    // Get position
    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
    _lastPosition = position;
    return LocationResult.success(position);
  }

  // Show permission-denied dialog with settings button
  static void showPermissionDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Location Required'),
        content: Text(
            'FluTour needs your location to set your pickup point. '
            'Please enable location access in Settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openAppSettings();
            },
            child: Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // Fallback stream — not used by the live BookingConfirmedScreen.
  // The live tracking reads directly from Realtime DB: drivers_location/{driverId}
  static Stream<LatLngPoint> watchDriverLocation(String driverId) async* {
    final points = [
      LatLngPoint(25.6950, 32.6380),
      LatLngPoint(25.6960, 32.6385),
      LatLngPoint(25.6970, 32.6388),
      LatLngPoint(25.6980, 32.6390),
      LatLngPoint(25.6987, 32.6390),
    ];
    for (final p in points) {
      await Future.delayed(Duration(seconds: 3));
      yield p;
    }
  }
}

class LocationResult {
  final Position? position;
  final String? errorMessage;
  bool get isSuccess => position != null;

  LocationResult.success(this.position) : errorMessage = null;
  LocationResult.error(this.errorMessage) : position = null;
}
