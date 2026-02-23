import 'package:uuid/uuid.dart';
import '../../data/models/safe_balance_model.dart';
import '../../data/repositories/safe_repository.dart';
import 'logging_service.dart';

/// Safe (Vault) Service - Manages pharmacy capital across shifts
/// 
/// SINGLE-BRANCH ARCHITECTURE: All operations use hardcoded branch_id = '1'
/// 
/// Key concepts:
/// - Safe: Holds pharmacy capital and accumulated cash across shifts
/// - Drawer: Starts at 0 each shift, used only for change, resets on close
/// - Cash sales go to Drawer during shift, then transfer to Safe on close
/// - Supplier payments and debt settlements come from Safe, never Drawer
class SafeService {
  static final SafeService _instance = SafeService._();
  static SafeService get instance => _instance;
  
  final _safeBalanceRepo = SafeBalanceRepository.instance;
  final _safeTransactionRepo = SafeTransactionRepository.instance;
  final _uuid = const Uuid();
  
  SafeService._();

  // =========================================================================
  // BALANCE OPERATIONS
  // =========================================================================

  /// Get current Safe balance for the branch
  Future<double> getCurrentBalance([String branchId = '1']) async {
    return _safeBalanceRepo.getCurrentBalance(branchId);
  }

  /// Get Safe balance details
  Future<SafeBalance> getSafeBalance([String branchId = '1']) async {
    return _safeBalanceRepo.getOrCreateForBranch(branchId);
  }

  /// Check if Safe has sufficient funds for a withdrawal
  Future<bool> hasSufficientFunds(double amount, [String branchId = '1']) async {
    final balance = await getCurrentBalance(branchId);
    return balance >= amount;
  }

  // =========================================================================
  // SHIFT TRANSFER OPERATIONS
  // =========================================================================

  /// Transfer net cash from shift to Safe on shift close
  /// 
  /// This is called when closing a financial shift:
  /// 1. Records the transfer as a Safe transaction
  /// 2. Updates the Safe balance
  /// 3. Returns updated balance
  /// 
  /// Net cash = Actual cash in drawer (after reconciliation)
  Future<SafeTransferResult> transferFromShift({
    required String financialShiftId,
    required double amount,
    required String employeeId,
    String source = 'system',
    String branchId = '1',
  }) async {
    if (amount <= 0) {
      // Zero or negative transfer - just return current balance
      final safe = await getSafeBalance(branchId);
      return SafeTransferResult(
        success: true,
        balanceBefore: safe.balance,
        balanceAfter: safe.balance,
        transferredAmount: 0,
        transactionId: null,
      );
    }

    final safe = await getSafeBalance(branchId);
    final balanceBefore = safe.balance;
    final balanceAfter = balanceBefore + amount;
    final transactionId = _uuid.v4();
    final now = DateTime.now();

    // Record the transaction
    final transaction = SafeTransaction(
      id: transactionId,
      branchId: branchId,
      financialShiftId: financialShiftId,
      transactionType: SafeTransactionType.shiftTransfer,
      amount: amount,
      balanceBefore: balanceBefore,
      balanceAfter: balanceAfter,
      description: 'Shift closure transfer - Net cash from shift $financialShiftId',
      recordedBy: employeeId,
      source: source,
      createdAt: now,
    );

    await _safeTransactionRepo.insert(transaction);
    
    // Update Safe balance
    await _safeBalanceRepo.updateBalance(
      branchId: branchId,
      newBalance: balanceAfter,
      updatedBy: employeeId,
      transactionId: transactionId,
    );

    LoggingService.instance.info(
      'SafeService',
      'Transferred $amount from shift $financialShiftId to Safe. '
      'Balance: $balanceBefore → $balanceAfter',
    );

    return SafeTransferResult(
      success: true,
      balanceBefore: balanceBefore,
      balanceAfter: balanceAfter,
      transferredAmount: amount,
      transactionId: transactionId,
    );
  }

  // =========================================================================
  // SUPPLIER PAYMENT OPERATIONS
  // =========================================================================

