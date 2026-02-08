import 'package:uuid/uuid.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/supplier_transaction_model.dart';
import '../../data/repositories/supplier_repository.dart';
import '../../data/repositories/supplier_transaction_repository.dart';
import 'logging_service.dart';
import 'branch_context_service.dart';

/// Supplier Service - Manages pharma company relationships and transactions
/// 
/// Handles:
/// - Supplier CRUD operations
/// - Recording purchases and payments
/// - Calculating balances
/// - Tracking overdue invoices
class SupplierService {
  static final SupplierService _instance = SupplierService._();
  static SupplierService get instance => _instance;
  
  final _supplierRepo = SupplierRepository.instance;
  final _transactionRepo = SupplierTransactionRepository.instance;
  final _uuid = const Uuid();
  
  SupplierService._();
  
  // =========================================================================
  // BRANCH CONTEXT VALIDATION (DEFENSIVE)
  // =========================================================================
  
  /// Validates that branch context is available.
  /// This is a LAST LINE OF DEFENSE - UI should prevent reaching here without branch.
  void _requireBranchContext(String operation) {
    final branchService = BranchContextService.instance;
    if (!branchService.hasBranch || branchService.activeBranch == null) {
      LoggingService.instance.error(
        'SupplierService',
        'DEFENSIVE GUARD TRIGGERED: $operation attempted without active branch',
      );
      throw SupplierException(
        'No active branch context. Please select a branch before performing supplier operations.',
        code: 'NO_BRANCH_CONTEXT',
      );
    }
  }
  
  /// Validates that a branch ID matches the current active branch.
  void _validateBranchId(String branchId, String operation) {
    _requireBranchContext(operation);
    final activeBranchId = BranchContextService.instance.activeBranchId;
    if (branchId != activeBranchId) {
      LoggingService.instance.warning(
        'SupplierService',
        '$operation: Branch ID mismatch - provided: $branchId, active: $activeBranchId',
      );
    }
  }

  // =========================================================================
  // SUPPLIER OPERATIONS
  // =========================================================================

  /// Create a new supplier
  Future<Supplier> createSupplier({
    required String branchId,
    required String name,
    String? code,
    String? phone,
    String? email,
    String? address,
    String? contactPerson,
    String? taxNumber,
    int paymentTermsDays = 30,
    double creditLimit = 0,
    String? notes,
  }) async {
    // DEFENSIVE: Validate branch context
    _validateBranchId(branchId, 'createSupplier');
    
    // Check for duplicate name
    if (await _supplierRepo.nameExists(branchId, name)) {
      throw SupplierException(
        'A supplier with this name already exists',
        code: 'DUPLICATE_NAME',
      );
    }

    final now = DateTime.now();
    final supplier = Supplier(
      id: _uuid.v4(),
      branchId: branchId,
      name: name,
      code: code,
      phone: phone,
      email: email,
      address: address,
      contactPerson: contactPerson,
      taxNumber: taxNumber,
      paymentTermsDays: paymentTermsDays,
      creditLimit: creditLimit,
      notes: notes,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );

    await _supplierRepo.insert(supplier);
    LoggingService.instance.info(
      'SupplierService',
      'Created supplier: ${supplier.id} - ${supplier.name}',
    );

    return supplier;
  }

  /// Update an existing supplier
  Future<Supplier> updateSupplier({
    required String supplierId,
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
  }) async {
    final existing = await _supplierRepo.getById(supplierId);
    if (existing == null) {
      throw SupplierException(
        'Supplier not found',
        code: 'NOT_FOUND',
      );
    }

    // Check for duplicate name if name is being changed
    if (name != null && name != existing.name) {
      if (await _supplierRepo.nameExists(existing.branchId, name, excludeId: supplierId)) {
        throw SupplierException(
          'A supplier with this name already exists',
          code: 'DUPLICATE_NAME',
        );
      }
    }

    final updated = existing.copyWith(
      name: name,
      code: code,
      phone: phone,
      email: email,
      address: address,
      contactPerson: contactPerson,
      taxNumber: taxNumber,
      paymentTermsDays: paymentTermsDays,
      creditLimit: creditLimit,
      notes: notes,
      isActive: isActive,
      updatedAt: DateTime.now(),
    );

    await _supplierRepo.update(updated, supplierId);
    LoggingService.instance.info(
      'SupplierService',
      'Updated supplier: $supplierId',
    );

    return updated;
  }

