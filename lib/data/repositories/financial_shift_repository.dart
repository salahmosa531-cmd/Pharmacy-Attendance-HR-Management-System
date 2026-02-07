import '../models/financial_shift_model.dart';
import 'base_repository.dart';

/// Repository for financial shift operations
class FinancialShiftRepository extends BaseRepository<FinancialShift> {
  static final FinancialShiftRepository _instance = FinancialShiftRepository._();
  static FinancialShiftRepository get instance => _instance;
  
  FinancialShiftRepository._();

  @override
  String get tableName => 'financial_shifts';

  @override
  FinancialShift fromMap(Map<String, dynamic> map) => FinancialShift.fromMap(map);

  @override
  Map<String, dynamic> toMap(FinancialShift item) => item.toMap();

  /// Get all financial shifts for a branch
  Future<List<FinancialShift>> getByBranch(String branchId, {
    bool? openOnly,
    int? limit,
    int? offset,
  }) async {
    String where = 'branch_id = ?';
    List<dynamic> whereArgs = [branchId];
    
    if (openOnly == true) {
      where += ' AND status = ?';
      whereArgs.add('open');
    }
    
    return getAll(
      where: where,
      whereArgs: whereArgs,
      orderBy: 'opened_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// Get currently open shift for an employee
  Future<FinancialShift?> getOpenShiftForEmployee(String employeeId) async {
    final results = await getAll(
      where: 'employee_id = ? AND status = ?',
      whereArgs: [employeeId, 'open'],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Get currently open shift for a branch
  Future<FinancialShift?> getOpenShiftForBranch(String branchId) async {
    final results = await getAll(
      where: 'branch_id = ? AND status = ?',
      whereArgs: [branchId, 'open'],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Get all open shifts for a branch
  Future<List<FinancialShift>> getOpenShiftsForBranch(String branchId) async {
    return getAll(
      where: 'branch_id = ? AND status = ?',
      whereArgs: [branchId, 'open'],
      orderBy: 'opened_at ASC',
    );
  }

  /// Get shifts by date range
  Future<List<FinancialShift>> getByDateRange(
    String branchId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    return getAll(
      where: 'branch_id = ? AND opened_at >= ? AND opened_at <= ?',
      whereArgs: [
        branchId,
        startDate.toIso8601String(),
        endDate.toIso8601String(),
      ],
      orderBy: 'opened_at DESC',
    );
  }

  /// Close a financial shift
  Future<void> closeShift(String shiftId, DateTime closedAt) async {
    final db = await database;
    await db.update(
      tableName,
      {
        'status': 'closed',
        'closed_at': closedAt.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [shiftId],
    );
  }

  /// Get shifts count by status
  Future<Map<String, int>> getShiftCountsByStatus(String branchId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT status, COUNT(*) as count 
      FROM $tableName 
      WHERE branch_id = ? 
      GROUP BY status
    ''', [branchId]);
    
    return Map.fromEntries(
      result.map((r) => MapEntry(
        r['status'] as String,
        (r['count'] as num).toInt(),
      )),
    );
  }

  /// Check if employee has an open shift
  Future<bool> hasOpenShift(String employeeId) async {
    final count = await this.count(
      where: 'employee_id = ? AND status = ?',
      whereArgs: [employeeId, 'open'],
    );
    return count > 0;
  }
}
