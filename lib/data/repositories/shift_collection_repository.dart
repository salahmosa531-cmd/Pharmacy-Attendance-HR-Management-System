import '../../core/enums/financial_enums.dart';
import '../models/shift_collection_model.dart';
import 'base_repository.dart';

/// Repository for shift collection (تحصيلات) operations
/// 
/// SINGLE-BRANCH ARCHITECTURE: All queries use hardcoded branch_id = '1'
class ShiftCollectionRepository extends BaseRepository<ShiftCollection> {
  static final ShiftCollectionRepository _instance = ShiftCollectionRepository._();
  static ShiftCollectionRepository get instance => _instance;
  
  ShiftCollectionRepository._();

  @override
  String get tableName => 'shift_collections';

  @override
  ShiftCollection fromMap(Map<String, dynamic> map) => ShiftCollection.fromMap(map);

  @override
  Map<String, dynamic> toMap(ShiftCollection item) => item.toMap();

  /// Get all collections for a financial shift
  Future<List<ShiftCollection>> getByFinancialShift(String financialShiftId) async {
    return getAll(
      where: 'financial_shift_id = ?',
      whereArgs: [financialShiftId],
      orderBy: 'created_at DESC',
    );
  }

  /// Get collections by date range
  Future<List<ShiftCollection>> getByDateRange(
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

  /// Get total collections for a shift
  Future<double> getTotalCollectionsForShift(String financialShiftId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as total 
      FROM $tableName 
      WHERE financial_shift_id = ?
    ''', [financialShiftId]);
    
    if (result.isEmpty) return 0;
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// Get collections grouped by type for a shift
  Future<Map<CollectionType, double>> getCollectionsByType(
    String financialShiftId,
  ) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT collection_type, COALESCE(SUM(amount), 0) as total 
      FROM $tableName 
      WHERE financial_shift_id = ?
      GROUP BY collection_type
    ''', [financialShiftId]);
    
    final map = <CollectionType, double>{};
    for (final row in result) {
      final type = CollectionType.fromString(row['collection_type'] as String);
      map[type] = (row['total'] as num?)?.toDouble() ?? 0;
    }
    return map;
  }

  /// Get collections count for a shift
  Future<int> getCollectionsCountForShift(String financialShiftId) async {
    return count(
      where: 'financial_shift_id = ?',
      whereArgs: [financialShiftId],
    );
  }

  /// Get recent collections for a branch
  Future<List<ShiftCollection>> getRecentCollections({
    required String branchId,
    int limit = 50,
  }) async {
    return getAll(
      where: 'branch_id = ?',
      whereArgs: [branchId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }
}
