import 'package:equatable/equatable.dart';
import '../../core/constants/app_constants.dart';

/// User model for authentication
class User extends Equatable {
  final String id;
  final String username;
  final String passwordHash;
  final String salt;
  final UserRole role;
  final String? employeeId;
  final String? branchId;
  final bool isActive;
  final DateTime? lastLogin;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? syncedAt;

  const User({
    required this.id,
    required this.username,
    required this.passwordHash,
    required this.salt,
    required this.role,
    this.employeeId,
    this.branchId,
    this.isActive = true,
    this.lastLogin,
    required this.createdAt,
    required this.updatedAt,
    this.syncedAt,
  });

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as String,
      username: map['username'] as String,
      passwordHash: map['password_hash'] as String,
      salt: map['salt'] as String,
      role: UserRole.fromString(map['role'] as String),
      employeeId: map['employee_id'] as String?,
      branchId: map['branch_id'] as String?,
      isActive: (map['is_active'] as int?) == 1,
      lastLogin: map['last_login'] != null
          ? DateTime.parse(map['last_login'] as String)
          : null,
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
      'username': username,
      'password_hash': passwordHash,
      'salt': salt,
      'role': role.value,
      'employee_id': employeeId,
      'branch_id': branchId,
      'is_active': isActive ? 1 : 0,
      'last_login': lastLogin?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'synced_at': syncedAt?.toIso8601String(),
    };
  }

  User copyWith({
    String? id,
    String? username,
    String? passwordHash,
    String? salt,
    UserRole? role,
    String? employeeId,
    String? branchId,
    bool? isActive,
    DateTime? lastLogin,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? syncedAt,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      passwordHash: passwordHash ?? this.passwordHash,
      salt: salt ?? this.salt,
      role: role ?? this.role,
      employeeId: employeeId ?? this.employeeId,
      branchId: branchId ?? this.branchId,
      isActive: isActive ?? this.isActive,
      lastLogin: lastLogin ?? this.lastLogin,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  /// Check if user has permission
  bool hasPermission(String permission) {
    switch (permission) {
      case 'manage_employees':
        return role.canManageEmployees;
      case 'manage_shifts':
        return role.canManageShifts;
      case 'approve_overrides':
        return role.canApproveOverrides;
      case 'view_reports':
        return role.canViewReports;
      case 'manage_settings':
        return role.canManageSettings;
      case 'manage_branches':
        return role.canManageBranches;
      default:
        return false;
    }
  }

  @override
  List<Object?> get props => [
        id,
        username,
        passwordHash,
        salt,
        role,
        employeeId,
        branchId,
        isActive,
        lastLogin,
        createdAt,
        updatedAt,
        syncedAt,
      ];
}
