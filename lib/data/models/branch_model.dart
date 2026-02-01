import 'package:equatable/equatable.dart';

/// Branch/Pharmacy model
class Branch extends Equatable {
  final String id;
  final String name;
  final String? address;
  final String? phone;
  final String? email;
  final bool isMainBranch;
  final String? ownerId;
  final String? deviceId;
  final double? locationLat;
  final double? locationLng;
  final double locationRadius;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? syncedAt;

  const Branch({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    this.email,
    this.isMainBranch = false,
    this.ownerId,
    this.deviceId,
    this.locationLat,
    this.locationLng,
    this.locationRadius = 100,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.syncedAt,
  });

  factory Branch.fromMap(Map<String, dynamic> map) {
    return Branch(
      id: map['id'] as String,
      name: map['name'] as String,
      address: map['address'] as String?,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      isMainBranch: (map['is_main_branch'] as int?) == 1,
      ownerId: map['owner_id'] as String?,
      deviceId: map['device_id'] as String?,
      locationLat: map['location_lat'] as double?,
      locationLng: map['location_lng'] as double?,
      locationRadius: (map['location_radius'] as num?)?.toDouble() ?? 100,
      isActive: (map['is_active'] as int?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      syncedAt: map['synced_at'] != null
          ? DateTime.parse(map['synced_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'phone': phone,
      'email': email,
      'is_main_branch': isMainBranch ? 1 : 0,
      'owner_id': ownerId,
      'device_id': deviceId,
      'location_lat': locationLat,
      'location_lng': locationLng,
      'location_radius': locationRadius,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'synced_at': syncedAt?.toIso8601String(),
    };
  }

  Branch copyWith({
    String? id,
    String? name,
    String? address,
    String? phone,
    String? email,
    bool? isMainBranch,
    String? ownerId,
    String? deviceId,
    double? locationLat,
    double? locationLng,
    double? locationRadius,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? syncedAt,
  }) {
    return Branch(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      isMainBranch: isMainBranch ?? this.isMainBranch,
      ownerId: ownerId ?? this.ownerId,
      deviceId: deviceId ?? this.deviceId,
      locationLat: locationLat ?? this.locationLat,
      locationLng: locationLng ?? this.locationLng,
      locationRadius: locationRadius ?? this.locationRadius,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        address,
        phone,
        email,
        isMainBranch,
        ownerId,
        deviceId,
        locationLat,
        locationLng,
        locationRadius,
        isActive,
        createdAt,
        updatedAt,
        syncedAt,
      ];
}
