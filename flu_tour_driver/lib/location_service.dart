// lib/location_service.dart — FluTour Driver App
// Background GPS broadcast every 3 seconds when driver is online + on an active trip
// TODO: Replace _broadcastToFirebase() stub with Realtime DB writes when account is recovered

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';

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

  /// Call when driver goes online. Starts broadcasting GPS to Firebase every 3s.
  static void startBroadcasting(String driverId) {
    if (_isBroadcasting) return;
    _isBroadcasting = true;

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

  /// Call when driver goes offline or the app closes.
  static void stopBroadcasting(String driverId) {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _isBroadcasting = false;
    _clearDriverLocation(driverId);
  }

  // ── Firebase stubs ────────────────────────────────────────────────────────

  static void _broadcastToFirebase(
      String driverId, double lat, double lng) {
    FirebaseDatabase.instance
        .ref('drivers_location/$driverId')
        .set({
          'lat': lat,
          'lng': lng,
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
  static const double _baseFare = 5.0;
  static const double _perKmRate = 3.0;
  static const double _surgeMultiplier = 1.0;

  static double distanceKm(
      double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2) / 1000;
  }

  static double estimateTotal(double distanceKm) {
    final subtotal =
        (_baseFare + distanceKm * _perKmRate) * _surgeMultiplier;
    final rounded = double.parse(subtotal.toStringAsFixed(1));
    return rounded < 12.0 ? 12.0 : rounded;
  }

  static String etaString(double distanceKm) {
    final minutes = (distanceKm / 0.5).round();
    if (minutes < 60) return '$minutes min';
    return '${(minutes / 60).floor()}h ${minutes % 60}min';
  }
}

// ── Result wrapper ─────────────────────────────────────────────────────────
class LocationResult {
  final Position? position;
  final String? errorMessage;
  bool get isSuccess => position != null;

  LocationResult.success(this.position) : errorMessage = null;
  LocationResult.error(this.errorMessage) : position = null;
}
