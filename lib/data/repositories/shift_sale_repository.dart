import '../models/shift_sale_model.dart';
import 'base_repository.dart';

/// Repository for shift sales operations
class ShiftSaleRepository extends BaseRepository<ShiftSale> {
  static final ShiftSaleRepository _instance = ShiftSaleRepository._();
  static ShiftSaleRepository get instance => _instance;
  
  ShiftSaleRepository._();

  @override
  String get tableName => 'shift_sales';

  @override
  ShiftSale fromMap(Map<String, dynamic> map) => ShiftSale.fromMap(map);

  @override
  Map<String, dynamic> toMap(ShiftSale item) => item.toMap();

  /// Get all sales for a financial shift
  Future<List<ShiftSale>> getByFinancialShift(String financialShiftId) async {
    return getAll(
      where: 'financial_shift_id = ?',
      whereArgs: [financialShiftId],
      orderBy: 'created_at DESC',
    );
  }

  /// Get sales for a branch in date range
  Future<List<ShiftSale>> getByDateRange(
    String branchId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    return getAll(
      where: 'branch_id = ? AND created_at >= ? AND created_at <= ?',
      whereArgs: [
        branchId,
        startDate.toIso8601String(),
        endDate.toIso8601String(),
      ],
      orderBy: 'created_at DESC',
    );
  }

  /// Get total sales for a financial shift
  Future<double> getTotalSalesForShift(String financialShiftId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as total 
      FROM $tableName 
      WHERE financial_shift_id = ?
    ''', [financialShiftId]);
    
    if (result.isEmpty) return 0;
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// Get sales totals by payment method for a shift
  Future<Map<PaymentMethod, double>> getSalesByPaymentMethod(
    String financialShiftId,
  ) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT payment_method, COALESCE(SUM(amount), 0) as total 
      FROM $tableName 
      WHERE financial_shift_id = ? 
      GROUP BY payment_method
    ''', [financialShiftId]);
    
    final Map<PaymentMethod, double> totals = {};
    for (final row in result) {
      final method = PaymentMethod.fromString(row['payment_method'] as String);
      totals[method] = (row['total'] as num?)?.toDouble() ?? 0;
    }
    return totals;
  }

  /// Get daily sales totals for a branch
  Future<List<Map<String, dynamic>>> getDailySalesTotals(
    String branchId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT 
        DATE(created_at) as date,
        payment_method,
        COUNT(*) as transaction_count,
        COALESCE(SUM(amount), 0) as total
      FROM $tableName 
      WHERE branch_id = ? 
        AND created_at >= ? 
        AND created_at <= ?
      GROUP BY DATE(created_at), payment_method
      ORDER BY date DESC, payment_method
    ''', [branchId, startDate.toIso8601String(), endDate.toIso8601String()]);
  }

  /// Get sales count for a financial shift
  Future<int> getSalesCountForShift(String financialShiftId) async {
    return count(
      where: 'financial_shift_id = ?',
      whereArgs: [financialShiftId],
    );
  }

  /// Get recent sales for a branch
  Future<List<ShiftSale>> getRecentSales(String branchId, {int limit = 50}) async {
    return getAll(
      where: 'branch_id = ?',
      whereArgs: [branchId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  /// Get total cash sales for a shift (for drawer reconciliation)
  Future<double> getCashSalesForShift(String financialShiftId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as total 
      FROM $tableName 
      WHERE financial_shift_id = ? AND payment_method = 'cash'
    ''', [financialShiftId]);
    
    if (result.isEmpty) return 0;
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }
}
