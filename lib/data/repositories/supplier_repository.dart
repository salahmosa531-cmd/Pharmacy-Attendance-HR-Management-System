import '../models/supplier_model.dart';
import 'base_repository.dart';

/// Repository for supplier operations
class SupplierRepository extends BaseRepository<Supplier> {
  static final SupplierRepository _instance = SupplierRepository._();
  static SupplierRepository get instance => _instance;
  
  SupplierRepository._();

  @override
  String get tableName => 'suppliers';

  @override
  Supplier fromMap(Map<String, dynamic> map) => Supplier.fromMap(map);

  @override
  Map<String, dynamic> toMap(Supplier item) => item.toMap();

  /// Get all suppliers for a branch
  Future<List<Supplier>> getByBranch(
    String branchId, {
    bool activeOnly = true,
  }) async {
    String where = 'branch_id = ?';
    List<dynamic> whereArgs = [branchId];
    
    if (activeOnly) {
      where += ' AND is_active = 1';
    }
    
    return getAll(
      where: where,
      whereArgs: whereArgs,
      orderBy: 'name ASC',
    );
  }

  /// Get supplier by name
  Future<Supplier?> getByName(String branchId, String name) async {
    final results = await getAll(
      where: 'branch_id = ? AND LOWER(name) = ?',
      whereArgs: [branchId, name.toLowerCase()],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Get supplier by code
  Future<Supplier?> getByCode(String branchId, String code) async {
    final results = await getAll(
      where: 'branch_id = ? AND code = ?',
      whereArgs: [branchId, code],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Search suppliers by name or code
  Future<List<Supplier>> search(String branchId, String query) async {
    final searchQuery = '%${query.toLowerCase()}%';
    return getAll(
      where: 'branch_id = ? AND (LOWER(name) LIKE ? OR LOWER(code) LIKE ?)',
      whereArgs: [branchId, searchQuery, searchQuery],
      orderBy: 'name ASC',
    );
  }

  /// Check if supplier name exists
  Future<bool> nameExists(
    String branchId,
    String name, {
    String? excludeId,
  }) async {
    String where = 'branch_id = ? AND LOWER(name) = ?';
    List<dynamic> whereArgs = [branchId, name.toLowerCase()];
    
    if (excludeId != null) {
      where += ' AND id != ?';
      whereArgs.add(excludeId);
    }
    
    final result = await count(where: where, whereArgs: whereArgs);
    return result > 0;
  }

  /// Set supplier active status
  Future<void> setActive(String supplierId, bool isActive) async {
    final db = await database;
    await db.update(
      tableName,
      {
        'is_active': isActive ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [supplierId],
    );
  }

  /// Get active supplier count for a branch
  Future<int> getActiveCount(String branchId) async {
    return count(
      where: 'branch_id = ? AND is_active = 1',
      whereArgs: [branchId],
    );
  }

  /// Get suppliers with overdue invoices (using transactions)
  Future<List<Map<String, dynamic>>> getSuppliersWithOverdueInvoices(
    String branchId,
  ) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT s.*, 
        COALESCE(SUM(CASE WHEN st.transaction_type = 'purchase' THEN st.amount ELSE 0 END), 0) as total_purchases,
        COALESCE(SUM(CASE WHEN st.transaction_type = 'payment' THEN st.amount ELSE 0 END), 0) as total_payments,
        COUNT(CASE WHEN st.transaction_type = 'purchase' AND st.due_date < datetime('now') THEN 1 END) as overdue_count
      FROM $tableName s
      LEFT JOIN supplier_transactions st ON s.id = st.supplier_id
      WHERE s.branch_id = ? AND s.is_active = 1
      GROUP BY s.id
      HAVING overdue_count > 0
      ORDER BY overdue_count DESC
    ''', [branchId]);
  }

  /// Get suppliers with balances
  Future<List<Map<String, dynamic>>> getSuppliersWithBalances(
    String branchId,
  ) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT s.*, 
        COALESCE(SUM(CASE WHEN st.transaction_type = 'purchase' THEN st.amount ELSE 0 END), 0) as total_purchases,
        COALESCE(SUM(CASE WHEN st.transaction_type = 'payment' THEN st.amount ELSE 0 END), 0) as total_payments,
        COALESCE(SUM(CASE WHEN st.transaction_type = 'purchase' THEN st.amount ELSE 0 END), 0) - 
        COALESCE(SUM(CASE WHEN st.transaction_type = 'payment' THEN st.amount ELSE 0 END), 0) as balance
      FROM $tableName s
      LEFT JOIN supplier_transactions st ON s.id = st.supplier_id
      WHERE s.branch_id = ? AND s.is_active = 1
      GROUP BY s.id
      ORDER BY balance DESC
    ''', [branchId]);
  }
}
