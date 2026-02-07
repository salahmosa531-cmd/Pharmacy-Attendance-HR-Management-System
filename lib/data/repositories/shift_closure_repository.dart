import '../models/shift_closure_model.dart';
import 'base_repository.dart';

/// Repository for shift closure operations
class ShiftClosureRepository extends BaseRepository<ShiftClosure> {
  static final ShiftClosureRepository _instance = ShiftClosureRepository._();
  static ShiftClosureRepository get instance => _instance;
  
  ShiftClosureRepository._();

  @override
  String get tableName => 'shift_closures';

  @override
  ShiftClosure fromMap(Map<String, dynamic> map) => ShiftClosure.fromMap(map);

  @override
  Map<String, dynamic> toMap(ShiftClosure item) => item.toMap();

  /// Get closure for a financial shift
  Future<ShiftClosure?> getByFinancialShift(String financialShiftId) async {
    final results = await getAll(
      where: 'financial_shift_id = ?',
      whereArgs: [financialShiftId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Get closures for a branch by date range
  Future<List<ShiftClosure>> getByDateRange(
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

  /// Get closures with discrepancies
  Future<List<ShiftClosure>> getClosuresWithDiscrepancies(
    String branchId, {
    int? limit,
  }) async {
    return getAll(
      where: 'branch_id = ? AND difference != 0',
      whereArgs: [branchId],
      orderBy: 'ABS(difference) DESC',
      limit: limit,
    );
  }

  /// Get total shortages for a period
  Future<double> getTotalShortages(
    String branchId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(ABS(difference)), 0) as total 
      FROM $tableName 
      WHERE branch_id = ? 
        AND difference < 0
        AND created_at >= ? 
        AND created_at <= ?
    ''', [branchId, startDate.toIso8601String(), endDate.toIso8601String()]);
    
    if (result.isEmpty) return 0;
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// Get total overages for a period
  Future<double> getTotalOverages(
    String branchId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(difference), 0) as total 
      FROM $tableName 
      WHERE branch_id = ? 
        AND difference > 0
        AND created_at >= ? 
        AND created_at <= ?
    ''', [branchId, startDate.toIso8601String(), endDate.toIso8601String()]);
    
    if (result.isEmpty) return 0;
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// Get summary statistics for a period
  Future<Map<String, dynamic>> getPeriodSummary(
    String branchId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT 
        COUNT(*) as total_closures,
        COALESCE(SUM(total_sales), 0) as total_sales,
        COALESCE(SUM(total_cash_sales), 0) as total_cash,
        COALESCE(SUM(total_card_sales), 0) as total_card,
        COALESCE(SUM(total_wallet_sales), 0) as total_wallet,
        COALESCE(SUM(total_insurance_sales), 0) as total_insurance,
        COALESCE(SUM(total_credit_sales), 0) as total_credit,
        COALESCE(SUM(total_expenses), 0) as total_expenses,
        COALESCE(SUM(CASE WHEN difference < 0 THEN ABS(difference) ELSE 0 END), 0) as total_shortages,
        COALESCE(SUM(CASE WHEN difference > 0 THEN difference ELSE 0 END), 0) as total_overages,
        COUNT(CASE WHEN difference != 0 THEN 1 END) as discrepancy_count
      FROM $tableName 
      WHERE branch_id = ? 
        AND created_at >= ? 
        AND created_at <= ?
    ''', [branchId, startDate.toIso8601String(), endDate.toIso8601String()]);
    
    if (result.isEmpty) {
      return {
        'total_closures': 0,
        'total_sales': 0.0,
        'total_cash': 0.0,
        'total_card': 0.0,
        'total_wallet': 0.0,
        'total_insurance': 0.0,
        'total_credit': 0.0,
        'total_expenses': 0.0,
        'total_shortages': 0.0,
        'total_overages': 0.0,
        'discrepancy_count': 0,
      };
    }
    
    return {
      'total_closures': (result.first['total_closures'] as num?)?.toInt() ?? 0,
      'total_sales': (result.first['total_sales'] as num?)?.toDouble() ?? 0.0,
      'total_cash': (result.first['total_cash'] as num?)?.toDouble() ?? 0.0,
      'total_card': (result.first['total_card'] as num?)?.toDouble() ?? 0.0,
      'total_wallet': (result.first['total_wallet'] as num?)?.toDouble() ?? 0.0,
      'total_insurance': (result.first['total_insurance'] as num?)?.toDouble() ?? 0.0,
      'total_credit': (result.first['total_credit'] as num?)?.toDouble() ?? 0.0,
      'total_expenses': (result.first['total_expenses'] as num?)?.toDouble() ?? 0.0,
      'total_shortages': (result.first['total_shortages'] as num?)?.toDouble() ?? 0.0,
      'total_overages': (result.first['total_overages'] as num?)?.toDouble() ?? 0.0,
      'discrepancy_count': (result.first['discrepancy_count'] as num?)?.toInt() ?? 0,
    };
  }

  /// Get daily totals
  Future<List<Map<String, dynamic>>> getDailyTotals(
    String branchId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT 
        DATE(created_at) as date,
        COUNT(*) as shift_count,
        COALESCE(SUM(total_sales), 0) as total_sales,
        COALESCE(SUM(total_expenses), 0) as total_expenses,
        COALESCE(SUM(total_sales) - SUM(total_expenses), 0) as net_profit,
        COALESCE(SUM(CASE WHEN difference < 0 THEN ABS(difference) ELSE 0 END), 0) as shortages,
        COALESCE(SUM(CASE WHEN difference > 0 THEN difference ELSE 0 END), 0) as overages
      FROM $tableName 
      WHERE branch_id = ? 
        AND created_at >= ? 
        AND created_at <= ?
      GROUP BY DATE(created_at)
      ORDER BY date DESC
    ''', [branchId, startDate.toIso8601String(), endDate.toIso8601String()]);
  }

  /// Verify a closure (by admin/manager)
  Future<void> verifyClosure(String closureId, String verifiedBy) async {
    final db = await database;
    await db.update(
      tableName,
      {'verified_by': verifiedBy},
      where: 'id = ?',
      whereArgs: [closureId],
    );
  }
}
