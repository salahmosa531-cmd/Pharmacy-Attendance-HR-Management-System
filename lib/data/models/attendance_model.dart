import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';

/// Attendance record model
class AttendanceRecord extends Equatable {
  final String id;
  final String employeeId;
  final String branchId;
  final String? shiftId;
  final DateTime date;
  final DateTime? clockInTime;
  final DateTime? clockOutTime;
  final AttendanceMethod? clockInMethod;
  final AttendanceMethod? clockOutMethod;
  final String? clockInDeviceId;
  final String? clockOutDeviceId;
  final TimeOfDay? scheduledStart;
  final TimeOfDay? scheduledEnd;
  final int lateMinutes;
  final int earlyLeaveMinutes;
  final int workedMinutes;
  final int overtimeMinutes;
  final int breakMinutes;
  final AttendanceStatus status;
  final bool isLateForgiven;
  final String? lateForgivenessReason;
  final String? lateForgivenBy;
  final DateTime? lateForgivenAt;
  final bool isManuallyModified;
  final String? modifiedBy;
  final DateTime? modifiedAt;
  final String? modificationReason;
  final String? notes;
  final String? qrToken;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? syncedAt;

  const AttendanceRecord({
    required this.id,
    required this.employeeId,
    required this.branchId,
    this.shiftId,
    required this.date,
    this.clockInTime,
    this.clockOutTime,
    this.clockInMethod,
    this.clockOutMethod,
    this.clockInDeviceId,
    this.clockOutDeviceId,
    this.scheduledStart,
    this.scheduledEnd,
    this.lateMinutes = 0,
    this.earlyLeaveMinutes = 0,
    this.workedMinutes = 0,
    this.overtimeMinutes = 0,
    this.breakMinutes = 0,
    this.status = AttendanceStatus.present,
    this.isLateForgiven = false,
    this.lateForgivenessReason,
    this.lateForgivenBy,
    this.lateForgivenAt,
    this.isManuallyModified = false,
    this.modifiedBy,
    this.modifiedAt,
    this.modificationReason,
    this.notes,
    this.qrToken,
    required this.createdAt,
    required this.updatedAt,
    this.syncedAt,
  });

