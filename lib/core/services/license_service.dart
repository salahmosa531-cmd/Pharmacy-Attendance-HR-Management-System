import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../constants/app_constants.dart';

/// Service for offline license management
class LicenseService {
  static LicenseService? _instance;
  
  static const String _licenseKey = 'pharmatrack_license';
  static const String _installDateKey = 'pharmatrack_install_date';
  static const String _deviceIdKey = 'pharmatrack_device_id';
  static const String _secretSalt = 'PharmaTrack_Enterprise_2024_Salt';
  
  LicenseInfo? _cachedLicense;
  
  LicenseService._();
  
  static LicenseService get instance {
    _instance ??= LicenseService._();
    return _instance!;
  }
  
  /// Get current license status
  Future<LicenseInfo> getLicenseInfo() async {
    if (_cachedLicense != null) {
      // Refresh cache if expiring soon
      final now = DateTime.now();
      if (_cachedLicense!.expiryDate != null && 
          _cachedLicense!.expiryDate!.isBefore(now)) {
        _cachedLicense = null;
      }
    }
    
    _cachedLicense ??= await _loadLicenseInfo();
    return _cachedLicense!;
  }
  
  /// Load license info from storage
  Future<LicenseInfo> _loadLicenseInfo() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check install date for trial
    String? installDateStr = prefs.getString(_installDateKey);
    DateTime installDate;
    
    if (installDateStr == null) {
      // First time install
      installDate = DateTime.now();
      await prefs.setString(_installDateKey, installDate.toIso8601String());
    } else {
      installDate = DateTime.parse(installDateStr);
    }
    
    // Get device ID
    final deviceId = await _getDeviceId();
    
    // Check for stored license
    final licenseData = prefs.getString(_licenseKey);
    
    if (licenseData == null) {
      // No license - check trial status
      return _createTrialLicense(installDate, deviceId);
    }
    
