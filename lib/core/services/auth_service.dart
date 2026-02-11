import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../data/models/user_model.dart';
import '../../data/models/branch_model.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/branch_repository.dart';
import '../../data/repositories/shift_repository.dart';
import '../../data/repositories/audit_repository.dart';
import '../../data/models/audit_log_model.dart';
import '../../data/models/shift_model.dart';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import 'logging_service.dart';

/// Authentication service for user login/logout
/// 
/// SINGLE-BRANCH ARCHITECTURE: All operations use hardcoded branch_id = '1'

/// Session persistence policy for admin authentication.
class AuthSessionPolicy {
  /// If true, authenticated admin sessions are restored after app restart.
  static const bool persistAdminSession = false;

  /// Maximum age for persisted session before forced logout.
  static const Duration maxSessionAge = Duration(days: 7);
}

class _SessionStorageKeys {
  static const String userId = 'auth_session_user_id';
  static const String issuedAt = 'auth_session_issued_at';
}

class AuthService {
  static AuthService? _instance;
  
  final UserRepository _userRepository = UserRepository.instance;
  final BranchRepository _branchRepository = BranchRepository.instance;
  final ShiftRepository _shiftRepository = ShiftRepository.instance;
  final AuditRepository _auditRepository = AuditRepository.instance;
  final Uuid _uuid = const Uuid();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  // SINGLE-BRANCH: Hardcoded branch ID and name
  static const String _branchId = '1';
  static const String _branchName = 'Main Branch';
  
  User? _currentUser;
  Branch? _currentBranch;
  
  AuthService._();
  
  static AuthService get instance {
    _instance ??= AuthService._();
    return _instance!;
  }
  
  /// Get current logged in user
  User? get currentUser => _currentUser;
  
  /// Get current branch (always the default branch in single-branch mode)
  Branch? get currentBranch => _currentBranch;
  
  /// Check if user is logged in
  bool get isLoggedIn => _currentUser != null;
  
  /// Check if user is admin
  bool get isAdmin => _currentUser?.role == UserRole.admin || 
                       _currentUser?.role == UserRole.superAdmin;
  
  /// Check if user is super admin
  bool get isSuperAdmin => _currentUser?.role == UserRole.superAdmin;
  
  /// Generate salt for password hashing
  String _generateSalt() {
    final random = Random.secure();
    final saltBytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Encode(saltBytes);
  }
  
