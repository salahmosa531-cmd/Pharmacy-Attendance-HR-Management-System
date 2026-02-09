import 'package:uuid/uuid.dart';
import '../../data/models/financial_shift_model.dart';
import '../../data/models/shift_sale_model.dart';
import '../../data/models/shift_expense_model.dart';
import '../../data/models/shift_closure_model.dart';
import '../../data/repositories/financial_shift_repository.dart';
import '../../data/repositories/shift_sale_repository.dart';
import '../../data/repositories/shift_expense_repository.dart';
import '../../data/repositories/shift_closure_repository.dart';
import 'logging_service.dart';
import 'branch_context_service.dart';

/// Financial Service - Orchestrates all shift-level financial operations
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
  final _uuid = const Uuid();
  
  FinancialService._();
  
  // =========================================================================
  // BRANCH CONTEXT VALIDATION (DEFENSIVE)
  // =========================================================================
  
  /// Validates that branch context is available.
  /// This is a LAST LINE OF DEFENSE - UI should prevent reaching here without branch.
  void _requireBranchContext(String operation) {
    final branchService = BranchContextService.instance;
    if (!branchService.hasBranch || branchService.activeBranch == null) {
      LoggingService.instance.error(
        'FinancialService',
        'DEFENSIVE GUARD TRIGGERED: $operation attempted without active branch',
      );
      throw FinancialException(
        'No active branch context. Please select a branch before performing financial operations.',
        code: 'NO_BRANCH_CONTEXT',
      );
    }
  }
  
  /// Validates that a branch ID matches the current active branch.
  /// Prevents operations on wrong branch.
  void _validateBranchId(String branchId, String operation) {
    _requireBranchContext(operation);
    final activeBranchId = BranchContextService.instance.activeBranchId;
    if (branchId != activeBranchId) {
      LoggingService.instance.warning(
        'FinancialService',
        '$operation: Branch ID mismatch - provided: $branchId, active: $activeBranchId',
      );
      // Allow operation but log the mismatch for debugging
    }
  }

  // =========================================================================
  // FINANCIAL SHIFT OPERATIONS
  // =========================================================================

  /// Open a new financial shift
  /// 
  /// Throws if employee already has an open shift
  Future<FinancialShift> openShift({
    required String branchId,
    required String employeeId,
    String? shiftId,
    double openingCash = 0,
    String? notes,
  }) async {
    // DEFENSIVE: Validate branch context
    _validateBranchId(branchId, 'openShift');
    
    // Check for existing open shift IN THIS BRANCH
    // Note: branchId is passed to scope the check to current branch only
    final existingShift = await _financialShiftRepo.getOpenShiftForEmployee(branchId, employeeId);
    if (existingShift != null) {
      throw FinancialException(
        'Employee already has an open shift in this branch. Please close it first.',
        code: 'SHIFT_ALREADY_OPEN',
      );
    }

    final now = DateTime.now();
    final financialShift = FinancialShift(
      id: _uuid.v4(),
      branchId: branchId,
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

  /// Get currently open shift for employee in a specific branch
  /// 
  /// IMPORTANT: branchId is required to scope results to the current branch.
  Future<FinancialShift?> getOpenShiftForEmployee(String branchId, String employeeId) async {
    return _financialShiftRepo.getOpenShiftForEmployee(branchId, employeeId);
  }

  /// Get all open shifts for a branch
  Future<List<FinancialShift>> getOpenShiftsForBranch(String branchId) async {
    return _financialShiftRepo.getOpenShiftsForBranch(branchId);
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
    required String branchId,
    required double amount,
    PaymentMethod paymentMethod = PaymentMethod.cash,
    String? description,
    String? invoiceNumber,
    String? customerName,
    String? recordedBy,
  }) async {
    // DEFENSIVE: Validate branch context
    _validateBranchId(branchId, 'recordSale');
    
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
      branchId: branchId,
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
    required String branchId,
    required double amount,
    required String description,
    ExpenseCategory category = ExpenseCategory.misc,
    String? receiptNumber,
    String? recordedBy,
    String? approvedBy,
  }) async {
    // DEFENSIVE: Validate branch context
    _validateBranchId(branchId, 'recordExpense');
    
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
      branchId: branchId,
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
      branchId: shift.branchId,
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
  Future<Map<String, dynamic>> getDailySummary(String branchId, DateTime date) async {
    // DEFENSIVE: Validate branch context
    _validateBranchId(branchId, 'getDailySummary');
    
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    
    return _shiftClosureRepo.getPeriodSummary(branchId, startOfDay, endOfDay);
  }

  /// Get monthly financial summary
  Future<Map<String, dynamic>> getMonthlySummary(String branchId, int year, int month) async {
    // DEFENSIVE: Validate branch context
    _validateBranchId(branchId, 'getMonthlySummary');
    
    final startOfMonth = DateTime(year, month, 1);
    final endOfMonth = DateTime(year, month + 1, 0, 23, 59, 59);
    
    return _shiftClosureRepo.getPeriodSummary(branchId, startOfMonth, endOfMonth);
  }

  /// Get daily totals for a period
  Future<List<Map<String, dynamic>>> getDailyTotals(
    String branchId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    return _shiftClosureRepo.getDailyTotals(branchId, startDate, endDate);
  }

  /// Get closures with discrepancies
  Future<List<ShiftClosure>> getDiscrepancies(String branchId, {int? limit}) async {
    return _shiftClosureRepo.getClosuresWithDiscrepancies(branchId, limit: limit);
  }

  /// Get recent closed shifts
  Future<List<FinancialShift>> getRecentClosedShifts(
    String branchId, {
    int limit = 50,
  }) async {
    return _financialShiftRepo.getByBranch(branchId, openOnly: false, limit: limit);
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

/// Exception for financial operations
class FinancialException implements Exception {
  final String message;
  final String? code;

  FinancialException(this.message, {this.code});

  @override
  String toString() => 'FinancialException: $message${code != null ? ' [$code]' : ''}';
}
