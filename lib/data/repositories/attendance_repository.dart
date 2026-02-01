import '../models/attendance_model.dart';
import '../../core/constants/app_constants.dart';
import 'base_repository.dart';

/// Repository for attendance operations
class AttendanceRepository extends BaseRepository<AttendanceRecord> {
  static AttendanceRepository? _instance;
  
  AttendanceRepository._();
  
  static AttendanceRepository get instance {
    _instance ??= AttendanceRepository._();
    return _instance!;
  }
  
  @override
  String get tableName => 'attendance_records';
  
  @override
  AttendanceRecord fromMap(Map<String, dynamic> map) => AttendanceRecord.fromMap(map);
  
  @override
  Map<String, dynamic> toMap(AttendanceRecord item) => item.toMap();
  
  /// Get attendance record for employee on specific date
  Future<AttendanceRecord?> getByEmployeeDate(String employeeId, DateTime date) async {
    final dateStr = date.toIso8601String().split('T')[0];
    final results = await getAll(
      where: 'employee_id = ? AND date = ?',
      whereArgs: [employeeId, dateStr],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }
  
  /// Get attendance records by branch for a date
  Future<List<AttendanceRecord>> getByBranchDate(String branchId, DateTime date) async {
    final dateStr = date.toIso8601String().split('T')[0];
    return await getAll(
      where: 'branch_id = ? AND date = ?',
      whereArgs: [branchId, dateStr],
      orderBy: 'clock_in_time ASC',
    );
  }
  
  /// Get attendance records by branch for date range
  Future<List<AttendanceRecord>> getByBranchDateRange(
    String branchId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate.toIso8601String().split('T')[0];
    return await getAll(
      where: 'branch_id = ? AND date >= ? AND date <= ?',
      whereArgs: [branchId, startStr, endStr],
      orderBy: 'date ASC, clock_in_time ASC',
    );
  }
  
  /// Get attendance records for employee in date range
  Future<List<AttendanceRecord>> getByEmployeeDateRange(
    String employeeId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate.toIso8601String().split('T')[0];
    return await getAll(
      where: 'employee_id = ? AND date >= ? AND date <= ?',
      whereArgs: [employeeId, startStr, endStr],
      orderBy: 'date ASC',
    );
  }
  
  /// Get employees currently clocked in
  Future<List<Map<String, dynamic>>> getCurrentlyClockedIn(String branchId) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final db = await database;
    return await db.rawQuery('''
      SELECT ar.*, e.full_name, e.employee_code, e.job_title, s.name as shift_name
      FROM attendance_records ar
      INNER JOIN employees e ON ar.employee_id = e.id
      LEFT JOIN shifts s ON ar.shift_id = s.id
      WHERE ar.branch_id = ?
        AND ar.date = ?
        AND ar.clock_in_time IS NOT NULL
        AND ar.clock_out_time IS NULL
      ORDER BY ar.clock_in_time ASC
    ''', [branchId, today]);
  }
  
  /// Get late arrivals for a date
  Future<List<Map<String, dynamic>>> getLateArrivals(String branchId, DateTime date) async {
    final dateStr = date.toIso8601String().split('T')[0];
    final db = await database;
    return await db.rawQuery('''
      SELECT ar.*, e.full_name, e.employee_code, s.name as shift_name
      FROM attendance_records ar
      INNER JOIN employees e ON ar.employee_id = e.id
      LEFT JOIN shifts s ON ar.shift_id = s.id
      WHERE ar.branch_id = ?
        AND ar.date = ?
        AND ar.late_minutes > 0
        AND ar.is_late_forgiven = 0
      ORDER BY ar.late_minutes DESC
    ''', [branchId, dateStr]);
  }
  
  /// Get absent employees for a date
  Future<List<Map<String, dynamic>>> getAbsentEmployees(String branchId, DateTime date) async {
    final dateStr = date.toIso8601String().split('T')[0];
    final db = await database;
    return await db.rawQuery('''
      SELECT e.id, e.full_name, e.employee_code, e.job_title, s.name as shift_name
      FROM employees e
      LEFT JOIN shifts s ON e.assigned_shift_id = s.id
      WHERE e.branch_id = ?
        AND e.is_active = 1
        AND e.status = 'active'
        AND e.id NOT IN (
          SELECT employee_id FROM attendance_records WHERE date = ?
        )
      ORDER BY e.full_name ASC
    ''', [branchId, dateStr]);
  }
  
