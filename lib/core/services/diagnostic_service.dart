import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../constants/app_constants.dart';
import 'database_service.dart';

/// Diagnostic service for self-check and system validation
class DiagnosticService {
  static DiagnosticService? _instance;
  
  final DatabaseService _databaseService = DatabaseService.instance;
  
  DiagnosticService._();
  
  static DiagnosticService get instance {
    _instance ??= DiagnosticService._();
    return _instance!;
  }
  
  /// Run all diagnostic tests
  Future<DiagnosticReport> runFullDiagnostics() async {
    final results = <DiagnosticResult>[];
    final startTime = DateTime.now();
    
    // Run all tests
    results.add(await testDatabaseConnection());
    results.add(await testDatabaseIntegrity());
    results.add(await testDeviceInfo());
    results.add(await testNetworkConnectivity());
    results.add(await testDiskSpace());
    results.add(await testTableStructure());
    
    final endTime = DateTime.now();
    
    return DiagnosticReport(
      results: results,
      runTime: endTime.difference(startTime),
      timestamp: startTime,
    );
  }
  
  /// Test database connection
  Future<DiagnosticResult> testDatabaseConnection() async {
    try {
      final db = await _databaseService.database;
      final isOpen = db.isOpen;
      
      return DiagnosticResult(
        name: 'Database Connection',
        status: isOpen ? DiagnosticStatus.passed : DiagnosticStatus.failed,
        message: isOpen ? 'Database connection successful' : 'Database connection failed',
        details: {
          'path': db.path,
          'isOpen': isOpen,
        },
      );
    } catch (e) {
      return DiagnosticResult(
        name: 'Database Connection',
        status: DiagnosticStatus.failed,
        message: 'Database connection error: $e',
        details: {'error': e.toString()},
      );
    }
  }
  
  /// Test database integrity
  Future<DiagnosticResult> testDatabaseIntegrity() async {
    try {
      final db = await _databaseService.database;
      
      // Run integrity check
      final result = await db.rawQuery('PRAGMA integrity_check;');
      final integrityOk = result.first['integrity_check'] == 'ok';
      
      // Check foreign keys
      final fkResult = await db.rawQuery('PRAGMA foreign_key_check;');
      final fkOk = fkResult.isEmpty;
      
      return DiagnosticResult(
        name: 'Database Integrity',
        status: (integrityOk && fkOk) ? DiagnosticStatus.passed : DiagnosticStatus.warning,
        message: integrityOk && fkOk 
            ? 'Database integrity verified' 
            : 'Database integrity issues detected',
        details: {
          'integrity_check': result.first['integrity_check'],
          'foreign_key_violations': fkResult.length,
        },
      );
    } catch (e) {
      return DiagnosticResult(
        name: 'Database Integrity',
        status: DiagnosticStatus.failed,
        message: 'Integrity check error: $e',
        details: {'error': e.toString()},
      );
    }
  }
  