  /// Pay supplier from Safe
  /// 
  /// All supplier payments must come from Safe, never Drawer.
  /// Throws SafeInsufficientFundsException if insufficient balance.
  Future<SafePaymentResult> paySupplier({
    required String supplierId,
    required double amount,
    required String description,
    String? financialShiftId,
    required String employeeId,
    String source = 'admin',
    String branchId = '1',
  }) async {
    if (amount <= 0) {
      throw SafePaymentException(
        'Payment amount must be positive',
        code: 'INVALID_AMOUNT',
      );
    }

    final safe = await getSafeBalance(branchId);
    
    if (safe.balance < amount) {
      throw SafeInsufficientFundsException(
        'Insufficient Safe balance for supplier payment. '
        'Available: ${safe.balance}, Required: $amount',
        available: safe.balance,
        required: amount,
      );
    }

    final balanceBefore = safe.balance;
    final balanceAfter = balanceBefore - amount;
    final transactionId = _uuid.v4();
    final now = DateTime.now();

    // Record the transaction
    final transaction = SafeTransaction(
      id: transactionId,
      branchId: branchId,
      financialShiftId: financialShiftId,
      transactionType: SafeTransactionType.supplierPayment,
      amount: amount,
      balanceBefore: balanceBefore,
      balanceAfter: balanceAfter,
      referenceId: supplierId,
      referenceType: 'supplier',
      description: description,
      recordedBy: employeeId,
      source: source,
      createdAt: now,
    );

    await _safeTransactionRepo.insert(transaction);
    
    // Update Safe balance
    await _safeBalanceRepo.updateBalance(
      branchId: branchId,
      newBalance: balanceAfter,
      updatedBy: employeeId,
      transactionId: transactionId,
    );

    LoggingService.instance.info(
      'SafeService',
      'Paid supplier $supplierId: $amount from Safe. '
      'Balance: $balanceBefore → $balanceAfter',
    );

    return SafePaymentResult(
      success: true,
      balanceBefore: balanceBefore,
      balanceAfter: balanceAfter,
      paidAmount: amount,
      transactionId: transactionId,
      paymentSource: PaymentSource.safe,
    );
  }

  // =========================================================================
  // DEBT SETTLEMENT OPERATIONS
  // =========================================================================

  /// Settle customer debt from Safe
  /// 
  /// Used when the pharmacy needs to return money or settle debts.
  /// All debt settlements must come from Safe, never Drawer.
  Future<SafePaymentResult> settleDebt({
    required String debtId,
    required double amount,
    required String description,
    String? financialShiftId,
    required String employeeId,
    String source = 'admin',
    String branchId = '1',
  }) async {
    if (amount <= 0) {
      throw SafePaymentException(
        'Settlement amount must be positive',
        code: 'INVALID_AMOUNT',
      );
    }

    final safe = await getSafeBalance(branchId);
    
    if (safe.balance < amount) {
      throw SafeInsufficientFundsException(
        'Insufficient Safe balance for debt settlement. '
        'Available: ${safe.balance}, Required: $amount',
        available: safe.balance,
        required: amount,
      );
    }

    final balanceBefore = safe.balance;
    final balanceAfter = balanceBefore - amount;
    final transactionId = _uuid.v4();
    final now = DateTime.now();

    // Record the transaction
    final transaction = SafeTransaction(
      id: transactionId,
      branchId: branchId,
      financialShiftId: financialShiftId,
      transactionType: SafeTransactionType.debtSettlement,
      amount: amount,
      balanceBefore: balanceBefore,
      balanceAfter: balanceAfter,
      referenceId: debtId,
      referenceType: 'customer_debt',
      description: description,
      recordedBy: employeeId,
      source: source,
      createdAt: now,
    );

    await _safeTransactionRepo.insert(transaction);
    
    // Update Safe balance
    await _safeBalanceRepo.updateBalance(
      branchId: branchId,
      newBalance: balanceAfter,
      updatedBy: employeeId,
      transactionId: transactionId,
    );

    LoggingService.instance.info(
      'SafeService',
      'Settled debt $debtId: $amount from Safe. '
      'Balance: $balanceBefore → $balanceAfter',
    );

    return SafePaymentResult(
      success: true,
      balanceBefore: balanceBefore,
      balanceAfter: balanceAfter,
      paidAmount: amount,
      transactionId: transactionId,
      paymentSource: PaymentSource.safe,
    );
  }

