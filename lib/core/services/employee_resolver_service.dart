import 'package:uuid/uuid.dart';
import '../../data/models/employee_model.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../core/constants/app_constants.dart';
import 'logging_service.dart';

/// EmployeeResolver Service - Guarantees employee context for users
/// 
/// SINGLE-BRANCH ARCHITECTURE: All employees use branch_id = '1'
/// 
/// This service ensures that every user has a valid employee record:
/// - If employee exists, returns it
/// - If employee is missing, creates one automatically
/// - Guarantees non-null result (only fails on database errors)
/// 
/// Logs:
/// - [EMPLOYEE_RESOLVED] - Employee found for user
/// - [EMPLOYEE_PROVISIONED] - New employee created for user
/// - [EMPLOYEE_ALREADY_EXISTS] - Employee already linked
class EmployeeResolverService {
  static final EmployeeResolverService _instance = EmployeeResolverService._();
  static EmployeeResolverService get instance => _instance;
  
  final _employeeRepo = EmployeeRepository.instance;
  final _userRepo = UserRepository.instance;
  final _uuid = const Uuid();
  final _logger = LoggingService.instance;
  
  // SINGLE-BRANCH: Hardcoded branch ID
  static const String _defaultBranchId = '1';
  
  EmployeeResolverService._();
  
  /// Get or create employee for a user
  /// 
  /// This method guarantees a non-null result:
  /// 1. If user.employeeId is set and employee exists -> returns existing employee
  /// 2. If user.employeeId is null -> creates new employee and links to user
  /// 3. Only throws on database failure
  /// 
  /// Returns: Employee (never null)
  /// Throws: EmployeeResolverException on database failure
  Future<Employee> getEmployeeForUser(User user) async {
    // Case 1: User already has employeeId linked
    if (user.employeeId != null) {
      final existingEmployee = await _employeeRepo.getById(user.employeeId!);
      
      if (existingEmployee != null) {
        _logger.info(
          'EmployeeResolver',
          '[EMPLOYEE_ALREADY_EXISTS] User ${user.username} (${user.id}) already linked to employee ${existingEmployee.id}',
        );
        return existingEmployee;
      }
      
      // Employee ID set but employee not found - create new one
      _logger.warning(
        'EmployeeResolver',
        '[EMPLOYEE_MISSING] User ${user.username} has employeeId ${user.employeeId} but employee not found. Creating new employee.',
      );
    }
    
    // Case 2: No employee linked - check if employee exists with matching criteria
    final existingByUsername = await _findExistingEmployee(user);
    if (existingByUsername != null) {
      // Link existing employee to user
      await _linkEmployeeToUser(user, existingByUsername);
      _logger.info(
        'EmployeeResolver',
        '[EMPLOYEE_RESOLVED] Found existing employee ${existingByUsername.id} for user ${user.username}',
      );
      return existingByUsername;
    }
    
    // Case 3: No employee exists - create new one
    final newEmployee = await _createEmployeeForUser(user);
    _logger.info(
      'EmployeeResolver',
      '[EMPLOYEE_PROVISIONED] Created employee ${newEmployee.id} for user ${user.username}',
    );
    return newEmployee;
  }
  
  /// Find existing employee that might match the user
  Future<Employee?> _findExistingEmployee(User user) async {
    // Try to find by employee code matching username
    final byCode = await _employeeRepo.getByCode(_defaultBranchId, user.username);
    if (byCode != null) return byCode;
    
    // Could add more matching criteria here (email, etc.)
    return null;
  }
  
