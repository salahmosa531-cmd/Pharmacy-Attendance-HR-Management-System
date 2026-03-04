import 'package:equatable/equatable.dart';
import '../../core/enums/financial_enums.dart';

/// Represents an expense during a financial shift
/// 
/// Records expenses with category classification for tracking
/// utilities, shortages, purchases, and other operational costs.
class ShiftExpense extends Equatable {
  final String id;
  final String financialShiftId;
  final String branchId;
  final double amount;
  final ExpenseCategory category;
  final String description;
  final String? receiptNumber;
  final String? recordedBy;
  final String? approvedBy;
  final DateTime createdAt;
  final DateTime? syncedAt;

  const ShiftExpense({
    required this.id,
    required this.financialShiftId,
    required this.branchId,
    required this.amount,
    this.category = ExpenseCategory.misc,
    required this.description,
    this.receiptNumber,
    this.recordedBy,
    this.approvedBy,
    required this.createdAt,
    this.syncedAt,
  });

  /// Create from database map
  factory ShiftExpense.fromMap(Map<String, dynamic> map) {
    return ShiftExpense(
      id: map['id'] as String,
      financialShiftId: map['financial_shift_id'] as String,
      branchId: map['branch_id'] as String,
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      category: ExpenseCategory.fromString(map['category'] as String? ?? 'misc'),
      description: map['description'] as String? ?? '',
      receiptNumber: map['receipt_number'] as String?,
      recordedBy: map['recorded_by'] as String?,
      approvedBy: map['approved_by'] as String?,
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
      'category': category.value,
      'description': description,
      'receipt_number': receiptNumber,
      'recorded_by': recordedBy,
      'approved_by': approvedBy,
      'created_at': createdAt.toIso8601String(),
      'synced_at': syncedAt?.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  ShiftExpense copyWith({
    String? id,
    String? financialShiftId,
    String? branchId,
    double? amount,
    ExpenseCategory? category,
    String? description,
    String? receiptNumber,
    String? recordedBy,
    String? approvedBy,
    DateTime? createdAt,
    DateTime? syncedAt,
  }) {
    return ShiftExpense(
      id: id ?? this.id,
      financialShiftId: financialShiftId ?? this.financialShiftId,
      branchId: branchId ?? this.branchId,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      description: description ?? this.description,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      recordedBy: recordedBy ?? this.recordedBy,
      approvedBy: approvedBy ?? this.approvedBy,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  @override
  List<Object?> get props => [
    id, financialShiftId, branchId, amount, category,
    description, receiptNumber, recordedBy, approvedBy,
    createdAt, syncedAt,
  ];
}
