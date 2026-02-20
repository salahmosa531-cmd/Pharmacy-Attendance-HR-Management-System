import 'package:uuid/uuid.dart';
import '../../data/models/financial_shift_model.dart';
import '../../data/models/shift_sale_model.dart';
import '../../data/models/shift_expense_model.dart';
import '../../data/models/shift_closure_model.dart';
import '../../data/repositories/financial_shift_repository.dart';
import '../../data/repositories/shift_sale_repository.dart';
import '../../data/repositories/shift_expense_repository.dart';
import '../../data/repositories/shift_closure_repository.dart';
import '../../data/repositories/supplier_transaction_repository.dart';
import '../../data/models/supplier_transaction_model.dart';
import 'logging_service.dart';
import 'employee_resolver_service.dart';

/// Financial Service - Orchestrates all shift-level financial operations
/// 
/// SINGLE-BRANCH ARCHITECTURE: All operations use hardcoded branch_id = '1'
/// Branch context validation has been removed for offline-first single-branch mode.
/// 
/// Handles:
/// - Opening/closing financial shifts
/// - Recording sales and expenses
/// - Calculating expected vs actual cash
/// - Generating financial reports
class FinancialService {
  static final FinancialService _instance = FinancialService._();
  static FinancialService get instance => _instance;
  
  final _financialShiftRepo = FinancialShiftRepository.instance;
  final _shiftSaleRepo = ShiftSaleRepository.instance;
  final _shiftExpenseRepo = ShiftExpenseRepository.instance;
  final _shiftClosureRepo = ShiftClosureRepository.instance;
  final _supplierTransactionRepo = SupplierTransactionRepository.instance;
  final _employeeResolver = EmployeeResolverService.instance;
  final _uuid = const Uuid();
  
  FinancialService._();

  // =========================================================================
  // FINANCIAL SHIFT OPERATIONS
  // =========================================================================

  /// Open a new financial shift
  /// 
  /// Throws if employee already has an open shift
  Future<FinancialShift> openShift({
    required String employeeId,
    String? shiftId,
    double openingCash = 0,
    String? notes,
  }) async {
    // Check for existing open shift
    final existingShift = await _financialShiftRepo.getOpenShiftForEmployee(employeeId);
    if (existingShift != null) {
      throw FinancialException(
        'Employee already has an open shift. Please close it first.',
        code: 'SHIFT_ALREADY_OPEN',
      );
    }

    final now = DateTime.now();
    final financialShift = FinancialShift(
      id: _uuid.v4(),
      branchId: '1', // SINGLE-BRANCH: Hardcoded
      shiftId: shiftId,
      employeeId: employeeId,
      openedAt: now,
      openingCash: openingCash,
      status: FinancialShiftStatus.open,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );

    await _financialShiftRepo.insert(financialShift);
    LoggingService.instance.info(
      'FinancialService',
      'Opened financial shift: ${financialShift.id} for employee: $employeeId',
    );

    return financialShift;
  }

  /// Get currently open shift for employee
  Future<FinancialShift?> getOpenShiftForEmployee(String employeeId) async {
    return _financialShiftRepo.getOpenShiftForEmployee(employeeId);
  }

  /// Get all open shifts for the branch
  Future<List<FinancialShift>> getOpenShiftsForBranch() async {
    return _financialShiftRepo.getOpenShiftsForBranch();
  }

  /// Get financial shift by ID
  Future<FinancialShift?> getFinancialShift(String shiftId) async {
    return _financialShiftRepo.getById(shiftId);
  }

  // =========================================================================
  // SALES OPERATIONS
  // =========================================================================

