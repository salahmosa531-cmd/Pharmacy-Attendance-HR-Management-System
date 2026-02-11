import 'package:uuid/uuid.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/supplier_transaction_model.dart';
import '../../data/repositories/supplier_repository.dart';
import '../../data/repositories/supplier_transaction_repository.dart';
import 'logging_service.dart';

/// Supplier Service - Manages pharma company relationships and transactions
/// 
/// SINGLE-BRANCH ARCHITECTURE: All operations use hardcoded branch_id = '1'
/// Branch context validation has been removed for offline-first single-branch mode.
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
  // SUPPLIER OPERATIONS
  // =========================================================================

  /// Create a new supplier
  Future<Supplier> createSupplier({
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
    // Check for duplicate name
    if (await _supplierRepo.nameExists(name)) {
      throw SupplierException(
        'A supplier with this name already exists',
        code: 'DUPLICATE_NAME',
      );
    }

    final now = DateTime.now();
    final supplier = Supplier(
      id: _uuid.v4(),
      branchId: '1', // SINGLE-BRANCH: Hardcoded
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
      if (await _supplierRepo.nameExists(name, excludeId: supplierId)) {
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

  /// Get all suppliers
  Future<List<Supplier>> getSuppliers({bool activeOnly = true}) async {
    return _supplierRepo.getByBranch(activeOnly: activeOnly);
  }

  /// Search suppliers
  Future<List<Supplier>> searchSuppliers(String query) async {
    return _supplierRepo.search(query);
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
    required double amount,
    String? invoiceNumber,
    DateTime? invoiceDate,
    DateTime? dueDate,
    String? notes,
    String? recordedBy,
  }) async {
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
      branchId: '1', // SINGLE-BRANCH: Hardcoded
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
    required double amount,
    String? paymentMethod,
    String? referenceNumber,
    String? notes,
    String? recordedBy,
  }) async {
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
      branchId: '1', // SINGLE-BRANCH: Hardcoded
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
    required double amount,
    String? invoiceNumber,
    String? notes,
    String? recordedBy,
  }) async {
    final now = DateTime.now();
    final transaction = SupplierTransaction(
      id: _uuid.v4(),
      supplierId: supplierId,
      branchId: '1', // SINGLE-BRANCH: Hardcoded
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
      totalPurchases: (summary['total_purchases'] as num).toDouble(),
      totalPayments: (summary['total_payments'] as num).toDouble(),
      balance: (summary['balance'] as num).toDouble(),
      purchaseCount: summary['purchase_count'] as int,
      paymentCount: summary['payment_count'] as int,
      overdueCount: summary['overdue_count'] as int,
    );
  }

  /// Get all suppliers with balances
  Future<List<Map<String, dynamic>>> getSuppliersWithBalances() async {
    return _supplierRepo.getSuppliersWithBalances();
  }

  /// Get suppliers with overdue invoices
  Future<List<Map<String, dynamic>>> getSuppliersWithOverdue() async {
    return _supplierRepo.getSuppliersWithOverdueInvoices();
  }

  /// Get overdue invoices for a supplier
  Future<List<SupplierTransaction>> getOverdueInvoices(String supplierId) async {
    return _transactionRepo.getOverdueInvoices(supplierId);
  }

  /// Get upcoming payments due
  Future<List<SupplierTransaction>> getUpcomingPayments({int withinDays = 7}) async {
    return _transactionRepo.getUpcomingPayments(withinDays: withinDays);
  }

  /// Get branch transaction summary
  Future<Map<String, dynamic>> getBranchSummary(
    DateTime startDate,
    DateTime endDate,
  ) async {
    return _transactionRepo.getBranchSummary(startDate, endDate);
  }

  /// Get top suppliers by balance (amount owed)
  Future<List<Map<String, dynamic>>> getTopSuppliersByBalance({int limit = 10}) async {
    final suppliers = await _supplierRepo.getSuppliersWithBalances();
    suppliers.sort((a, b) => (b['balance'] as num).toDouble().compareTo(
          (a['balance'] as num).toDouble(),
        ));
    return suppliers.take(limit).toList();
  }

  /// Get total amount owed to all suppliers
  Future<double> getTotalOwed() async {
    final suppliers = await _supplierRepo.getSuppliersWithBalances();
    double total = 0;
    for (final s in suppliers) {
      final balance = (s['balance'] as num).toDouble();
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
