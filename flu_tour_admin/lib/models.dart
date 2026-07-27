// lib/models.dart — FluTour Admin App

// ── Enums ──────────────────────────────────────────────────────────────────

enum TripStatus { requested, accepted, inProgress, completed, cancelled }

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
  static VehicleType fromString(String s) =>
      s == 'felucca' ? VehicleType.felucca : VehicleType.horseCarriage;
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
}

enum UserAccountStatus { active, blocked }
enum DriverAccountStatus { pending, approved, rejected, suspended }

extension DriverAccountStatusX on DriverAccountStatus {
  String get label {
    switch (this) {
      case DriverAccountStatus.pending:   return 'Pending';
      case DriverAccountStatus.approved:  return 'Approved';
      case DriverAccountStatus.rejected:  return 'Rejected';
      case DriverAccountStatus.suspended: return 'Suspended';
    }
  }
  static DriverAccountStatus fromString(String s) {
    switch (s) {
      case 'approved':  return DriverAccountStatus.approved;
      case 'rejected':  return DriverAccountStatus.rejected;
      case 'suspended': return DriverAccountStatus.suspended;
      default:          return DriverAccountStatus.pending;
    }
  }
}

// ── PassengerModel ────────────────────────────────────────────────────────
// Firestore path: users/{uid}
class PassengerModel {
  final String uid;
  final String name;
  final String phone;
  final int totalRides;
  final UserAccountStatus status;
  final DateTime joinedAt;

  PassengerModel({
    required this.uid,
    required this.name,
    required this.phone,
    this.totalRides = 0,
    this.status = UserAccountStatus.active,
    required this.joinedAt,
  });

  Map<String, dynamic> toMap() => {
    'uid': uid, 'name': name, 'phone': phone,
    'totalRides': totalRides,
    'status': status == UserAccountStatus.active ? 'active' : 'blocked',
    'joinedAt': joinedAt.toIso8601String(),
  };

  factory PassengerModel.fromMap(Map<String, dynamic> m) => PassengerModel(
    uid: m['uid'] ?? m['id'] ?? '',
    name: m['name'] ?? '',
    phone: m['phone'] ?? '',
    totalRides: m['rides'] ?? m['totalRides'] ?? 0,
    status: m['status'] == 'Blocked' || m['status'] == 'blocked'
        ? UserAccountStatus.blocked : UserAccountStatus.active,
    joinedAt: DateTime.tryParse(m['joinedAt'] ?? '') ?? DateTime.now(),
  );

  PassengerModel copyWith({UserAccountStatus? status}) => PassengerModel(
    uid: uid, name: name, phone: phone,
    totalRides: totalRides,
    status: status ?? this.status,
    joinedAt: joinedAt,
  );
}

// ── DriverModel ───────────────────────────────────────────────────────────
// Firestore path: drivers/{uid}
class DriverModel {
  final String uid;
  final String name;
  final String phone;
  final VehicleType vehicleType;
  final String vehicleId;
  final double rating;
  final int totalTrips;
  final DriverAccountStatus status;
  final bool isOnline;
  final double? latitude;
  final double? longitude;

  DriverModel({
    required this.uid,
    required this.name,
    required this.phone,
    required this.vehicleType,
    required this.vehicleId,
    this.rating = 0.0,
    this.totalTrips = 0,
    this.status = DriverAccountStatus.pending,
    this.isOnline = false,
    this.latitude,
    this.longitude,
  });

  Map<String, dynamic> toMap() => {
    'uid': uid, 'name': name, 'phone': phone,
    'vehicleType': vehicleType.value, 'vehicleId': vehicleId,
    'rating': rating, 'totalTrips': totalTrips, 'status': status.label,
    'isOnline': isOnline, 'latitude': latitude, 'longitude': longitude,
  };

  factory DriverModel.fromMap(Map<String, dynamic> m) => DriverModel(
    uid: m['uid'] ?? m['id'] ?? '',
    name: m['name'] ?? '',
    phone: m['phone'] ?? '',
    vehicleType: VehicleTypeX.fromString(m['type'] == 'Felucca' ? 'felucca' : 'horse_carriage'),
    vehicleId: m['vehicle'] ?? m['vehicleId'] ?? '',
    rating: (m['rating'] ?? 0).toDouble(),
    totalTrips: m['trips'] ?? m['totalTrips'] ?? 0,
    status: DriverAccountStatusX.fromString((m['status'] ?? 'pending').toLowerCase()),
    isOnline: m['isOnline'] ?? false,
    latitude: m['latitude']?.toDouble(),
    longitude: m['longitude']?.toDouble(),
  );

  DriverModel copyWith({DriverAccountStatus? status, bool? isOnline}) => DriverModel(
    uid: uid, name: name, phone: phone, vehicleType: vehicleType,
    vehicleId: vehicleId, rating: rating, totalTrips: totalTrips,
    status: status ?? this.status,
    isOnline: isOnline ?? this.isOnline,
    latitude: latitude, longitude: longitude,
  );
}

// ── TripModel ─────────────────────────────────────────────────────────────
// Firestore path: trips/{tripId}
class TripModel {
  final String id;
  final String passengerName;
  final String driverName;
  final String vehicleId;
  final VehicleType vehicleType;
  final TripStatus status;
  final double fare;
  final PaymentMethod paymentMethod;
  final DateTime date;

  TripModel({
    required this.id,
    required this.passengerName,
    required this.driverName,
    required this.vehicleId,
    required this.vehicleType,
    required this.status,
    required this.fare,
    required this.paymentMethod,
    required this.date,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'passengerName': passengerName, 'driverName': driverName,
    'vehicleId': vehicleId, 'vehicleType': vehicleType.value,
    'status': status.value, 'fare': fare, 'paymentMethod': paymentMethod.value,
    'date': date.toIso8601String(),
  };

  factory TripModel.fromMap(Map<String, dynamic> m) => TripModel(
    id: m['id'] ?? '',
    passengerName: m['passenger'] ?? m['passengerName'] ?? '',
    driverName: m['driver'] ?? m['driverName'] ?? '',
    vehicleId: m['vehicle'] ?? m['vehicleId'] ?? '',
    vehicleType: VehicleTypeX.fromString(
        m['type'] == 'Felucca' ? 'felucca' : 'horse_carriage'),
    status: TripStatusX.fromString((m['status'] ?? 'completed').toLowerCase()
        .replaceAll(' ', '_')),
    fare: (m['amount'] ?? m['fare'] ?? 0).toDouble(),
    paymentMethod: m['payment'] == 'Credit Card'
        ? PaymentMethod.creditCard
        : m['payment'] == 'Mobile Wallet'
            ? PaymentMethod.mobileWallet
            : PaymentMethod.cash,
    date: DateTime.tryParse(m['date'] ?? '') ?? DateTime.now(),
  );
}

// ── DashboardStats ────────────────────────────────────────────────────────
class DashboardStats {
  final int totalPassengers;
  final int activeDrivers;
  final int pendingDrivers;
  final int activeTrips;
  final double revenueToday;
  final int tripsToday;

  DashboardStats({
    required this.totalPassengers,
    required this.activeDrivers,
    required this.pendingDrivers,
    required this.activeTrips,
    required this.revenueToday,
    required this.tripsToday,
  });
}
