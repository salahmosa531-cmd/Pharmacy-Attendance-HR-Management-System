import '../../core/enums/financial_enums.dart';
import '../models/shift_expense_model.dart';
import 'base_repository.dart';

/// Repository for shift expense operations
class ShiftExpenseRepository extends BaseRepository<ShiftExpense> {
  static final ShiftExpenseRepository _instance = ShiftExpenseRepository._();
  static ShiftExpenseRepository get instance => _instance;
  
  ShiftExpenseRepository._();

  @override
  String get tableName => 'shift_expenses';

  @override
  ShiftExpense fromMap(Map<String, dynamic> map) => ShiftExpense.fromMap(map);

  @override
  Map<String, dynamic> toMap(ShiftExpense item) => item.toMap();

  /// Get all expenses for a financial shift
  Future<List<ShiftExpense>> getByFinancialShift(String financialShiftId) async {
    return getAll(
      where: 'financial_shift_id = ?',
      whereArgs: [financialShiftId],
      orderBy: 'created_at DESC',
    );
  }

  /// Get expenses for a branch in date range
  Future<List<ShiftExpense>> getByDateRange(
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

  /// Get total expenses for a financial shift
  Future<double> getTotalExpensesForShift(String financialShiftId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as total 
      FROM $tableName 
      WHERE financial_shift_id = ?
    ''', [financialShiftId]);
    
    if (result.isEmpty) return 0;
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// Get expenses totals by category for a shift
  Future<Map<ExpenseCategory, double>> getExpensesByCategory(
    String financialShiftId,
  ) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT category, COALESCE(SUM(amount), 0) as total 
      FROM $tableName 
      WHERE financial_shift_id = ? 
      GROUP BY category
    ''', [financialShiftId]);
    
    final Map<ExpenseCategory, double> totals = {};
    for (final row in result) {
      final category = ExpenseCategory.fromString(row['category'] as String);
      totals[category] = (row['total'] as num?)?.toDouble() ?? 0;
    }
    return totals;
  }

  /// Get daily expense totals for a branch
  Future<List<Map<String, dynamic>>> getDailyExpenseTotals(
    String branchId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT 
        DATE(created_at) as date,
        category,
        COUNT(*) as expense_count,
        COALESCE(SUM(amount), 0) as total
      FROM $tableName 
      WHERE branch_id = ? 
        AND created_at >= ? 
        AND created_at <= ?
      GROUP BY DATE(created_at), category
      ORDER BY date DESC, category
    ''', [branchId, startDate.toIso8601String(), endDate.toIso8601String()]);
  }

  /// Get expense count for a financial shift
  Future<int> getExpenseCountForShift(String financialShiftId) async {
    return count(
      where: 'financial_shift_id = ?',
      whereArgs: [financialShiftId],
    );
  }

  /// Get recent expenses for a branch
  Future<List<ShiftExpense>> getRecentExpenses(
    String branchId, {
    int limit = 50,
  }) async {
    return getAll(
      where: 'branch_id = ?',
      whereArgs: [branchId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  /// Get unapproved expenses
  Future<List<ShiftExpense>> getUnapprovedExpenses(String branchId) async {
    return getAll(
      where: 'branch_id = ? AND approved_by IS NULL',
      whereArgs: [branchId],
      orderBy: 'created_at DESC',
    );
  }

  /// Approve an expense
  Future<void> approveExpense(String expenseId, String approvedBy) async {
    final db = await database;
    await db.update(
      tableName,
      {'approved_by': approvedBy},
      where: 'id = ?',
      whereArgs: [expenseId],
    );
  }
}