  /// Record a sale
  Future<ShiftSale> recordSale({
    required String financialShiftId,
    required double amount,
    PaymentMethod paymentMethod = PaymentMethod.cash,
    String? description,
    String? invoiceNumber,
    String? customerName,
    String? recordedBy,
  }) async {
    // Verify shift is open
    final shift = await _financialShiftRepo.getById(financialShiftId);
    if (shift == null) {
      throw FinancialException(
        'Financial shift not found',
        code: 'SHIFT_NOT_FOUND',
      );
    }
    if (!shift.isOpen) {
      throw FinancialException(
        'Cannot record sale on closed shift',
        code: 'SHIFT_CLOSED',
      );
    }

    final sale = ShiftSale(
      id: _uuid.v4(),
      financialShiftId: financialShiftId,
      branchId: '1', // SINGLE-BRANCH: Hardcoded
      amount: amount,
      paymentMethod: paymentMethod,
      description: description,
      invoiceNumber: invoiceNumber,
      customerName: customerName,
      recordedBy: recordedBy,
      createdAt: DateTime.now(),
    );

    await _shiftSaleRepo.insert(sale);
    LoggingService.instance.info(
      'FinancialService',
      'Recorded sale: ${sale.id}, amount: $amount, method: ${paymentMethod.value}',
    );

    return sale;
  }

  /// Get sales for a financial shift
  Future<List<ShiftSale>> getSalesForShift(String financialShiftId) async {
    return _shiftSaleRepo.getByFinancialShift(financialShiftId);
  }

  /// Get total sales for a shift
  Future<double> getTotalSalesForShift(String financialShiftId) async {
    return _shiftSaleRepo.getTotalSalesForShift(financialShiftId);
  }

  /// Get sales breakdown by payment method
  Future<Map<PaymentMethod, double>> getSalesBreakdown(String financialShiftId) async {
    return _shiftSaleRepo.getSalesByPaymentMethod(financialShiftId);
  }

  // =========================================================================
  // EXPENSE OPERATIONS
  // =========================================================================

  /// Record an expense
  Future<ShiftExpense> recordExpense({
    required String financialShiftId,
    required double amount,
    required String description,
    ExpenseCategory category = ExpenseCategory.misc,
    String? receiptNumber,
    String? recordedBy,
    String? approvedBy,
  }) async {
    // Verify shift is open
    final shift = await _financialShiftRepo.getById(financialShiftId);
    if (shift == null) {
      throw FinancialException(
        'Financial shift not found',
        code: 'SHIFT_NOT_FOUND',
      );
    }
    if (!shift.isOpen) {
      throw FinancialException(
        'Cannot record expense on closed shift',
        code: 'SHIFT_CLOSED',
      );
    }

    final expense = ShiftExpense(
      id: _uuid.v4(),
      financialShiftId: financialShiftId,
      branchId: '1', // SINGLE-BRANCH: Hardcoded
      amount: amount,
      category: category,
      description: description,
      receiptNumber: receiptNumber,
      recordedBy: recordedBy,
      approvedBy: approvedBy,
      createdAt: DateTime.now(),
    );

    await _shiftExpenseRepo.insert(expense);
    LoggingService.instance.info(
      'FinancialService',
      'Recorded expense: ${expense.id}, amount: $amount, category: ${category.value}',
    );

    return expense;
  }

  /// Get expenses for a financial shift
  Future<List<ShiftExpense>> getExpensesForShift(String financialShiftId) async {
    return _shiftExpenseRepo.getByFinancialShift(financialShiftId);
  }

  /// Get total expenses for a shift
  Future<double> getTotalExpensesForShift(String financialShiftId) async {
    return _shiftExpenseRepo.getTotalExpensesForShift(financialShiftId);
  }

  /// Get expenses breakdown by category
  Future<Map<ExpenseCategory, double>> getExpensesBreakdown(String financialShiftId) async {
    return _shiftExpenseRepo.getExpensesByCategory(financialShiftId);
  }

  // =========================================================================
  // SHIFT CLOSING OPERATIONS
  // =========================================================================