    // Validate stored license
    try {
      final license = _decodeLicense(licenseData);
      
      // Verify device binding
      if (license['device_id'] != deviceId) {
        return LicenseInfo(
          type: LicenseType.expired,
          status: LicenseStatus.invalid,
          message: 'License is bound to a different device',
          deviceId: deviceId,
          installDate: installDate,
        );
      }
      
      return _createLicenseFromData(license, deviceId, installDate);
    } catch (e) {
      return _createTrialLicense(installDate, deviceId);
    }
  }
  
  /// Create trial license info
  LicenseInfo _createTrialLicense(DateTime installDate, String deviceId) {
    final trialEndDate = installDate.add(
      Duration(days: AppConstants.trialPeriodDays),
    );
    final now = DateTime.now();
    final daysRemaining = trialEndDate.difference(now).inDays;
    
    if (daysRemaining <= 0) {
      return LicenseInfo(
        type: LicenseType.trial,
        status: LicenseStatus.expired,
        message: 'Trial period has expired. Please activate a license.',
        deviceId: deviceId,
        installDate: installDate,
        expiryDate: trialEndDate,
        daysRemaining: 0,
      );
    }
    
    return LicenseInfo(
      type: LicenseType.trial,
      status: LicenseStatus.active,
      message: '$daysRemaining days remaining in trial',
      deviceId: deviceId,
      installDate: installDate,
      expiryDate: trialEndDate,
      daysRemaining: daysRemaining,
    );
  }
  
  /// Create license from decoded data
  LicenseInfo _createLicenseFromData(
    Map<String, dynamic> data,
    String deviceId,
    DateTime installDate,
  ) {
    final licenseType = LicenseType.values.firstWhere(
      (t) => t.value == data['type'],
      orElse: () => LicenseType.trial,
    );
    
    DateTime? expiryDate;
    if (data['expiry_date'] != null) {
      expiryDate = DateTime.parse(data['expiry_date']);
    }
    
    // Check expiry for subscription
    if (expiryDate != null && licenseType == LicenseType.subscription) {
      final now = DateTime.now();
      if (expiryDate.isBefore(now)) {
        return LicenseInfo(
          type: licenseType,
          status: LicenseStatus.expired,
          message: 'Subscription has expired. Please renew.',
          deviceId: deviceId,
          installDate: installDate,
          expiryDate: expiryDate,
          activationDate: DateTime.tryParse(data['activation_date'] ?? ''),
          licenseKey: data['key'],
        );
      }
      
      final daysRemaining = expiryDate.difference(now).inDays;
      return LicenseInfo(
        type: licenseType,
        status: LicenseStatus.active,
        message: 'Subscription active - $daysRemaining days remaining',
        deviceId: deviceId,
        installDate: installDate,
        expiryDate: expiryDate,
        daysRemaining: daysRemaining,
        activationDate: DateTime.tryParse(data['activation_date'] ?? ''),
        licenseKey: data['key'],
        features: List<String>.from(data['features'] ?? []),
      );
    }
    
    // Lifetime license
    return LicenseInfo(
      type: licenseType,
      status: LicenseStatus.active,
      message: 'Lifetime license active',
      deviceId: deviceId,
      installDate: installDate,
      activationDate: DateTime.tryParse(data['activation_date'] ?? ''),
      licenseKey: data['key'],
      features: List<String>.from(data['features'] ?? []),
    );
  }
  
  /// Activate license with key
  Future<LicenseActivationResult> activateLicense(String licenseKey) async {
    try {
      // Validate license key format
      if (!_isValidKeyFormat(licenseKey)) {
        return LicenseActivationResult(
          success: false,
          message: 'Invalid license key format',
        );
      }
      
      // Decode and verify license key
      final licenseData = _decodeLicenseKey(licenseKey);
      if (licenseData == null) {
        return LicenseActivationResult(
          success: false,
          message: 'Invalid license key',
        );
      }
      
      // Get device ID
      final deviceId = await _getDeviceId();
      
      // Create license data for storage
      final storedData = {
        'key': licenseKey,
        'type': licenseData['type'],
        'device_id': deviceId,
        'activation_date': DateTime.now().toIso8601String(),
        'expiry_date': licenseData['expiry_date'],
        'features': licenseData['features'] ?? _getAllFeatures(),
        'customer_name': licenseData['customer_name'],
        'pharmacy_name': licenseData['pharmacy_name'],
      };
      
      // Encode and store
      final encodedLicense = _encodeLicense(storedData);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_licenseKey, encodedLicense);
      
      // Also save to file for backup
      await _saveLicenseBackup(storedData);
      
      // Clear cache
      _cachedLicense = null;
      
      return LicenseActivationResult(
        success: true,
        message: 'License activated successfully',
        license: await getLicenseInfo(),
      );
    } catch (e) {
      return LicenseActivationResult(
        success: false,
        message: 'Activation failed: $e',
      );
    }
  }
  
  /// Deactivate current license
  Future<void> deactivateLicense() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_licenseKey);
    _cachedLicense = null;
  }
  
  /// Generate offline activation request
  Future<String> generateActivationRequest() async {
    final deviceId = await _getDeviceId();
    final deviceInfo = await _getDeviceInfo();
    
    final request = {
      'device_id': deviceId,
      'device_info': deviceInfo,
      'request_date': DateTime.now().toIso8601String(),
      'app_version': AppConstants.appVersion,
    };
    
    // Sign the request
    final signature = _generateSignature(jsonEncode(request));
    request['signature'] = signature;
    
    // Encode as base64 for easy sharing
    return base64Encode(utf8.encode(jsonEncode(request)));
  }
  
  /// Apply offline activation response
  Future<LicenseActivationResult> applyOfflineActivation(String response) async {
    try {
      final decoded = utf8.decode(base64Decode(response));
      final data = jsonDecode(decoded) as Map<String, dynamic>;
      
      // Verify signature
      final signature = data.remove('signature');
      final expectedSignature = _generateSignature(jsonEncode(data));
      
      if (signature != expectedSignature) {
        return LicenseActivationResult(
          success: false,
          message: 'Invalid activation response',
        );
      }
      
      // Verify device ID
      final deviceId = await _getDeviceId();
      if (data['device_id'] != deviceId) {
        return LicenseActivationResult(
          success: false,
          message: 'Activation response is for a different device',
        );
      }
      
      // Store license
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_licenseKey, _encodeLicense(data));
      
      _cachedLicense = null;
      
      return LicenseActivationResult(
        success: true,
        message: 'Offline activation successful',
        license: await getLicenseInfo(),
      );
    } catch (e) {
      return LicenseActivationResult(
        success: false,
        message: 'Offline activation failed: $e',
      );
    }
  }
  
  /// Check if a feature is available
  Future<bool> hasFeature(String feature) async {
    final license = await getLicenseInfo();
    
    // Trial has all features
    if (license.type == LicenseType.trial && 
        license.status == LicenseStatus.active) {
      return true;
    }
    
    // Check feature list
    return license.features?.contains(feature) ?? false;
  }
  
  /// Get device ID
  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_deviceIdKey);
    
    if (deviceId == null) {
      deviceId = await _generateDeviceId();
      await prefs.setString(_deviceIdKey, deviceId);
    }
    
    return deviceId;
  }
  
  /// Generate unique device ID
  Future<String> _generateDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    String identifier = '';
    
    try {
      if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        identifier = '${info.computerName}-${info.deviceId}';
      } else if (Platform.isLinux) {
        final info = await deviceInfo.linuxInfo;
        identifier = '${info.name}-${info.machineId ?? "linux"}';
      } else if (Platform.isMacOS) {
        final info = await deviceInfo.macOsInfo;
        identifier = '${info.computerName}-${info.systemGUID ?? "mac"}';
      }
    } catch (e) {
      identifier = 'device-${DateTime.now().millisecondsSinceEpoch}';
    }
    
    // Hash for privacy
    final bytes = utf8.encode(identifier + _secretSalt);
    return sha256.convert(bytes).toString().substring(0, 32);
  }
  
  /// Get device info for activation request
  Future<Map<String, dynamic>> _getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    
    try {
      if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        return {
          'platform': 'Windows',
          'computer_name': info.computerName,
          'product_name': info.productName,
        };
      } else if (Platform.isLinux) {
        final info = await deviceInfo.linuxInfo;
        return {
          'platform': 'Linux',
          'name': info.name,
          'version': info.version,
        };
      } else if (Platform.isMacOS) {
        final info = await deviceInfo.macOsInfo;
        return {
          'platform': 'macOS',
          'computer_name': info.computerName,
          'model': info.model,
        };
      }
    } catch (e) {
      // Ignore
    }
    
    return {'platform': Platform.operatingSystem};
  }
  
  /// Validate license key format
  bool _isValidKeyFormat(String key) {
    // Format: XXXX-XXXX-XXXX-XXXX (16 alphanumeric chars with dashes)
    final regex = RegExp(r'^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$');
    return regex.hasMatch(key.toUpperCase());
  }
  
  /// Decode license key to extract data
  Map<String, dynamic>? _decodeLicenseKey(String key) {
    try {
      final cleanKey = key.replaceAll('-', '').toUpperCase();
      
      // First 4 chars = type (LIFE = lifetime, SUBS = subscription)
      // Next 8 chars = encoded data
      // Last 4 chars = checksum
      
      final typeCode = cleanKey.substring(0, 4);
      final dataCode = cleanKey.substring(4, 12);
      final checksum = cleanKey.substring(12, 16);
      
      // Verify checksum
      final expectedChecksum = _generateChecksum(typeCode + dataCode);
      if (checksum != expectedChecksum) {
        return null;
      }
      
      // Decode type
      String licenseType;
      DateTime? expiryDate;
      
      switch (typeCode) {
        case 'LIFE':
          licenseType = 'lifetime';
          break;
        case 'SUB1':
          licenseType = 'subscription';
          expiryDate = DateTime.now().add(const Duration(days: 30));
          break;
        case 'SUB3':
          licenseType = 'subscription';
          expiryDate = DateTime.now().add(const Duration(days: 90));
          break;
        case 'SUBA':
          licenseType = 'subscription';
          expiryDate = DateTime.now().add(const Duration(days: 365));
          break;
        default:
          return null;
      }
      
      return {
        'type': licenseType,
        'expiry_date': expiryDate?.toIso8601String(),
        'features': _getAllFeatures(),
      };
    } catch (e) {
      return null;
    }
  }
  
  /// Generate checksum for license validation
  String _generateChecksum(String data) {
    final bytes = utf8.encode(data + _secretSalt);
    final hash = sha256.convert(bytes).toString();
    return hash.substring(0, 4).toUpperCase();
  }
  
  /// Generate signature for data
  String _generateSignature(String data) {
    final bytes = utf8.encode(data + _secretSalt);
    return sha256.convert(bytes).toString();
  }
  
  /// Encode license data for storage
  String _encodeLicense(Map<String, dynamic> data) {
    final json = jsonEncode(data);
    return base64Encode(utf8.encode(json));
  }
  
  /// Decode stored license data
  Map<String, dynamic> _decodeLicense(String encoded) {
    final decoded = utf8.decode(base64Decode(encoded));
    return jsonDecode(decoded) as Map<String, dynamic>;
  }
  
  /// Save license backup to file
  Future<void> _saveLicenseBackup(Map<String, dynamic> data) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/pharmatrack_license.dat');
      await file.writeAsString(_encodeLicense(data));
    } catch (e) {
      // Ignore backup errors
    }
  }
  
  /// Get all available features
  List<String> _getAllFeatures() {
    return [
      'attendance_tracking',
      'employee_management',
      'shift_management',
      'payroll_calculation',
      'reports_generation',
      'pdf_export',
      'excel_export',
      'multi_branch',
      'barcode_scanner',
      'qr_code_attendance',
      'fingerprint_support',
      'offline_mode',
      'cloud_sync',
      'audit_logging',
    ];
  }
  
  /// Generate a sample license key (for testing/demo)
  static String generateSampleKey(LicenseType type) {
    String typeCode;
    switch (type) {
      case LicenseType.lifetime:
        typeCode = 'LIFE';
        break;
      case LicenseType.subscription:
        typeCode = 'SUBA'; // Annual
        break;
      default:
        typeCode = 'LIFE';
    }
    
    // Generate random data portion
    final dataCode = 'TEST1234';
    
    // Generate checksum
    final bytes = utf8.encode(typeCode + dataCode + _secretSalt);
    final checksum = sha256.convert(bytes).toString().substring(0, 4).toUpperCase();
    
    return '${typeCode.substring(0, 4)}-${dataCode.substring(0, 4)}-${dataCode.substring(4, 8)}-$checksum';
  }
}

