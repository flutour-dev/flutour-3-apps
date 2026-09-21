// lib/database_service.dart — FluTour Passenger App
// Firestore data layer — all reads/writes go to Firebase project flutour-3fc69
//
// Firestore indexes needed (add in Firebase Console):
//   trips: passengerId ASC, createdAt DESC
//   trips: status ASC, createdAt DESC
//   notifications: userId ASC, createdAt DESC

import 'models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._();
  DatabaseService._();

  static final _db = FirebaseFirestore.instance;

  Future<UserModel> getProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    final d = doc.data() ?? {};
    return UserModel(
      uid: uid,
      name: d['name'] ?? '',
      phone: d['phone'] ?? '',
      totalRides: d['totalRides'] ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Future<void> updateProfile(String uid, {String? name, String? phone}) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (phone != null) data['phone'] = phone;
    if (data.isNotEmpty) await _db.collection('users').doc(uid).update(data);
  }

  Future<void> createUserProfile(UserModel user) async {
    await _db.collection('users').doc(user.uid).set({
      'name': user.name,
      'phone': user.phone,
      'role': 'passenger',
      'totalRides': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<TripModel>> getTripHistory(String uid) async {
    final snap = await _db
        .collection('trips')
        .where('passengerId', isEqualTo: uid)
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
        status: TripStatusX.fromString(data['status'] ?? 'requested'),
        passengerRating: data['passengerRating'] ?? 0,
        createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      );
    }).toList();
  }

  Future<TripModel> requestTrip({
    required String passengerId,
    required String passengerName,
    required VehicleType vehicleType,
    required String pickup,
    required String dropoff,
    required double fare,
    required PaymentMethod paymentMethod,
    double? pickupLat,
    double? pickupLng,
    double? dropoffLat,
    double? dropoffLng,
    String? scheduledAt,
    int passengerCount = 1,
  }) async {
    final ref = await _db.collection('trips').add({
      'passengerId': passengerId,
      'passengerName': passengerName,
      'driverId': '',
      'driverName': '',
      'vehicleId': '',
      'vehicleType': vehicleType.value,
      'pickup': pickup,
      'dropoff': dropoff,
      'fare': fare,
      'proposedFare': fare,
      'counterFare': null,
      'negotiationStatus': 'open',
      'paymentMethod': paymentMethod.value,
      'status': 'requested',
      'passengerCount': passengerCount,
      'createdAt': FieldValue.serverTimestamp(),
      if (pickupLat != null) 'pickupLat': pickupLat,
      if (pickupLng != null) 'pickupLng': pickupLng,
      if (dropoffLat != null) 'dropoffLat': dropoffLat,
      if (dropoffLng != null) 'dropoffLng': dropoffLng,
      if (scheduledAt != null) 'scheduledAt': scheduledAt,
      if (scheduledAt != null) 'isScheduled': true,
    });
    return TripModel(
      id: ref.id,
      passengerId: passengerId,
      passengerName: passengerName,
      driverId: '',
      driverName: '',
      vehicleId: '',
      vehicleType: vehicleType,
      pickup: pickup,
      dropoff: dropoff,
      fare: fare,
      paymentMethod: paymentMethod,
      status: TripStatus.requested,
      createdAt: DateTime.now(),
    );
  }

  Future<void> cancelTrip(String tripId,
      {String reason = '', String cancelledBy = 'passenger'}) async {
    await _db.collection('trips').doc(tripId).update({
      'status': 'cancelled',
      'cancelledBy': cancelledBy,
      'cancellationReason': reason,
      'cancelledAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> acceptDriverOffer({
    required String tripId,
    required String driverUid,
    required String driverName,
    required String driverPhone,
    required String instapayPhone,
    required double agreedFare,
  }) async {
    await _db.collection('trips').doc(tripId).update({
      'status': 'accepted',
      'driverId': driverUid,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'driverInstapayPhone': instapayPhone,
      'agreedFare': agreedFare,
      'acceptedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> rateTrip(String tripId, int rating, {String? comment}) async {
    await _db.collection('trips').doc(tripId).update({
      'passengerRating': rating,
      if (comment != null && comment.isNotEmpty) 'passengerComment': comment,
    });
  }

  Future<List<NotificationModel>> getNotifications(String uid) async {
    final snap = await _db
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      return NotificationModel(
        id: d.id,
        userId: data['userId'] ?? '',
        title: data['title'] ?? '',
        body: data['body'] ?? '',
        read: data['read'] ?? false,
        createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
    }).toList();
  }
}