  /// Close a financial shift with cash count
  /// 
  /// This is the critical operation that:
  /// 1. Calculates expected cash (opening + cash sales - expenses)
  /// 2. Records actual cash count
  /// 3. Calculates difference (shortage or overage)
  /// 4. Requires reason if there's a difference
  Future<ShiftClosure> closeShift({
    required String financialShiftId,
    required double actualCash,
    required String closedBy,
    String? differenceReason,
    String? verifiedBy,
    String? notes,
  }) async {
    // Get and verify the shift
    final shift = await _financialShiftRepo.getById(financialShiftId);
    if (shift == null) {
      throw FinancialException(
        'Financial shift not found',
        code: 'SHIFT_NOT_FOUND',
      );
    }
    if (!shift.isOpen) {
      throw FinancialException(
        'Shift is already closed',
        code: 'SHIFT_ALREADY_CLOSED',
      );
    }

    // Calculate totals
    final salesByMethod = await getSalesBreakdown(financialShiftId);
    final totalSales = salesByMethod.values.fold(0.0, (sum, v) => sum + v);
    final totalCashSales = salesByMethod[PaymentMethod.cash] ?? 0;
    final totalCardSales = salesByMethod[PaymentMethod.card] ?? 0;
    final totalWalletSales = salesByMethod[PaymentMethod.wallet] ?? 0;
    final totalInsuranceSales = salesByMethod[PaymentMethod.insurance] ?? 0;
    final totalCreditSales = salesByMethod[PaymentMethod.credit] ?? 0;
    final totalExpenses = await getTotalExpensesForShift(financialShiftId);

    // Calculate expected cash
    final expectedCash = shift.openingCash + totalCashSales - totalExpenses;
    final difference = actualCash - expectedCash;

    // Require reason if there's a difference
    if (difference != 0 && (differenceReason == null || differenceReason.isEmpty)) {
      throw FinancialException(
        'A reason is required when actual cash differs from expected cash. '
        'Expected: $expectedCash, Actual: $actualCash, Difference: $difference',
        code: 'REASON_REQUIRED',
      );
    }

    final now = DateTime.now();

    // Create closure record
    final closure = ShiftClosure(
      id: _uuid.v4(),
      financialShiftId: financialShiftId,
      branchId: '1', // SINGLE-BRANCH: Hardcoded
      totalSales: totalSales,
      totalCashSales: totalCashSales,
      totalCardSales: totalCardSales,
      totalWalletSales: totalWalletSales,
      totalInsuranceSales: totalInsuranceSales,
      totalCreditSales: totalCreditSales,
      totalExpenses: totalExpenses,
      expectedCash: expectedCash,
      actualCash: actualCash,
      difference: difference,
      differenceReason: differenceReason,
      closedBy: closedBy,
      verifiedBy: verifiedBy,
      notes: notes,
      createdAt: now,
    );

    // Save closure and update shift status
    await _shiftClosureRepo.insert(closure);
    await _financialShiftRepo.closeShift(financialShiftId, now);

    LoggingService.instance.info(
      'FinancialService',
      'Closed shift: $financialShiftId, Sales: $totalSales, Expenses: $totalExpenses, '
      'Expected: $expectedCash, Actual: $actualCash, Difference: $difference',
    );

    return closure;
  }

  /// Get shift summary (for display before closing)
  Future<ShiftSummary> getShiftSummary(String financialShiftId) async {
    final shift = await _financialShiftRepo.getById(financialShiftId);
    if (shift == null) {
      throw FinancialException(
        'Financial shift not found',
        code: 'SHIFT_NOT_FOUND',
      );
    }

    final salesByMethod = await getSalesBreakdown(financialShiftId);
    final totalSales = salesByMethod.values.fold(0.0, (sum, v) => sum + v);
    final totalCashSales = salesByMethod[PaymentMethod.cash] ?? 0;
    final expensesByCategory = await getExpensesBreakdown(financialShiftId);
    final totalExpenses = expensesByCategory.values.fold(0.0, (sum, v) => sum + v);
    final salesCount = await _shiftSaleRepo.getSalesCountForShift(financialShiftId);
    final expenseCount = await _shiftExpenseRepo.getExpenseCountForShift(financialShiftId);
    final expectedCash = shift.openingCash + totalCashSales - totalExpenses;

    return ShiftSummary(
      financialShift: shift,
      totalSales: totalSales,
      salesCount: salesCount,
      salesByMethod: salesByMethod,
      totalExpenses: totalExpenses,
      expenseCount: expenseCount,
      expensesByCategory: expensesByCategory,
      expectedCash: expectedCash,
    );
  }

