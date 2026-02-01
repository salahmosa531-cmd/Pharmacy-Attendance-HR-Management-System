import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/attendance_model.dart';
import '../../data/models/employee_model.dart';
import '../../data/models/shift_model.dart';
import '../../data/models/audit_log_model.dart';
import '../../data/repositories/attendance_repository.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/shift_repository.dart';
import '../../data/repositories/audit_repository.dart';
import '../constants/app_constants.dart';
import 'auth_service.dart';
import 'device_service.dart';

/// Service for handling attendance operations
class AttendanceService {
  static AttendanceService? _instance;
  
  final AttendanceRepository _attendanceRepository = AttendanceRepository.instance;
  final EmployeeRepository _employeeRepository = EmployeeRepository.instance;
  final ShiftRepository _shiftRepository = ShiftRepository.instance;
  final AuditRepository _auditRepository = AuditRepository.instance;
  final AuthService _authService = AuthService.instance;
  final DeviceService _deviceService = DeviceService.instance;
  final Uuid _uuid = const Uuid();
  
  AttendanceService._();
  
  static AttendanceService get instance {
    _instance ??= AttendanceService._();
    return _instance!;
  }
  
  /// Clock in an employee
  Future<AttendanceRecord> clockIn({
    required String employeeIdentifier,
    required AttendanceMethod method,
    String? qrToken,
  }) async {
    final branchId = _authService.currentBranch?.id;
    if (branchId == null) {
      throw Exception('No branch selected');
    }
    
    final deviceId = await _deviceService.getDeviceId();
    
    // Verify device is authorized
    if (!await _deviceService.isDeviceAuthorized(branchId)) {
      throw Exception('This device is not authorized for this branch');
    }
    
    // Find employee
    final employee = await _employeeRepository.findForAttendance(branchId, employeeIdentifier);
    if (employee == null) {
      throw Exception('Employee not found or cannot attend');
    }
    
    // Check for duplicate clock in
    final today = DateTime.now();
    if (await _attendanceRepository.hasDuplicateClockIn(employee.id, today)) {
      throw Exception('Employee has already clocked in today');
    }
    
    // Get employee's shift for today
    final shift = await _shiftRepository.getEmployeeShiftForDate(employee.id, today);
    
    // Calculate late minutes
    int lateMinutes = 0;
    TimeOfDay? scheduledStart;
    TimeOfDay? scheduledEnd;
    
    if (shift != null) {
      scheduledStart = shift.startTime;
      scheduledEnd = shift.endTime;
      
      final clockInTime = TimeOfDay.fromDateTime(today);
      lateMinutes = shift.calculateLateMinutes(clockInTime);
    }
    
    // Determine attendance status
    AttendanceStatus status = AttendanceStatus.present;
    if (lateMinutes > 0) {
      status = AttendanceStatus.late;
    }
    
    final now = DateTime.now();
    final record = AttendanceRecord(
      id: _uuid.v4(),
      employeeId: employee.id,
      branchId: branchId,
      shiftId: shift?.id,
      date: DateTime(today.year, today.month, today.day),
      clockInTime: now,
      clockInMethod: method,
      clockInDeviceId: deviceId,
      scheduledStart: scheduledStart,
      scheduledEnd: scheduledEnd,
      lateMinutes: lateMinutes,
      status: status,
      qrToken: qrToken,
      createdAt: now,
      updatedAt: now,
    );
    
    await _attendanceRepository.insert(record);
    
    // Log the clock in
    await _auditRepository.log(
      id: _uuid.v4(),
      branchId: branchId,
      userId: _authService.currentUser?.id,
      action: AuditAction.clockIn,
      entityType: AuditEntityType.attendance,
      entityId: record.id,
      newValues: {
        'employee_id': employee.id,
        'employee_name': employee.fullName,
        'method': method.value,
        'late_minutes': lateMinutes,
      },
      deviceId: deviceId,
    );
    
    return record;
  }
  