  /// Record clock in
  Future<void> clockIn(AttendanceRecord record) async {
    await insert(record);
  }
  
  /// Record clock out
  Future<void> clockOut(
    String recordId, {
    required DateTime clockOutTime,
    required AttendanceMethod method,
    required String deviceId,
    required int workedMinutes,
    required int overtimeMinutes,
    required int earlyLeaveMinutes,
  }) async {
    final db = await database;
    await db.update(
      tableName,
      {
        'clock_out_time': clockOutTime.toIso8601String(),
        'clock_out_method': method.value,
        'clock_out_device_id': deviceId,
        'worked_minutes': workedMinutes,
        'overtime_minutes': overtimeMinutes,
        'early_leave_minutes': earlyLeaveMinutes,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }
  
  /// Forgive lateness
  Future<void> forgiveLateness(
    String recordId, {
    required String reason,
    required String forgivenBy,
  }) async {
    final db = await database;
    await db.update(
      tableName,
      {
        'is_late_forgiven': 1,
        'late_forgiveness_reason': reason,
        'late_forgiven_by': forgivenBy,
        'late_forgiven_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }
  
  /// Manual override
  Future<void> manualOverride(
    String recordId, {
    DateTime? clockInTime,
    DateTime? clockOutTime,
    required String modifiedBy,
    required String reason,
  }) async {
    final db = await database;
    final updates = <String, dynamic>{
      'is_manually_modified': 1,
      'modified_by': modifiedBy,
      'modified_at': DateTime.now().toIso8601String(),
      'modification_reason': reason,
      'updated_at': DateTime.now().toIso8601String(),
    };
    
    if (clockInTime != null) {
      updates['clock_in_time'] = clockInTime.toIso8601String();
    }
    if (clockOutTime != null) {
      updates['clock_out_time'] = clockOutTime.toIso8601String();
    }
    
    await db.update(
      tableName,
      updates,
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }
  
  /// Get attendance summary for employee
  Future<Map<String, dynamic>> getEmployeeSummary(
    String employeeId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate.toIso8601String().split('T')[0];
    final db = await database;
    
    final result = await db.rawQuery('''
      SELECT
        COUNT(*) as total_days,
        SUM(CASE WHEN status = 'present' THEN 1 ELSE 0 END) as present_days,
        SUM(CASE WHEN status = 'late' THEN 1 ELSE 0 END) as late_days,
        SUM(CASE WHEN status = 'absent' THEN 1 ELSE 0 END) as absent_days,
        SUM(late_minutes) as total_late_minutes,
        SUM(early_leave_minutes) as total_early_leave_minutes,
        SUM(worked_minutes) as total_worked_minutes,
        SUM(overtime_minutes) as total_overtime_minutes
      FROM attendance_records
      WHERE employee_id = ?
        AND date >= ?
        AND date <= ?
    ''', [employeeId, startStr, endStr]);
    
    return result.first;
  }
  
  /// Get branch daily summary
  Future<Map<String, dynamic>> getBranchDailySummary(String branchId, DateTime date) async {
    final dateStr = date.toIso8601String().split('T')[0];
    final db = await database;
    
    final result = await db.rawQuery('''
      SELECT
        COUNT(*) as total_attendance,
        SUM(CASE WHEN clock_in_time IS NOT NULL THEN 1 ELSE 0 END) as clocked_in,
        SUM(CASE WHEN clock_out_time IS NOT NULL THEN 1 ELSE 0 END) as clocked_out,
        SUM(CASE WHEN late_minutes > 0 AND is_late_forgiven = 0 THEN 1 ELSE 0 END) as late_count,
        SUM(CASE WHEN early_leave_minutes > 0 THEN 1 ELSE 0 END) as early_leave_count,
        SUM(overtime_minutes) as total_overtime_minutes,
        AVG(worked_minutes) as avg_worked_minutes
      FROM attendance_records
      WHERE branch_id = ?
        AND date = ?
    ''', [branchId, dateStr]);
    
    // Get absent count
    final absentResult = await db.rawQuery('''
      SELECT COUNT(*) as absent_count
      FROM employees e
      WHERE e.branch_id = ?
        AND e.is_active = 1
        AND e.status = 'active'
        AND e.id NOT IN (
          SELECT employee_id FROM attendance_records WHERE date = ?
        )
    ''', [branchId, dateStr]);
    
    return {
      ...result.first,
      'absent_count': absentResult.first['absent_count'],
    };
  }
  
  /// Check for duplicate clock in (anti-fraud)
  Future<bool> hasDuplicateClockIn(String employeeId, DateTime date) async {
    final dateStr = date.toIso8601String().split('T')[0];
    final count = await this.count(
      where: 'employee_id = ? AND date = ? AND clock_in_time IS NOT NULL',
      whereArgs: [employeeId, dateStr],
    );
    return count > 0;
  }
  
  /// Get recent attendance by QR token
  Future<AttendanceRecord?> getByQrToken(String token) async {
    final results = await getAll(
      where: 'qr_token = ?',
      whereArgs: [token],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }
  
  /// Auto clock out employees who forgot to clock out
  Future<int> autoClockOutMissing(String branchId, DateTime date) async {
    final dateStr = date.toIso8601String().split('T')[0];
    final db = await database;
    
    return await db.rawUpdate('''
      UPDATE attendance_records
      SET 
        clock_out_time = scheduled_end,
        clock_out_method = 'manual',
        is_manually_modified = 1,
        modification_reason = 'Auto clock-out: Employee forgot to clock out',
        updated_at = ?
      WHERE branch_id = ?
        AND date = ?
        AND clock_in_time IS NOT NULL
        AND clock_out_time IS NULL
        AND scheduled_end IS NOT NULL
    ''', [DateTime.now().toIso8601String(), branchId, dateStr]);
  }
  
  /// Get daily report
  Future<List<Map<String, dynamic>>> getDailyReport(String branchId, DateTime date) async {
    final dateStr = date.toIso8601String().split('T')[0];
    final db = await database;
    return await db.rawQuery('''
      SELECT 
        e.full_name as employee_name,
        ar.status,
        ar.clock_in_time as clock_in,
        ar.clock_out_time as clock_out,
        ar.worked_minutes / 60.0 as worked_hours,
        ar.late_minutes
      FROM employees e
      LEFT JOIN attendance_records ar ON e.id = ar.employee_id AND ar.date = ?
      WHERE e.branch_id = ?
        AND e.status = 'active'
      ORDER BY e.full_name ASC
    ''', [dateStr, branchId]);
  }
  
  /// Get date range report
  Future<List<Map<String, dynamic>>> getDateRangeReport(
    String branchId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate.toIso8601String().split('T')[0];
    final db = await database;
    return await db.rawQuery('''
      SELECT 
        e.full_name as employee_name,
        SUM(CASE WHEN ar.status = 'present' THEN 1 ELSE 0 END) as present_count,
        SUM(CASE WHEN ar.late_minutes > 0 THEN 1 ELSE 0 END) as late_count,
        SUM(CASE WHEN ar.status = 'absent' OR ar.id IS NULL THEN 1 ELSE 0 END) as absent_count,
        SUM(COALESCE(ar.worked_minutes, 0)) / 60.0 as total_hours,
        SUM(COALESCE(ar.late_minutes, 0)) as total_late_minutes
      FROM employees e
      LEFT JOIN attendance_records ar ON e.id = ar.employee_id 
        AND ar.date >= ? AND ar.date <= ?
      WHERE e.branch_id = ?
        AND e.status = 'active'
      GROUP BY e.id, e.full_name
      ORDER BY e.full_name ASC
    ''', [startStr, endStr, branchId]);
  }
  
  /// Get employee report
  Future<List<Map<String, dynamic>>> getEmployeeReport(
    String employeeId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate.toIso8601String().split('T')[0];
    final db = await database;
    return await db.rawQuery('''
      SELECT 
        ar.date,
        ar.status,
        ar.clock_in_time as clock_in,
        ar.clock_out_time as clock_out,
        ar.worked_minutes / 60.0 as worked_hours,
        ar.late_minutes
      FROM attendance_records ar
      WHERE ar.employee_id = ?
        AND ar.date >= ?
        AND ar.date <= ?
      ORDER BY ar.date ASC
    ''', [employeeId, startStr, endStr]);
  }
}
