import 'package:equatable/equatable.dart';

/// Represents the closure/settlement of a financial shift
/// 
/// Records final totals, expected vs actual cash, and any differences.
/// Created when an employee closes their shift and counts the cash drawer.
class ShiftClosure extends Equatable {
  final String id;
  final String financialShiftId;
  final String branchId;
  
  // Sales breakdown by payment method
  final double totalSales;
  final double totalCashSales;
  final double totalCardSales;
  final double totalWalletSales;
  final double totalInsuranceSales;
  final double totalCreditSales;
  
  // Expenses and cash reconciliation
  final double totalExpenses;
  final double expectedCash;
  final double actualCash;
  final double difference;
  final String? differenceReason;
  
  // Accountability
  final String closedBy;
  final String? verifiedBy;
  final String? notes;
  
  final DateTime createdAt;
  final DateTime? syncedAt;

  const ShiftClosure({
    required this.id,
    required this.financialShiftId,
    required this.branchId,
    this.totalSales = 0,
    this.totalCashSales = 0,
    this.totalCardSales = 0,
    this.totalWalletSales = 0,
    this.totalInsuranceSales = 0,
    this.totalCreditSales = 0,
    this.totalExpenses = 0,
    this.expectedCash = 0,
    required this.actualCash,
    this.difference = 0,
    this.differenceReason,
    required this.closedBy,
    this.verifiedBy,
    this.notes,
    required this.createdAt,
    this.syncedAt,
  });

  /// Create from database map
  factory ShiftClosure.fromMap(Map<String, dynamic> map) {
    return ShiftClosure(
      id: map['id'] as String,
      financialShiftId: map['financial_shift_id'] as String,
      branchId: map['branch_id'] as String,
      totalSales: (map['total_sales'] as num?)?.toDouble() ?? 0,
      totalCashSales: (map['total_cash_sales'] as num?)?.toDouble() ?? 0,
      totalCardSales: (map['total_card_sales'] as num?)?.toDouble() ?? 0,
      totalWalletSales: (map['total_wallet_sales'] as num?)?.toDouble() ?? 0,
      totalInsuranceSales: (map['total_insurance_sales'] as num?)?.toDouble() ?? 0,
      totalCreditSales: (map['total_credit_sales'] as num?)?.toDouble() ?? 0,
      totalExpenses: (map['total_expenses'] as num?)?.toDouble() ?? 0,
      expectedCash: (map['expected_cash'] as num?)?.toDouble() ?? 0,
      actualCash: (map['actual_cash'] as num).toDouble(),
      difference: (map['difference'] as num?)?.toDouble() ?? 0,
      differenceReason: map['difference_reason'] as String?,
      closedBy: map['closed_by'] as String,
      verifiedBy: map['verified_by'] as String?,
      notes: map['notes'] as String?,
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
      'total_sales': totalSales,
      'total_cash_sales': totalCashSales,
      'total_card_sales': totalCardSales,
      'total_wallet_sales': totalWalletSales,
      'total_insurance_sales': totalInsuranceSales,
      'total_credit_sales': totalCreditSales,
      'total_expenses': totalExpenses,
      'expected_cash': expectedCash,
      'actual_cash': actualCash,
      'difference': difference,
      'difference_reason': differenceReason,
      'closed_by': closedBy,
      'verified_by': verifiedBy,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'synced_at': syncedAt?.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  ShiftClosure copyWith({
    String? id,
    String? financialShiftId,
    String? branchId,
    double? totalSales,
    double? totalCashSales,
    double? totalCardSales,
    double? totalWalletSales,
    double? totalInsuranceSales,
    double? totalCreditSales,
    double? totalExpenses,
    double? expectedCash,
    double? actualCash,
    double? difference,
    String? differenceReason,
    String? closedBy,
    String? verifiedBy,
    String? notes,
    DateTime? createdAt,
    DateTime? syncedAt,
  }) {
    return ShiftClosure(
      id: id ?? this.id,
      financialShiftId: financialShiftId ?? this.financialShiftId,
      branchId: branchId ?? this.branchId,
      totalSales: totalSales ?? this.totalSales,
      totalCashSales: totalCashSales ?? this.totalCashSales,
      totalCardSales: totalCardSales ?? this.totalCardSales,
      totalWalletSales: totalWalletSales ?? this.totalWalletSales,
      totalInsuranceSales: totalInsuranceSales ?? this.totalInsuranceSales,
      totalCreditSales: totalCreditSales ?? this.totalCreditSales,
      totalExpenses: totalExpenses ?? this.totalExpenses,
      expectedCash: expectedCash ?? this.expectedCash,
      actualCash: actualCash ?? this.actualCash,
      difference: difference ?? this.difference,
      differenceReason: differenceReason ?? this.differenceReason,
      closedBy: closedBy ?? this.closedBy,
      verifiedBy: verifiedBy ?? this.verifiedBy,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  /// Calculate expected cash based on opening cash + cash sales - expenses
  static double calculateExpectedCash({
    required double openingCash,
    required double cashSales,
    required double expenses,
  }) {
    return openingCash + cashSales - expenses;
  }

  /// Check if there's a shortage (negative difference)
  bool get hasShortage => difference < 0;

  /// Check if there's an overage (positive difference)
  bool get hasOverage => difference > 0;

  /// Check if cash matches expected
  bool get isBalanced => difference == 0;

  /// Get absolute difference value
  double get absoluteDifference => difference.abs();

  /// Net profit from shift (sales - expenses)
  double get netProfit => totalSales - totalExpenses;

  @override
  List<Object?> get props => [
    id, financialShiftId, branchId, totalSales, totalCashSales,
    totalCardSales, totalWalletSales, totalInsuranceSales, totalCreditSales,
    totalExpenses, expectedCash, actualCash, difference, differenceReason,
    closedBy, verifiedBy, notes, createdAt, syncedAt,
  ];
}
