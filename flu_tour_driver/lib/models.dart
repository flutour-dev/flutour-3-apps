// lib/models.dart — FluTour Driver App
// Firestore-ready data models
// TODO: Connect toMap()/fromMap() to Firestore when Google account is recovered

// ── Enums ──────────────────────────────────────────────────────────────────

enum TripStatus {
  requested,
  accepted,
  inProgress,
  completed,
  cancelled,
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
      case 'credit_card':   return PaymentMethod.creditCard;
      case 'mobile_wallet': return PaymentMethod.mobileWallet;
      default:              return PaymentMethod.cash;
    }
  }
}

enum DriverStatus { pending, approved, rejected, suspended }

extension DriverStatusX on DriverStatus {
  String get label {
    switch (this) {
      case DriverStatus.pending:   return 'Pending';
      case DriverStatus.approved:  return 'Approved';
      case DriverStatus.rejected:  return 'Rejected';
      case DriverStatus.suspended: return 'Suspended';
    }
  }
  String get value {
    switch (this) {
      case DriverStatus.pending:   return 'pending';
      case DriverStatus.approved:  return 'approved';
      case DriverStatus.rejected:  return 'rejected';
      case DriverStatus.suspended: return 'suspended';
    }
  }
  static DriverStatus fromString(String s) {
    switch (s) {
      case 'approved':  return DriverStatus.approved;
      case 'rejected':  return DriverStatus.rejected;
      case 'suspended': return DriverStatus.suspended;
      default:          return DriverStatus.pending;
    }
  }
}

// ── DriverModel ───────────────────────────────────────────────────────────
// Firestore path: drivers/{uid}
class DriverModel {
  final String uid;
  final String name;
  final String phone;
  final String vehicleId;
  final VehicleType vehicleType;
  final DriverStatus status;
  final double rating;
  final int totalTrips;
  final double balance;
  final bool isOnline;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;

  DriverModel({
    required this.uid,
    required this.name,
    required this.phone,
    required this.vehicleId,
    required this.vehicleType,
    this.status = DriverStatus.pending,
    this.rating = 0.0,
    this.totalTrips = 0,
    this.balance = 0.0,
    this.isOnline = false,
    this.latitude,
    this.longitude,
    required this.createdAt,
  });

  // TODO: Use with FirebaseFirestore.instance.collection('drivers').doc(uid).set(toMap())
  Map<String, dynamic> toMap() => {
    'uid': uid,
    'name': name,
    'phone': phone,
    'vehicleId': vehicleId,
    'vehicleType': vehicleType.value,
    'status': status.value,
    'rating': rating,
    'totalTrips': totalTrips,
    'balance': balance,
    'isOnline': isOnline,
    'latitude': latitude,
    'longitude': longitude,
    'createdAt': createdAt.toIso8601String(),
  };

  factory DriverModel.fromMap(Map<String, dynamic> m) => DriverModel(
    uid: m['uid'] ?? '',
    name: m['name'] ?? '',
    phone: m['phone'] ?? '',
    vehicleId: m['vehicleId'] ?? '',
    vehicleType: VehicleTypeX.fromString(m['vehicleType'] ?? 'felucca'),
    status: DriverStatusX.fromString(m['status'] ?? 'pending'),
    rating: (m['rating'] ?? 0).toDouble(),
    totalTrips: m['totalTrips'] ?? 0,
    balance: (m['balance'] ?? 0).toDouble(),
    isOnline: m['isOnline'] ?? false,
    latitude: m['latitude']?.toDouble(),
    longitude: m['longitude']?.toDouble(),
    createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
  );

  DriverModel copyWith({
    bool? isOnline, double? latitude, double? longitude,
    double? balance, int? totalTrips, double? rating, DriverStatus? status,
  }) => DriverModel(
    uid: uid, name: name, phone: phone, vehicleId: vehicleId,
    vehicleType: vehicleType,
    status: status ?? this.status,
    rating: rating ?? this.rating,
    totalTrips: totalTrips ?? this.totalTrips,
    balance: balance ?? this.balance,
    isOnline: isOnline ?? this.isOnline,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    createdAt: createdAt,
  );
}

