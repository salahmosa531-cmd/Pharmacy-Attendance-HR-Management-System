import '../models/user_model.dart';
import '../../core/constants/app_constants.dart';
import 'base_repository.dart';

/// Repository for user operations
class UserRepository extends BaseRepository<User> {
  static UserRepository? _instance;
  
  UserRepository._();
  
  static UserRepository get instance {
    _instance ??= UserRepository._();
    return _instance!;
  }
  
  @override
  String get tableName => 'users';
  
  @override
  User fromMap(Map<String, dynamic> map) => User.fromMap(map);
  
  @override
  Map<String, dynamic> toMap(User item) => item.toMap();
  
  /// Get user by username
  Future<User?> getByUsername(String username) async {
    final results = await getAll(
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }
  
  /// Get user by employee ID
  Future<User?> getByEmployeeId(String employeeId) async {
    final results = await getAll(
      where: 'employee_id = ?',
      whereArgs: [employeeId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }
  
  /// Get all users by branch
  Future<List<User>> getByBranch(String branchId) async {
    return await getAll(
      where: 'branch_id = ? AND is_active = 1',
      whereArgs: [branchId],
      orderBy: 'username ASC',
    );
  }
  
  /// Get all users by role
  Future<List<User>> getByRole(UserRole role) async {
    return await getAll(
      where: 'role = ? AND is_active = 1',
      whereArgs: [role.value],
      orderBy: 'username ASC',
    );
  }
  
  /// Update last login timestamp
  Future<void> updateLastLogin(String userId) async {
    final db = await database;
    await db.update(
      tableName,
      {
        'last_login': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }
  
  /// Update password
  Future<void> updatePassword(String userId, String passwordHash, String salt) async {
    final db = await database;
    await db.update(
      tableName,
      {
        'password_hash': passwordHash,
        'salt': salt,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }
  
  /// Deactivate user
  Future<void> deactivate(String userId) async {
    final db = await database;
    await db.update(
      tableName,
      {
        'is_active': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }
  
  /// Activate user
  Future<void> activate(String userId) async {
    final db = await database;
    await db.update(
      tableName,
      {
        'is_active': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }
  
  /// Check if username exists
  Future<bool> usernameExists(String username, {String? excludeId}) async {
    String where = 'LOWER(username) = LOWER(?)';
    List<dynamic> whereArgs = [username];
    
    if (excludeId != null) {
      where += ' AND id != ?';
      whereArgs.add(excludeId);
    }
    
    final count = await this.count(where: where, whereArgs: whereArgs);
    return count > 0;
  }
  
  /// Get super admin count
  Future<int> getSuperAdminCount() async {
    return await count(
      where: 'role = ? AND is_active = 1',
      whereArgs: [UserRole.superAdmin.value],
    );
  }
  
  /// Get all active users
  Future<List<User>> getActiveUsers() async {
    return await getAll(
      where: 'is_active = 1',
      orderBy: 'username ASC',
    );
  }
  
  /// Update employee link for a user
  /// 
  /// SINGLE-BRANCH ARCHITECTURE: Links user to employee
  Future<void> updateEmployeeLink(String userId, String employeeId) async {
    final db = await database;
    await db.update(
      tableName,
      {
        'employee_id': employeeId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }
  
  /// Get users without employee links
  /// 
  /// Used for migration to ensure all users have employees
  Future<List<User>> getUsersWithoutEmployees() async {
    return await getAll(
      where: 'employee_id IS NULL AND is_active = 1',
      orderBy: 'created_at ASC',
    );
  }
}