  /// Get closure details
  Future<ShiftClosure?> getClosureForShift(String financialShiftId) async {
    return _shiftClosureRepo.getByFinancialShift(financialShiftId);
  }

  // =========================================================================
  // REPORTING OPERATIONS
  // =========================================================================

  /// Get daily financial summary
  Future<Map<String, dynamic>> getDailySummary(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    
    return _shiftClosureRepo.getPeriodSummary('1', startOfDay, endOfDay);
  }

  /// Get monthly financial summary
  Future<Map<String, dynamic>> getMonthlySummary(int year, int month) async {
    final startOfMonth = DateTime(year, month, 1);
    final endOfMonth = DateTime(year, month + 1, 0, 23, 59, 59);
    
    return _shiftClosureRepo.getPeriodSummary('1', startOfMonth, endOfMonth);
  }

  /// Get daily totals for a period
  Future<List<Map<String, dynamic>>> getDailyTotals(
    DateTime startDate,
    DateTime endDate,
  ) async {
    return _shiftClosureRepo.getDailyTotals('1', startDate, endDate);
  }

  /// Get closures with discrepancies
  Future<List<ShiftClosure>> getDiscrepancies({int? limit}) async {
    return _shiftClosureRepo.getClosuresWithDiscrepancies('1', limit: limit);
  }

  /// Get recent closed shifts
  Future<List<FinancialShift>> getRecentClosedShifts({int limit = 50}) async {
    return _financialShiftRepo.getByBranch(openOnly: false, limit: limit);
  }

  // =========================================================================
  // SHIFT CASH FLOW INTEGRATION (PHASE 3)
  // =========================================================================
  
  /// Get cash sales for a shift (cash-in component)
  /// 
  /// Returns the total cash sales amount for the shift.
  /// Used in shift closing cash reconciliation.
  Future<double> getShiftSalesCash(String financialShiftId) async {
    final salesByMethod = await getSalesBreakdown(financialShiftId);
    return salesByMethod[PaymentMethod.cash] ?? 0;
  }
  
  /// Get total expenses for a shift (cash-out component)
  /// 
  /// Returns the total expenses amount for the shift.
  /// Used in shift closing cash reconciliation.
  Future<double> getShiftExpenses(String financialShiftId) async {
    return getTotalExpensesForShift(financialShiftId);
  }
  
  /// Get purchase payments made during a shift period (cash-out component)
  /// 
  /// Returns supplier payments (cash-out) recorded during the shift's time period.
  /// These are payments to suppliers for purchases.
  /// 
  /// Note: This queries supplier_transactions for payments made during
  /// the shift's open period (opened_at to closed_at or now).
  Future<double> getShiftPurchasePayments(String financialShiftId) async {
    final shift = await _financialShiftRepo.getById(financialShiftId);
    if (shift == null) {
      return 0;
    }
    
    final startTime = shift.openedAt;
    final endTime = shift.closedAt ?? DateTime.now();
    
    // Get supplier payments during shift period
    final payments = await _supplierTransactionRepo.getByDateRange(
      startTime,
      endTime,
    );
    
    // Sum only payment transactions (cash-out to suppliers)
    return payments
        .where((tx) => tx.transactionType == SupplierTransactionType.payment)
        .fold(0.0, (sum, tx) => sum + tx.amount);
  }
  
  /// Get debt collection payments received during a shift period (cash-in component)
  /// 
  /// Returns credit sales payments received from customers during the shift period.
  /// In pharmacy context, this could be insurance reimbursements or credit account payments.
  /// 
  /// Note: Currently returns 0 as credit collection is not implemented.
  /// This is a placeholder for future integration.
  Future<double> getShiftDebtPaymentsReceived(String financialShiftId) async {
    // TODO: Implement when credit/debt collection feature is added
    // This would track:
    // - Insurance reimbursements received
    // - Credit account payments from customers
    // - Instalment payments received
    return 0;
  }
  