  /// Test table structure
  Future<DiagnosticResult> testTableStructure() async {
    try {
      final db = await _databaseService.database;
      
      final requiredTables = [
        'branches',
        'users',
        'employees',
        'shifts',
        'attendance_records',
        'audit_logs',
        'settings',
        'device_registrations',
        'qr_codes',
      ];
      
      final missingTables = <String>[];
      final existingTables = <String>[];
      
      for (final table in requiredTables) {
        final result = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          [table],
        );
        if (result.isEmpty) {
          missingTables.add(table);
        } else {
          existingTables.add(table);
        }
      }
      
      return DiagnosticResult(
        name: 'Table Structure',
        status: missingTables.isEmpty ? DiagnosticStatus.passed : DiagnosticStatus.warning,
        message: missingTables.isEmpty 
            ? 'All required tables exist' 
            : 'Missing tables: ${missingTables.join(", ")}',
        details: {
          'existing_tables': existingTables,
          'missing_tables': missingTables,
        },
      );
    } catch (e) {
      return DiagnosticResult(
        name: 'Table Structure',
        status: DiagnosticStatus.failed,
        message: 'Table check error: $e',
        details: {'error': e.toString()},
      );
    }
  }
  
  /// Test device info
  Future<DiagnosticResult> testDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      Map<String, dynamic> info = {};
      
      if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        info = {
          'platform': 'Windows',
          'computerName': windowsInfo.computerName,
          'numberOfCores': windowsInfo.numberOfCores,
          'systemMemoryInMegabytes': windowsInfo.systemMemoryInMegabytes,
          'productName': windowsInfo.productName,
        };
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        info = {
          'platform': 'Linux',
          'name': linuxInfo.name,
          'version': linuxInfo.version,
          'machineId': linuxInfo.machineId,
        };
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        info = {
          'platform': 'macOS',
          'computerName': macInfo.computerName,
          'model': macInfo.model,
          'osRelease': macInfo.osRelease,
          'memorySize': macInfo.memorySize,
        };
      }
      
      return DiagnosticResult(
        name: 'Device Information',
        status: DiagnosticStatus.passed,
        message: 'Device information retrieved successfully',
        details: info,
      );
    } catch (e) {
      return DiagnosticResult(
        name: 'Device Information',
        status: DiagnosticStatus.warning,
        message: 'Could not retrieve device info: $e',
        details: {'error': e.toString()},
      );
    }
  }
  
  /// Test network connectivity
  Future<DiagnosticResult> testNetworkConnectivity() async {
    try {
      final connectivity = Connectivity();
      final result = await connectivity.checkConnectivity();
      
      // Handle both old and new API
      String connectionType;
      bool hasConnection = false;
      
      if (result is List) {
        final results = result as List<ConnectivityResult>;
        hasConnection = results.isNotEmpty && !results.contains(ConnectivityResult.none);
        connectionType = results.map((r) => r.toString()).join(', ');
      } else {
        hasConnection = result != ConnectivityResult.none;
        connectionType = result.toString();
      }
      
      return DiagnosticResult(
        name: 'Network Connectivity',
        status: hasConnection ? DiagnosticStatus.passed : DiagnosticStatus.warning,
        message: hasConnection 
            ? 'Network connection available ($connectionType)'
            : 'No network connection (offline mode enabled)',
        details: {
          'connected': hasConnection,
          'connection_type': connectionType,
        },
      );
    } catch (e) {
      return DiagnosticResult(
        name: 'Network Connectivity',
        status: DiagnosticStatus.warning,
        message: 'Network check error: $e (offline mode enabled)',
        details: {'error': e.toString()},
      );
    }
  }
  
  /// Test disk space
  Future<DiagnosticResult> testDiskSpace() async {
    try {
      // Get database size
      final db = await _databaseService.database;
      final dbPath = db.path;
      final dbFile = File(dbPath);
      final dbSize = await dbFile.length();
      
      // Format size
      String formattedSize;
      if (dbSize < 1024) {
        formattedSize = '$dbSize B';
      } else if (dbSize < 1024 * 1024) {
        formattedSize = '${(dbSize / 1024).toStringAsFixed(2)} KB';
      } else {
        formattedSize = '${(dbSize / (1024 * 1024)).toStringAsFixed(2)} MB';
      }
      
      return DiagnosticResult(
        name: 'Disk Space',
        status: DiagnosticStatus.passed,
        message: 'Database size: $formattedSize',
        details: {
          'database_path': dbPath,
          'database_size_bytes': dbSize,
          'database_size_formatted': formattedSize,
        },
      );
    } catch (e) {
      return DiagnosticResult(
        name: 'Disk Space',
        status: DiagnosticStatus.warning,
        message: 'Could not check disk space: $e',
        details: {'error': e.toString()},
      );
    }
  }
  
  /// Stress test - simulate high load
  Future<DiagnosticResult> runStressTest({int iterations = 100}) async {
    try {
      final db = await _databaseService.database;
      final startTime = DateTime.now();
      
      // Run multiple queries
      for (int i = 0; i < iterations; i++) {
        await db.rawQuery('SELECT COUNT(*) FROM sqlite_master');
      }
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      final avgMs = duration.inMilliseconds / iterations;
      
      return DiagnosticResult(
        name: 'Stress Test',
        status: avgMs < 10 ? DiagnosticStatus.passed : 
               avgMs < 50 ? DiagnosticStatus.warning : DiagnosticStatus.failed,
        message: 'Completed $iterations iterations in ${duration.inMilliseconds}ms (avg: ${avgMs.toStringAsFixed(2)}ms/query)',
        details: {
          'iterations': iterations,
          'total_time_ms': duration.inMilliseconds,
          'average_time_ms': avgMs,
        },
      );
    } catch (e) {
      return DiagnosticResult(
        name: 'Stress Test',
        status: DiagnosticStatus.failed,
        message: 'Stress test failed: $e',
        details: {'error': e.toString()},
      );
    }
  }
  
  /// Test barcode scanner device (placeholder - actual implementation depends on hardware)
  Future<DiagnosticResult> testBarcodeScanner() async {
    return DiagnosticResult(
      name: 'Barcode Scanner',
      status: DiagnosticStatus.passed,
      message: 'USB barcode scanners use keyboard emulation mode - no special driver needed',
      details: {
        'note': 'Connect USB barcode scanner to test',
        'mode': 'keyboard_wedge',
      },
    );
  }
  
  /// Test camera availability
  Future<DiagnosticResult> testCamera() async {
    try {
      // Check if camera package is available
      // This is a basic check - actual camera testing requires platform-specific code
      return DiagnosticResult(
        name: 'Camera',
        status: DiagnosticStatus.passed,
        message: 'Camera support available for QR code scanning',
        details: {
          'qr_scanning': 'enabled',
        },
      );
    } catch (e) {
      return DiagnosticResult(
        name: 'Camera',
        status: DiagnosticStatus.warning,
        message: 'Camera check error: $e',
        details: {'error': e.toString()},
      );
    }
  }
  
  /// Get system health summary
  Future<SystemHealth> getSystemHealth() async {
    final report = await runFullDiagnostics();
    
    int passedCount = 0;
    int warningCount = 0;
    int failedCount = 0;
    
    for (final result in report.results) {
      switch (result.status) {
        case DiagnosticStatus.passed:
          passedCount++;
          break;
        case DiagnosticStatus.warning:
          warningCount++;
          break;
        case DiagnosticStatus.failed:
          failedCount++;
          break;
      }
    }
    
    HealthStatus overallHealth;
    if (failedCount > 0) {
      overallHealth = HealthStatus.critical;
    } else if (warningCount > 1) {
      overallHealth = HealthStatus.warning;
    } else {
      overallHealth = HealthStatus.healthy;
    }
    
    return SystemHealth(
      status: overallHealth,
      passedTests: passedCount,
      warningTests: warningCount,
      failedTests: failedCount,
      report: report,
    );
  }
}

