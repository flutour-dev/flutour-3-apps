// lib/database_service.dart — FluTour Admin App

import 'models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart' as rtdb;

class AdminDatabaseService {
  static final AdminDatabaseService instance = AdminDatabaseService._();
  AdminDatabaseService._();

  static final _db = FirebaseFirestore.instance;
  static final _rtdb = rtdb.FirebaseDatabase.instance;

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
        photoUrl: data['photoUrl'] ?? '',
        vehiclePhotoUrl: data['vehiclePhotoUrl'] ?? '',
        licensePhotoUrl: data['licensePhotoUrl'] ?? '',
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

  Future<List<Map<String, dynamic>>> getWithdrawalRequests({String? status}) async {
    final snap = await _db.collection('withdrawal_requests')
        .orderBy('requestedAt', descending: true)
        .get();
    final all = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    // Filter by status in Dart — avoids compound index requirement
    if (status != null) return all.where((r) => r['status'] == status).toList();
    return all;
  }

  Future<void> markWithdrawalPaid(String requestId, String driverId, double amount) async {
    final batch = _db.batch();
    batch.update(_db.collection('withdrawal_requests').doc(requestId), {
      'status': 'paid',
      'paidAt': FieldValue.serverTimestamp(),
    });
    batch.update(_db.collection('drivers').doc(driverId), {
      'balance': FieldValue.increment(-amount),
    });
    await batch.commit();
  }

  Future<double> getPlatformEarnings() async {
    final snap = await _db.collection('trips').where('status', isEqualTo: 'completed').get();
    return snap.docs.fold<double>(
        0, (s, d) => s + ((d.data()['fare'] as num?)?.toDouble() ?? 0) * 0.15);
  }

  Future<String> getAdminInstapay() async {
    try {
      final doc = await _db.collection('settings').doc('admin').get();
      return (doc.data()?['instapayPhone'] as String?) ?? '';
    } catch (_) { return ''; }
  }

  Future<void> setAdminInstapay(String phone) async {
    await _db.collection('settings').doc('admin').set(
      {'instapayPhone': phone, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<DashboardStats> getDashboardStats() async {
    final now = DateTime.now();
    final todayStart = Timestamp.fromDate(DateTime(now.year, now.month, now.day));

    final countResults = await Future.wait([
      _db.collection('users').where('role', isEqualTo: 'passenger').count().get(),
      _db.collection('drivers').where('status', isEqualTo: 'approved').count().get(),
      _db.collection('drivers').where('status', isEqualTo: 'pending').count().get(),
      _db.collection('trips').where('status', isEqualTo: 'in_progress').count().get(),
    ]);

    // Query today's completed trips (needs composite index: status ASC + completedAt ASC)
    int tripsToday = 0;
    double revenueToday = 0.0;
    try {
      final todaySnap = await _db
          .collection('trips')
          .where('status', isEqualTo: 'completed')
          .where('completedAt', isGreaterThanOrEqualTo: todayStart)
          .get();
      tripsToday = todaySnap.docs.length;
      revenueToday = todaySnap.docs.fold(0.0,
          (sum, d) => sum + ((d.data()['fare'] as num?) ?? 0).toDouble());
    } catch (_) {
      // Index not yet created — falls back to 0 until index is deployed
    }

    return DashboardStats(
      totalPassengers: countResults[0].count ?? 0,
      activeDrivers: countResults[1].count ?? 0,
      pendingDrivers: countResults[2].count ?? 0,
      activeTrips: countResults[3].count ?? 0,
      revenueToday: revenueToday,
      tripsToday: tripsToday,
    );
  }
}
