import 'dart:convert';
import 'package:equatable/equatable.dart';

/// Audit log model for tracking all changes
class AuditLog extends Equatable {
  final String id;
  final String? branchId;
  final String? userId;
  final AuditAction action;
  final AuditEntityType entityType;
  final String entityId;
  final Map<String, dynamic>? oldValues;
  final Map<String, dynamic>? newValues;
  final String? description;
  final String? ipAddress;
  final String? deviceId;
  final DateTime createdAt;
  final DateTime? syncedAt;

  const AuditLog({
    required this.id,
    this.branchId,
    this.userId,
    required this.action,
    required this.entityType,
    required this.entityId,
    this.oldValues,
    this.newValues,
    this.description,
    this.ipAddress,
    this.deviceId,
    required this.createdAt,
    this.syncedAt,
  });

  factory AuditLog.fromMap(Map<String, dynamic> map) {
    return AuditLog(
      id: map['id'] as String,
      branchId: map['branch_id'] as String?,
      userId: map['user_id'] as String?,
      action: AuditAction.fromString(map['action'] as String),
      entityType: AuditEntityType.fromString(map['entity_type'] as String),
      entityId: map['entity_id'] as String? ?? '',
      oldValues: map['old_values'] != null
          ? jsonDecode(map['old_values'] as String) as Map<String, dynamic>
          : null,
      newValues: map['new_values'] != null
          ? jsonDecode(map['new_values'] as String) as Map<String, dynamic>
          : null,
      description: map['description'] as String?,
      ipAddress: map['ip_address'] as String?,
      deviceId: map['device_id'] as String?,
      createdAt: DateTime.parse(map['timestamp'] as String),
      syncedAt: map['synced_at'] != null
          ? DateTime.parse(map['synced_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'branch_id': branchId,
      'user_id': userId,
      'action': action.value,
      'entity_type': entityType.value,
      'entity_id': entityId,
      'old_values': oldValues != null ? jsonEncode(oldValues) : null,
      'new_values': newValues != null ? jsonEncode(newValues) : null,
      'description': description,
      'ip_address': ipAddress,
      'device_id': deviceId,
      'timestamp': createdAt.toIso8601String(),
      'synced_at': syncedAt?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
        id,
        branchId,
        userId,
        action,
        entityType,
        entityId,
        oldValues,
        newValues,
        description,
        ipAddress,
        deviceId,
        createdAt,
        syncedAt,
      ];
}

/// Audit action types
enum AuditAction {
  create,
  update,
  delete,
  login,
  logout,
  clockIn,
  clockOut,
  manualOverride,
  forgiveLateness,
  sync,
  deviceAuthorize,
  deviceRevoke,
  backup,
  restore,
  settingsChange,
  generateReport,
  exportData,
  importData;

  static AuditAction fromString(String value) {
    switch (value) {
      case 'CREATE':
        return AuditAction.create;
      case 'UPDATE':
        return AuditAction.update;
      case 'DELETE':
        return AuditAction.delete;
      case 'LOGIN':
        return AuditAction.login;
      case 'LOGOUT':
        return AuditAction.logout;
      case 'CLOCK_IN':
        return AuditAction.clockIn;
      case 'CLOCK_OUT':
        return AuditAction.clockOut;
      case 'MANUAL_OVERRIDE':
        return AuditAction.manualOverride;
      case 'FORGIVE_LATENESS':
        return AuditAction.forgiveLateness;
      case 'SYNC':
        return AuditAction.sync;
      case 'DEVICE_AUTHORIZE':
        return AuditAction.deviceAuthorize;
      case 'DEVICE_REVOKE':
        return AuditAction.deviceRevoke;
      case 'BACKUP':
        return AuditAction.backup;
      case 'RESTORE':
        return AuditAction.restore;
      case 'SETTINGS_CHANGE':
        return AuditAction.settingsChange;
      case 'GENERATE_REPORT':
        return AuditAction.generateReport;
      case 'EXPORT_DATA':
        return AuditAction.exportData;
      case 'IMPORT_DATA':
        return AuditAction.importData;
      default:
        return AuditAction.create;
    }
  }
}

extension AuditActionExtension on AuditAction {
  String get value {
    switch (this) {
      case AuditAction.create:
        return 'CREATE';
      case AuditAction.update:
        return 'UPDATE';
      case AuditAction.delete:
        return 'DELETE';
      case AuditAction.login:
        return 'LOGIN';
      case AuditAction.logout:
        return 'LOGOUT';
      case AuditAction.clockIn:
        return 'CLOCK_IN';
      case AuditAction.clockOut:
        return 'CLOCK_OUT';
      case AuditAction.manualOverride:
        return 'MANUAL_OVERRIDE';
      case AuditAction.forgiveLateness:
        return 'FORGIVE_LATENESS';
      case AuditAction.sync:
        return 'SYNC';
      case AuditAction.deviceAuthorize:
        return 'DEVICE_AUTHORIZE';
      case AuditAction.deviceRevoke:
        return 'DEVICE_REVOKE';
      case AuditAction.backup:
        return 'BACKUP';
      case AuditAction.restore:
        return 'RESTORE';
      case AuditAction.settingsChange:
        return 'SETTINGS_CHANGE';
      case AuditAction.generateReport:
        return 'GENERATE_REPORT';
      case AuditAction.exportData:
        return 'EXPORT_DATA';
      case AuditAction.importData:
        return 'IMPORT_DATA';
    }
  }

  String get displayName {
    switch (this) {
      case AuditAction.create:
        return 'Created';
      case AuditAction.update:
        return 'Updated';
      case AuditAction.delete:
        return 'Deleted';
      case AuditAction.login:
        return 'Login';
      case AuditAction.logout:
        return 'Logout';
      case AuditAction.clockIn:
        return 'Clock In';
      case AuditAction.clockOut:
        return 'Clock Out';
      case AuditAction.manualOverride:
        return 'Manual Override';
      case AuditAction.forgiveLateness:
        return 'Forgive Lateness';
      case AuditAction.sync:
        return 'Sync';
      case AuditAction.deviceAuthorize:
        return 'Device Authorized';
      case AuditAction.deviceRevoke:
        return 'Device Revoked';
      case AuditAction.backup:
        return 'Backup';
      case AuditAction.restore:
        return 'Restore';
      case AuditAction.settingsChange:
        return 'Settings Changed';
      case AuditAction.generateReport:
        return 'Report Generated';
      case AuditAction.exportData:
        return 'Data Exported';
      case AuditAction.importData:
        return 'Data Imported';
    }
  }
}

/// Entity types for audit logging
enum AuditEntityType {
  user,
  employee,
  shift,
  attendance,
  branch,
  settings,
  device;

  static AuditEntityType fromString(String value) {
    switch (value) {
      case 'USER':
        return AuditEntityType.user;
      case 'EMPLOYEE':
        return AuditEntityType.employee;
      case 'SHIFT':
        return AuditEntityType.shift;
      case 'ATTENDANCE':
        return AuditEntityType.attendance;
      case 'BRANCH':
        return AuditEntityType.branch;
      case 'SETTINGS':
        return AuditEntityType.settings;
      case 'DEVICE':
        return AuditEntityType.device;
      default:
        return AuditEntityType.user;
    }
  }
}

extension AuditEntityTypeExtension on AuditEntityType {
  String get value {
    switch (this) {
      case AuditEntityType.user:
        return 'USER';
      case AuditEntityType.employee:
        return 'EMPLOYEE';
      case AuditEntityType.shift:
        return 'SHIFT';
      case AuditEntityType.attendance:
        return 'ATTENDANCE';
      case AuditEntityType.branch:
        return 'BRANCH';
      case AuditEntityType.settings:
        return 'SETTINGS';
      case AuditEntityType.device:
        return 'DEVICE';
    }
  }

  String get displayName {
    switch (this) {
      case AuditEntityType.user:
        return 'User';
      case AuditEntityType.employee:
        return 'Employee';
      case AuditEntityType.shift:
        return 'Shift';
      case AuditEntityType.attendance:
        return 'Attendance';
      case AuditEntityType.branch:
        return 'Branch';
      case AuditEntityType.settings:
        return 'Settings';
      case AuditEntityType.device:
        return 'Device';
    }
  }
}