  /// Hash password with salt
  String _hashPassword(String password, String salt) {
    final bytes = utf8.encode(password + salt);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
  
  /// Verify password
  bool _verifyPassword(String password, String hash, String salt) {
    final computedHash = _hashPassword(password, salt);
    return computedHash == hash;
  }
  
  /// Register a new user
  Future<User> registerUser({
    required String username,
    required String password,
    required UserRole role,
    String? employeeId,
    String? branchId,
  }) async {
    // Check if username exists
    if (await _userRepository.usernameExists(username)) {
      throw Exception('Username already exists');
    }
    
    final salt = _generateSalt();
    final passwordHash = _hashPassword(password, salt);
    final now = DateTime.now();
    
    final user = User(
      id: _uuid.v4(),
      username: username,
      passwordHash: passwordHash,
      salt: salt,
      role: role,
      employeeId: employeeId,
      branchId: branchId ?? _branchId, // SINGLE-BRANCH: Default to '1'
      createdAt: now,
      updatedAt: now,
    );
    
    await _userRepository.insert(user);
    
    // Log the action
    await _auditRepository.log(
      id: _uuid.v4(),
      branchId: _branchId,
      userId: _currentUser?.id,
      action: AuditAction.create,
      entityType: AuditEntityType.user,
      entityId: user.id,
      newValues: {'username': username, 'role': role.value},
    );
    
    return user;
  }
  
  /// Login user
  Future<User> login(String username, String password, {String? deviceId}) async {
    final user = await _userRepository.getByUsername(username);
    
    if (user == null) {
      throw Exception('Invalid username or password');
    }
    
    if (!user.isActive) {
      throw Exception('User account is deactivated');
    }
    
    if (!_verifyPassword(password, user.passwordHash, user.salt)) {
      throw Exception('Invalid username or password');
    }
    
    // Update last login
    await _userRepository.updateLastLogin(user.id);
    
    _currentUser = user.copyWith(lastLogin: DateTime.now());

    if (AuthSessionPolicy.persistAdminSession) {
      await _persistSession(_currentUser!.id);
    }
    
    // Load the default branch
    _currentBranch = await _branchRepository.getById(_branchId);
    
    // Log the login
    await _auditRepository.log(
      id: _uuid.v4(),
      branchId: _branchId,
      userId: user.id,
      action: AuditAction.login,
      entityType: AuditEntityType.user,
      entityId: user.id,
      deviceId: deviceId,
    );
    
    return _currentUser!;
  }
  
  /// Logout user
  Future<void> logout() async {
    if (_currentUser != null) {
      // Log the logout
      await _auditRepository.log(
        id: _uuid.v4(),
        branchId: _branchId,
        userId: _currentUser!.id,
        action: AuditAction.logout,
        entityType: AuditEntityType.user,
        entityId: _currentUser!.id,
      );
    }
    
    _currentUser = null;
    await _clearPersistedSession();
  }
  
  /// Change password
  Future<void> changePassword(String currentPassword, String newPassword) async {
    if (_currentUser == null) {
      throw Exception('Not logged in');
    }
    
    if (!_verifyPassword(currentPassword, _currentUser!.passwordHash, _currentUser!.salt)) {
      throw Exception('Current password is incorrect');
    }
    
    if (newPassword.length < AppConstants.minPasswordLength) {
      throw Exception('Password must be at least ${AppConstants.minPasswordLength} characters');
    }
    
    final newSalt = _generateSalt();
    final newHash = _hashPassword(newPassword, newSalt);
    
    await _userRepository.updatePassword(_currentUser!.id, newHash, newSalt);
    
    _currentUser = _currentUser!.copyWith(
      passwordHash: newHash,
      salt: newSalt,
      updatedAt: DateTime.now(),
    );
  }
  
  /// Reset user password (admin function)
  Future<void> resetUserPassword(String userId, String newPassword) async {
    if (_currentUser == null || !isAdmin) {
      throw Exception('Unauthorized');
    }
    
    final user = await _userRepository.getById(userId);
    if (user == null) {
      throw Exception('User not found');
    }
    
    final newSalt = _generateSalt();
    final newHash = _hashPassword(newPassword, newSalt);
    
    await _userRepository.updatePassword(userId, newHash, newSalt);
    
    // Log the action
    await _auditRepository.log(
      id: _uuid.v4(),
      branchId: _branchId,
      userId: _currentUser!.id,
      action: AuditAction.update,
      entityType: AuditEntityType.user,
      entityId: userId,
      newValues: {'password_reset': true},
    );
  }
  
  /// Check if current user has permission
  bool hasPermission(String permission) {
    return _currentUser?.hasPermission(permission) ?? false;
  }
  
  /// Create initial super admin (for first-time setup)
  Future<User> createInitialSuperAdmin({
    required String username,
    required String password,
    required String branchName,
  }) async {
    // Check if any users exist
    final userCount = await _userRepository.count();
    if (userCount > 0) {
      throw Exception('System already initialized');
    }
    
    LoggingService.instance.info('Auth', 'Creating initial setup with branch: $branchName');
    
    // Create the main branch with hardcoded ID
    final branch = await _createBranchWithDefaults(
      name: branchName,
    );
    
    // Set as main branch
    await _branchRepository.setAsMainBranch(branch.id);
    _currentBranch = branch;
    
    LoggingService.instance.info('Auth', 'Created main branch: ${branch.id}');
    
    // Create super admin user
    final user = await registerUser(
      username: username,
      password: password,
      role: UserRole.superAdmin,
      branchId: branch.id,
    );
    
    LoggingService.instance.info('Auth', 'Created super admin user: ${user.id}');
    
    return user;
  }
  
  /// Create branch with default shifts
  Future<Branch> _createBranchWithDefaults({required String name}) async {
    final now = DateTime.now();
    
    // Use hardcoded branch ID for single-branch architecture
    final branch = Branch(
      id: _branchId,
      name: name,
      isMainBranch: true,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
    
    // Insert or update the branch
    final existing = await _branchRepository.getById(_branchId);
    if (existing != null) {
      await _branchRepository.update(branch, _branchId);
    } else {
      await _branchRepository.insert(branch);
    }
    
    // Create default shifts
    await _createDefaultShifts(branch.id);
    
    return branch;
  }
  
  /// Create default work shifts
  Future<void> _createDefaultShifts(String branchId) async {
    final shifts = [
      Shift(
        id: _uuid.v4(),
        branchId: branchId,
        name: 'Morning Shift',
        startTime: const TimeOfDay(hour: 8, minute: 0),
        endTime: const TimeOfDay(hour: 16, minute: 0),
        gracePeriodMinutes: 15,
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      Shift(
        id: _uuid.v4(),
        branchId: branchId,
        name: 'Evening Shift',
        startTime: const TimeOfDay(hour: 16, minute: 0),
        endTime: const TimeOfDay(hour: 0, minute: 0),
        gracePeriodMinutes: 15,
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      Shift(
        id: _uuid.v4(),
        branchId: branchId,
        name: 'Night Shift',
        startTime: const TimeOfDay(hour: 0, minute: 0),
        endTime: const TimeOfDay(hour: 8, minute: 0),
        gracePeriodMinutes: 15,
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];
    
    for (final shift in shifts) {
      await _shiftRepository.insert(shift);
    }
    
    LoggingService.instance.info('Auth', 'Created ${shifts.length} default shifts for branch $branchId');
  }

  /// Initialize and restore persisted admin session based on policy.
  Future<void> initializeSession() async {
    // Always load the default branch
    _currentBranch = await _branchRepository.getById(_branchId);
    
    if (!AuthSessionPolicy.persistAdminSession) {
      await _clearPersistedSession();
      return;
    }

    try {
      final persistedUserId = await _secureStorage.read(key: _SessionStorageKeys.userId);
      final issuedAtRaw = await _secureStorage.read(key: _SessionStorageKeys.issuedAt);

      if (persistedUserId == null || issuedAtRaw == null) {
        return;
      }

      final issuedAt = DateTime.tryParse(issuedAtRaw);
      if (issuedAt == null) {
        await _clearPersistedSession();
        return;
      }

      if (DateTime.now().difference(issuedAt) > AuthSessionPolicy.maxSessionAge) {
        LoggingService.instance.info('Auth', 'Persisted session expired by policy');
        await _clearPersistedSession();
        return;
      }

      final user = await _userRepository.getById(persistedUserId);
      if (user == null || !user.isActive) {
        LoggingService.instance.warning('Auth', 'Persisted session user missing/inactive, clearing session');
        await _clearPersistedSession();
        return;
      }

      _currentUser = user;
      LoggingService.instance.info('Auth', 'Restored persisted admin session for ${user.username}');
    } catch (e, stack) {
      LoggingService.instance.error('Auth', 'Failed to restore persisted session', e, stack);
      await _clearPersistedSession();
    }
  }

  Future<void> _persistSession(String userId) async {
    await _secureStorage.write(key: _SessionStorageKeys.userId, value: userId);
    await _secureStorage.write(
      key: _SessionStorageKeys.issuedAt,
      value: DateTime.now().toIso8601String(),
    );
  }

  Future<void> _clearPersistedSession() async {
    await _secureStorage.delete(key: _SessionStorageKeys.userId);
    await _secureStorage.delete(key: _SessionStorageKeys.issuedAt);
  }

  /// Check if system needs initial setup
  Future<bool> needsInitialSetup() async {
    final userCount = await _userRepository.count();
    return userCount == 0;
  }
}