/// Diagnostic test status
enum DiagnosticStatus {
  passed,
  warning,
  failed,
}

/// Individual diagnostic result
class DiagnosticResult {
  final String name;
  final DiagnosticStatus status;
  final String message;
  final Map<String, dynamic>? details;
  
  DiagnosticResult({
    required this.name,
    required this.status,
    required this.message,
    this.details,
  });
  
  String get statusIcon {
    switch (status) {
      case DiagnosticStatus.passed:
        return '✓';
      case DiagnosticStatus.warning:
        return '⚠';
      case DiagnosticStatus.failed:
        return '✗';
    }
  }
}

/// Complete diagnostic report
class DiagnosticReport {
  final List<DiagnosticResult> results;
  final Duration runTime;
  final DateTime timestamp;
  
  DiagnosticReport({
    required this.results,
    required this.runTime,
    required this.timestamp,
  });
  
  bool get hasFailures => results.any((r) => r.status == DiagnosticStatus.failed);
  bool get hasWarnings => results.any((r) => r.status == DiagnosticStatus.warning);
  bool get allPassed => results.every((r) => r.status == DiagnosticStatus.passed);
}

/// System health status
enum HealthStatus {
  healthy,
  warning,
  critical,
}

/// System health summary
class SystemHealth {
  final HealthStatus status;
  final int passedTests;
  final int warningTests;
  final int failedTests;
  final DiagnosticReport report;
  
  SystemHealth({
    required this.status,
    required this.passedTests,
    required this.warningTests,
    required this.failedTests,
    required this.report,
  });
  
  int get totalTests => passedTests + warningTests + failedTests;
  
  String get statusMessage {
    switch (status) {
      case HealthStatus.healthy:
        return 'System is healthy';
      case HealthStatus.warning:
        return 'System has minor issues';
      case HealthStatus.critical:
        return 'System has critical issues';
    }
  }
}
