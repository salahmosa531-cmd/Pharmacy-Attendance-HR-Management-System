import 'package:equatable/equatable.dart';

/// Represents a pharmaceutical supplier/vendor
/// 
/// Tracks supplier information and payment terms for managing
/// purchases and accounts payable with pharma companies.
class Supplier extends Equatable {
  final String id;
  final String branchId;
  final String name;
  final String? code;
  final String? phone;
  final String? email;
  final String? address;
  final String? contactPerson;
  final String? taxNumber;
  final int paymentTermsDays;
  final double creditLimit;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? syncedAt;

  const Supplier({
    required this.id,
    required this.branchId,
    required this.name,
    this.code,
    this.phone,
    this.email,
    this.address,
    this.contactPerson,
    this.taxNumber,
    this.paymentTermsDays = 30,
    this.creditLimit = 0,
    this.notes,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.syncedAt,
  });

  /// Create from database map
  factory Supplier.fromMap(Map<String, dynamic> map) {
    return Supplier(
      id: map['id'] as String,
      branchId: map['branch_id'] as String,
      name: map['name'] as String,
      code: map['code'] as String?,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      address: map['address'] as String?,
      contactPerson: map['contact_person'] as String?,
      taxNumber: map['tax_number'] as String?,
      paymentTermsDays: (map['payment_terms_days'] as int?) ?? 30,
      creditLimit: (map['credit_limit'] as num?)?.toDouble() ?? 0,
      notes: map['notes'] as String?,
      isActive: (map['is_active'] as int?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      syncedAt: map['synced_at'] != null 
          ? DateTime.parse(map['synced_at'] as String)
          : null,
    );
  }

  /// Convert to database map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'branch_id': branchId,
      'name': name,
      'code': code,
      'phone': phone,
      'email': email,
      'address': address,
      'contact_person': contactPerson,
      'tax_number': taxNumber,
      'payment_terms_days': paymentTermsDays,
      'credit_limit': creditLimit,
      'notes': notes,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'synced_at': syncedAt?.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  Supplier copyWith({
    String? id,
    String? branchId,
    String? name,
    String? code,
    String? phone,
    String? email,
    String? address,
    String? contactPerson,
    String? taxNumber,
    int? paymentTermsDays,
    double? creditLimit,
    String? notes,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? syncedAt,
  }) {
    return Supplier(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      name: name ?? this.name,
      code: code ?? this.code,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      contactPerson: contactPerson ?? this.contactPerson,
      taxNumber: taxNumber ?? this.taxNumber,
      paymentTermsDays: paymentTermsDays ?? this.paymentTermsDays,
      creditLimit: creditLimit ?? this.creditLimit,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  @override
  List<Object?> get props => [
    id, branchId, name, code, phone, email, address, contactPerson,
    taxNumber, paymentTermsDays, creditLimit, notes, isActive,
    createdAt, updatedAt, syncedAt,
  ];
}