  // =========================================================================
  // MANUAL OPERATIONS (Admin only)
  // =========================================================================

  /// Deposit cash into Safe (manual deposit by admin)
  Future<SafeTransferResult> deposit({
    required double amount,
    required String description,
    required String employeeId,
    String source = 'admin',
    String branchId = '1',
  }) async {
    if (amount <= 0) {
      throw SafePaymentException(
        'Deposit amount must be positive',
        code: 'INVALID_AMOUNT',
      );
    }

    final safe = await getSafeBalance(branchId);
    final balanceBefore = safe.balance;
    final balanceAfter = balanceBefore + amount;
    final transactionId = _uuid.v4();
    final now = DateTime.now();

    // Record the transaction
    final transaction = SafeTransaction(
      id: transactionId,
      branchId: branchId,
      transactionType: SafeTransactionType.deposit,
      amount: amount,
      balanceBefore: balanceBefore,
      balanceAfter: balanceAfter,
      description: description,
      recordedBy: employeeId,
      source: source,
      createdAt: now,
    );

    await _safeTransactionRepo.insert(transaction);
    
    // Update Safe balance
    await _safeBalanceRepo.updateBalance(
      branchId: branchId,
      newBalance: balanceAfter,
      updatedBy: employeeId,
      transactionId: transactionId,
    );

    LoggingService.instance.info(
      'SafeService',
      'Manual deposit: $amount to Safe. Balance: $balanceBefore → $balanceAfter',
    );

    return SafeTransferResult(
      success: true,
      balanceBefore: balanceBefore,
      balanceAfter: balanceAfter,
      transferredAmount: amount,
      transactionId: transactionId,
    );
  }

  /// Withdraw cash from Safe (manual withdrawal by admin)
  Future<SafeTransferResult> withdraw({
    required double amount,
    required String description,
    required String employeeId,
    String source = 'admin',
    String branchId = '1',
  }) async {
    if (amount <= 0) {
      throw SafePaymentException(
        'Withdrawal amount must be positive',
        code: 'INVALID_AMOUNT',
      );
    }

    final safe = await getSafeBalance(branchId);
    
    if (safe.balance < amount) {
      throw SafeInsufficientFundsException(
        'Insufficient Safe balance for withdrawal. '
        'Available: ${safe.balance}, Required: $amount',
        available: safe.balance,
        required: amount,
      );
    }

    final balanceBefore = safe.balance;
    final balanceAfter = balanceBefore - amount;
    final transactionId = _uuid.v4();
    final now = DateTime.now();

    // Record the transaction
    final transaction = SafeTransaction(
      id: transactionId,
      branchId: branchId,
      transactionType: SafeTransactionType.withdrawal,
      amount: amount,
      balanceBefore: balanceBefore,
      balanceAfter: balanceAfter,
      description: description,
      recordedBy: employeeId,
      source: source,
      createdAt: now,
    );

    await _safeTransactionRepo.insert(transaction);
    
    // Update Safe balance
    await _safeBalanceRepo.updateBalance(
      branchId: branchId,
      newBalance: balanceAfter,
      updatedBy: employeeId,
      transactionId: transactionId,
    );

    LoggingService.instance.info(
      'SafeService',
      'Manual withdrawal: $amount from Safe. Balance: $balanceBefore → $balanceAfter',
    );

    return SafeTransferResult(
      success: true,
      balanceBefore: balanceBefore,
      balanceAfter: balanceAfter,
      transferredAmount: amount,
      transactionId: transactionId,
    );
  }

