import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../data/repositories/repositories.dart';
import '../../data/models/audit_log_model.dart';
import 'auth_service.dart';
import 'database_service.dart';

/// Service for device management and binding
class DeviceService {
  static DeviceService? _instance;
  
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final AuditRepository _auditRepository = AuditRepository.instance;
  final AuthService _authService = AuthService.instance;
  final Uuid _uuid = const Uuid();
  
  static const String _deviceIdKey = 'device_id';
  
  String? _cachedDeviceId;
  
  DeviceService._();
  
  static DeviceService get instance {
    _instance ??= DeviceService._();
    return _instance!;
  }
  
  /// Get unique device ID
  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) {
      return _cachedDeviceId!;
    }
    
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);
    
    if (deviceId == null) {
      // Generate new device ID based on hardware info
      deviceId = await _generateDeviceId();
      await prefs.setString(_deviceIdKey, deviceId);
    }
    
    _cachedDeviceId = deviceId;
    return deviceId;
  }
  
  /// Generate device ID based on hardware info
  Future<String> _generateDeviceId() async {
    String identifier = '';
    
    if (Platform.isWindows) {
      final windowsInfo = await _deviceInfo.windowsInfo;
      identifier = '${windowsInfo.computerName}_${windowsInfo.deviceId}';
    } else if (Platform.isLinux) {
      final linuxInfo = await _deviceInfo.linuxInfo;
      identifier = '${linuxInfo.name}_${linuxInfo.machineId ?? _uuid.v4()}';
    } else if (Platform.isMacOS) {
      final macInfo = await _deviceInfo.macOsInfo;
      identifier = '${macInfo.computerName}_${macInfo.systemGUID ?? _uuid.v4()}';
    } else {
      identifier = _uuid.v4();
    }
    
    return identifier;
  }
  
  /// Get device name
  Future<String> getDeviceName() async {
    if (Platform.isWindows) {
      final windowsInfo = await _deviceInfo.windowsInfo;
      return windowsInfo.computerName;
    } else if (Platform.isLinux) {
      final linuxInfo = await _deviceInfo.linuxInfo;
      return linuxInfo.prettyName;
    } else if (Platform.isMacOS) {
      final macInfo = await _deviceInfo.macOsInfo;
      return macInfo.computerName;
    }
    return 'Unknown Device';
  }
  
  /// Get device type
  String getDeviceType() {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isMacOS) return 'macOS';
    return 'Unknown';
  }
  
  /// Check if device is authorized for a branch
  Future<bool> isDeviceAuthorized(String branchId) async {
    final deviceId = await getDeviceId();
    
    final db = await DatabaseService.instance.database;
    final results = await db.query(
      'device_registrations',
      where: 'branch_id = ? AND device_id = ? AND is_authorized = 1 AND is_active = 1',
      whereArgs: [branchId, deviceId],
      limit: 1,
    );
    
    // If no registrations exist yet, allow the device (first-time setup)
    if (results.isEmpty) {
      final registrationCount = await db.rawQuery(
        'SELECT COUNT(*) as count FROM device_registrations WHERE branch_id = ?',
        [branchId],
      );
      
      final count = registrationCount.first['count'] as int;
      if (count == 0) {
        // No devices registered - auto-authorize this device
        await registerDevice(branchId, autoAuthorize: true);
        return true;
      }
      
      return false;
    }
    
    // Update last seen
    await db.update(
      'device_registrations',
      {'last_seen': DateTime.now().toIso8601String()},
      where: 'branch_id = ? AND device_id = ?',
      whereArgs: [branchId, deviceId],
    );
    
    return true;
  }
  
  /// Register a device for a branch
  Future<void> registerDevice(String branchId, {bool autoAuthorize = false}) async {
    final deviceId = await getDeviceId();
    final deviceName = await getDeviceName();
    final deviceType = getDeviceType();
    final now = DateTime.now();
    
    final db = await DatabaseService.instance.database;
    await db.insert(
      'device_registrations',
      {
        'id': _uuid.v4(),
        'branch_id': branchId,
        'device_id': deviceId,
        'device_name': deviceName,
        'device_type': deviceType,
        'is_authorized': autoAuthorize ? 1 : 0,
        'authorized_by': autoAuthorize ? _authService.currentUser?.id : null,
        'authorized_at': autoAuthorize ? now.toIso8601String() : null,
        'last_seen': now.toIso8601String(),
        'is_active': 1,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    if (autoAuthorize) {
      await _auditRepository.log(
        id: _uuid.v4(),
        branchId: branchId,
        userId: _authService.currentUser?.id,
        action: AuditAction.deviceAuthorize,
        entityType: AuditEntityType.device,
        entityId: deviceId,
        newValues: {
          'device_name': deviceName,
          'device_type': deviceType,
          'auto_authorized': true,
        },
      );
    }
  }
  
  /// Authorize a device
  Future<void> authorizeDevice(String branchId, String deviceId) async {
    if (!_authService.hasPermission('manage_settings')) {
      throw Exception('Unauthorized');
    }
    
    final now = DateTime.now();
    final db = await DatabaseService.instance.database;
    
    await db.update(
      'device_registrations',
      {
        'is_authorized': 1,
        'authorized_by': _authService.currentUser!.id,
        'authorized_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      where: 'branch_id = ? AND device_id = ?',
      whereArgs: [branchId, deviceId],
    );
    
    await _auditRepository.log(
      id: _uuid.v4(),
      branchId: branchId,
      userId: _authService.currentUser!.id,
      action: AuditAction.deviceAuthorize,
      entityType: AuditEntityType.device,
      entityId: deviceId,
    );
  }
  
  /// Revoke device authorization
  Future<void> revokeDevice(String branchId, String deviceId) async {
    if (!_authService.hasPermission('manage_settings')) {
      throw Exception('Unauthorized');
    }
    
    final now = DateTime.now();
    final db = await DatabaseService.instance.database;
    
    await db.update(
      'device_registrations',
      {
        'is_authorized': 0,
        'is_active': 0,
        'updated_at': now.toIso8601String(),
      },
      where: 'branch_id = ? AND device_id = ?',
      whereArgs: [branchId, deviceId],
    );
    
    await _auditRepository.log(
      id: _uuid.v4(),
      branchId: branchId,
      userId: _authService.currentUser!.id,
      action: AuditAction.deviceRevoke,
      entityType: AuditEntityType.device,
      entityId: deviceId,
    );
  }
  
  /// Get all registered devices for a branch
  Future<List<Map<String, dynamic>>> getRegisteredDevices(String branchId) async {
    final db = await DatabaseService.instance.database;
    return await db.query(
      'device_registrations',
      where: 'branch_id = ?',
      whereArgs: [branchId],
      orderBy: 'created_at DESC',
    );
  }
  
  /// Get pending device authorizations
  Future<List<Map<String, dynamic>>> getPendingAuthorizations(String branchId) async {
    final db = await DatabaseService.instance.database;
    return await db.query(
      'device_registrations',
      where: 'branch_id = ? AND is_authorized = 0 AND is_active = 1',
      whereArgs: [branchId],
      orderBy: 'created_at DESC',
    );
  }
}
