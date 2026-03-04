/// ⚠️ DOMAIN CONTRACT - FINANCIAL ENUMS
/// 
/// SINGLE SOURCE OF TRUTH for all financial enums.
/// Do not rename enum values without migration.
/// Do not move this file.
/// All financial modules must import from this file.

// =============================================================================
// PAYMENT METHOD ENUM
// =============================================================================

/// Payment methods accepted for sales transactions
enum PaymentMethod {
  cash,
  card,
  wallet,
  insurance,
  credit;

  /// Alias for card (backwards compatibility)
  static PaymentMethod get visa => card;

  /// Parse from database string with legacy value support
  static PaymentMethod fromString(String value) {
    switch (value.toLowerCase()) {
      case 'cash':
        return PaymentMethod.cash;
      case 'card':
      case 'visa': // Legacy support
        return PaymentMethod.card;
      case 'wallet':
        return PaymentMethod.wallet;
      case 'insurance':
        return PaymentMethod.insurance;
      case 'credit':
        return PaymentMethod.credit;
      default:
        return PaymentMethod.cash;
    }
  }
}

extension PaymentMethodExtension on PaymentMethod {
  /// Human-readable display name for UI
  String get displayName {
    switch (this) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.card:
        return 'Visa/Card';
      case PaymentMethod.wallet:
        return 'E-Wallet';
      case PaymentMethod.insurance:
        return 'Insurance';
      case PaymentMethod.credit:
        return 'Credit/Deferred';
    }
  }

  /// Database storage value
  String get value {
    switch (this) {
      case PaymentMethod.cash:
        return 'cash';
      case PaymentMethod.card:
        return 'card';
      case PaymentMethod.wallet:
        return 'wallet';
      case PaymentMethod.insurance:
        return 'insurance';
      case PaymentMethod.credit:
        return 'credit';
    }
  }
}

// =============================================================================
// EXPENSE CATEGORY ENUM
// =============================================================================

/// Categories for expense classification
enum ExpenseCategory {
  utilities,
  shortage,
  emergency,
  supplies,
  maintenance,
  transport,
  misc;

  /// Alias for transport (backwards compatibility)
  static ExpenseCategory get transportation => transport;

  /// Parse from database string with legacy value support
  static ExpenseCategory fromString(String value) {
    switch (value.toLowerCase()) {
      case 'utilities':
        return ExpenseCategory.utilities;
      case 'shortage':
        return ExpenseCategory.shortage;
      case 'emergency':
        return ExpenseCategory.emergency;
      case 'supplies':
        return ExpenseCategory.supplies;
      case 'maintenance':
        return ExpenseCategory.maintenance;
      case 'transport':
      case 'transportation': // Legacy support
        return ExpenseCategory.transport;
      case 'misc':
      case 'miscellaneous': // Legacy support
        return ExpenseCategory.misc;
      default:
        return ExpenseCategory.misc;
    }
  }
}

extension ExpenseCategoryExtension on ExpenseCategory {
  /// Human-readable display name for UI
  String get displayName {
    switch (this) {
      case ExpenseCategory.utilities:
        return 'Utilities';
      case ExpenseCategory.shortage:
        return 'Shortage/Deficit';
      case ExpenseCategory.emergency:
        return 'Emergency';
      case ExpenseCategory.supplies:
        return 'Supplies';
      case ExpenseCategory.maintenance:
        return 'Maintenance';
      case ExpenseCategory.transport:
        return 'Transportation';
      case ExpenseCategory.misc:
        return 'Miscellaneous';
    }
  }

  /// Database storage value
  String get value {
    switch (this) {
      case ExpenseCategory.utilities:
        return 'utilities';
      case ExpenseCategory.shortage:
        return 'shortage';
      case ExpenseCategory.emergency:
        return 'emergency';
      case ExpenseCategory.supplies:
        return 'supplies';
      case ExpenseCategory.maintenance:
        return 'maintenance';
      case ExpenseCategory.transport:
        return 'transport';
      case ExpenseCategory.misc:
        return 'misc';
    }
  }
}

// =============================================================================
// SUPPLIER TRANSACTION TYPE ENUM
// =============================================================================

/// Types of transactions with suppliers
enum SupplierTransactionType {
  purchase,
  payment,
  refund,
  adjustment;

  /// Parse from database string with legacy value support
  static SupplierTransactionType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'purchase':
        return SupplierTransactionType.purchase;
      case 'payment':
        return SupplierTransactionType.payment;
      case 'refund':
      case 'return': // Legacy support
      case 'returngoods': // Legacy support
        return SupplierTransactionType.refund;
      case 'adjustment':
        return SupplierTransactionType.adjustment;
      default:
        return SupplierTransactionType.purchase;
    }
  }
}

extension SupplierTransactionTypeExtension on SupplierTransactionType {
  String get displayName {
    switch (this) {
      case SupplierTransactionType.purchase:
        return 'Purchase';
      case SupplierTransactionType.payment:
        return 'Payment';
      case SupplierTransactionType.refund:
        return 'Refund';
      case SupplierTransactionType.adjustment:
        return 'Adjustment';
    }
  }

  String get value {
    switch (this) {
      case SupplierTransactionType.purchase:
        return 'purchase';
      case SupplierTransactionType.payment:
        return 'payment';
      case SupplierTransactionType.refund:
        return 'refund';
      case SupplierTransactionType.adjustment:
        return 'adjustment';
    }
  }

  /// Returns true if this transaction increases supplier balance (we owe them)
  bool get increasesBalance => this == SupplierTransactionType.purchase;

  /// Returns true if this transaction decreases supplier balance (we paid them)
  bool get decreasesBalance =>
      this == SupplierTransactionType.payment ||
      this == SupplierTransactionType.refund;
}

// =============================================================================
// FINANCIAL SHIFT STATUS ENUM
// =============================================================================

/// Status of a financial shift
enum FinancialShiftStatus {
  open('open', 'Open'),
  closed('closed', 'Closed'),
  cancelled('cancelled', 'Cancelled');

  final String value;
  final String displayName;

  const FinancialShiftStatus(this.value, this.displayName);

  static FinancialShiftStatus fromString(String value) {
    return FinancialShiftStatus.values.firstWhere(
      (s) => s.value == value.toLowerCase(),
      orElse: () => FinancialShiftStatus.open,
    );
  }
}