  factory AttendanceRecord.fromMap(Map<String, dynamic> map) {
    TimeOfDay? parseTimeOfDay(String? timeStr) {
      if (timeStr == null) return null;
      final parts = timeStr.split(':');
      return TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
    }

    return AttendanceRecord(
      id: map['id'] as String,
      employeeId: map['employee_id'] as String,
      branchId: map['branch_id'] as String,
      shiftId: map['shift_id'] as String?,
      date: DateTime.parse(map['date'] as String),
      clockInTime: map['clock_in_time'] != null
          ? DateTime.parse(map['clock_in_time'] as String)
          : null,
      clockOutTime: map['clock_out_time'] != null
          ? DateTime.parse(map['clock_out_time'] as String)
          : null,
      clockInMethod: map['clock_in_method'] != null
          ? AttendanceMethodExtension.fromString(map['clock_in_method'] as String)
          : null,
      clockOutMethod: map['clock_out_method'] != null
          ? AttendanceMethodExtension.fromString(map['clock_out_method'] as String)
          : null,
      clockInDeviceId: map['clock_in_device_id'] as String?,
      clockOutDeviceId: map['clock_out_device_id'] as String?,
      scheduledStart: parseTimeOfDay(map['scheduled_start'] as String?),
      scheduledEnd: parseTimeOfDay(map['scheduled_end'] as String?),
      lateMinutes: (map['late_minutes'] as int?) ?? 0,
      earlyLeaveMinutes: (map['early_leave_minutes'] as int?) ?? 0,
      workedMinutes: (map['worked_minutes'] as int?) ?? 0,
      overtimeMinutes: (map['overtime_minutes'] as int?) ?? 0,
      breakMinutes: (map['break_minutes'] as int?) ?? 0,
      status: AttendanceStatusExtension.fromString(map['status'] as String? ?? 'present'),
      isLateForgiven: (map['is_late_forgiven'] as int?) == 1,
      lateForgivenessReason: map['late_forgiveness_reason'] as String?,
      lateForgivenBy: map['late_forgiven_by'] as String?,
      lateForgivenAt: map['late_forgiven_at'] != null
          ? DateTime.parse(map['late_forgiven_at'] as String)
          : null,
      isManuallyModified: (map['is_manually_modified'] as int?) == 1,
      modifiedBy: map['modified_by'] as String?,
      modifiedAt: map['modified_at'] != null
          ? DateTime.parse(map['modified_at'] as String)
          : null,
      modificationReason: map['modification_reason'] as String?,
      notes: map['notes'] as String?,
      qrToken: map['qr_token'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      syncedAt: map['synced_at'] != null
          ? DateTime.parse(map['synced_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    String? formatTimeOfDay(TimeOfDay? time) {
      if (time == null) return null;
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }

    return {
      'id': id,
      'employee_id': employeeId,
      'branch_id': branchId,
      'shift_id': shiftId,
      'date': date.toIso8601String().split('T')[0],
      'clock_in_time': clockInTime?.toIso8601String(),
      'clock_out_time': clockOutTime?.toIso8601String(),
      'clock_in_method': clockInMethod?.value,
      'clock_out_method': clockOutMethod?.value,
      'clock_in_device_id': clockInDeviceId,
      'clock_out_device_id': clockOutDeviceId,
      'scheduled_start': formatTimeOfDay(scheduledStart),
      'scheduled_end': formatTimeOfDay(scheduledEnd),
      'late_minutes': lateMinutes,
      'early_leave_minutes': earlyLeaveMinutes,
      'worked_minutes': workedMinutes,
      'overtime_minutes': overtimeMinutes,
      'break_minutes': breakMinutes,
      'status': status.value,
      'is_late_forgiven': isLateForgiven ? 1 : 0,
      'late_forgiveness_reason': lateForgivenessReason,
      'late_forgiven_by': lateForgivenBy,
      'late_forgiven_at': lateForgivenAt?.toIso8601String(),
      'is_manually_modified': isManuallyModified ? 1 : 0,
      'modified_by': modifiedBy,
      'modified_at': modifiedAt?.toIso8601String(),
      'modification_reason': modificationReason,
      'notes': notes,
      'qr_token': qrToken,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'synced_at': syncedAt?.toIso8601String(),
    };
  }

  AttendanceRecord copyWith({
    String? id,
    String? employeeId,
    String? branchId,
    String? shiftId,
    DateTime? date,
    DateTime? clockInTime,
    DateTime? clockOutTime,
    AttendanceMethod? clockInMethod,
    AttendanceMethod? clockOutMethod,
    String? clockInDeviceId,
    String? clockOutDeviceId,
    TimeOfDay? scheduledStart,
    TimeOfDay? scheduledEnd,
    int? lateMinutes,
    int? earlyLeaveMinutes,
    int? workedMinutes,
    int? overtimeMinutes,
    int? breakMinutes,
    AttendanceStatus? status,
    bool? isLateForgiven,
    String? lateForgivenessReason,
    String? lateForgivenBy,
    DateTime? lateForgivenAt,
    bool? isManuallyModified,
    String? modifiedBy,
    DateTime? modifiedAt,
    String? modificationReason,
    String? notes,
    String? qrToken,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? syncedAt,
  }) {
    return AttendanceRecord(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      branchId: branchId ?? this.branchId,
      shiftId: shiftId ?? this.shiftId,
      date: date ?? this.date,
      clockInTime: clockInTime ?? this.clockInTime,
      clockOutTime: clockOutTime ?? this.clockOutTime,
      clockInMethod: clockInMethod ?? this.clockInMethod,
      clockOutMethod: clockOutMethod ?? this.clockOutMethod,
      clockInDeviceId: clockInDeviceId ?? this.clockInDeviceId,
      clockOutDeviceId: clockOutDeviceId ?? this.clockOutDeviceId,
      scheduledStart: scheduledStart ?? this.scheduledStart,
      scheduledEnd: scheduledEnd ?? this.scheduledEnd,
      lateMinutes: lateMinutes ?? this.lateMinutes,
      earlyLeaveMinutes: earlyLeaveMinutes ?? this.earlyLeaveMinutes,
      workedMinutes: workedMinutes ?? this.workedMinutes,
      overtimeMinutes: overtimeMinutes ?? this.overtimeMinutes,
      breakMinutes: breakMinutes ?? this.breakMinutes,
      status: status ?? this.status,
      isLateForgiven: isLateForgiven ?? this.isLateForgiven,
      lateForgivenessReason: lateForgivenessReason ?? this.lateForgivenessReason,
      lateForgivenBy: lateForgivenBy ?? this.lateForgivenBy,
      lateForgivenAt: lateForgivenAt ?? this.lateForgivenAt,
      isManuallyModified: isManuallyModified ?? this.isManuallyModified,
      modifiedBy: modifiedBy ?? this.modifiedBy,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      modificationReason: modificationReason ?? this.modificationReason,
      notes: notes ?? this.notes,
      qrToken: qrToken ?? this.qrToken,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  /// Check if employee has clocked in
  bool get hasClockedIn => clockInTime != null;

  /// Check if employee has clocked out
  bool get hasClockedOut => clockOutTime != null;

  /// Check if attendance is complete
  bool get isComplete => hasClockedIn && hasClockedOut;

  /// Get worked hours as formatted string
  String get workedHoursFormatted {
    final hours = workedMinutes ~/ 60;
    final minutes = workedMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  /// Get overtime hours as formatted string
  String get overtimeHoursFormatted {
    final hours = overtimeMinutes ~/ 60;
    final minutes = overtimeMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  /// Get effective late minutes (considering forgiveness)
  int get effectiveLateMinutes => isLateForgiven ? 0 : lateMinutes;

  @override
  List<Object?> get props => [
        id,
        employeeId,
        branchId,
        shiftId,
        date,
        clockInTime,
        clockOutTime,
        clockInMethod,
        clockOutMethod,
        clockInDeviceId,
        clockOutDeviceId,
        scheduledStart,
        scheduledEnd,
        lateMinutes,
        earlyLeaveMinutes,
        workedMinutes,
        overtimeMinutes,
        breakMinutes,
        status,
        isLateForgiven,
        lateForgivenessReason,
        lateForgivenBy,
        lateForgivenAt,
        isManuallyModified,
        modifiedBy,
        modifiedAt,
        modificationReason,
        notes,
        qrToken,
        createdAt,
        updatedAt,
        syncedAt,
      ];
}