  /// Clock out an employee
  Future<AttendanceRecord> clockOut({
    required String employeeIdentifier,
    required AttendanceMethod method,
  }) async {
    final branchId = _authService.currentBranch?.id;
    if (branchId == null) {
      throw Exception('No branch selected');
    }
    
    final deviceId = await _deviceService.getDeviceId();
    
    // Verify device is authorized
    if (!await _deviceService.isDeviceAuthorized(branchId)) {
      throw Exception('This device is not authorized for this branch');
    }
    
    // Find employee
    final employee = await _employeeRepository.findForAttendance(branchId, employeeIdentifier);
    if (employee == null) {
      throw Exception('Employee not found');
    }
    
    // Get today's attendance record
    final today = DateTime.now();
    final record = await _attendanceRepository.getByEmployeeDate(employee.id, today);
    if (record == null) {
      throw Exception('Employee has not clocked in today');
    }
    
    if (record.clockOutTime != null) {
      throw Exception('Employee has already clocked out today');
    }
    
    // Calculate worked minutes, overtime, and early leave
    final clockOutTime = DateTime.now();
    final clockInTime = record.clockInTime!;
    
    int totalMinutes = clockOutTime.difference(clockInTime).inMinutes;
    int breakMinutes = record.breakMinutes;
    int workedMinutes = totalMinutes - breakMinutes;
    
    int overtimeMinutes = 0;
    int earlyLeaveMinutes = 0;
    
    // Get shift for calculations
    final shift = record.shiftId != null 
        ? await _shiftRepository.getById(record.shiftId!)
        : null;
    
    if (shift != null) {
      // Calculate early leave
      final clockOutTOD = TimeOfDay.fromDateTime(clockOutTime);
      earlyLeaveMinutes = shift.calculateEarlyLeaveMinutes(clockOutTOD);
      
      // Calculate overtime (if worked more than shift duration)
      final shiftDuration = shift.durationMinutes;
      if (workedMinutes > shiftDuration) {
        overtimeMinutes = workedMinutes - shiftDuration;
      }
    }
    
    await _attendanceRepository.clockOut(
      record.id,
      clockOutTime: clockOutTime,
      method: method,
      deviceId: deviceId,
      workedMinutes: workedMinutes,
      overtimeMinutes: overtimeMinutes,
      earlyLeaveMinutes: earlyLeaveMinutes,
    );
    
    // Log the clock out
    await _auditRepository.log(
      id: _uuid.v4(),
      branchId: branchId,
      userId: _authService.currentUser?.id,
      action: AuditAction.clockOut,
      entityType: AuditEntityType.attendance,
      entityId: record.id,
      newValues: {
        'employee_id': employee.id,
        'employee_name': employee.fullName,
        'method': method.value,
        'worked_minutes': workedMinutes,
        'overtime_minutes': overtimeMinutes,
        'early_leave_minutes': earlyLeaveMinutes,
      },
      deviceId: deviceId,
    );
    
    // Return updated record
    return record.copyWith(
      clockOutTime: clockOutTime,
      clockOutMethod: method,
      clockOutDeviceId: deviceId,
      workedMinutes: workedMinutes,
      overtimeMinutes: overtimeMinutes,
      earlyLeaveMinutes: earlyLeaveMinutes,
      updatedAt: DateTime.now(),
    );
  }
  
  /// Forgive employee's lateness
  Future<void> forgiveLateness(String recordId, String reason) async {
    if (!_authService.hasPermission('approve_overrides')) {
      throw Exception('Unauthorized');
    }
    
    final record = await _attendanceRepository.getById(recordId);
    if (record == null) {
      throw Exception('Attendance record not found');
    }
    
    await _attendanceRepository.forgiveLateness(
      recordId,
      reason: reason,
      forgivenBy: _authService.currentUser!.id,
    );
    
    // Log the action
    await _auditRepository.log(
      id: _uuid.v4(),
      branchId: record.branchId,
      userId: _authService.currentUser!.id,
      action: AuditAction.forgiveLateness,
      entityType: AuditEntityType.attendance,
      entityId: recordId,
      oldValues: {'late_minutes': record.lateMinutes},
      newValues: {'reason': reason, 'forgiven': true},
    );
  }
  