// ── TripRequestModel ──────────────────────────────────────────────────────
// Incoming ride request shown to driver
// Firestore path: trips/{tripId} with status='requested'
class TripRequestModel {
  final String id;
  final String passengerId;
  final String passengerName;
  final String pickup;
  final String dropoff;
  final String distanceKm;
  final String durationMin;
  final double fare;
  final PaymentMethod paymentMethod;
  final DateTime requestedAt;

  TripRequestModel({
    required this.id,
    required this.passengerId,
    required this.passengerName,
    required this.pickup,
    required this.dropoff,
    required this.distanceKm,
    required this.durationMin,
    required this.fare,
    required this.paymentMethod,
    required this.requestedAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'passengerId': passengerId, 'passengerName': passengerName,
    'pickup': pickup, 'dropoff': dropoff,
    'distanceKm': distanceKm, 'durationMin': durationMin,
    'fare': fare, 'paymentMethod': paymentMethod.value,
    'requestedAt': requestedAt.toIso8601String(),
  };

  factory TripRequestModel.fromMap(Map<String, dynamic> m) => TripRequestModel(
    id: m['id'] ?? '',
    passengerId: m['passengerId'] ?? '',
    passengerName: m['passengerName'] ?? '',
    pickup: m['pickup'] ?? '', dropoff: m['dropoff'] ?? '',
    distanceKm: m['distanceKm'] ?? '', durationMin: m['durationMin'] ?? '',
    fare: (m['fare'] ?? 0).toDouble(),
    paymentMethod: PaymentMethodX.fromString(m['paymentMethod'] ?? 'cash'),
    requestedAt: DateTime.tryParse(m['requestedAt'] ?? '') ?? DateTime.now(),
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
  final int driverRating;
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
    this.driverRating = 0,
    required this.createdAt,
    this.completedAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'passengerId': passengerId, 'passengerName': passengerName,
    'driverId': driverId, 'driverName': driverName, 'vehicleId': vehicleId,
    'vehicleType': vehicleType.value, 'pickup': pickup, 'dropoff': dropoff,
    'fare': fare, 'paymentMethod': paymentMethod.value, 'status': status.value,
    'driverRating': driverRating,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };

  factory TripModel.fromMap(Map<String, dynamic> m) => TripModel(
    id: m['id'] ?? '', passengerId: m['passengerId'] ?? '',
    passengerName: m['passengerName'] ?? '',
    driverId: m['driverId'] ?? '', driverName: m['driverName'] ?? '',
    vehicleId: m['vehicleId'] ?? '',
    vehicleType: VehicleTypeX.fromString(m['vehicleType'] ?? 'felucca'),
    pickup: m['pickup'] ?? '', dropoff: m['dropoff'] ?? '',
    fare: (m['fare'] ?? 0).toDouble(),
    paymentMethod: PaymentMethodX.fromString(m['paymentMethod'] ?? 'cash'),
    status: TripStatusX.fromString(m['status'] ?? 'completed'),
    driverRating: m['driverRating'] ?? 0,
    createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
    completedAt: m['completedAt'] != null ? DateTime.tryParse(m['completedAt']) : null,
  );

  TripModel copyWith({TripStatus? status, DateTime? completedAt}) => TripModel(
    id: id, passengerId: passengerId, passengerName: passengerName,
    driverId: driverId, driverName: driverName, vehicleId: vehicleId,
    vehicleType: vehicleType, pickup: pickup, dropoff: dropoff,
    fare: fare, paymentMethod: paymentMethod,
    status: status ?? this.status,
    driverRating: driverRating, createdAt: createdAt,
    completedAt: completedAt ?? this.completedAt,
  );
}

// ── EarningsSummary ───────────────────────────────────────────────────────
class EarningsSummary {
  final double today;
  final double thisWeek;
  final double thisMonth;
  final int tripsToday;
  final int tripsThisWeek;

  EarningsSummary({
    required this.today,
    required this.thisWeek,
    required this.thisMonth,
    required this.tripsToday,
    required this.tripsThisWeek,
  });
}