  /// Set initial Safe balance (first-time setup)
  Future<SafeTransferResult> setInitialBalance({
    required double amount,
    required String employeeId,
    String source = 'admin',
    String branchId = '1',
  }) async {
    final safe = await getSafeBalance(branchId);
    
    if (safe.balance > 0) {
      throw SafePaymentException(
        'Safe already has a balance. Use deposit for additions.',
        code: 'BALANCE_EXISTS',
      );
    }

    final transactionId = _uuid.v4();
    final now = DateTime.now();

    // Record the transaction
    final transaction = SafeTransaction(
      id: transactionId,
      branchId: branchId,
      transactionType: SafeTransactionType.initialBalance,
      amount: amount,
      balanceBefore: 0,
      balanceAfter: amount,
      description: 'Initial Safe balance setup',
      recordedBy: employeeId,
      source: source,
      createdAt: now,
    );

    await _safeTransactionRepo.insert(transaction);
    
    // Update Safe balance
    await _safeBalanceRepo.updateBalance(
      branchId: branchId,
      newBalance: amount,
      updatedBy: employeeId,
      transactionId: transactionId,
    );

    LoggingService.instance.info(
      'SafeService',
      'Set initial Safe balance: $amount',
    );

    return SafeTransferResult(
      success: true,
      balanceBefore: 0,
      balanceAfter: amount,
      transferredAmount: amount,
      transactionId: transactionId,
    );
  }

  // =========================================================================
  // TRANSACTION HISTORY
  // =========================================================================

  /// Get recent Safe transactions
  Future<List<SafeTransaction>> getRecentTransactions({
    int limit = 50,
    String branchId = '1',
  }) async {
    return _safeTransactionRepo.getByBranch(branchId, limit: limit);
  }

  /// Get transactions for a specific shift
  Future<List<SafeTransaction>> getShiftTransactions(String financialShiftId) async {
    return _safeTransactionRepo.getByFinancialShift(financialShiftId);
  }

  /// Get transactions for a date range
  Future<List<SafeTransaction>> getTransactionsByDateRange({
    required DateTime fromDate,
    required DateTime toDate,
    String branchId = '1',
  }) async {
    return _safeTransactionRepo.getByBranch(
      branchId,
      fromDate: fromDate,
      toDate: toDate,
    );
  }

  /// Get total supplier payments during a period
  Future<double> getTotalSupplierPayments({
    required DateTime fromDate,
    required DateTime toDate,
    String branchId = '1',
  }) async {
    return _safeTransactionRepo.getTotalDebits(branchId, fromDate, toDate);
  }

  /// Get total shift transfers during a period
  Future<double> getTotalShiftTransfers({
    required DateTime fromDate,
    required DateTime toDate,
    String branchId = '1',
  }) async {
    return _safeTransactionRepo.getTotalCredits(branchId, fromDate, toDate);
  }
}

/// Result of a Safe transfer operation
class SafeTransferResult {
  final bool success;
  final double balanceBefore;
  final double balanceAfter;
  final double transferredAmount;
  final String? transactionId;
  final String? errorMessage;

  SafeTransferResult({
    required this.success,
    required this.balanceBefore,
    required this.balanceAfter,
    required this.transferredAmount,
    this.transactionId,
    this.errorMessage,
  });

  double get balanceChange => balanceAfter - balanceBefore;
}

/// Result of a Safe payment operation
class SafePaymentResult {
  final bool success;
  final double balanceBefore;
  final double balanceAfter;
  final double paidAmount;
  final String? transactionId;
  final PaymentSource paymentSource;
  final String? errorMessage;

  SafePaymentResult({
    required this.success,
    required this.balanceBefore,
    required this.balanceAfter,
    required this.paidAmount,
    this.transactionId,
    required this.paymentSource,
    this.errorMessage,
  });

  double get balanceChange => balanceAfter - balanceBefore;
}

/// Exception for Safe payment operations
class SafePaymentException implements Exception {
  final String message;
  final String? code;

  SafePaymentException(this.message, {this.code});

  @override
  String toString() => 'SafePaymentException: $message${code != null ? ' [$code]' : ''}';
}
