import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../../data/repositories/repositories.dart';
import '../constants/app_constants.dart';
import 'device_service.dart';
import 'database_service.dart';
import 'logging_service.dart';

/// Service for QR code generation and validation (anti-fraud)
/// 
/// SINGLE-BRANCH ARCHITECTURE: All operations use hardcoded branch_id = '1'
class QrService {
  static QrService? _instance;
  
  final DeviceService _deviceService = DeviceService.instance;
  final Uuid _uuid = const Uuid();
  final Random _random = Random.secure();
  
  // SINGLE-BRANCH: Hardcoded branch ID
  static const String _branchId = '1';
  static const String _branchName = 'Main Branch';
  
  String? _currentToken;
  DateTime? _tokenGeneratedAt;
  
  QrService._();
  
  static QrService get instance {
    _instance ??= QrService._();
    return _instance!;
  }
  
  /// Generate a new QR token
  Future<String> generateToken() async {
    final deviceId = await _deviceService.getDeviceId();
    final timestamp = DateTime.now();
    
    // Create token data
    final tokenData = {
      'branch_id': _branchId,
      'device_id': deviceId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'nonce': _generateNonce(),
    };
    
    // Create signature
    final dataString = jsonEncode(tokenData);
    final signature = _createSignature(dataString);
    
    final token = base64Encode(utf8.encode(jsonEncode({
      ...tokenData,
      'signature': signature,
    })));
    
    // Store in database
    final db = await DatabaseService.instance.database;
    final expiresAt = timestamp.add(Duration(seconds: AppConstants.qrRefreshSeconds));
    
    await db.insert('qr_codes', {
      'id': _uuid.v4(),
      'branch_id': _branchId,
      'token': token,
      'generated_at': timestamp.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'is_used': 0,
    });
    
    _currentToken = token;
    _tokenGeneratedAt = timestamp;
    
    return token;
  }
  
  /// Generate nonce for token
  String _generateNonce() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Encode(bytes);
  }
  
  /// Create signature for token data
  String _createSignature(String data) {
    // In production, use a secret key stored securely
    const secretKey = 'pharmacy_attendance_secret_key_2024';
    final key = utf8.encode(secretKey);
    final bytes = utf8.encode(data);
    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(bytes);
    return digest.toString();
  }
  
  /// Validate a QR token
  Future<QrValidationResult> validateToken(String token) async {
    try {
      // Decode token
      final decodedBytes = base64Decode(token);
      final decodedString = utf8.decode(decodedBytes);
      final tokenData = jsonDecode(decodedString) as Map<String, dynamic>;
      
      final branchId = tokenData['branch_id'] as String;
      final deviceId = tokenData['device_id'] as String;
      final timestamp = tokenData['timestamp'] as int;
      final signature = tokenData['signature'] as String;
      
      // Verify signature
      final dataForSignature = {
        'branch_id': branchId,
        'device_id': deviceId,
        'timestamp': timestamp,
        'nonce': tokenData['nonce'],
      };
      final expectedSignature = _createSignature(jsonEncode(dataForSignature));
      
      if (signature != expectedSignature) {
        return QrValidationResult(
          isValid: false,
          error: 'Invalid QR code signature',
        );
      }
      
      // Check if token is from current branch
      if (branchId != _branchId) {
        return QrValidationResult(
          isValid: false,
          error: 'QR code is for a different branch',
        );
      }
      
      // Check expiration
      final tokenTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final now = DateTime.now();
      final age = now.difference(tokenTime).inSeconds;
      
      if (age > AppConstants.qrRefreshSeconds) {
        return QrValidationResult(
          isValid: false,
          error: 'QR code has expired',
        );
      }
      
      // Check if already used
      final db = await DatabaseService.instance.database;
      final results = await db.query(
        'qr_codes',
        where: 'token = ? AND is_used = 1',
        whereArgs: [token],
        limit: 1,
      );
      
      if (results.isNotEmpty) {
        return QrValidationResult(
          isValid: false,
          error: 'QR code has already been used',
        );
      }
      
      return QrValidationResult(
        isValid: true,
        branchId: branchId,
        deviceId: deviceId,
        token: token,
      );
    } catch (e, stack) {
      LoggingService.instance.error('QR', 'Failed to validate QR token', e, stack);
      return QrValidationResult(
        isValid: false,
        error: 'Invalid QR code format',
      );
    }
  }
  
  /// Mark token as used
  Future<void> markTokenUsed(String token, String employeeId) async {
    final db = await DatabaseService.instance.database;
    await db.update(
      'qr_codes',
      {
        'is_used': 1,
        'used_by': employeeId,
        'used_at': DateTime.now().toIso8601String(),
      },
      where: 'token = ?',
      whereArgs: [token],
    );
  }
  
  /// Get current token (if still valid)
  String? get currentToken {
    if (_currentToken == null || _tokenGeneratedAt == null) {
      return null;
    }
    
    final age = DateTime.now().difference(_tokenGeneratedAt!).inSeconds;
    if (age > AppConstants.qrRefreshSeconds) {
      _currentToken = null;
      _tokenGeneratedAt = null;
      return null;
    }
    
    return _currentToken;
  }
  
  /// Get remaining seconds for current token
  int? get tokenRemainingSeconds {
    if (_tokenGeneratedAt == null) return null;
    
    final age = DateTime.now().difference(_tokenGeneratedAt!).inSeconds;
    final remaining = AppConstants.qrRefreshSeconds - age;
    
    return remaining > 0 ? remaining : null;
  }
  
  /// Clean up expired tokens
  Future<int> cleanupExpiredTokens() async {
    final db = await DatabaseService.instance.database;
    return await db.delete(
      'qr_codes',
      where: 'expires_at < ?',
      whereArgs: [DateTime.now().toIso8601String()],
    );
  }
  
  /// Generate QR data for display (includes all needed info)
  Future<Map<String, dynamic>> generateQrDisplayData() async {
    final token = await generateToken();
    
    return {
      'token': token,
      'generated_at': _tokenGeneratedAt?.toIso8601String(),
      'expires_in_seconds': AppConstants.qrRefreshSeconds,
      'branch_name': _branchName,
    };
  }
}

/// Result of QR token validation
class QrValidationResult {
  final bool isValid;
  final String? error;
  final String? branchId;
  final String? deviceId;
  final String? token;
  
  QrValidationResult({
    required this.isValid,
    this.error,
    this.branchId,
    this.deviceId,
    this.token,
  });
}
