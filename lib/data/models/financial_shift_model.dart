import 'package:equatable/equatable.dart';
import '../../core/enums/financial_enums.dart';

/// Represents a financial shift session for cash management
/// 
/// A financial shift tracks all monetary transactions (sales, expenses)
/// during an employee's work period. It must be opened at shift start
/// and closed with a cash count at shift end.
/// 
/// SCHEDULE-DRIVEN ARCHITECTURE:
/// - Financial shifts are linked to scheduled shifts
/// - Only scheduled employees can operate the shift
/// - Schedule context is stored for audit and display
class FinancialShift extends Equatable {
  final String id;
  final String branchId;
  final String? shiftId; // Optional link to attendance shift
  final String employeeId;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingCash;
  final FinancialShiftStatus status;
  final String? notes;
  // Schedule context fields
  final String? scheduledShiftId;   // ID of the scheduled shift
  final String? scheduledShiftName; // Name of the scheduled shift for display
  final String? openedByEmployeeName; // Name of employee who opened
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? syncedAt;

  const FinancialShift({
    required this.id,
    required this.branchId,
    this.shiftId,
    required this.employeeId,
    required this.openedAt,
    this.closedAt,
    this.openingCash = 0,
    this.status = FinancialShiftStatus.open,
    this.notes,
    this.scheduledShiftId,
    this.scheduledShiftName,
    this.openedByEmployeeName,
    required this.createdAt,
    required this.updatedAt,
    this.syncedAt,
  });

  /// Create from database map
  factory FinancialShift.fromMap(Map<String, dynamic> map) {
    return FinancialShift(
      id: map['id'] as String,
      branchId: map['branch_id'] as String,
      shiftId: map['shift_id'] as String?,
      employeeId: map['employee_id'] as String,
      openedAt: DateTime.parse(map['opened_at'] as String),
      closedAt: map['closed_at'] != null 
          ? DateTime.parse(map['closed_at'] as String)
          : null,
      openingCash: (map['opening_cash'] as num).toDouble(),
      status: FinancialShiftStatus.fromString(map['status'] as String? ?? 'open'),
      notes: map['notes'] as String?,
      scheduledShiftId: map['scheduled_shift_id'] as String?,
      scheduledShiftName: map['scheduled_shift_name'] as String?,
      openedByEmployeeName: map['opened_by_employee_name'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      syncedAt: map['synced_at'] != null 
          ? DateTime.parse(map['synced_at'] as String)
          : null,
    );
  }

  /// Convert to database map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'branch_id': branchId,
      'shift_id': shiftId,
      'employee_id': employeeId,
      'opened_at': openedAt.toIso8601String(),
      'closed_at': closedAt?.toIso8601String(),
      'opening_cash': openingCash,
      'status': status.value,
      'notes': notes,
      'scheduled_shift_id': scheduledShiftId,
      'scheduled_shift_name': scheduledShiftName,
      'opened_by_employee_name': openedByEmployeeName,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'synced_at': syncedAt?.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  FinancialShift copyWith({
    String? id,
    String? branchId,
    String? shiftId,
    String? employeeId,
    DateTime? openedAt,
    DateTime? closedAt,
    double? openingCash,
    FinancialShiftStatus? status,
    String? notes,
    String? scheduledShiftId,
    String? scheduledShiftName,
    String? openedByEmployeeName,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? syncedAt,
  }) {
    return FinancialShift(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      shiftId: shiftId ?? this.shiftId,
      employeeId: employeeId ?? this.employeeId,
      openedAt: openedAt ?? this.openedAt,
      closedAt: closedAt ?? this.closedAt,
      openingCash: openingCash ?? this.openingCash,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      scheduledShiftId: scheduledShiftId ?? this.scheduledShiftId,
      scheduledShiftName: scheduledShiftName ?? this.scheduledShiftName,
      openedByEmployeeName: openedByEmployeeName ?? this.openedByEmployeeName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  /// Check if shift is open
  bool get isOpen => status == FinancialShiftStatus.open;

  /// Check if shift is closed
  bool get isClosed => status == FinancialShiftStatus.closed;

  /// Check if shift is linked to a schedule
  bool get isScheduleLinked => scheduledShiftId != null;

  /// Duration in hours (only if closed)
  double? get durationHours {
    if (closedAt == null) return null;
    return closedAt!.difference(openedAt).inMinutes / 60.0;
  }

  @override
  List<Object?> get props => [
    id, branchId, shiftId, employeeId, openedAt, closedAt,
    openingCash, status, notes, scheduledShiftId, scheduledShiftName,
    openedByEmployeeName, createdAt, updatedAt, syncedAt,
  ];
}
