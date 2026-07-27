// lib/models.dart — FluTour Passenger App
// Firestore-ready data models
// TODO: Connect toMap()/fromMap() to Firestore when Google account is recovered

// ── Enums ──────────────────────────────────────────────────────────────────

enum TripStatus {
  requested,   // Passenger booked, waiting for driver
  accepted,    // Driver accepted
  inProgress,  // Trip started
  completed,   // Trip finished
  cancelled,   // Cancelled by passenger or driver
}

extension TripStatusX on TripStatus {
  String get label {
    switch (this) {
      case TripStatus.requested:  return 'Requested';
      case TripStatus.accepted:   return 'Accepted';
      case TripStatus.inProgress: return 'In Progress';
      case TripStatus.completed:  return 'Completed';
      case TripStatus.cancelled:  return 'Cancelled';
    }
  }

  // Firestore string representation
  String get value {
    switch (this) {
      case TripStatus.requested:  return 'requested';
      case TripStatus.accepted:   return 'accepted';
      case TripStatus.inProgress: return 'in_progress';
      case TripStatus.completed:  return 'completed';
      case TripStatus.cancelled:  return 'cancelled';
    }
  }

  static TripStatus fromString(String s) {
    switch (s) {
      case 'accepted':    return TripStatus.accepted;
      case 'in_progress': return TripStatus.inProgress;
      case 'completed':   return TripStatus.completed;
      case 'cancelled':   return TripStatus.cancelled;
      default:            return TripStatus.requested;
    }
  }
}

enum VehicleType { felucca, horseCarriage }

extension VehicleTypeX on VehicleType {
  String get label => this == VehicleType.felucca ? 'Felucca' : 'Horse Carriage';
  String get value => this == VehicleType.felucca ? 'felucca' : 'horse_carriage';
  static VehicleType fromString(String s) {
    final v = s.toLowerCase().replaceAll(' ', '_');
    return v == 'felucca' ? VehicleType.felucca : VehicleType.horseCarriage;
  }
}

enum PaymentMethod { cash, creditCard, mobileWallet }

extension PaymentMethodX on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.cash:         return 'Cash';
      case PaymentMethod.creditCard:   return 'Credit Card';
      case PaymentMethod.mobileWallet: return 'Mobile Wallet';
    }
  }
  String get value {
    switch (this) {
      case PaymentMethod.cash:         return 'cash';
      case PaymentMethod.creditCard:   return 'credit_card';
      case PaymentMethod.mobileWallet: return 'mobile_wallet';
    }
  }
  static PaymentMethod fromString(String s) {
    switch (s) {
      case 'credit_card':    return PaymentMethod.creditCard;
      case 'mobile_wallet':  return PaymentMethod.mobileWallet;
      default:               return PaymentMethod.cash;
    }
  }
}

// ── UserModel ─────────────────────────────────────────────────────────────
// Firestore path: users/{uid}
class UserModel {
  final String uid;
  final String name;
  final String phone;
  final String role;         // 'passenger'
  final int totalRides;
  final DateTime createdAt;

  UserModel({
    required this.uid,
    required this.name,
    required this.phone,
    this.role = 'passenger',
    this.totalRides = 0,
    required this.createdAt,
  });

  // TODO: Use with FirebaseFirestore.instance.collection('users').doc(uid).set(toMap())
  Map<String, dynamic> toMap() => {
    'uid': uid,
    'name': name,
    'phone': phone,
    'role': role,
    'totalRides': totalRides,
    'createdAt': createdAt.toIso8601String(),
  };

  // TODO: Use with snapshot.data() from Firestore
  factory UserModel.fromMap(Map<String, dynamic> m) => UserModel(
    uid: m['uid'] ?? '',
    name: m['name'] ?? '',
    phone: m['phone'] ?? '',
    role: m['role'] ?? 'passenger',
    totalRides: m['totalRides'] ?? 0,
    createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
  );

  UserModel copyWith({String? name, String? phone, int? totalRides}) => UserModel(
    uid: uid,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    role: role,
    totalRides: totalRides ?? this.totalRides,
    createdAt: createdAt,
  );
}

// ── TripModel ─────────────────────────────────────────────────────────────
// Firestore path: trips/{tripId}
class TripModel {
  final String id;
  final String passengerId;
  final String passengerName;
  final String driverId;
  final String driverName;
  final String vehicleId;
  final VehicleType vehicleType;
  final String pickup;
  final String dropoff;
  final double fare;
  final PaymentMethod paymentMethod;
  final TripStatus status;
  final int passengerRating;   // 1–5, 0 = not rated
  final DateTime createdAt;
  final DateTime? completedAt;

