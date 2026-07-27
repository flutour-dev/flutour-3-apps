// lib/database_service.dart — FluTour Admin App

import 'models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';

class AdminDatabaseService {
  static final AdminDatabaseService instance = AdminDatabaseService._();
  AdminDatabaseService._();

  static final _db = FirebaseFirestore.instance;
  static final _rtdb = FirebaseDatabase.instance;

  Future<List<PassengerModel>> getPassengers() async {
    final snap = await _db
        .collection('users')
        .where('role', isEqualTo: 'passenger')
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      return PassengerModel(
        uid: d.id,
        name: data['name'] ?? '',
        phone: data['phone'] ?? '',
        totalRides: data['totalRides'] ?? 0,
        status: (data['status'] == 'blocked')
            ? UserAccountStatus.blocked
            : UserAccountStatus.active,
        joinedAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
    }).toList();
  }

  Future<void> setPassengerStatus(String uid, UserAccountStatus status) async {
    await _db.collection('users').doc(uid).update({
      'status': status == UserAccountStatus.blocked ? 'blocked' : 'active',
    });
  }

  Future<List<DriverModel>> getDrivers() async {
    final snap = await _db
        .collection('drivers')
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      return DriverModel(
        uid: d.id,
        name: data['name'] ?? '',
        phone: data['phone'] ?? '',
        vehicleType: VehicleTypeX.fromString(data['vehicleType'] ?? 'felucca'),
        vehicleId: data['vehicleId'] ?? '',
        rating: (data['rating'] as num?)?.toDouble() ?? 0.0,
        totalTrips: data['totalTrips'] ?? 0,
        status: DriverAccountStatusX.fromString(data['status'] ?? 'pending'),
        isOnline: data['isOnline'] ?? false,
        latitude: (data['latitude'] as num?)?.toDouble(),
        longitude: (data['longitude'] as num?)?.toDouble(),
      );
    }).toList();
  }

  Future<void> approveDriver(String uid) async {
    await _db.collection('drivers').doc(uid).update({'status': 'approved'});
  }

  Future<void> rejectDriver(String uid) async {
    await _db.collection('drivers').doc(uid).update({'status': 'rejected'});
  }

  Future<void> suspendDriver(String uid) async {
    await _db.collection('drivers').doc(uid).update({'status': 'suspended'});
  }

  Future<List<DriverModel>> getOnlineDrivers() async {
    final snap = _rtdb.ref('drivers_location');
    final event = await snap.once();
    final data = event.snapshot.value as Map<dynamic, dynamic>? ?? {};
    return data.entries.map((e) {
      final v = Map<String, dynamic>.from(e.value as Map);
      return DriverModel(
        uid: e.key,
        name: v['name'] ?? 'Driver',
        phone: '',
        vehicleType: VehicleType.felucca,
        vehicleId: '',
        rating: 0.0,
        totalTrips: 0,
        status: DriverAccountStatus.approved,
        isOnline: true,
        latitude: (v['lat'] as num?)?.toDouble(),
        longitude: (v['lng'] as num?)?.toDouble(),
      );
    }).toList();
  }

  Future<List<TripModel>> getTrips() async {
    final snap = await _db
        .collection('trips')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      return TripModel(
        id: d.id,
        passengerName: data['passengerName'] ?? '',
        driverName: data['driverName'] ?? '',
        vehicleId: data['vehicleId'] ?? '',
        vehicleType: VehicleTypeX.fromString(data['vehicleType'] ?? 'felucca'),
        status: TripStatusX.fromString(data['status'] ?? 'completed'),
        fare: (data['fare'] as num?)?.toDouble() ?? 0.0,
        paymentMethod: data['paymentMethod'] == 'credit_card'
            ? PaymentMethod.creditCard
            : data['paymentMethod'] == 'mobile_wallet'
                ? PaymentMethod.mobileWallet
                : PaymentMethod.cash,
        date: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
    }).toList();
  }

  Future<void> cancelTrip(String tripId) async {
    await _db.collection('trips').doc(tripId)
        .update({'status': 'cancelled', 'cancelledBy': 'admin'});
  }

  Future<DashboardStats> getDashboardStats() async {
    final results = await Future.wait([
      _db.collection('users').where('role', isEqualTo: 'passenger').count().get(),
      _db.collection('drivers').where('status', isEqualTo: 'approved').count().get(),
      _db.collection('drivers').where('status', isEqualTo: 'pending').count().get(),
      _db.collection('trips').where('status', isEqualTo: 'in_progress').count().get(),
    ]);
    return DashboardStats(
      totalPassengers: results[0].count ?? 0,
      activeDrivers: results[1].count ?? 0,
      pendingDrivers: results[2].count ?? 0,
      activeTrips: results[3].count ?? 0,
      revenueToday: 0.0, // requires aggregation query or Cloud Function
      tripsToday: 0,
    );
  }
}
