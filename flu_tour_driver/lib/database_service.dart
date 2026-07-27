// lib/database_service.dart — FluTour Driver App
// Firestore-ready data layer with mock data
// TODO: Replace mock implementations with Firestore calls when Google account is recovered
//
// Firestore indexes needed (add in Firebase Console):
//   trips: driverId ASC, createdAt DESC
//   trips: status ASC, createdAt DESC
//   drivers: isOnline ASC, vehicleType ASC

import 'models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';

class DriverDatabaseService {
  static final DriverDatabaseService instance = DriverDatabaseService._();
  DriverDatabaseService._();

  static final _db = FirebaseFirestore.instance;
  static final _rtdb = FirebaseDatabase.instance;

  Future<DriverModel> getDriverProfile(String uid) async {
    final doc = await _db.collection('drivers').doc(uid).get();
    final d = doc.data() ?? {};
    return DriverModel(
      uid: uid,
      name: d['name'] ?? '',
      phone: d['phone'] ?? '',
      vehicleId: d['vehicleId'] ?? '',
      vehicleType: VehicleTypeX.fromString(d['vehicleType'] ?? 'felucca'),
      status: DriverStatusX.fromString(d['status'] ?? 'pending'),
      rating: (d['rating'] as num?)?.toDouble() ?? 0.0,
      totalTrips: d['totalTrips'] ?? 0,
      balance: (d['balance'] as num?)?.toDouble() ?? 0.0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Future<void> createDriverProfile(DriverModel driver) async {
    await _db.collection('drivers').doc(driver.uid).set({
      'name': driver.name,
      'phone': driver.phone,
      'vehicleId': driver.vehicleId,
      'vehicleType': driver.vehicleType.value,
      'status': 'pending',
      'rating': 0.0,
      'totalTrips': 0,
      'balance': 0.0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setOnlineStatus(String uid, bool isOnline,
      {double? latitude, double? longitude}) async {
    await _db.collection('drivers').doc(uid).update({
      'isOnline': isOnline,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    });
    if (!isOnline) {
      await _rtdb.ref('drivers_location/$uid').remove();
    }
  }

  Future<void> updateLocation(String uid, double lat, double lng) async {
    await _rtdb.ref('drivers_location/$uid').update({
      'lat': lat,
      'lng': lng,
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<List<TripRequestModel>> getIncomingRequests(String driverId) async {
    final snap = await _db
        .collection('trips')
        .where('status', isEqualTo: 'requested')
        .orderBy('createdAt')
        .limit(10)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      return TripRequestModel(
        id: d.id,
        passengerId: data['passengerId'] ?? '',
        passengerName: data['passengerName'] ?? '',
        pickup: data['pickup'] ?? '',
        dropoff: data['dropoff'] ?? '',
        distanceKm: data['distanceKm'] ?? '—',
        durationMin: data['durationMin'] ?? '—',
        fare: (data['fare'] as num?)?.toDouble() ?? 0.0,
        paymentMethod: PaymentMethodX.fromString(data['paymentMethod'] ?? 'cash'),
        requestedAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
    }).toList();
  }

  Future<void> acceptTrip(String tripId, String driverId, String driverName) async {
    await _db.collection('trips').doc(tripId).update({
      'status': 'accepted',
      'driverId': driverId,
      'driverName': driverName,
      'acceptedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> declineTrip(String tripId) async {
    // Re-queue the trip for another driver
    await _db.collection('trips').doc(tripId).update({'status': 'requested', 'driverId': ''});
  }

  Future<void> arriveTrip(String tripId) async {
    await _db.collection('trips').doc(tripId).update({
      'status': 'arrived',
      'arrivedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> startTrip(String tripId) async {
    await _db.collection('trips').doc(tripId).update({
      'status': 'in_progress',
      'startedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> completeTrip(String tripId, double fare, String driverId) async {
    final batch = _db.batch();
    batch.update(_db.collection('trips').doc(tripId), {
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
    });
    // 85% driver share (15% platform fee)
    final driverEarning = fare * 0.85;
    batch.update(_db.collection('drivers').doc(driverId), {
      'balance': FieldValue.increment(driverEarning),
      'totalTrips': FieldValue.increment(1),
    });
    await batch.commit();
  }

  Future<List<TripModel>> getTripHistory(String uid) async {
    final snap = await _db
        .collection('trips')
        .where('driverId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      return TripModel(
        id: d.id,
        passengerId: data['passengerId'] ?? '',
        passengerName: data['passengerName'] ?? '',
        driverId: data['driverId'] ?? '',
        driverName: data['driverName'] ?? '',
        vehicleId: data['vehicleId'] ?? '',
        vehicleType: VehicleTypeX.fromString(data['vehicleType'] ?? 'felucca'),
        pickup: data['pickup'] ?? '',
        dropoff: data['dropoff'] ?? '',
        fare: (data['fare'] as num?)?.toDouble() ?? 0.0,
        paymentMethod: PaymentMethodX.fromString(data['paymentMethod'] ?? 'cash'),
        status: TripStatusX.fromString(data['status'] ?? 'completed'),
        createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      );
    }).toList();
  }

  Future<EarningsSummary> getEarningsSummary(String uid) async {
    final snap = await _db
        .collection('trips')
        .where('driverId', isEqualTo: uid)
        .where('status', isEqualTo: 'completed')
        .get();
    final trips = snap.docs.map((d) => d.data()).toList();
    final now = DateTime.now();
    final today = trips.where((t) {
      final dt = (t['completedAt'] as Timestamp?)?.toDate();
      return dt != null && dt.day == now.day && dt.month == now.month && dt.year == now.year;
    }).toList();
    final weekAgo = now.subtract(Duration(days: 7));
    final week = trips.where((t) {
      final dt = (t['completedAt'] as Timestamp?)?.toDate();
      return dt != null && dt.isAfter(weekAgo);
    }).toList();
    final monthAgo = DateTime(now.year, now.month - 1, now.day);
    final month = trips.where((t) {
      final dt = (t['completedAt'] as Timestamp?)?.toDate();
      return dt != null && dt.isAfter(monthAgo);
    }).toList();
    double sum(List<Map<String, dynamic>> list) =>
        list.fold(0.0, (s, t) => s + ((t['fare'] as num?)?.toDouble() ?? 0.0) * 0.85);
    return EarningsSummary(
      today: sum(today),
      thisWeek: sum(week),
      thisMonth: sum(month),
      tripsToday: today.length,
      tripsThisWeek: week.length,
    );
  }

  Future<void> submitRating(String driverUid, int rating, String comment) async {
    final batch = _db.batch();
    final reviewRef = _db.collection('drivers').doc(driverUid)
        .collection('reviews').doc();
    batch.set(reviewRef, {
      'rating': rating,
      'comment': comment,
      'createdAt': FieldValue.serverTimestamp(),
    });
    // Rating average recalculated by Cloud Function; local update omitted.
    await batch.commit();
  }
}