  /// Create a new employee for the user
  Future<Employee> _createEmployeeForUser(User user) async {
    final now = DateTime.now();
    final employeeCode = await _generateEmployeeCode(user);
    
    // Determine job title based on user role
    final jobTitle = _getJobTitleForRole(user.role);
    
    final employee = Employee(
      id: _uuid.v4(),
      branchId: _defaultBranchId,
      employeeCode: employeeCode,
      fullName: _formatNameFromUsername(user.username),
      jobTitle: jobTitle,
      salaryType: SalaryType.monthly,
      salaryValue: 0,
      status: EmployeeStatus.active,
      hireDate: now,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
    
    try {
      await _employeeRepo.insert(employee);
      
      // Link employee to user
      await _linkEmployeeToUser(user, employee);
      
      return employee;
    } catch (e) {
      _logger.error(
        'EmployeeResolver',
        'Failed to create employee for user ${user.username}',
        e,
        StackTrace.current,
      );
      throw EmployeeResolverException(
        'Failed to create employee for user: $e',
        code: 'CREATE_FAILED',
      );
    }
  }
  
  /// Link an employee to a user
  Future<void> _linkEmployeeToUser(User user, Employee employee) async {
    try {
      await _userRepo.updateEmployeeLink(user.id, employee.id);
    } catch (e) {
      _logger.error(
        'EmployeeResolver',
        'Failed to link employee ${employee.id} to user ${user.id}',
        e,
        StackTrace.current,
      );
      // Don't throw - employee was created successfully
    }
  }
  
  /// Generate a unique employee code
  Future<String> _generateEmployeeCode(User user) async {
    // Try username first
    String baseCode = user.username.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (baseCode.length > 10) baseCode = baseCode.substring(0, 10);
    if (baseCode.isEmpty) baseCode = 'EMP';
    
    String code = baseCode;
    int counter = 1;
    
    while (await _employeeRepo.codeExists(_defaultBranchId, code)) {
      code = '$baseCode$counter';
      counter++;
      if (counter > 999) {
        // Fallback to UUID-based code
        code = 'EMP${_uuid.v4().substring(0, 8).toUpperCase()}';
        break;
      }
    }
    
    return code;
  }
  
  /// Get job title based on user role
  String _getJobTitleForRole(UserRole role) {
    switch (role) {
      case UserRole.superAdmin:
        return 'System Administrator';
      case UserRole.admin:
        return 'Manager';
      case UserRole.manager:
        return 'Supervisor';
      case UserRole.employee:
        return 'Staff';
    }
  }
  
  /// Format a display name from username
  String _formatNameFromUsername(String username) {
    // Convert username to title case
    return username
        .replaceAll(RegExp(r'[_\-.]'), ' ')
        .split(' ')
        .map((word) => word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }
  
  /// Resolve employee ID for a user, creating if necessary
  /// 
  /// Returns the employee ID (never null)
  Future<String> resolveEmployeeId(User user) async {
    final employee = await getEmployeeForUser(user);
    return employee.id;
  }
  
  /// Ensure all users have employees (migration helper)
  /// 
  /// This method finds all users without employees and creates them.
  /// Call this during app initialization or as a migration.
  /// 
  /// Returns: Number of employees created
  Future<int> migrateUsersWithoutEmployees() async {
    _logger.info('EmployeeResolver', 'Starting migration: Users without employees');
    
    int created = 0;
    
    try {
      // Get all users
      final users = await _userRepo.getAll();
      
      for (final user in users) {
        if (user.employeeId == null) {
          try {
            await getEmployeeForUser(user);
            created++;
          } catch (e) {
            _logger.error(
              'EmployeeResolver',
              'Failed to create employee for user ${user.username} during migration',
              e,
              StackTrace.current,
            );
          }
        }
      }
      
      _logger.info(
        'EmployeeResolver',
        'Migration complete: Created $created employees for users without employees',
      );
      
      return created;
    } catch (e) {
      _logger.error(
        'EmployeeResolver',
        'Migration failed',
        e,
        StackTrace.current,
      );
      throw EmployeeResolverException(
        'Migration failed: $e',
        code: 'MIGRATION_FAILED',
      );
    }
  }
}

/// Exception for employee resolver operations
class EmployeeResolverException implements Exception {
  final String message;
  final String? code;
  
  EmployeeResolverException(this.message, {this.code});
  
  @override
  String toString() => 'EmployeeResolverException: $message${code != null ? ' [$code]' : ''}';
}
