import 'package:equatable/equatable.dart';

/// Payroll record model
class PayrollRecord extends Equatable {
  final String id;
  final String employeeId;
  final String branchId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double baseSalary;
  final int daysWorked;
  final double hoursWorked;
  final int shiftsWorked;
  final double overtimeHours;
  final double overtimePay;
  final double lateDeductions;
  final double absenceDeductions;
  final double bonus;
  final String? bonusReason;
  final double otherDeductions;
  final String? otherDeductionsReason;
  final double grossSalary;
  final double netSalary;
  final PayrollStatus status;
  final DateTime? paidAt;
  final String? paidBy;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? syncedAt;

  const PayrollRecord({
    required this.id,
    required this.employeeId,
    required this.branchId,
    required this.periodStart,
    required this.periodEnd,
    required this.baseSalary,
    this.daysWorked = 0,
    this.hoursWorked = 0,
    this.shiftsWorked = 0,
    this.overtimeHours = 0,
    this.overtimePay = 0,
    this.lateDeductions = 0,
    this.absenceDeductions = 0,
    this.bonus = 0,
    this.bonusReason,
    this.otherDeductions = 0,
    this.otherDeductionsReason,
    required this.grossSalary,
    required this.netSalary,
    this.status = PayrollStatus.pending,
    this.paidAt,
    this.paidBy,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.syncedAt,
  });

