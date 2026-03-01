import 'package:equatable/equatable.dart';
import '../../core/enums/financial_enums.dart';

/// Represents a transaction with a supplier (purchase or payment)
/// 
/// Tracks all monetary exchanges with suppliers for maintaining
/// accurate accounts payable records and supplier balances.
class SupplierTransaction extends Equatable {
  final String id;
  final String supplierId;
  final String branchId;
  final SupplierTransactionType transactionType;
  final double amount;
  final String? invoiceNumber;
  final DateTime? invoiceDate;
  final DateTime? dueDate;
  final String? paymentMethod;
  final String? referenceNumber;
  final String? notes;
  final String? recordedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? syncedAt;

  const SupplierTransaction({
    required this.id,
    required this.supplierId,
    required this.branchId,
    required this.transactionType,
    required this.amount,
    this.invoiceNumber,
    this.invoiceDate,
    this.dueDate,
    this.paymentMethod,
    this.referenceNumber,
    this.notes,
    this.recordedBy,
    required this.createdAt,
    required this.updatedAt,
    this.syncedAt,
  });

  /// Create from database map
  factory SupplierTransaction.fromMap(Map<String, dynamic> map) {
    return SupplierTransaction(
      id: map['id'] as String,
      supplierId: map['supplier_id'] as String,
      branchId: map['branch_id'] as String,
      transactionType: SupplierTransactionType.fromString(
        map['transaction_type'] as String,
      ),
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      invoiceNumber: map['invoice_number'] as String?,
      invoiceDate: map['invoice_date'] != null 
          ? DateTime.parse(map['invoice_date'] as String)
          : null,
      dueDate: map['due_date'] != null 
          ? DateTime.parse(map['due_date'] as String)
          : null,
      paymentMethod: map['payment_method'] as String?,
      referenceNumber: map['reference_number'] as String?,
      notes: map['notes'] as String?,
      recordedBy: map['recorded_by'] as String?,
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
      'supplier_id': supplierId,
      'branch_id': branchId,
      'transaction_type': transactionType.value,
      'amount': amount,
      'invoice_number': invoiceNumber,
      'invoice_date': invoiceDate?.toIso8601String(),
      'due_date': dueDate?.toIso8601String(),
      'payment_method': paymentMethod,
      'reference_number': referenceNumber,
      'notes': notes,
      'recorded_by': recordedBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'synced_at': syncedAt?.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  SupplierTransaction copyWith({
    String? id,
    String? supplierId,
    String? branchId,
    SupplierTransactionType? transactionType,
    double? amount,
    String? invoiceNumber,
    DateTime? invoiceDate,
    DateTime? dueDate,
    String? paymentMethod,
    String? referenceNumber,
    String? notes,
    String? recordedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? syncedAt,
  }) {
    return SupplierTransaction(
      id: id ?? this.id,
      supplierId: supplierId ?? this.supplierId,
      branchId: branchId ?? this.branchId,
      transactionType: transactionType ?? this.transactionType,
      amount: amount ?? this.amount,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      dueDate: dueDate ?? this.dueDate,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      notes: notes ?? this.notes,
      recordedBy: recordedBy ?? this.recordedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  /// Check if this is a purchase (increases balance owed)
  bool get isPurchase => transactionType == SupplierTransactionType.purchase;

  /// Check if this is a payment (decreases balance owed)
  bool get isPayment => transactionType == SupplierTransactionType.payment;

  /// Check if payment is overdue
  bool get isOverdue {
    if (dueDate == null || isPayment) return false;
    return DateTime.now().isAfter(dueDate!);
  }

  /// Days until due (negative if overdue)
  int? get daysUntilDue {
    if (dueDate == null) return null;
    return dueDate!.difference(DateTime.now()).inDays;
  }

  @override
  List<Object?> get props => [
    id, supplierId, branchId, transactionType, amount, invoiceNumber,
    invoiceDate, dueDate, paymentMethod, referenceNumber, notes,
    recordedBy, createdAt, updatedAt, syncedAt,
  ];
}

/// Transaction type enum
enum SupplierTransactionType {
  purchase('purchase', 'Purchase', 'Purchase from supplier'),
  payment('payment', 'Payment', 'Payment to supplier'),
  returnGoods('return', 'Return', 'Return goods to supplier'),
  adjustment('adjustment', 'Adjustment', 'Balance adjustment');

  final String value;
  final String displayName;
  final String description;

  const SupplierTransactionType(this.value, this.displayName, this.description);

  static SupplierTransactionType fromString(String value) {
    return SupplierTransactionType.values.firstWhere(
      (t) => t.value == value,
      orElse: () => SupplierTransactionType.purchase,
    );
  }
}
