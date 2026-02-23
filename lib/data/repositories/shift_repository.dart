import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/shift_model.dart';
import 'base_repository.dart';

/// Repository for shift operations
class ShiftRepository extends BaseRepository<Shift> {
  static ShiftRepository? _instance;
  
  ShiftRepository._();
  
  static ShiftRepository get instance {
    _instance ??= ShiftRepository._();
    return _instance!;
  }
  
  @override
  String get tableName => 'shifts';
  
  @override
  Shift fromMap(Map<String, dynamic> map) => Shift.fromMap(map);
  
  @override
  Map<String, dynamic> toMap(Shift item) => item.toMap();
  
  /// Get shifts by branch
  Future<List<Shift>> getByBranch(String branchId, {bool activeOnly = true}) async {
    String where = 'branch_id = ?';
    if (activeOnly) {
      where += ' AND is_active = 1';
    }
    
    return await getAll(
      where: where,
      whereArgs: [branchId],
      orderBy: 'start_time ASC',
    );
  }
  
  /// Get shift by name
  Future<Shift?> getByName(String branchId, String name) async {
    final results = await getAll(
      where: 'branch_id = ? AND name = ?',
      whereArgs: [branchId, name],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }
  
  /// Get current shift based on time
  Future<Shift?> getCurrentShift(String branchId, TimeOfDay currentTime) async {
    final shifts = await getByBranch(branchId);
    
    for (final shift in shifts) {
      if (shift.isTimeWithinShift(currentTime)) {
        return shift;
      }
    }
    
    return null;
  }
  
  /// Get shift for employee on a specific date
  Future<Shift?> getEmployeeShiftForDate(String employeeId, DateTime date) async {
    // First check for daily override
    final db = await database;
    final overrideResults = await db.query(
      'employee_shift_assignments',
      where: 'employee_id = ? AND date = ?',
      whereArgs: [employeeId, date.toIso8601String().split('T')[0]],
      limit: 1,
    );
    
    if (overrideResults.isNotEmpty) {
      final shiftId = overrideResults.first['shift_id'] as String;
      return await getById(shiftId);
    }
    
    // Fall back to assigned shift
    final employeeResults = await db.query(
      'employees',
      columns: ['assigned_shift_id'],
      where: 'id = ?',
      whereArgs: [employeeId],
      limit: 1,
    );
    
    if (employeeResults.isNotEmpty && employeeResults.first['assigned_shift_id'] != null) {
      final shiftId = employeeResults.first['assigned_shift_id'] as String;
      return await getById(shiftId);
    }
    
    return null;
  }
  
  /// Update shift active status
  Future<void> setActive(String shiftId, bool isActive) async {
    final db = await database;
    await db.update(
      tableName,
      {
        'is_active': isActive ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [shiftId],
    );
  }
  
  /// Check if shift name exists
  Future<bool> nameExists(String branchId, String name, {String? excludeId}) async {
    String where = 'branch_id = ? AND LOWER(name) = LOWER(?)';
    List<dynamic> whereArgs = [branchId, name];
    
    if (excludeId != null) {
      where += ' AND id != ?';
      whereArgs.add(excludeId);
    }
    
    final count = await this.count(where: where, whereArgs: whereArgs);
    return count > 0;
  }
  
  /// Get shift count by branch
  Future<int> getCountByBranch(String branchId, {bool activeOnly = true}) async {
    String where = 'branch_id = ?';
    if (activeOnly) {
      where += ' AND is_active = 1';
    }
    
    return await count(
      where: where,
      whereArgs: [branchId],
    );
  }
  
  /// Assign shift override for employee on specific date
  Future<void> assignShiftOverride({
    required String id,
    required String employeeId,
    required String shiftId,
    required DateTime date,
    required String createdBy,
  }) async {
    final db = await database;
    await db.insert(
      'employee_shift_assignments',
      {
        'id': id,
        'employee_id': employeeId,
        'shift_id': shiftId,
        'date': date.toIso8601String().split('T')[0],
        'is_override': 1,
        'created_by': createdBy,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  
  /// Remove shift override for employee on specific date
  Future<void> removeShiftOverride(String employeeId, DateTime date) async {
    final db = await database;
    await db.delete(
      'employee_shift_assignments',
      where: 'employee_id = ? AND date = ? AND is_override = 1',
      whereArgs: [employeeId, date.toIso8601String().split('T')[0]],
    );
  }
  
  /// Get shift overrides for date range
  Future<List<Map<String, dynamic>>> getShiftOverrides(
    String branchId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT esa.*, e.full_name as employee_name, s.name as shift_name
      FROM employee_shift_assignments esa
      INNER JOIN employees e ON esa.employee_id = e.id
      INNER JOIN shifts s ON esa.shift_id = s.id
      WHERE e.branch_id = ?
        AND esa.date >= ?
        AND esa.date <= ?
        AND esa.is_override = 1
      ORDER BY esa.date ASC, e.full_name ASC
    ''', [
      branchId,
      startDate.toIso8601String().split('T')[0],
      endDate.toIso8601String().split('T')[0],
    ]);
  }
  
  /// Check if an employee is scheduled for the current time
  /// Returns the scheduled shift if within shift window, null otherwise
  Future<Shift?> getEmployeeCurrentScheduledShift(String employeeId) async {
    final now = DateTime.now();
    final currentTime = TimeOfDay.fromDateTime(now);
    
    // Get employee's shift for today
    final shift = await getEmployeeShiftForDate(employeeId, now);
    
    if (shift == null) return null;
    
    // Check if current time is within the shift window (including grace period)
    if (shift.isTimeWithinShift(currentTime, includeGrace: true)) {
      return shift;
    }
    
    return null;
  }
  
  /// Get employees scheduled for a specific shift at current time
  Future<List<String>> getScheduledEmployeesForCurrentShift(String branchId) async {
    final now = DateTime.now();
    final currentTime = TimeOfDay.fromDateTime(now);
    final todayDate = now.toIso8601String().split('T')[0];
    final db = await database;
    
    // Get the current shift based on time
    final currentShift = await getCurrentShift(branchId, currentTime);
    if (currentShift == null) return [];
    
    // Find employees with daily overrides to this shift today
    final overrideResults = await db.rawQuery('''
      SELECT DISTINCT e.id
      FROM employees e
      INNER JOIN employee_shift_assignments esa ON e.id = esa.employee_id
      WHERE e.branch_id = ?
        AND esa.shift_id = ?
        AND esa.date = ?
        AND e.is_active = 1
    ''', [branchId, currentShift.id, todayDate]);
    
    // Find employees with this shift as their default assigned shift
    final defaultResults = await db.rawQuery('''
      SELECT DISTINCT e.id
      FROM employees e
      WHERE e.branch_id = ?
        AND e.assigned_shift_id = ?
        AND e.is_active = 1
        AND e.id NOT IN (
          SELECT employee_id FROM employee_shift_assignments WHERE date = ?
        )
    ''', [branchId, currentShift.id, todayDate]);
    
    final employeeIds = <String>{};
    for (final row in overrideResults) {
      employeeIds.add(row['id'] as String);
    }
    for (final row in defaultResults) {
      employeeIds.add(row['id'] as String);
    }
    
    return employeeIds.toList();
  }
}