  /// Get supplier by ID
  Future<Supplier?> getSupplier(String supplierId) async {
    return _supplierRepo.getById(supplierId);
  }

  /// Get all suppliers for a branch
  Future<List<Supplier>> getSuppliersByBranch(
    String branchId, {
    bool activeOnly = true,
  }) async {
    return _supplierRepo.getByBranch(branchId, activeOnly: activeOnly);
  }

  /// Search suppliers
  Future<List<Supplier>> searchSuppliers(String branchId, String query) async {
    return _supplierRepo.search(branchId, query);
  }

  /// Deactivate a supplier
  Future<void> deactivateSupplier(String supplierId) async {
    await _supplierRepo.setActive(supplierId, false);
    LoggingService.instance.info(
      'SupplierService',
      'Deactivated supplier: $supplierId',
    );
  }

  /// Reactivate a supplier
  Future<void> reactivateSupplier(String supplierId) async {
    await _supplierRepo.setActive(supplierId, true);
    LoggingService.instance.info(
      'SupplierService',
      'Reactivated supplier: $supplierId',
    );
  }

  // =========================================================================
  // TRANSACTION OPERATIONS
  // =========================================================================

  /// Record a purchase from a supplier
  Future<SupplierTransaction> recordPurchase({
    required String supplierId,
    required String branchId,
    required double amount,
    String? invoiceNumber,
    DateTime? invoiceDate,
    DateTime? dueDate,
    String? notes,
    String? recordedBy,
  }) async {
    // DEFENSIVE: Validate branch context
    _validateBranchId(branchId, 'recordPurchase');
    
    // Verify supplier exists
    final supplier = await _supplierRepo.getById(supplierId);
    if (supplier == null) {
      throw SupplierException(
        'Supplier not found',
        code: 'SUPPLIER_NOT_FOUND',
      );
    }

    // Calculate due date if not provided
    final actualDueDate = dueDate ?? 
        (invoiceDate ?? DateTime.now()).add(Duration(days: supplier.paymentTermsDays));

    final now = DateTime.now();
    final transaction = SupplierTransaction(
      id: _uuid.v4(),
      supplierId: supplierId,
      branchId: branchId,
      transactionType: SupplierTransactionType.purchase,
      amount: amount,
      invoiceNumber: invoiceNumber,
      invoiceDate: invoiceDate ?? now,
      dueDate: actualDueDate,
      notes: notes,
      recordedBy: recordedBy,
      createdAt: now,
      updatedAt: now,
    );

    await _transactionRepo.insert(transaction);
    LoggingService.instance.info(
      'SupplierService',
      'Recorded purchase: ${transaction.id}, supplier: $supplierId, amount: $amount',
    );

    return transaction;
  }

  /// Record a payment to a supplier
  Future<SupplierTransaction> recordPayment({
    required String supplierId,
    required String branchId,
    required double amount,
    String? paymentMethod,
    String? referenceNumber,
    String? notes,
    String? recordedBy,
  }) async {
    // DEFENSIVE: Validate branch context
    _validateBranchId(branchId, 'recordPayment');
    
    // Verify supplier exists
    final supplier = await _supplierRepo.getById(supplierId);
    if (supplier == null) {
      throw SupplierException(
        'Supplier not found',
        code: 'SUPPLIER_NOT_FOUND',
      );
    }

    final now = DateTime.now();
    final transaction = SupplierTransaction(
      id: _uuid.v4(),
      supplierId: supplierId,
      branchId: branchId,
      transactionType: SupplierTransactionType.payment,
      amount: amount,
      paymentMethod: paymentMethod,
      referenceNumber: referenceNumber,
      notes: notes,
      recordedBy: recordedBy,
      createdAt: now,
      updatedAt: now,
    );

    await _transactionRepo.insert(transaction);
    LoggingService.instance.info(
      'SupplierService',
      'Recorded payment: ${transaction.id}, supplier: $supplierId, amount: $amount',
    );

    return transaction;
  }

  /// Record a return of goods to supplier
  Future<SupplierTransaction> recordReturn({
    required String supplierId,
    required String branchId,
    required double amount,
    String? invoiceNumber,
    String? notes,
    String? recordedBy,
  }) async {
    final now = DateTime.now();
    final transaction = SupplierTransaction(
      id: _uuid.v4(),
      supplierId: supplierId,
      branchId: branchId,
      transactionType: SupplierTransactionType.returnGoods,
      amount: amount,
      invoiceNumber: invoiceNumber,
      notes: notes,
      recordedBy: recordedBy,
      createdAt: now,
      updatedAt: now,
    );

    await _transactionRepo.insert(transaction);
    LoggingService.instance.info(
      'SupplierService',
      'Recorded return: ${transaction.id}, supplier: $supplierId, amount: $amount',
    );

    return transaction;
  }

