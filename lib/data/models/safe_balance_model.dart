import 'package:equatable/equatable.dart';

/// Represents the pharmacy Safe (Vault) balance
/// 
/// The Safe holds pharmacy capital and accumulated cash across shifts.
/// Key rules:
/// - Safe balance persists across shifts (never resets)
/// - Supplier payments and debt settlements are deducted from Safe
/// - Net shift cash is transferred to Safe on shift close
/// - Drawer is separate and starts at 0 each shift, used only for change
class SafeBalance extends Equatable {
  final String id;
  final String branchId;
  final double balance;
  final DateTime lastUpdatedAt;
  final String? lastUpdatedBy;
  final String? lastTransactionId;
  final DateTime createdAt;
  final DateTime? syncedAt;

  const SafeBalance({
    required this.id,
    required this.branchId,
    required this.balance,
    required this.lastUpdatedAt,
    this.lastUpdatedBy,
    this.lastTransactionId,
    required this.createdAt,
    this.syncedAt,
  });

  /// Create from database map
  factory SafeBalance.fromMap(Map<String, dynamic> map) {
    return SafeBalance(
      id: map['id'] as String,
      branchId: map['branch_id'] as String,
      balance: (map['balance'] as num).toDouble(),
      lastUpdatedAt: DateTime.parse(map['last_updated_at'] as String),
      lastUpdatedBy: map['last_updated_by'] as String?,
      lastTransactionId: map['last_transaction_id'] as String?,
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
      'branch_id': branchId,
      'balance': balance,
      'last_updated_at': lastUpdatedAt.toIso8601String(),
      'last_updated_by': lastUpdatedBy,
      'last_transaction_id': lastTransactionId,
      'created_at': createdAt.toIso8601String(),
      'synced_at': syncedAt?.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  SafeBalance copyWith({
    String? id,
    String? branchId,
    double? balance,
    DateTime? lastUpdatedAt,
    String? lastUpdatedBy,
    String? lastTransactionId,
    DateTime? createdAt,
    DateTime? syncedAt,
  }) {
    return SafeBalance(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      balance: balance ?? this.balance,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      lastUpdatedBy: lastUpdatedBy ?? this.lastUpdatedBy,
      lastTransactionId: lastTransactionId ?? this.lastTransactionId,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  /// Check if safe has sufficient balance for a withdrawal
  bool canWithdraw(double amount) => balance >= amount;

  /// Check if safe is empty
  bool get isEmpty => balance <= 0;

  /// Check if safe has funds
  bool get hasFunds => balance > 0;

  @override
  List<Object?> get props => [
    id, branchId, balance, lastUpdatedAt, lastUpdatedBy,
    lastTransactionId, createdAt, syncedAt,
  ];
}

/// Represents a transaction on the Safe
/// 
/// Tracks all movements into and out of the Safe:
/// - SHIFT_TRANSFER: Net cash transferred from shift closure
/// - SUPPLIER_PAYMENT: Payment to supplier (debit)
/// - DEBT_SETTLEMENT: Payment of customer debt (debit)
/// - DEPOSIT: Manual deposit into safe
/// - WITHDRAWAL: Manual withdrawal from safe
/// - ADJUSTMENT: Administrative adjustment
class SafeTransaction extends Equatable {
  final String id;
  final String branchId;
  final String? financialShiftId;
  final SafeTransactionType transactionType;
  final double amount;
  final double balanceBefore;
  final double balanceAfter;
  final String? referenceId; // e.g., supplier_id, debt_id
  final String? referenceType; // e.g., 'supplier', 'customer_debt'
  final String description;
  final String? recordedBy;
  final String source; // 'kiosk', 'admin', 'system'
  final DateTime createdAt;
  final DateTime? syncedAt;

  const SafeTransaction({
    required this.id,
    required this.branchId,
    this.financialShiftId,
    required this.transactionType,
    required this.amount,
    required this.balanceBefore,
    required this.balanceAfter,
    this.referenceId,
    this.referenceType,
    required this.description,
    this.recordedBy,
    required this.source,
    required this.createdAt,
    this.syncedAt,
  });

  /// Create from database map
  factory SafeTransaction.fromMap(Map<String, dynamic> map) {
    return SafeTransaction(
      id: map['id'] as String,
      branchId: map['branch_id'] as String,
      financialShiftId: map['financial_shift_id'] as String?,
      transactionType: SafeTransactionType.fromString(map['transaction_type'] as String),
      amount: (map['amount'] as num).toDouble(),
      balanceBefore: (map['balance_before'] as num).toDouble(),
      balanceAfter: (map['balance_after'] as num).toDouble(),
      referenceId: map['reference_id'] as String?,
      referenceType: map['reference_type'] as String?,
      description: map['description'] as String,
      recordedBy: map['recorded_by'] as String?,
      source: map['source'] as String? ?? 'system',
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
      'branch_id': branchId,
      'financial_shift_id': financialShiftId,
      'transaction_type': transactionType.value,
      'amount': amount,
      'balance_before': balanceBefore,
      'balance_after': balanceAfter,
      'reference_id': referenceId,
      'reference_type': referenceType,
      'description': description,
      'recorded_by': recordedBy,
      'source': source,
      'created_at': createdAt.toIso8601String(),
      'synced_at': syncedAt?.toIso8601String(),
    };
  }

  /// Check if this is a debit (withdrawal) transaction
  bool get isDebit => transactionType.isDebit;

  /// Check if this is a credit (deposit) transaction
  bool get isCredit => transactionType.isCredit;

  /// Get the signed amount (negative for debits)
  double get signedAmount => isDebit ? -amount.abs() : amount.abs();

  @override
  List<Object?> get props => [
    id, branchId, financialShiftId, transactionType, amount,
    balanceBefore, balanceAfter, referenceId, referenceType,
    description, recordedBy, source, createdAt, syncedAt,
  ];
}

/// Safe transaction types
enum SafeTransactionType {
  shiftTransfer('shift_transfer', 'Shift Transfer', false),
  supplierPayment('supplier_payment', 'Supplier Payment', true),
  debtSettlement('debt_settlement', 'Debt Settlement', true),
  deposit('deposit', 'Deposit', false),
  withdrawal('withdrawal', 'Withdrawal', true),
  adjustment('adjustment', 'Adjustment', false),
  initialBalance('initial_balance', 'Initial Balance', false);

  final String value;
  final String displayName;
  final bool isDebit;

  const SafeTransactionType(this.value, this.displayName, this.isDebit);

  bool get isCredit => !isDebit;

  static SafeTransactionType fromString(String value) {
    return SafeTransactionType.values.firstWhere(
      (t) => t.value == value,
      orElse: () => SafeTransactionType.adjustment,
    );
  }
}

/// Payment source for supplier/debt payments
enum PaymentSource {
  safe('safe', 'Safe (Vault)'),
  drawer('drawer', 'Cash Drawer'); // Not allowed for supplier/debt payments

  final String value;
  final String displayName;

  const PaymentSource(this.value, this.displayName);

  static PaymentSource fromString(String value) {
    return PaymentSource.values.firstWhere(
      (s) => s.value == value,
      orElse: () => PaymentSource.safe,
    );
  }
}
