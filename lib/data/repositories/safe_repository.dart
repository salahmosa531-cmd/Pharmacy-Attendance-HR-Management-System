import '../models/safe_balance_model.dart';
import 'base_repository.dart';

/// Repository for Safe Balance operations
/// 
/// Manages the pharmacy Safe (Vault) which holds capital across shifts.
/// Only one SafeBalance record exists per branch.
class SafeBalanceRepository extends BaseRepository<SafeBalance> {
  static final SafeBalanceRepository _instance = SafeBalanceRepository._();
  static SafeBalanceRepository get instance => _instance;
  
  SafeBalanceRepository._();

  @override
  String get tableName => 'safe_balances';

  @override
  SafeBalance fromMap(Map<String, dynamic> map) => SafeBalance.fromMap(map);

  @override
  Map<String, dynamic> toMap(SafeBalance entity) => entity.toMap();

  /// Get the Safe balance for a branch
  /// Creates one with 0 balance if it doesn't exist
  Future<SafeBalance> getOrCreateForBranch([String branchId = '1']) async {
    final db = await database;
    
    final results = await db.query(
      tableName,
      where: 'branch_id = ?',
      whereArgs: [branchId],
      limit: 1,
    );
    
    if (results.isNotEmpty) {
      return fromMap(results.first);
    }
    
    // Create new safe balance with 0
    final now = DateTime.now();
    final newSafe = SafeBalance(
      id: 'safe_$branchId',
      branchId: branchId,
      balance: 0,
      lastUpdatedAt: now,
      createdAt: now,
    );
    
    await insert(newSafe);
    return newSafe;
  }

  /// Update safe balance atomically
  /// Returns the updated SafeBalance
  Future<SafeBalance> updateBalance({
    required String branchId,
    required double newBalance,
    String? updatedBy,
    String? transactionId,
  }) async {
    final db = await database;
    final now = DateTime.now();
    
    await db.update(
      tableName,
      {
        'balance': newBalance,
        'last_updated_at': now.toIso8601String(),
        'last_updated_by': updatedBy,
        'last_transaction_id': transactionId,
      },
      where: 'branch_id = ?',
      whereArgs: [branchId],
    );
    
    return getOrCreateForBranch(branchId);
  }

  /// Add amount to safe balance (credit)
  Future<SafeBalance> addToBalance({
    required String branchId,
    required double amount,
    String? updatedBy,
    String? transactionId,
  }) async {
    final current = await getOrCreateForBranch(branchId);
    return updateBalance(
      branchId: branchId,
      newBalance: current.balance + amount,
      updatedBy: updatedBy,
      transactionId: transactionId,
    );
  }

  /// Subtract amount from safe balance (debit)
  /// Throws if insufficient balance
  Future<SafeBalance> subtractFromBalance({
    required String branchId,
    required double amount,
    String? updatedBy,
    String? transactionId,
  }) async {
    final current = await getOrCreateForBranch(branchId);
    
    if (current.balance < amount) {
      throw SafeInsufficientFundsException(
        'Insufficient safe balance. Available: ${current.balance}, Required: $amount',
        available: current.balance,
        required: amount,
      );
    }
    
    return updateBalance(
      branchId: branchId,
      newBalance: current.balance - amount,
      updatedBy: updatedBy,
      transactionId: transactionId,
    );
  }

  /// Get current balance for branch
  Future<double> getCurrentBalance([String branchId = '1']) async {
    final safe = await getOrCreateForBranch(branchId);
    return safe.balance;
  }
}

/// Repository for Safe Transaction operations
/// 
/// Tracks all movements into and out of the Safe for audit purposes.
class SafeTransactionRepository extends BaseRepository<SafeTransaction> {
  static final SafeTransactionRepository _instance = SafeTransactionRepository._();
  static SafeTransactionRepository get instance => _instance;
  
  SafeTransactionRepository._();

  @override
  String get tableName => 'safe_transactions';

  @override
  SafeTransaction fromMap(Map<String, dynamic> map) => SafeTransaction.fromMap(map);

  @override
  Map<String, dynamic> toMap(SafeTransaction entity) => entity.toMap();

  /// Get all transactions for a branch
  Future<List<SafeTransaction>> getByBranch(
    String branchId, {
    int? limit,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final db = await database;
    
    String whereClause = 'branch_id = ?';
    List<dynamic> whereArgs = [branchId];
    
    if (fromDate != null) {
      whereClause += ' AND created_at >= ?';
      whereArgs.add(fromDate.toIso8601String());
    }
    if (toDate != null) {
      whereClause += ' AND created_at <= ?';
      whereArgs.add(toDate.toIso8601String());
    }
    
    final results = await db.query(
      tableName,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    
    return results.map((map) => fromMap(map)).toList();
  }

  /// Get transactions for a specific financial shift
  Future<List<SafeTransaction>> getByFinancialShift(String financialShiftId) async {
    final db = await database;
    
    final results = await db.query(
      tableName,
      where: 'financial_shift_id = ?',
      whereArgs: [financialShiftId],
      orderBy: 'created_at DESC',
    );
    
    return results.map((map) => fromMap(map)).toList();
  }

  /// Get transactions by type
  Future<List<SafeTransaction>> getByType(
    String branchId,
    SafeTransactionType type, {
    int? limit,
  }) async {
    final db = await database;
    
    final results = await db.query(
      tableName,
      where: 'branch_id = ? AND transaction_type = ?',
      whereArgs: [branchId, type.value],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    
    return results.map((map) => fromMap(map)).toList();
  }

  /// Get total credits for a period
  Future<double> getTotalCredits(
    String branchId,
    DateTime fromDate,
    DateTime toDate,
  ) async {
    final db = await database;
    
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as total
      FROM $tableName
      WHERE branch_id = ?
        AND created_at >= ?
        AND created_at <= ?
        AND transaction_type IN ('shift_transfer', 'deposit', 'initial_balance')
    ''', [branchId, fromDate.toIso8601String(), toDate.toIso8601String()]);
    
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// Get total debits for a period
  Future<double> getTotalDebits(
    String branchId,
    DateTime fromDate,
    DateTime toDate,
  ) async {
    final db = await database;
    
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as total
      FROM $tableName
      WHERE branch_id = ?
        AND created_at >= ?
        AND created_at <= ?
        AND transaction_type IN ('supplier_payment', 'debt_settlement', 'withdrawal')
    ''', [branchId, fromDate.toIso8601String(), toDate.toIso8601String()]);
    
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// Get recent supplier payments
  Future<List<SafeTransaction>> getRecentSupplierPayments(
    String branchId, {
    int limit = 10,
  }) async {
    return getByType(branchId, SafeTransactionType.supplierPayment, limit: limit);
  }
}

/// Exception for insufficient safe balance
class SafeInsufficientFundsException implements Exception {
  final String message;
  final double available;
  final double required;

  SafeInsufficientFundsException(
    this.message, {
    required this.available,
    required this.required,
  });

  double get shortfall => required - available;

  @override
  String toString() => 'SafeInsufficientFundsException: $message';
}