  /// Get comprehensive shift cash flow summary
  /// 
  /// Returns a breakdown of all cash movements during the shift:
  /// - Cash In: Opening cash + Cash sales + Debt payments received
  /// - Cash Out: Expenses + Purchase payments to suppliers
  /// - Expected Cash: Cash In - Cash Out
  Future<ShiftCashFlowSummary> getShiftCashFlowSummary(String financialShiftId) async {
    final shift = await _financialShiftRepo.getById(financialShiftId);
    if (shift == null) {
      throw FinancialException(
        'Financial shift not found',
        code: 'SHIFT_NOT_FOUND',
      );
    }
    
    // Cash In components
    final openingCash = shift.openingCash;
    final cashSales = await getShiftSalesCash(financialShiftId);
    final debtPaymentsReceived = await getShiftDebtPaymentsReceived(financialShiftId);
    
    // Cash Out components
    final expenses = await getShiftExpenses(financialShiftId);
    final purchasePayments = await getShiftPurchasePayments(financialShiftId);
    
    // Calculate totals
    final totalCashIn = openingCash + cashSales + debtPaymentsReceived;
    final totalCashOut = expenses + purchasePayments;
    final expectedCash = totalCashIn - totalCashOut;
    
    return ShiftCashFlowSummary(
      financialShiftId: financialShiftId,
      openingCash: openingCash,
      cashSales: cashSales,
      debtPaymentsReceived: debtPaymentsReceived,
      totalCashIn: totalCashIn,
      expenses: expenses,
      purchasePayments: purchasePayments,
      totalCashOut: totalCashOut,
      expectedCash: expectedCash,
    );
  }
}

/// Summary of a financial shift (for display)
class ShiftSummary {
  final FinancialShift financialShift;
  final double totalSales;
  final int salesCount;
  final Map<PaymentMethod, double> salesByMethod;
  final double totalExpenses;
  final int expenseCount;
  final Map<ExpenseCategory, double> expensesByCategory;
  final double expectedCash;

  ShiftSummary({
    required this.financialShift,
    required this.totalSales,
    required this.salesCount,
    required this.salesByMethod,
    required this.totalExpenses,
    required this.expenseCount,
    required this.expensesByCategory,
    required this.expectedCash,
  });

  /// Net profit (sales - expenses)
  double get netProfit => totalSales - totalExpenses;

  /// Cash sales only
  double get cashSales => salesByMethod[PaymentMethod.cash] ?? 0;

  /// Card sales only
  double get cardSales => salesByMethod[PaymentMethod.card] ?? 0;

  /// Wallet sales only
  double get walletSales => salesByMethod[PaymentMethod.wallet] ?? 0;
}

/// Comprehensive cash flow summary for a shift
/// 
/// Breaks down all cash movements:
/// - Cash In: Opening cash + Cash sales + Debt payments received
/// - Cash Out: Expenses + Purchase payments to suppliers
/// - Expected Cash: Cash In - Cash Out
class ShiftCashFlowSummary {
  final String financialShiftId;
  
  // Cash In components
  final double openingCash;
  final double cashSales;
  final double debtPaymentsReceived;
  final double totalCashIn;
  
  // Cash Out components
  final double expenses;
  final double purchasePayments;
  final double totalCashOut;
  
  // Result
  final double expectedCash;
  
  ShiftCashFlowSummary({
    required this.financialShiftId,
    required this.openingCash,
    required this.cashSales,
    required this.debtPaymentsReceived,
    required this.totalCashIn,
    required this.expenses,
    required this.purchasePayments,
    required this.totalCashOut,
    required this.expectedCash,
  });
  
  /// Net cash flow for the shift period
  double get netCashFlow => totalCashIn - openingCash - totalCashOut;
  
  /// Whether the shift has any purchase payments
  bool get hasPurchasePayments => purchasePayments > 0;
  
  /// Whether the shift has any debt payments received
  bool get hasDebtPaymentsReceived => debtPaymentsReceived > 0;
}

/// Exception for financial operations
class FinancialException implements Exception {
  final String message;
  final String? code;

  FinancialException(this.message, {this.code});

  @override
  String toString() => 'FinancialException: $message${code != null ? ' [$code]' : ''}';
}
