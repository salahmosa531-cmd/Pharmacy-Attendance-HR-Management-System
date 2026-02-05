import 'dart:async';
import 'package:uuid/uuid.dart';
import '../constants/app_constants.dart';
import 'database_service.dart';
import 'branch_context_service.dart';

/// Central Settings Manager with stream-based reactive updates
/// 
/// This service ensures:
/// - All settings are persisted to SQLite immediately
/// - Changes are broadcast to all listeners via streams
/// - UI updates instantly without manual refresh
/// - Settings are loaded from database on app start
class SettingsService {
  static SettingsService? _instance;
  
  final DatabaseService _databaseService = DatabaseService.instance;
  final BranchContextService _branchContextService = BranchContextService.instance;
  final Uuid _uuid = const Uuid();
  
  // Stream controller for settings changes
  final _settingsController = StreamController<SettingsState>.broadcast();
  
  // Current settings state
  SettingsState _currentState = SettingsState();
  
  // Cache for quick access
  final Map<String, dynamic> _cache = {};
  
  SettingsService._();
  
  static SettingsService get instance {
    _instance ??= SettingsService._();
    return _instance!;
  }
  
  /// Stream of settings changes - subscribe to get real-time updates
  Stream<SettingsState> get settingsStream => _settingsController.stream;
  
  /// Current settings state
  SettingsState get currentState => _currentState;
  
  /// Initialize settings from database
  Future<void> initialize([String? branchId]) async {
    await _loadAllSettings(branchId);
    _notifyListeners();
  }
  
  /// Load all settings from database
  Future<void> _loadAllSettings([String? branchId]) async {
    final db = await _databaseService.database;
    final effectiveBranchId = branchId ?? _branchContextService.activeBranchId;
    
    List<Map<String, dynamic>> results;
    if (effectiveBranchId != null) {
      results = await db.query(
        'settings',
        where: 'branch_id = ? OR branch_id IS NULL',
        whereArgs: [effectiveBranchId],
      );
    } else {
      results = await db.query(
        'settings',
        where: 'branch_id IS NULL',
      );
    }
    
    _cache.clear();
    for (final row in results) {
      final key = row['key'] as String;
      final value = _parseValue(row['value'], row['value_type'] as String?);
      _cache[key] = value;
    }
    
    // Update state from cache
    _currentState = SettingsState(
      // Attendance Methods
      allowManualEntry: getBool(SettingKeys.allowManualEntry, true),
      allowBarcodeEntry: getBool(SettingKeys.allowBarcodeEntry, true),
      allowQrEntry: getBool(SettingKeys.allowQrEntry, true),
      allowFingerprintEntry: getBool(SettingKeys.allowFingerprintEntry, false),
      
      // Attendance Rules
      gracePeriodMinutes: getInt(SettingKeys.gracePeriodMinutes, AppConstants.defaultGracePeriodMinutes),
      attendanceWindowMinutes: getInt(SettingKeys.attendanceWindowMinutes, AppConstants.attendanceWindowMinutes),
      qrRefreshSeconds: getInt(SettingKeys.qrRefreshSeconds, AppConstants.qrRefreshSeconds),
      duplicateScanProtectionSeconds: getInt(SettingKeys.duplicateScanProtectionSeconds, AppConstants.duplicateScanProtectionSeconds),
      
      // Security
      requireDeviceBinding: getBool(SettingKeys.requireDeviceBinding, true),
      enableLocationVerification: getBool(SettingKeys.enableLocationVerification, false),
      
      // Payroll
      calculateOvertime: getBool(SettingKeys.calculateOvertime, true),
      overtimeMultiplier: getDouble(SettingKeys.overtimeMultiplier, AppConstants.defaultOvertimeMultiplier),
      weekendMultiplier: getDouble(SettingKeys.weekendMultiplier, AppConstants.weekendOvertimeMultiplier),
      
      // System
      autoBackup: getBool(SettingKeys.autoBackup, true),
      backupIntervalHours: getInt(SettingKeys.backupIntervalHours, 24),
      cloudSyncEnabled: getBool(SettingKeys.cloudSyncEnabled, false),
      
      // UI
      soundEnabled: getBool(SettingKeys.soundEnabled, true),
      showLastAttendance: getBool(SettingKeys.showLastAttendance, true),
      kioskModeTimeout: getInt(SettingKeys.kioskModeTimeout, 30),
      
      // Kiosk
      kioskAdminPassword: getString(SettingKeys.kioskAdminPassword, ''),
    );
  }
  
  /// Get a setting value with type conversion
  dynamic getValue(String key, [dynamic defaultValue]) {
    return _cache[key] ?? defaultValue;
  }
  
  /// Get string setting
  String getString(String key, [String defaultValue = '']) {
    final value = _cache[key];
    if (value == null) return defaultValue;
    return value.toString();
  }
  
