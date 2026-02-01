import '../models/employee_model.dart';
import '../../core/constants/app_constants.dart';
import 'base_repository.dart';

/// Repository for employee operations
class EmployeeRepository extends BaseRepository<Employee> {
  static EmployeeRepository? _instance;
  
  EmployeeRepository._();
  
  static EmployeeRepository get instance {
    _instance ??= EmployeeRepository._();
    return _instance!;
  }
  
  @override
  String get tableName => 'employees';
  
  @override
  Employee fromMap(Map<String, dynamic> map) => Employee.fromMap(map);
  
  @override
  Map<String, dynamic> toMap(Employee item) => item.toMap();
  
  /// Get employees by branch
  Future<List<Employee>> getByBranch(String branchId, {bool activeOnly = true}) async {
    String where = 'branch_id = ?';
    if (activeOnly) {
      where += ' AND is_active = 1 AND status = ?';
    }
    
    return await getAll(
      where: where,
      whereArgs: activeOnly ? [branchId, EmployeeStatus.active.value] : [branchId],
      orderBy: 'full_name ASC',
    );
  }
  
  /// Get employee by code
  Future<Employee?> getByCode(String branchId, String employeeCode) async {
    final results = await getAll(
      where: 'branch_id = ? AND employee_code = ?',
      whereArgs: [branchId, employeeCode],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }
  
  /// Get employee by barcode
  Future<Employee?> getByBarcode(String branchId, String barcode) async {
    final results = await getAll(
      where: 'branch_id = ? AND barcode_serial = ?',
      whereArgs: [branchId, barcode],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }
  
  /// Get employee by fingerprint ID
  Future<Employee?> getByFingerprintId(String branchId, String fingerprintId) async {
    final results = await getAll(
      where: 'branch_id = ? AND fingerprint_id = ?',
      whereArgs: [branchId, fingerprintId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }
  
  /// Get employees by shift
  Future<List<Employee>> getByShift(String shiftId) async {
    return await getAll(
      where: 'assigned_shift_id = ? AND is_active = 1',
      whereArgs: [shiftId],
      orderBy: 'full_name ASC',
    );
  }
  
  /// Search employees
  Future<List<Employee>> search(String branchId, String query) async {
    final searchQuery = '%$query%';
    return await getAll(
      where: 'branch_id = ? AND is_active = 1 AND (full_name LIKE ? OR employee_code LIKE ? OR job_title LIKE ?)',
      whereArgs: [branchId, searchQuery, searchQuery, searchQuery],
      orderBy: 'full_name ASC',
    );
  }
  
  /// Update attendance score
  Future<void> updateAttendanceScore(String employeeId, double score) async {
    final db = await database;
    await db.update(
      tableName,
      {
        'attendance_score': score,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [employeeId],
    );
  }
  
  /// Update employee status
  Future<void> updateStatus(String employeeId, EmployeeStatus status) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    
    Map<String, dynamic> updates = {
      'status': status.value,
      'updated_at': now,
    };
    
    if (status == EmployeeStatus.terminated) {
      updates['termination_date'] = now;
      updates['is_active'] = 0;
    }
    
    await db.update(
      tableName,
      updates,
      where: 'id = ?',
      whereArgs: [employeeId],
    );
  }
  
  /// Update assigned shift
  Future<void> updateAssignedShift(String employeeId, String? shiftId) async {
    final db = await database;
    await db.update(
      tableName,
      {
        'assigned_shift_id': shiftId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [employeeId],
    );
  }
  
  /// Update salary info
  Future<void> updateSalary(String employeeId, SalaryType type, double value, {double? overtimeRate}) async {
    final db = await database;
    await db.update(
      tableName,
      {
        'salary_type': type.value,
        'salary_value': value,
        'overtime_rate': overtimeRate,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [employeeId],
    );
  }
  
  /// Check if employee code exists
  Future<bool> codeExists(String branchId, String code, {String? excludeId}) async {
    String where = 'branch_id = ? AND employee_code = ?';
    List<dynamic> whereArgs = [branchId, code];
    
    if (excludeId != null) {
      where += ' AND id != ?';
      whereArgs.add(excludeId);
    }
    
    final count = await this.count(where: where, whereArgs: whereArgs);
    return count > 0;
  }
  
  /// Check if barcode exists
  Future<bool> barcodeExists(String branchId, String barcode, {String? excludeId}) async {
    String where = 'branch_id = ? AND barcode_serial = ?';
    List<dynamic> whereArgs = [branchId, barcode];
    
    if (excludeId != null) {
      where += ' AND id != ?';
      whereArgs.add(excludeId);
    }
    
    final count = await this.count(where: where, whereArgs: whereArgs);
    return count > 0;
  }
  
  /// Get employee count by branch
  Future<int> getCountByBranch(String branchId, {bool activeOnly = true}) async {
    String where = 'branch_id = ?';
    if (activeOnly) {
      where += ' AND is_active = 1 AND status = ?';
    }
    
    return await count(
      where: where,
      whereArgs: activeOnly ? [branchId, EmployeeStatus.active.value] : [branchId],
    );
  }
  
  /// Get employees by salary type
  Future<List<Employee>> getBySalaryType(String branchId, SalaryType salaryType) async {
    return await getAll(
      where: 'branch_id = ? AND salary_type = ? AND is_active = 1',
      whereArgs: [branchId, salaryType.value],
      orderBy: 'full_name ASC',
    );
  }
  
  /// Find employee for attendance (by code, barcode, or fingerprint)
  Future<Employee?> findForAttendance(String branchId, String identifier) async {
    // Try by employee code first
    var employee = await getByCode(branchId, identifier);
    if (employee != null && employee.canAttend) return employee;
    
    // Try by barcode
    employee = await getByBarcode(branchId, identifier);
    if (employee != null && employee.canAttend) return employee;
    
    // Try by fingerprint ID
    employee = await getByFingerprintId(branchId, identifier);
    if (employee != null && employee.canAttend) return employee;
    
    return null;
  }
}
