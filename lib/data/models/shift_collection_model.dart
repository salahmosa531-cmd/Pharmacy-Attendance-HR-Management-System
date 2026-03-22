import 'package:equatable/equatable.dart';
import '../../core/enums/financial_enums.dart';

/// Represents a collection (تحصيل) received during a financial shift
/// 
/// Collections are cash-in transactions representing money received from:
/// - Credit sale payments (آجل)
/// - Insurance reimbursements (تأمين)
/// - Installment payments (أقساط)
/// - Supplier refunds (مرتجعات)
/// - Other sources
/// 
/// These are added to the shift's cash total (similar to sales).
class ShiftCollection extends Equatable {
  final String id;
  final String financialShiftId;
  final String branchId;
  final double amount;
  final CollectionType collectionType;
  final String? customerName;      // اسم العميل
  final String? referenceNumber;   // رقم مرجعي (فاتورة أصلية / رقم تأمين)
  final String? description;
  final String? recordedBy;
  final DateTime createdAt;
  final DateTime? syncedAt;

  const ShiftCollection({
    required this.id,
    required this.financialShiftId,
    required this.branchId,
    required this.amount,
    this.collectionType = CollectionType.creditSale,
    this.customerName,
    this.referenceNumber,
    this.description,
    this.recordedBy,
    required this.createdAt,
    this.syncedAt,
  });

  /// Create from database map
  factory ShiftCollection.fromMap(Map<String, dynamic> map) {
    return ShiftCollection(
      id: map['id'] as String,
      financialShiftId: map['financial_shift_id'] as String,
      branchId: map['branch_id'] as String,
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      collectionType: CollectionType.fromString(
        map['collection_type'] as String? ?? 'credit_sale',
      ),
      customerName: map['customer_name'] as String?,
      referenceNumber: map['reference_number'] as String?,
      description: map['description'] as String?,
      recordedBy: map['recorded_by'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      syncedAt: map['synced_at'] != null 
          ? DateTime.parse(map['synced_at'] as String)
          : null,
    );
  }

  /// Convert to database map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'financial_shift_id': financialShiftId,
      'branch_id': branchId,
      'amount': amount,
      'collection_type': collectionType.value,
      'customer_name': customerName,
      'reference_number': referenceNumber,
      'description': description,
      'recorded_by': recordedBy,
      'created_at': createdAt.toIso8601String(),
      'synced_at': syncedAt?.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  ShiftCollection copyWith({
    String? id,
    String? financialShiftId,
    String? branchId,
    double? amount,
    CollectionType? collectionType,
    String? customerName,
    String? referenceNumber,
    String? description,
    String? recordedBy,
    DateTime? createdAt,
    DateTime? syncedAt,
  }) {
    return ShiftCollection(
      id: id ?? this.id,
      financialShiftId: financialShiftId ?? this.financialShiftId,
      branchId: branchId ?? this.branchId,
      amount: amount ?? this.amount,
      collectionType: collectionType ?? this.collectionType,
      customerName: customerName ?? this.customerName,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      description: description ?? this.description,
      recordedBy: recordedBy ?? this.recordedBy,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  @override
  List<Object?> get props => [
    id, financialShiftId, branchId, amount, collectionType,
    customerName, referenceNumber, description, recordedBy,
    createdAt, syncedAt,
  ];
}