  /// Get int setting
  int getInt(String key, [int defaultValue = 0]) {
    final value = _cache[key];
    if (value == null) return defaultValue;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? defaultValue;
  }
  
  /// Get double setting
  double getDouble(String key, [double defaultValue = 0.0]) {
    final value = _cache[key];
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? defaultValue;
  }
  
  /// Get bool setting
  bool getBool(String key, [bool defaultValue = false]) {
    final value = _cache[key];
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) return value.toLowerCase() == 'true' || value == '1';
    return defaultValue;
  }
  
  /// Set a setting value - persists immediately and broadcasts change
  Future<void> setValue(String key, dynamic value, {String? category, String? description}) async {
    final db = await _databaseService.database;
    final branchId = _branchContextService.activeBranchId;
    final now = DateTime.now().toIso8601String();
    
    // Determine value type
    String valueType = 'string';
    String stringValue = value.toString();
    if (value is bool) {
      valueType = 'bool';
      stringValue = value ? '1' : '0';
    } else if (value is int) {
      valueType = 'int';
    } else if (value is double) {
      valueType = 'double';
    }
    
    // Check if setting exists
    final existing = await db.query(
      'settings',
      where: 'key = ? AND (branch_id = ? OR (branch_id IS NULL AND ? IS NULL))',
      whereArgs: [key, branchId, branchId],
      limit: 1,
    );
    
    if (existing.isNotEmpty) {
      await db.update(
        'settings',
        {
          'value': stringValue,
          'value_type': valueType,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      await db.insert('settings', {
        'id': _uuid.v4(),
        'branch_id': branchId,
        'key': key,
        'value': stringValue,
        'value_type': valueType,
        'category': category,
        'description': description,
        'is_system': 0,
        'created_at': now,
        'updated_at': now,
      });
    }
    
    // Update cache
    _cache[key] = value;
    
    // Reload state and notify
    await _loadAllSettings(branchId);
    _notifyListeners();
  }
  
  /// Set multiple settings at once
  Future<void> setValues(Map<String, dynamic> settings) async {
    for (final entry in settings.entries) {
      await setValue(entry.key, entry.value);
    }
  }
  
  /// Notify all listeners of state change
  void _notifyListeners() {
    if (!_settingsController.isClosed) {
      _settingsController.add(_currentState);
    }
  }
  
  /// Parse value based on type
  dynamic _parseValue(dynamic value, String? type) {
    if (value == null) return null;
    
    switch (type) {
      case 'bool':
        return value == '1' || value == 'true';
      case 'int':
        return int.tryParse(value.toString()) ?? 0;
      case 'double':
        return double.tryParse(value.toString()) ?? 0.0;
      default:
        return value.toString();
    }
  }
  
  /// Reset all settings to defaults
  Future<void> resetToDefaults() async {
    final db = await _databaseService.database;
    final branchId = _branchContextService.activeBranchId;
    
    if (branchId != null) {
      await db.delete(
        'settings',
        where: 'branch_id = ? AND is_system = 0',
        whereArgs: [branchId],
      );
    }
    
    _cache.clear();
    await _loadAllSettings(branchId);
    _notifyListeners();
  }
  
  /// Dispose resources
  void dispose() {
    _settingsController.close();
  }
}

/// Setting keys constants
class SettingKeys {
  // Attendance Methods
  static const allowManualEntry = 'attendance.allow_manual_entry';
  static const allowBarcodeEntry = 'attendance.allow_barcode_entry';
  static const allowQrEntry = 'attendance.allow_qr_entry';
  static const allowFingerprintEntry = 'attendance.allow_fingerprint_entry';
  
  // Attendance Rules
  static const gracePeriodMinutes = 'attendance.grace_period_minutes';
  static const attendanceWindowMinutes = 'attendance.attendance_window_minutes';
  static const qrRefreshSeconds = 'attendance.qr_refresh_seconds';
  static const duplicateScanProtectionSeconds = 'attendance.duplicate_scan_protection_seconds';
  static const minClockInOutDuration = 'attendance.min_clock_in_out_duration';
  
  // Security
  static const requireDeviceBinding = 'security.require_device_binding';
  static const enableLocationVerification = 'security.enable_location_verification';
  
  // Payroll
  static const calculateOvertime = 'payroll.calculate_overtime';
  static const overtimeMultiplier = 'payroll.overtime_multiplier';
  static const weekendMultiplier = 'payroll.weekend_multiplier';
  static const lateDeductionPerMinute = 'payroll.late_deduction_per_minute';
  static const absenceDeductionPercent = 'payroll.absence_deduction_percent';
  
  // System
  static const autoBackup = 'system.auto_backup';
  static const backupIntervalHours = 'system.backup_interval_hours';
  static const cloudSyncEnabled = 'system.cloud_sync_enabled';
  static const cloudEndpoint = 'system.cloud_endpoint';
  
  // UI / Kiosk
  static const soundEnabled = 'ui.sound_enabled';
  static const showLastAttendance = 'ui.show_last_attendance';
  static const kioskModeTimeout = 'kiosk.timeout_seconds';
  static const kioskAdminPassword = 'kiosk.admin_password';
}

/// Immutable settings state
class SettingsState {
  // Attendance Methods
  final bool allowManualEntry;
  final bool allowBarcodeEntry;
  final bool allowQrEntry;
  final bool allowFingerprintEntry;
  
  // Attendance Rules
  final int gracePeriodMinutes;
  final int attendanceWindowMinutes;
  final int qrRefreshSeconds;
  final int duplicateScanProtectionSeconds;
  
  // Security
  final bool requireDeviceBinding;
  final bool enableLocationVerification;
  
  // Payroll
  final bool calculateOvertime;
  final double overtimeMultiplier;
  final double weekendMultiplier;
  
  // System
  final bool autoBackup;
  final int backupIntervalHours;
  final bool cloudSyncEnabled;
  
  // UI
  final bool soundEnabled;
  final bool showLastAttendance;
  final int kioskModeTimeout;
  
  // Kiosk
  final String kioskAdminPassword;
  
  const SettingsState({
    this.allowManualEntry = true,
    this.allowBarcodeEntry = true,
    this.allowQrEntry = true,
    this.allowFingerprintEntry = false,
    this.gracePeriodMinutes = 15,
    this.attendanceWindowMinutes = 120,
    this.qrRefreshSeconds = 30,
    this.duplicateScanProtectionSeconds = 60,
    this.requireDeviceBinding = true,
    this.enableLocationVerification = false,
    this.calculateOvertime = true,
    this.overtimeMultiplier = 1.5,
    this.weekendMultiplier = 2.0,
    this.autoBackup = true,
    this.backupIntervalHours = 24,
    this.cloudSyncEnabled = false,
    this.soundEnabled = true,
    this.showLastAttendance = true,
    this.kioskModeTimeout = 30,
    this.kioskAdminPassword = '',
  });
  
  /// Check if any attendance method is enabled
  bool get hasAnyAttendanceMethod => 
      allowManualEntry || allowBarcodeEntry || allowQrEntry || allowFingerprintEntry;
  
  /// Create a copy with some values changed
  SettingsState copyWith({
    bool? allowManualEntry,
    bool? allowBarcodeEntry,
    bool? allowQrEntry,
    bool? allowFingerprintEntry,
    int? gracePeriodMinutes,
    int? attendanceWindowMinutes,
    int? qrRefreshSeconds,
    int? duplicateScanProtectionSeconds,
    bool? requireDeviceBinding,
    bool? enableLocationVerification,
    bool? calculateOvertime,
    double? overtimeMultiplier,
    double? weekendMultiplier,
    bool? autoBackup,
    int? backupIntervalHours,
    bool? cloudSyncEnabled,
    bool? soundEnabled,
    bool? showLastAttendance,
    int? kioskModeTimeout,
    String? kioskAdminPassword,
  }) {
    return SettingsState(
      allowManualEntry: allowManualEntry ?? this.allowManualEntry,
      allowBarcodeEntry: allowBarcodeEntry ?? this.allowBarcodeEntry,
      allowQrEntry: allowQrEntry ?? this.allowQrEntry,
      allowFingerprintEntry: allowFingerprintEntry ?? this.allowFingerprintEntry,
      gracePeriodMinutes: gracePeriodMinutes ?? this.gracePeriodMinutes,
      attendanceWindowMinutes: attendanceWindowMinutes ?? this.attendanceWindowMinutes,
      qrRefreshSeconds: qrRefreshSeconds ?? this.qrRefreshSeconds,
      duplicateScanProtectionSeconds: duplicateScanProtectionSeconds ?? this.duplicateScanProtectionSeconds,
      requireDeviceBinding: requireDeviceBinding ?? this.requireDeviceBinding,
      enableLocationVerification: enableLocationVerification ?? this.enableLocationVerification,
      calculateOvertime: calculateOvertime ?? this.calculateOvertime,
      overtimeMultiplier: overtimeMultiplier ?? this.overtimeMultiplier,
      weekendMultiplier: weekendMultiplier ?? this.weekendMultiplier,
      autoBackup: autoBackup ?? this.autoBackup,
      backupIntervalHours: backupIntervalHours ?? this.backupIntervalHours,
      cloudSyncEnabled: cloudSyncEnabled ?? this.cloudSyncEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      showLastAttendance: showLastAttendance ?? this.showLastAttendance,
      kioskModeTimeout: kioskModeTimeout ?? this.kioskModeTimeout,
      kioskAdminPassword: kioskAdminPassword ?? this.kioskAdminPassword,
    );
  }
}
