import 'package:equatable/equatable.dart';
import '../../core/constants/app_constants.dart';

/// Employee model
class Employee extends Equatable {
  final String id;
  final String branchId;
  final String employeeCode;
  final String fullName;
  final String? jobTitle;
  final String? email;
  final String? phone;
  final String? barcodeSerial;
  final String? fingerprintId;
  final String? assignedShiftId;
  final SalaryType salaryType;
  final double salaryValue;
  final double? overtimeRate;
  final EmployeeStatus status;
  final DateTime? hireDate;
  final DateTime? terminationDate;
  final String? photoPath;
  final String? notes;
  final double attendanceScore;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? syncedAt;

  const Employee({
    required this.id,
    required this.branchId,
    required this.employeeCode,
    required this.fullName,
    this.jobTitle,
    this.email,
    this.phone,
    this.barcodeSerial,
    this.fingerprintId,
    this.assignedShiftId,
    this.salaryType = SalaryType.monthly,
    this.salaryValue = 0,
    this.overtimeRate,
    this.status = EmployeeStatus.active,
    this.hireDate,
    this.terminationDate,
    this.photoPath,
    this.notes,
    this.attendanceScore = 100,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.syncedAt,
  });

  factory Employee.fromMap(Map<String, dynamic> map) {
    return Employee(
      id: map['id'] as String,
      branchId: map['branch_id'] as String,
      employeeCode: map['employee_code'] as String,
      fullName: map['full_name'] as String,
      jobTitle: map['job_title'] as String?,
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      barcodeSerial: map['barcode_serial'] as String?,
      fingerprintId: map['fingerprint_id'] as String?,
      assignedShiftId: map['assigned_shift_id'] as String?,
      salaryType: SalaryTypeExtension.fromString(map['salary_type'] as String? ?? 'monthly'),
      salaryValue: (map['salary_value'] as num?)?.toDouble() ?? 0,
      overtimeRate: (map['overtime_rate'] as num?)?.toDouble(),
      status: EmployeeStatusExtension.fromString(map['status'] as String? ?? 'active'),
      hireDate: map['hire_date'] != null
          ? DateTime.parse(map['hire_date'] as String)
          : null,
      terminationDate: map['termination_date'] != null
          ? DateTime.parse(map['termination_date'] as String)
          : null,
      photoPath: map['photo_path'] as String?,
      notes: map['notes'] as String?,
      attendanceScore: (map['attendance_score'] as num?)?.toDouble() ?? 100,
      isActive: (map['is_active'] as int?) == 1,
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
      'branch_id': branchId,
      'employee_code': employeeCode,
      'full_name': fullName,
      'job_title': jobTitle,
      'email': email,
      'phone': phone,
      'barcode_serial': barcodeSerial,
      'fingerprint_id': fingerprintId,
      'assigned_shift_id': assignedShiftId,
      'salary_type': salaryType.value,
      'salary_value': salaryValue,
      'overtime_rate': overtimeRate,
      'status': status.value,
      'hire_date': hireDate?.toIso8601String(),
      'termination_date': terminationDate?.toIso8601String(),
      'photo_path': photoPath,
      'notes': notes,
      'attendance_score': attendanceScore,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'synced_at': syncedAt?.toIso8601String(),
    };
  }

  Employee copyWith({
    String? id,
    String? branchId,
    String? employeeCode,
    String? fullName,
    String? jobTitle,
    String? email,
    String? phone,
    String? barcodeSerial,
    String? fingerprintId,
    String? assignedShiftId,
    SalaryType? salaryType,
    double? salaryValue,
    double? overtimeRate,
    EmployeeStatus? status,
    DateTime? hireDate,
    DateTime? terminationDate,
    String? photoPath,
    String? notes,
    double? attendanceScore,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? syncedAt,
  }) {
    return Employee(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      employeeCode: employeeCode ?? this.employeeCode,
      fullName: fullName ?? this.fullName,
      jobTitle: jobTitle ?? this.jobTitle,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      barcodeSerial: barcodeSerial ?? this.barcodeSerial,
      fingerprintId: fingerprintId ?? this.fingerprintId,
      assignedShiftId: assignedShiftId ?? this.assignedShiftId,
      salaryType: salaryType ?? this.salaryType,
      salaryValue: salaryValue ?? this.salaryValue,
      overtimeRate: overtimeRate ?? this.overtimeRate,
      status: status ?? this.status,
      hireDate: hireDate ?? this.hireDate,
      terminationDate: terminationDate ?? this.terminationDate,
      photoPath: photoPath ?? this.photoPath,
      notes: notes ?? this.notes,
      attendanceScore: attendanceScore ?? this.attendanceScore,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  /// Get initials from full name
  String get initials {
    final names = fullName.split(' ');
    if (names.length >= 2) {
      return '${names.first[0]}${names.last[0]}'.toUpperCase();
    }
    return fullName.substring(0, fullName.length >= 2 ? 2 : fullName.length).toUpperCase();
  }

  /// Check if employee can clock in/out
  bool get canAttend => status == EmployeeStatus.active && isActive;

  @override
  List<Object?> get props => [
        id,
        branchId,
        employeeCode,
        fullName,
        jobTitle,
        email,
        phone,
        barcodeSerial,
        fingerprintId,
        assignedShiftId,
        salaryType,
        salaryValue,
        overtimeRate,
        status,
        hireDate,
        terminationDate,
        photoPath,
        notes,
        attendanceScore,
        isActive,
        createdAt,
        updatedAt,
        syncedAt,
      ];
}
