import '../models/supplier_transaction_model.dart';
import 'base_repository.dart';

/// Repository for supplier transaction operations
/// 
/// SINGLE-BRANCH ARCHITECTURE: All queries use hardcoded branch_id = '1'
class SupplierTransactionRepository extends BaseRepository<SupplierTransaction> {
  static final SupplierTransactionRepository _instance = SupplierTransactionRepository._();
  static SupplierTransactionRepository get instance => _instance;
  
  // SINGLE-BRANCH: Hardcoded branch ID
  static const String _defaultBranchId = '1';
  
  SupplierTransactionRepository._();

  @override
  String get tableName => 'supplier_transactions';

  @override
  SupplierTransaction fromMap(Map<String, dynamic> map) => SupplierTransaction.fromMap(map);

  @override
  Map<String, dynamic> toMap(SupplierTransaction item) {
    final map = item.toMap();
    // SINGLE-BRANCH: Ensure branch_id is always '1'
    map['branch_id'] = _defaultBranchId;
    return map;
  }

  /// Get transactions for a supplier
  /// SINGLE-BRANCH: Includes branch_id = '1' filter
  Future<List<SupplierTransaction>> getBySupplier(
    String supplierId, {
    int? limit,
    int? offset,
  }) async {
    return getAll(
      where: 'supplier_id = ? AND branch_id = ?',
      whereArgs: [supplierId, _defaultBranchId],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// Get transactions by date range
  Future<List<SupplierTransaction>> getByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    return getAll(
      where: 'branch_id = ? AND created_at >= ? AND created_at <= ?',
      whereArgs: [
        _defaultBranchId,
        startDate.toIso8601String(),
        endDate.toIso8601String(),
      ],
      orderBy: 'created_at DESC',
    );
  }

  /// Get supplier balance (purchases - payments)
  /// SINGLE-BRANCH: Includes branch_id = '1' filter
  Future<double> getSupplierBalance(String supplierId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(CASE WHEN transaction_type = 'purchase' THEN amount ELSE 0 END), 0) -
        COALESCE(SUM(CASE WHEN transaction_type = 'payment' THEN amount ELSE 0 END), 0) as balance
      FROM $tableName 
      WHERE supplier_id = ? AND branch_id = ?
    ''', [supplierId, _defaultBranchId]);
    
    if (result.isEmpty) return 0;
    return (result.first['balance'] as num?)?.toDouble() ?? 0;
  }

  /// Get total purchases for a supplier
  /// SINGLE-BRANCH: Includes branch_id = '1' filter
  Future<double> getTotalPurchases(String supplierId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as total 
      FROM $tableName 
      WHERE supplier_id = ? AND branch_id = ? AND transaction_type = 'purchase'
    ''', [supplierId, _defaultBranchId]);
    
    if (result.isEmpty) return 0;
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// Get total payments for a supplier
  /// SINGLE-BRANCH: Includes branch_id = '1' filter
  Future<double> getTotalPayments(String supplierId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as total 
      FROM $tableName 
      WHERE supplier_id = ? AND branch_id = ? AND transaction_type = 'payment'
    ''', [supplierId, _defaultBranchId]);
    
    if (result.isEmpty) return 0;
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// Get overdue invoices for a supplier
  /// SINGLE-BRANCH: Includes branch_id = '1' filter
  Future<List<SupplierTransaction>> getOverdueInvoices(String supplierId) async {
    return getAll(
      where: 'supplier_id = ? AND branch_id = ? AND transaction_type = ? AND due_date < ?',
      whereArgs: [supplierId, _defaultBranchId, 'purchase', DateTime.now().toIso8601String()],
      orderBy: 'due_date ASC',
    );
  }

  /// Get upcoming payments (due within days)
  Future<List<SupplierTransaction>> getUpcomingPayments({int withinDays = 7}) async {
    final now = DateTime.now();
    final futureDate = now.add(Duration(days: withinDays));
    
    return getAll(
      where: 'branch_id = ? AND transaction_type = ? AND due_date >= ? AND due_date <= ?',
      whereArgs: [
        _defaultBranchId,
        'purchase',
        now.toIso8601String(),
        futureDate.toIso8601String(),
      ],
      orderBy: 'due_date ASC',
    );
  }

  /// Get branch summary for a period
  Future<Map<String, dynamic>> getBranchSummary(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT 
        COUNT(CASE WHEN transaction_type = 'purchase' THEN 1 END) as purchase_count,
        COUNT(CASE WHEN transaction_type = 'payment' THEN 1 END) as payment_count,
        COALESCE(SUM(CASE WHEN transaction_type = 'purchase' THEN amount ELSE 0 END), 0) as total_purchases,
        COALESCE(SUM(CASE WHEN transaction_type = 'payment' THEN amount ELSE 0 END), 0) as total_payments
      FROM $tableName 
      WHERE branch_id = ? 
        AND created_at >= ? 
        AND created_at <= ?
    ''', [_defaultBranchId, startDate.toIso8601String(), endDate.toIso8601String()]);
    
    if (result.isEmpty) {
      return {
        'purchase_count': 0,
        'payment_count': 0,
        'total_purchases': 0.0,
        'total_payments': 0.0,
      };
    }
    
    return {
      'purchase_count': (result.first['purchase_count'] as num?)?.toInt() ?? 0,
      'payment_count': (result.first['payment_count'] as num?)?.toInt() ?? 0,
      'total_purchases': (result.first['total_purchases'] as num?)?.toDouble() ?? 0.0,
      'total_payments': (result.first['total_payments'] as num?)?.toDouble() ?? 0.0,
    };
  }

  /// Get supplier summary
  /// SINGLE-BRANCH: Includes branch_id = '1' filter
  Future<Map<String, dynamic>> getSupplierSummary(String supplierId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT 
        COUNT(CASE WHEN transaction_type = 'purchase' THEN 1 END) as purchase_count,
        COUNT(CASE WHEN transaction_type = 'payment' THEN 1 END) as payment_count,
        COALESCE(SUM(CASE WHEN transaction_type = 'purchase' THEN amount ELSE 0 END), 0) as total_purchases,
        COALESCE(SUM(CASE WHEN transaction_type = 'payment' THEN amount ELSE 0 END), 0) as total_payments,
        COUNT(CASE WHEN transaction_type = 'purchase' AND due_date < datetime('now') THEN 1 END) as overdue_count
      FROM $tableName 
      WHERE supplier_id = ? AND branch_id = ?
    ''', [supplierId, _defaultBranchId]);
    
    if (result.isEmpty) {
      return {
        'purchase_count': 0,
        'payment_count': 0,
        'total_purchases': 0.0,
        'total_payments': 0.0,
        'balance': 0.0,
        'overdue_count': 0,
      };
    }
    
    final totalPurchases = (result.first['total_purchases'] as num?)?.toDouble() ?? 0.0;
    final totalPayments = (result.first['total_payments'] as num?)?.toDouble() ?? 0.0;
    
    return {
      'purchase_count': (result.first['purchase_count'] as num?)?.toInt() ?? 0,
      'payment_count': (result.first['payment_count'] as num?)?.toInt() ?? 0,
      'total_purchases': totalPurchases,
      'total_payments': totalPayments,
      'balance': totalPurchases - totalPayments,
      'overdue_count': (result.first['overdue_count'] as num?)?.toInt() ?? 0,
    };
  }

  /// Get recent transactions
  Future<List<SupplierTransaction>> getRecentTransactions({int limit = 50}) async {
    return getAll(
      where: 'branch_id = ?',
      whereArgs: [_defaultBranchId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }
}