  factory PayrollRecord.fromMap(Map<String, dynamic> map) {
    return PayrollRecord(
      id: map['id'] as String,
      employeeId: map['employee_id'] as String,
      branchId: map['branch_id'] as String,
      periodStart: DateTime.parse(map['period_start'] as String),
      periodEnd: DateTime.parse(map['period_end'] as String),
      baseSalary: (map['base_salary'] as num?)?.toDouble() ?? 0,
      daysWorked: (map['days_worked'] as int?) ?? 0,
      hoursWorked: (map['hours_worked'] as num?)?.toDouble() ?? 0,
      shiftsWorked: (map['shifts_worked'] as int?) ?? 0,
      overtimeHours: (map['overtime_hours'] as num?)?.toDouble() ?? 0,
      overtimePay: (map['overtime_pay'] as num?)?.toDouble() ?? 0,
      lateDeductions: (map['late_deductions'] as num?)?.toDouble() ?? 0,
      absenceDeductions: (map['absence_deductions'] as num?)?.toDouble() ?? 0,
      bonus: (map['bonus'] as num?)?.toDouble() ?? 0,
      bonusReason: map['bonus_reason'] as String?,
      otherDeductions: (map['other_deductions'] as num?)?.toDouble() ?? 0,
      otherDeductionsReason: map['other_deductions_reason'] as String?,
      grossSalary: (map['gross_salary'] as num?)?.toDouble() ?? 0,
      netSalary: (map['net_salary'] as num?)?.toDouble() ?? 0,
      status: PayrollStatusExtension.fromString(map['status'] as String? ?? 'pending'),
      paidAt: map['paid_at'] != null ? DateTime.parse(map['paid_at'] as String) : null,
      paidBy: map['paid_by'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      syncedAt: map['synced_at'] != null
          ? DateTime.parse(map['synced_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'employee_id': employeeId,
      'branch_id': branchId,
      'period_start': periodStart.toIso8601String().split('T')[0],
      'period_end': periodEnd.toIso8601String().split('T')[0],
      'base_salary': baseSalary,
      'days_worked': daysWorked,
      'hours_worked': hoursWorked,
      'shifts_worked': shiftsWorked,
      'overtime_hours': overtimeHours,
      'overtime_pay': overtimePay,
      'late_deductions': lateDeductions,
      'absence_deductions': absenceDeductions,
      'bonus': bonus,
      'bonus_reason': bonusReason,
      'other_deductions': otherDeductions,
      'other_deductions_reason': otherDeductionsReason,
      'gross_salary': grossSalary,
      'net_salary': netSalary,
      'status': status.value,
      'paid_at': paidAt?.toIso8601String(),
      'paid_by': paidBy,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'synced_at': syncedAt?.toIso8601String(),
    };
  }

  PayrollRecord copyWith({
    String? id,
    String? employeeId,
    String? branchId,
    DateTime? periodStart,
    DateTime? periodEnd,
    double? baseSalary,
    int? daysWorked,
    double? hoursWorked,
    int? shiftsWorked,
    double? overtimeHours,
    double? overtimePay,
    double? lateDeductions,
    double? absenceDeductions,
    double? bonus,
    String? bonusReason,
    double? otherDeductions,
    String? otherDeductionsReason,
    double? grossSalary,
    double? netSalary,
    PayrollStatus? status,
    DateTime? paidAt,
    String? paidBy,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? syncedAt,
  }) {
    return PayrollRecord(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      branchId: branchId ?? this.branchId,
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      baseSalary: baseSalary ?? this.baseSalary,
      daysWorked: daysWorked ?? this.daysWorked,
      hoursWorked: hoursWorked ?? this.hoursWorked,
      shiftsWorked: shiftsWorked ?? this.shiftsWorked,
      overtimeHours: overtimeHours ?? this.overtimeHours,
      overtimePay: overtimePay ?? this.overtimePay,
      lateDeductions: lateDeductions ?? this.lateDeductions,
      absenceDeductions: absenceDeductions ?? this.absenceDeductions,
      bonus: bonus ?? this.bonus,
      bonusReason: bonusReason ?? this.bonusReason,
      otherDeductions: otherDeductions ?? this.otherDeductions,
      otherDeductionsReason: otherDeductionsReason ?? this.otherDeductionsReason,
      grossSalary: grossSalary ?? this.grossSalary,
      netSalary: netSalary ?? this.netSalary,
      status: status ?? this.status,
      paidAt: paidAt ?? this.paidAt,
      paidBy: paidBy ?? this.paidBy,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  /// Get total deductions
  double get totalDeductions => lateDeductions + absenceDeductions + otherDeductions;

  /// Get total additions
  double get totalAdditions => overtimePay + bonus;

  @override
  List<Object?> get props => [
        id,
        employeeId,
        branchId,
        periodStart,
        periodEnd,
        baseSalary,
        daysWorked,
        hoursWorked,
        shiftsWorked,
        overtimeHours,
        overtimePay,
        lateDeductions,
        absenceDeductions,
        bonus,
        bonusReason,
        otherDeductions,
        otherDeductionsReason,
        grossSalary,
        netSalary,
        status,
        paidAt,
        paidBy,
        notes,
        createdAt,
        updatedAt,
        syncedAt,
      ];
}

/// Payroll status enum
enum PayrollStatus {
  pending,
  approved,
  paid,
  cancelled,
}

extension PayrollStatusExtension on PayrollStatus {
  String get displayName {
    switch (this) {
      case PayrollStatus.pending:
        return 'Pending';
      case PayrollStatus.approved:
        return 'Approved';
      case PayrollStatus.paid:
        return 'Paid';
      case PayrollStatus.cancelled:
        return 'Cancelled';
    }
  }

  String get value {
    switch (this) {
      case PayrollStatus.pending:
        return 'pending';
      case PayrollStatus.approved:
        return 'approved';
      case PayrollStatus.paid:
        return 'paid';
      case PayrollStatus.cancelled:
        return 'cancelled';
    }
  }

  static PayrollStatus fromString(String value) {
    switch (value) {
      case 'pending':
        return PayrollStatus.pending;
      case 'approved':
        return PayrollStatus.approved;
      case 'paid':
        return PayrollStatus.paid;
      case 'cancelled':
        return PayrollStatus.cancelled;
      default:
        return PayrollStatus.pending;
    }
  }
}