  /// Get transactions for a supplier
  Future<List<SupplierTransaction>> getTransactions(
    String supplierId, {
    int? limit,
    int? offset,
  }) async {
    return _transactionRepo.getBySupplier(supplierId, limit: limit, offset: offset);
  }

  // =========================================================================
  // BALANCE & REPORTING
  // =========================================================================

  /// Get supplier balance (amount owed)
  Future<double> getSupplierBalance(String supplierId) async {
    return _transactionRepo.getSupplierBalance(supplierId);
  }

  /// Get supplier with full summary
  Future<SupplierSummary> getSupplierSummary(String supplierId) async {
    final supplier = await _supplierRepo.getById(supplierId);
    if (supplier == null) {
      throw SupplierException(
        'Supplier not found',
        code: 'NOT_FOUND',
      );
    }

    final summary = await _transactionRepo.getSupplierSummary(supplierId);
    
    return SupplierSummary(
      supplier: supplier,
      totalPurchases: summary['total_purchases'] as double,
      totalPayments: summary['total_payments'] as double,
      balance: summary['balance'] as double,
      purchaseCount: summary['purchase_count'] as int,
      paymentCount: summary['payment_count'] as int,
      overdueCount: summary['overdue_count'] as int,
    );
  }

  /// Get all suppliers with balances
  Future<List<Map<String, dynamic>>> getSuppliersWithBalances(String branchId) async {
    // DEFENSIVE: Validate branch context
    _validateBranchId(branchId, 'getSuppliersWithBalances');
    
    return _supplierRepo.getSuppliersWithBalances(branchId);
  }

  /// Get suppliers with overdue invoices
  Future<List<Map<String, dynamic>>> getSuppliersWithOverdue(String branchId) async {
    return _supplierRepo.getSuppliersWithOverdueInvoices(branchId);
  }

  /// Get overdue invoices for a supplier
  Future<List<SupplierTransaction>> getOverdueInvoices(String supplierId) async {
    return _transactionRepo.getOverdueInvoices(supplierId);
  }

  /// Get upcoming payments due
  Future<List<SupplierTransaction>> getUpcomingPayments(
    String branchId, {
    int withinDays = 7,
  }) async {
    return _transactionRepo.getUpcomingPayments(branchId, withinDays: withinDays);
  }

  /// Get branch transaction summary
  Future<Map<String, dynamic>> getBranchSummary(
    String branchId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    return _transactionRepo.getBranchSummary(branchId, startDate, endDate);
  }

  /// Get top suppliers by balance (amount owed)
  Future<List<Map<String, dynamic>>> getTopSuppliersByBalance(
    String branchId, {
    int limit = 10,
  }) async {
    final suppliers = await _supplierRepo.getSuppliersWithBalances(branchId);
    suppliers.sort((a, b) => (b['balance'] as double).compareTo(a['balance'] as double));
    return suppliers.take(limit).toList();
  }

  /// Get total amount owed to all suppliers
  Future<double> getTotalOwed(String branchId) async {
    final suppliers = await _supplierRepo.getSuppliersWithBalances(branchId);
    double total = 0;
    for (final s in suppliers) {
      final balance = s['balance'] as double;
      if (balance > 0) {
        total += balance;
      }
    }
    return total;
  }
}

/// Summary of a supplier with financial data
class SupplierSummary {
  final Supplier supplier;
  final double totalPurchases;
  final double totalPayments;
  final double balance;
  final int purchaseCount;
  final int paymentCount;
  final int overdueCount;

  SupplierSummary({
    required this.supplier,
    required this.totalPurchases,
    required this.totalPayments,
    required this.balance,
    required this.purchaseCount,
    required this.paymentCount,
    required this.overdueCount,
  });

  bool get hasOverdue => overdueCount > 0;
  bool get hasBalance => balance > 0;
}

/// Exception for supplier operations
class SupplierException implements Exception {
  final String message;
  final String? code;

  SupplierException(this.message, {this.code});

  @override
  String toString() => 'SupplierException: $message${code != null ? ' [$code]' : ''}';
}
