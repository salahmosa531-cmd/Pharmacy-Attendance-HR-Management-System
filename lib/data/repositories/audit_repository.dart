import '../models/audit_log_model.dart';
import 'base_repository.dart';

/// Repository for audit log operations
class AuditRepository extends BaseRepository<AuditLog> {
  static AuditRepository? _instance;
  
  AuditRepository._();
  
  static AuditRepository get instance {
    _instance ??= AuditRepository._();
    return _instance!;
  }
  
  @override
  String get tableName => 'audit_logs';
  
  @override
  AuditLog fromMap(Map<String, dynamic> map) => AuditLog.fromMap(map);
  
  @override
  Map<String, dynamic> toMap(AuditLog item) => item.toMap();
  
  /// Log an action
  Future<void> log({
    required String id,
    String? branchId,
    String? userId,
    required AuditAction action,
    required AuditEntityType entityType,
    String? entityId,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
    String? description,
    String? deviceId,
  }) async {
    final auditLog = AuditLog(
      id: id,
      branchId: branchId,
      userId: userId,
      action: action,
      entityType: entityType,
      entityId: entityId ?? '',
      oldValues: oldValues,
      newValues: newValues,
      description: description,
      deviceId: deviceId,
      createdAt: DateTime.now(),
    );
    
    await insert(auditLog);
  }
  
  /// Get logs with filters
  Future<List<AuditLog>> getLogs(
    String branchId, {
    AuditAction? action,
    AuditEntityType? entityType,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 100,
    int offset = 0,
  }) async {
    final conditions = <String>['branch_id = ?'];
    final whereArgs = <dynamic>[branchId];
    
    if (action != null) {
      conditions.add('action = ?');
      whereArgs.add(action.value);
    }
    
    if (entityType != null) {
      conditions.add('entity_type = ?');
      whereArgs.add(entityType.value);
    }
    
    if (startDate != null) {
      conditions.add('timestamp >= ?');
      whereArgs.add(startDate.toIso8601String());
    }
    
    if (endDate != null) {
      conditions.add('timestamp <= ?');
      whereArgs.add(endDate.toIso8601String());
    }
    
    return await getAll(
      where: conditions.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
  }
  
  /// Get logs by branch
  Future<List<AuditLog>> getByBranch(
    String branchId, {
    int limit = 100,
    int offset = 0,
  }) async {
    return await getAll(
      where: 'branch_id = ?',
      whereArgs: [branchId],
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
  }
  
  /// Get logs by user
  Future<List<AuditLog>> getByUser(
    String userId, {
    int limit = 100,
    int offset = 0,
  }) async {
    return await getAll(
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
  }
  
  /// Get logs by entity
  Future<List<AuditLog>> getByEntity(
    AuditEntityType entityType,
    String entityId, {
    int limit = 100,
    int offset = 0,
  }) async {
    return await getAll(
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType.value, entityId],
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
  }
  
  /// Get logs by action type
  Future<List<AuditLog>> getByAction(
    AuditAction action, {
    String? branchId,
    int limit = 100,
    int offset = 0,
  }) async {
    String where = 'action = ?';
    List<dynamic> whereArgs = [action.value];
    
    if (branchId != null) {
      where += ' AND branch_id = ?';
      whereArgs.add(branchId);
    }
    
    return await getAll(
      where: where,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
  }
  
  /// Get logs for date range
  Future<List<AuditLog>> getByDateRange(
    DateTime startDate,
    DateTime endDate, {
    String? branchId,
    String? userId,
    AuditEntityType? entityType,
    int limit = 500,
    int offset = 0,
  }) async {
    final conditions = <String>['timestamp >= ? AND timestamp <= ?'];
    final whereArgs = <dynamic>[
      startDate.toIso8601String(),
      endDate.toIso8601String(),
    ];
    
    if (branchId != null) {
      conditions.add('branch_id = ?');
      whereArgs.add(branchId);
    }
    
    if (userId != null) {
      conditions.add('user_id = ?');
      whereArgs.add(userId);
    }
    
    if (entityType != null) {
      conditions.add('entity_type = ?');
      whereArgs.add(entityType.value);
    }
    
    return await getAll(
      where: conditions.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
  }
  
  /// Get attendance-related logs (clock in/out, late forgiveness, overrides)
  Future<List<AuditLog>> getAttendanceLogs(
    String branchId, {
    DateTime? date,
    int limit = 100,
    int offset = 0,
  }) async {
    String where = 'branch_id = ? AND action IN (?, ?, ?, ?)';
    List<dynamic> whereArgs = [
      branchId,
      AuditAction.clockIn.value,
      AuditAction.clockOut.value,
      AuditAction.forgiveLateness.value,
      AuditAction.manualOverride.value,
    ];
    
    if (date != null) {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      where += ' AND timestamp >= ? AND timestamp < ?';
      whereArgs.addAll([startOfDay.toIso8601String(), endOfDay.toIso8601String()]);
    }
    
    return await getAll(
      where: where,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
  }
  
  /// Get security-related logs (login, logout, device auth)
  Future<List<AuditLog>> getSecurityLogs(
    String branchId, {
    int limit = 100,
    int offset = 0,
  }) async {
    return await getAll(
      where: 'branch_id = ? AND action IN (?, ?, ?, ?)',
      whereArgs: [
        branchId,
        AuditAction.login.value,
        AuditAction.logout.value,
        AuditAction.deviceAuthorize.value,
        AuditAction.deviceRevoke.value,
      ],
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
  }
  
  /// Cleanup old logs (keep last X days)
  Future<int> cleanupOldLogs(int retentionDays) async {
    final cutoffDate = DateTime.now().subtract(Duration(days: retentionDays));
    final db = await database;
    return await db.delete(
      tableName,
      where: 'timestamp < ?',
      whereArgs: [cutoffDate.toIso8601String()],
    );
  }
  
  /// Get log count by action type
  Future<Map<String, int>> getActionCounts(String branchId, DateTime startDate, DateTime endDate) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT action, COUNT(*) as count
      FROM audit_logs
      WHERE branch_id = ?
        AND timestamp >= ?
        AND timestamp <= ?
      GROUP BY action
    ''', [
      branchId,
      startDate.toIso8601String(),
      endDate.toIso8601String(),
    ]);
    
    final counts = <String, int>{};
    for (final row in results) {
      counts[row['action'] as String] = row['count'] as int;
    }
    return counts;
  }
}
