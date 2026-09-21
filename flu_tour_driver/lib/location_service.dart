// lib/location_service.dart — FluTour Driver App
// Background GPS broadcast every 3 seconds when driver is online + on an active trip

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ── Luxor bounding box (rough) ─────────────────────────────────────────────
// lat: 25.65 – 25.78  |  lng: 32.58 – 32.73
class LuxorBounds {
  static const double minLat = 25.65;
  static const double maxLat = 25.78;
  static const double minLng = 32.58;
  static const double maxLng = 32.73;

  static bool contains(double lat, double lng) =>
      lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng;
}

// ── Luxor landmarks ────────────────────────────────────────────────────────
class LatLngPoint {
  final double lat;
  final double lng;
  const LatLngPoint(this.lat, this.lng);
}

// ── Driver Location Service ────────────────────────────────────────────────
class DriverLocationService {
  static Position? _lastPosition;
  static Position? get lastPosition => _lastPosition;

  static Timer? _broadcastTimer;
  static bool _isBroadcasting = false;
  static bool get isBroadcasting => _isBroadcasting;

  // ── Permission & single-shot GPS ─────────────────────────────────────────

  static Future<LocationResult> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationResult.error(
          'GPS is disabled. Please turn on location services.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return LocationResult.error(
            'Location permission denied. FluTour Driver needs GPS to work.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationResult.error(
          'Location permanently denied. Please enable it in Settings.');
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _lastPosition = position;
      return LocationResult.success(position);
    } catch (e) {
      return LocationResult.error('Could not get location: $e');
    }
  }

  // ── 3-second broadcast loop ───────────────────────────────────────────────

  static String _driverName = '';
  static bool _isOnTrip = false;

  /// Call when driver goes online. Starts broadcasting GPS to Firebase every 3s.
  static void startBroadcasting(String driverId, {String driverName = '', bool isOnTrip = false}) {
    if (_isBroadcasting) return;
    _isBroadcasting = true;
    _driverName = driverName;
    _isOnTrip = isOnTrip;

    _broadcastTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
        _lastPosition = position;
        _broadcastToFirebase(driverId, position.latitude, position.longitude);
      } catch (_) {
        // GPS unavailable — silently skip this tick
      }
    });
  }

  static void updateOnTripStatus(String driverId, bool isOnTrip) {
    _isOnTrip = isOnTrip;
    if (_lastPosition != null) {
      _broadcastToFirebase(driverId, _lastPosition!.latitude, _lastPosition!.longitude);
    }
  }

  /// Immediately push a known position to Firebase — called from the active
  /// ride screen on every GPS update so tracking works even if the background
  /// timer hasn't fired yet or wasn't started.
  static void broadcastPosition(String driverId, double lat, double lng) {
    _lastPosition = null; // ensure next timer tick also re-broadcasts
    _broadcastToFirebase(driverId, lat, lng);
  }

  /// Call when driver goes offline or the app closes.
  static void stopBroadcasting(String driverId) {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _isBroadcasting = false;
    _clearDriverLocation(driverId);
  }

  // ── Firebase Realtime DB writes ───────────────────────────────────────────

  static void _broadcastToFirebase(
      String driverId, double lat, double lng) {
    FirebaseDatabase.instance
        .ref('drivers_location/$driverId')
        .set({
          'lat': lat,
          'lng': lng,
          'name': _driverName,
          'isOnTrip': _isOnTrip,
          'timestamp': ServerValue.timestamp,
        });
  }

  static void _clearDriverLocation(String driverId) {
    FirebaseDatabase.instance.ref('drivers_location/$driverId').remove();
  }

  // ── Permission dialog ─────────────────────────────────────────────────────

  static void showPermissionDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Location Required'),
        content: const Text(
            'FluTour Driver needs your GPS location to show passengers '
            'where you are and to broadcast your position during trips. '
            'Please enable location access in Settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // ── Background location hint ──────────────────────────────────────────────

  /// On Android, background location requires the user to explicitly grant it
  /// ("Allow all the time") in system settings after the initial permission.
  static Future<bool> hasBackgroundPermission() async {
    final perm = await Geolocator.checkPermission();
    return perm == LocationPermission.always;
  }

  static void showBackgroundPermissionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Background Location'),
        content: const Text(
            'To keep broadcasting your location while the app is in the '
            'background, please set location to "Allow all the time" in '
            'your phone Settings → App Info → Permissions → Location.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

// ── Fare helpers (driver-side display only) ────────────────────────────────
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

  static double distanceKm(
      double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2) / 1000;
  }

  /// Felucca: time-based pricing. Horse carriage: distance-based pricing.
  static FareBreakdown estimate(double distanceKm,
      {String vehicleType = 'felucca', double durationMinutes = 0}) {
    final surge = vehicleType == 'felucca' ? feluccaSurge : hantourSurge;

    double base;
    double variable = 0.0;
    String unit;
    String description;

    if (vehicleType == 'felucca') {
      final mins = durationMinutes > 0
          ? durationMinutes
          : (distanceKm / 0.083); // ~5 km/h on water fallback
      if (mins <= 15) {
        base = 50.0; description = 'Up to 15 min';
      } else if (mins <= 30) {
        base = 80.0; description = 'Up to 30 min';
      } else if (mins <= 60) {
        base = 120.0; description = 'Up to 60 min';
      } else {
        base = 150.0;
        variable = (mins - 60) * 2.0;
        description = '${mins.round()} min';
      }
      unit = 'min';
    } else {
      if (distanceKm <= 0.5) {
        base = 30.0; description = 'Up to 500 m';
      } else if (distanceKm <= 1.0) {
        base = 50.0; description = 'Up to 1 km';
      } else {
        base = 50.0;
        variable = (distanceKm - 1.0) * 40.0;
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

  /// Convenience method — returns just the total fare double.
  static double estimateTotal(double distanceKm,
      {String vehicleType = 'felucca', double durationMinutes = 0}) {
    return estimate(distanceKm,
            vehicleType: vehicleType, durationMinutes: durationMinutes)
        .total;
  }

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
  final String unit;
  final String description;

  FareBreakdown({
    required this.baseFare,
    required this.variableFare,
    required this.surgeMultiplier,
    required this.total,
    required this.unit,
    required this.description,
  });
}

// ── Result wrapper ─────────────────────────────────────────────────────────
class LocationResult {
  final Position? position;
  final String? errorMessage;
  bool get isSuccess => position != null;

  LocationResult.success(this.position) : errorMessage = null;
  LocationResult.error(this.errorMessage) : position = null;
}
