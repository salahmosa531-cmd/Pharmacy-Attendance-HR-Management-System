import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/user_model.dart';
import '../../data/models/branch_model.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/branch_repository.dart';
import '../../data/repositories/audit_repository.dart';
import '../../data/models/audit_log_model.dart';
import '../constants/app_constants.dart';
import 'branch_context_service.dart';
import 'logging_service.dart';

/// Authentication service for user login/logout
class AuthService {
  static AuthService? _instance;
  
  final UserRepository _userRepository = UserRepository.instance;
  final BranchRepository _branchRepository = BranchRepository.instance;
  final AuditRepository _auditRepository = AuditRepository.instance;
  final Uuid _uuid = const Uuid();
  
  User? _currentUser;
  Branch? _currentBranch;
  
  AuthService._();
  
  static AuthService get instance {
    _instance ??= AuthService._();
    return _instance!;
  }
  
  /// Get current logged in user
  User? get currentUser => _currentUser;
  
  /// Get current branch
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
      branchId: branchId,
      createdAt: now,
      updatedAt: now,
    );
    
    await _userRepository.insert(user);
    
    // Log the action
    await _auditRepository.log(
      id: _uuid.v4(),
      branchId: branchId,
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
    
    // Get user's branch
    if (user.branchId != null) {
      _currentBranch = await _branchRepository.getById(user.branchId!);
    } else {
      // Get main branch for super admin
      _currentBranch = await _branchRepository.getMainBranch();
    }
    
    // Sync with BranchContextService for consistent branch context
    if (_currentBranch != null) {
      try {
        await BranchContextService.instance.setActiveBranch(_currentBranch!);
        LoggingService.instance.info('Auth', 'Synced branch context to ${_currentBranch!.name}');
      } catch (e) {
        LoggingService.instance.warning('Auth', 'Failed to sync branch context: $e');
      }
    }
    
    // Log the login
    await _auditRepository.log(
      id: _uuid.v4(),
      branchId: _currentBranch?.id,
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
        branchId: _currentBranch?.id,
        userId: _currentUser!.id,
        action: AuditAction.logout,
        entityType: AuditEntityType.user,
        entityId: _currentUser!.id,
      );
    }
    
    _currentUser = null;
    _currentBranch = null;
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
      branchId: _currentBranch?.id,
      userId: _currentUser!.id,
      action: AuditAction.update,
      entityType: AuditEntityType.user,
      entityId: userId,
      newValues: {'password_reset': true},
    );
  }
  
  /// Switch branch (for users with access to multiple branches)
  Future<void> switchBranch(String branchId) async {
    if (_currentUser == null) {
      throw Exception('Not logged in');
    }
    
    // Super admins can switch to any branch
    if (!isSuperAdmin && _currentUser!.branchId != branchId) {
      throw Exception('Unauthorized to access this branch');
    }
    
    final branch = await _branchRepository.getById(branchId);
    if (branch == null || !branch.isActive) {
      throw Exception('Branch not found or inactive');
    }
    
    _currentBranch = branch;
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
    
    // Create the main branch with default shifts using BranchContextService
    final branch = await BranchContextService.instance.createBranchWithDefaults(
      name: branchName,
      setAsActive: true, // This is the first branch, so set it as active
    );
    
    // Set as main branch
    await _branchRepository.setAsMainBranch(branch.id);
    
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
  
  /// Check if system needs initial setup
  Future<bool> needsInitialSetup() async {
    final userCount = await _userRepository.count();
    return userCount == 0;
  }
}