  /// Manual override for attendance
  Future<void> manualOverride({
    required String recordId,
    DateTime? clockInTime,
    DateTime? clockOutTime,
    required String reason,
    required String password,
  }) async {
    if (!_authService.hasPermission('approve_overrides')) {
      throw Exception('Unauthorized');
    }
    
    // Verify admin password (additional security for manual overrides)
    // In production, you'd verify the password here
    
    final record = await _attendanceRepository.getById(recordId);
    if (record == null) {
      throw Exception('Attendance record not found');
    }
    
    await _attendanceRepository.manualOverride(
      recordId,
      clockInTime: clockInTime,
      clockOutTime: clockOutTime,
      modifiedBy: _authService.currentUser!.id,
      reason: reason,
    );
    
    // Log the action
    await _auditRepository.log(
      id: _uuid.v4(),
      branchId: record.branchId,
      userId: _authService.currentUser!.id,
      action: AuditAction.manualOverride,
      entityType: AuditEntityType.attendance,
      entityId: recordId,
      oldValues: {
        'clock_in_time': record.clockInTime?.toIso8601String(),
        'clock_out_time': record.clockOutTime?.toIso8601String(),
      },
      newValues: {
        'clock_in_time': clockInTime?.toIso8601String(),
        'clock_out_time': clockOutTime?.toIso8601String(),
        'reason': reason,
      },
    );
  }
  
  /// Get today's attendance for current branch
  Future<List<AttendanceRecord>> getTodayAttendance() async {
    final branchId = _authService.currentBranch?.id;
    if (branchId == null) {
      throw Exception('No branch selected');
    }
    
    return await _attendanceRepository.getByBranchDate(branchId, DateTime.now());
  }
  
  /// Get currently clocked in employees
  Future<List<Map<String, dynamic>>> getCurrentlyClockedIn() async {
    final branchId = _authService.currentBranch?.id;
    if (branchId == null) {
      throw Exception('No branch selected');
    }
    
    return await _attendanceRepository.getCurrentlyClockedIn(branchId);
  }
  
  /// Get late arrivals for today
  Future<List<Map<String, dynamic>>> getTodayLateArrivals() async {
    final branchId = _authService.currentBranch?.id;
    if (branchId == null) {
      throw Exception('No branch selected');
    }
    
    return await _attendanceRepository.getLateArrivals(branchId, DateTime.now());
  }
  
  /// Get absent employees for today
  Future<List<Map<String, dynamic>>> getTodayAbsentees() async {
    final branchId = _authService.currentBranch?.id;
    if (branchId == null) {
      throw Exception('No branch selected');
    }
    
    return await _attendanceRepository.getAbsentEmployees(branchId, DateTime.now());
  }
  
  /// Get attendance summary for current branch today
  Future<Map<String, dynamic>> getTodaySummary() async {
    final branchId = _authService.currentBranch?.id;
    if (branchId == null) {
      throw Exception('No branch selected');
    }
    
    return await _attendanceRepository.getBranchDailySummary(branchId, DateTime.now());
  }
  
  /// Auto clock out missing (run at end of day)
  Future<int> autoClockOutMissing() async {
    final branchId = _authService.currentBranch?.id;
    if (branchId == null) {
      throw Exception('No branch selected');
    }
    
    return await _attendanceRepository.autoClockOutMissing(branchId, DateTime.now());
  }
  
  /// Get employee attendance history
  Future<List<AttendanceRecord>> getEmployeeHistory(
    String employeeId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final start = startDate ?? DateTime.now().subtract(const Duration(days: 30));
    final end = endDate ?? DateTime.now();
    
    return await _attendanceRepository.getByEmployeeDateRange(employeeId, start, end);
  }
  
  /// Get employee attendance summary
  Future<Map<String, dynamic>> getEmployeeSummary(
    String employeeId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final start = startDate ?? DateTime(DateTime.now().year, DateTime.now().month, 1);
    final end = endDate ?? DateTime.now();
    
    return await _attendanceRepository.getEmployeeSummary(employeeId, start, end);
  }
}