  TripModel({
    required this.id,
    required this.passengerId,
    required this.passengerName,
    required this.driverId,
    required this.driverName,
    required this.vehicleId,
    required this.vehicleType,
    required this.pickup,
    required this.dropoff,
    required this.fare,
    required this.paymentMethod,
    required this.status,
    this.passengerRating = 0,
    required this.createdAt,
    this.completedAt,
  });

  // TODO: Use with trips collection in Firestore
  Map<String, dynamic> toMap() => {
    'id': id,
    'passengerId': passengerId,
    'passengerName': passengerName,
    'driverId': driverId,
    'driverName': driverName,
    'vehicleId': vehicleId,
    'vehicleType': vehicleType.value,
    'pickup': pickup,
    'dropoff': dropoff,
    'fare': fare,
    'paymentMethod': paymentMethod.value,
    'status': status.value,
    'passengerRating': passengerRating,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };

  factory TripModel.fromMap(Map<String, dynamic> m) => TripModel(
    id: m['id'] ?? '',
    passengerId: m['passengerId'] ?? '',
    passengerName: m['passengerName'] ?? '',
    driverId: m['driverId'] ?? '',
    driverName: m['driverName'] ?? '',
    vehicleId: m['vehicleId'] ?? '',
    vehicleType: VehicleTypeX.fromString(m['vehicleType'] ?? 'felucca'),
    pickup: m['pickup'] ?? '',
    dropoff: m['dropoff'] ?? '',
    fare: (m['fare'] ?? 0).toDouble(),
    paymentMethod: PaymentMethodX.fromString(m['paymentMethod'] ?? 'cash'),
    status: TripStatusX.fromString(m['status'] ?? 'requested'),
    passengerRating: m['passengerRating'] ?? 0,
    createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
    completedAt: m['completedAt'] != null ? DateTime.tryParse(m['completedAt']) : null,
  );

  TripModel copyWith({TripStatus? status, int? passengerRating, DateTime? completedAt}) =>
      TripModel(
        id: id, passengerId: passengerId, passengerName: passengerName,
        driverId: driverId, driverName: driverName, vehicleId: vehicleId,
        vehicleType: vehicleType, pickup: pickup, dropoff: dropoff,
        fare: fare, paymentMethod: paymentMethod,
        status: status ?? this.status,
        passengerRating: passengerRating ?? this.passengerRating,
        createdAt: createdAt,
        completedAt: completedAt ?? this.completedAt,
      );
}

// ── PaymentModel ──────────────────────────────────────────────────────────
// Firestore path: payments/{paymentId}
class PaymentModel {
  final String id;
  final String tripId;
  final String passengerId;
  final String driverId;
  final double amount;
  final PaymentMethod method;
  final String status;  // 'pending', 'completed', 'refunded'
  final DateTime createdAt;

  PaymentModel({
    required this.id,
    required this.tripId,
    required this.passengerId,
    required this.driverId,
    required this.amount,
    required this.method,
    required this.status,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'tripId': tripId, 'passengerId': passengerId,
    'driverId': driverId, 'amount': amount, 'method': method.value,
    'status': status, 'createdAt': createdAt.toIso8601String(),
  };

  factory PaymentModel.fromMap(Map<String, dynamic> m) => PaymentModel(
    id: m['id'] ?? '', tripId: m['tripId'] ?? '',
    passengerId: m['passengerId'] ?? '', driverId: m['driverId'] ?? '',
    amount: (m['amount'] ?? 0).toDouble(),
    method: PaymentMethodX.fromString(m['method'] ?? 'cash'),
    status: m['status'] ?? 'pending',
    createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
  );
}

// ── NotificationModel ─────────────────────────────────────────────────────
// Firestore path: notifications/{notifId}
class NotificationModel {
  final String id;
  final String userId;
  final String title;
  final String body;
  final bool read;
  final DateTime createdAt;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    this.read = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'userId': userId, 'title': title,
    'body': body, 'read': read, 'createdAt': createdAt.toIso8601String(),
  };

  factory NotificationModel.fromMap(Map<String, dynamic> m) => NotificationModel(
    id: m['id'] ?? '', userId: m['userId'] ?? '',
    title: m['title'] ?? '', body: m['body'] ?? '',
    read: m['read'] ?? false,
    createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
  );
}