/// License types
enum LicenseType {
  trial,
  lifetime,
  subscription,
  expired,
}

extension LicenseTypeExtension on LicenseType {
  String get value {
    switch (this) {
      case LicenseType.trial:
        return 'trial';
      case LicenseType.lifetime:
        return 'lifetime';
      case LicenseType.subscription:
        return 'subscription';
      case LicenseType.expired:
        return 'expired';
    }
  }
  
  String get displayName {
    switch (this) {
      case LicenseType.trial:
        return 'Trial';
      case LicenseType.lifetime:
        return 'Lifetime';
      case LicenseType.subscription:
        return 'Subscription';
      case LicenseType.expired:
        return 'Expired';
    }
  }
}

/// License status
enum LicenseStatus {
  active,
  expired,
  invalid,
}

/// License information
class LicenseInfo {
  final LicenseType type;
  final LicenseStatus status;
  final String message;
  final String deviceId;
  final DateTime installDate;
  final DateTime? expiryDate;
  final DateTime? activationDate;
  final int? daysRemaining;
  final String? licenseKey;
  final String? customerName;
  final String? pharmacyName;
  final List<String>? features;
  
  LicenseInfo({
    required this.type,
    required this.status,
    required this.message,
    required this.deviceId,
    required this.installDate,
    this.expiryDate,
    this.activationDate,
    this.daysRemaining,
    this.licenseKey,
    this.customerName,
    this.pharmacyName,
    this.features,
  });
  
  bool get isActive => status == LicenseStatus.active;
  bool get isTrial => type == LicenseType.trial;
  bool get isLifetime => type == LicenseType.lifetime;
  bool get isExpired => status == LicenseStatus.expired;
}

/// License activation result
class LicenseActivationResult {
  final bool success;
  final String message;
  final LicenseInfo? license;
  
  LicenseActivationResult({
    required this.success,
    required this.message,
    this.license,
  });
}
