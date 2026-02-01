import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import '../constants/app_constants.dart';
import '../../data/repositories/repositories.dart';
import '../../data/models/audit_log_model.dart';
import 'database_service.dart';
import 'auth_service.dart';

/// Service for cloud synchronization and backup
class SyncService {
  static SyncService? _instance;
  
  final DatabaseService _databaseService = DatabaseService.instance;
  final AuthService _authService = AuthService.instance;
  final AuditRepository _auditRepository = AuditRepository.instance;
  final Uuid _uuid = const Uuid();
  
  SyncStatus _status = SyncStatus.idle;
  DateTime? _lastSyncTime;
  String? _cloudEndpoint;
  String? _apiKey;
  bool _autoSync = false;
  
  SyncService._();
  
  static SyncService get instance {
    _instance ??= SyncService._();
    return _instance!;
  }
  
  /// Current sync status
  SyncStatus get status => _status;
  
  /// Last sync time
  DateTime? get lastSyncTime => _lastSyncTime;
  
  /// Is auto sync enabled
  bool get isAutoSyncEnabled => _autoSync;
  
  /// Check if network is available
  Future<bool> isNetworkAvailable() async {
    final result = await Connectivity().checkConnectivity();
    // In older connectivity_plus versions, returns single ConnectivityResult
    // In newer versions (6.0.0+), returns List<ConnectivityResult>
    if (result is List) {
      final results = result as List<ConnectivityResult>;
      return results.isNotEmpty && !results.contains(ConnectivityResult.none);
    }
    // Fallback for older versions
    return result != ConnectivityResult.none;
  }
  
  /// Configure cloud endpoint
  void configure({
    required String endpoint,
    required String apiKey,
    bool autoSync = false,
  }) {
    _cloudEndpoint = endpoint;
    _apiKey = apiKey;
    _autoSync = autoSync;
    
    if (_autoSync) {
      _startAutoSync();
    }
  }
  
  /// Start automatic sync
  void _startAutoSync() {
    // Listen for connectivity changes
    Connectivity().onConnectivityChanged.listen((result) async {
      // Handle both old API (single result) and new API (list)
      bool hasConnection = false;
      if (result is List) {
        final results = result as List<ConnectivityResult>;
        hasConnection = results.isNotEmpty && !results.contains(ConnectivityResult.none);
      } else {
        hasConnection = result != ConnectivityResult.none;
      }
      if (_autoSync && hasConnection) {
        await sync();
      }
    });
  }
  
  /// Perform full sync
  Future<SyncResult> sync() async {
    if (_status == SyncStatus.syncing) {
      return SyncResult(
        success: false,
        message: 'Sync already in progress',
      );
    }
    
    if (!await isNetworkAvailable()) {
      return SyncResult(
        success: false,
        message: 'No network connection',
      );
    }
    
    _status = SyncStatus.syncing;
    
    try {
      final branchId = _authService.currentBranch?.id;
      if (branchId == null) {
        _status = SyncStatus.error;
        return SyncResult(
          success: false,
          message: 'No branch selected',
        );
      }
      
      // Get pending changes
      final pendingChanges = await _getPendingChanges(branchId);
      
      // Upload changes
      if (pendingChanges.isNotEmpty) {
        await _uploadChanges(branchId, pendingChanges);
      }
      
      // Download remote changes
      final remoteChanges = await _downloadChanges(branchId);
      
      // Apply remote changes
      if (remoteChanges.isNotEmpty) {
        await _applyChanges(remoteChanges);
      }
      
      _lastSyncTime = DateTime.now();
      _status = SyncStatus.idle;
      
      // Log sync
      await _auditRepository.log(
        id: _uuid.v4(),
        branchId: branchId,
        userId: _authService.currentUser?.id,
        action: AuditAction.sync,
        entityType: AuditEntityType.branch,
        entityId: branchId,
        newValues: {
          'uploaded': pendingChanges.length,
          'downloaded': remoteChanges.length,
        },
      );
      
      return SyncResult(
        success: true,
        message: 'Sync completed successfully',
        uploadedCount: pendingChanges.length,
        downloadedCount: remoteChanges.length,
      );
    } catch (e) {
      _status = SyncStatus.error;
      return SyncResult(
        success: false,
        message: 'Sync failed: $e',
      );
    }
  }
  
  /// Get pending local changes
  Future<List<Map<String, dynamic>>> _getPendingChanges(String branchId) async {
    final db = await _databaseService.database;
    
    // Get records that need syncing (synced_at is null or updated_at > synced_at)
    final tables = [
      'employees',
      'shifts',
      'attendance_records',
      'users',
    ];
    
    final changes = <Map<String, dynamic>>[];
    
    for (final table in tables) {
      final results = await db.query(
        table,
        where: 'branch_id = ? AND (synced_at IS NULL OR updated_at > synced_at)',
        whereArgs: [branchId],
      );
      
      for (final row in results) {
        changes.add({
          'table': table,
          'action': row['synced_at'] == null ? 'create' : 'update',
          'data': row,
        });
      }
    }
    
    return changes;
  }
  
  /// Upload changes to cloud
  Future<void> _uploadChanges(
    String branchId,
    List<Map<String, dynamic>> changes,
  ) async {
    if (_cloudEndpoint == null) return;
    
    final response = await http.post(
      Uri.parse('$_cloudEndpoint/sync/upload'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'branch_id': branchId,
        'changes': changes,
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to upload changes: ${response.body}');
    }
    
    // Mark records as synced
    final db = await _databaseService.database;
    for (final change in changes) {
      final table = change['table'] as String;
      final data = change['data'] as Map<String, dynamic>;
      
      await db.update(
        table,
        {'synced_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [data['id']],
      );
    }
  }
  
  /// Download changes from cloud
  Future<List<Map<String, dynamic>>> _downloadChanges(String branchId) async {
    if (_cloudEndpoint == null) return [];
    
    final lastSync = _lastSyncTime?.toIso8601String() ?? '1970-01-01';
    
    final response = await http.get(
      Uri.parse('$_cloudEndpoint/sync/download?branch_id=$branchId&since=$lastSync'),
      headers: {
        'Authorization': 'Bearer $_apiKey',
      },
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to download changes: ${response.body}');
    }
    
    final data = jsonDecode(response.body);
    return List<Map<String, dynamic>>.from(data['changes'] ?? []);
  }
  
  /// Apply downloaded changes
  Future<void> _applyChanges(List<Map<String, dynamic>> changes) async {
    final db = await _databaseService.database;
    
    for (final change in changes) {
      final table = change['table'] as String;
      final action = change['action'] as String;
      final data = change['data'] as Map<String, dynamic>;
      
      switch (action) {
        case 'create':
        case 'update':
          await db.insert(
            table,
            {
              ...data,
              'synced_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          break;
        case 'delete':
          await db.delete(
            table,
            where: 'id = ?',
            whereArgs: [data['id']],
          );
          break;
      }
    }
  }
  
  /// Create local backup
  Future<String> createBackup() async {
    final db = await _databaseService.database;
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final backupPath = '${directory.path}/backups/backup_$timestamp.db';
    
    // Create backups directory if needed
    final backupDir = Directory('${directory.path}/backups');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    
    // Copy database file
    final dbPath = db.path;
    await File(dbPath).copy(backupPath);
    
    return backupPath;
  }
  
  /// Restore from backup
  Future<void> restoreBackup(String backupPath) async {
    final db = await _databaseService.database;
    final dbPath = db.path;
    
    // Close current database
    await db.close();
    
    // Replace with backup
    await File(backupPath).copy(dbPath);
    
    // Reinitialize database
    await _databaseService.database;
  }
  
  /// Get list of available backups
  Future<List<BackupInfo>> getBackups() async {
    final directory = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${directory.path}/backups');
    
    if (!await backupDir.exists()) {
      return [];
    }
    
    final backups = <BackupInfo>[];
    
    await for (final entity in backupDir.list()) {
      if (entity is File && entity.path.endsWith('.db')) {
        final stat = await entity.stat();
        backups.add(BackupInfo(
          path: entity.path,
          name: entity.path.split('/').last,
          createdAt: stat.modified,
          size: stat.size,
        ));
      }
    }
    
    backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return backups;
  }
  
  /// Delete a backup
  Future<void> deleteBackup(String backupPath) async {
    final file = File(backupPath);
    if (await file.exists()) {
      await file.delete();
    }
  }
  
  /// Export database to JSON
  Future<String> exportToJson() async {
    final db = await _databaseService.database;
    final branchId = _authService.currentBranch?.id;
    
    final tables = [
      'branches',
      'users',
      'employees',
      'shifts',
      'attendance_records',
      'payroll_records',
      'settings',
    ];
    
    final exportData = <String, dynamic>{
      'version': AppConstants.appVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'branch_id': branchId,
    };
    
    for (final table in tables) {
      try {
        final results = await db.query(table);
        exportData[table] = results;
      } catch (e) {
        // Table might not exist
      }
    }
    
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final exportPath = '${directory.path}/exports/export_$timestamp.json';
    
    final exportDir = Directory('${directory.path}/exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    
    final file = File(exportPath);
    await file.writeAsString(jsonEncode(exportData));
    
    return exportPath;
  }
}

/// Sync status enum
enum SyncStatus {
  idle,
  syncing,
  error,
}

/// Sync result
class SyncResult {
  final bool success;
  final String message;
  final int uploadedCount;
  final int downloadedCount;
  
  SyncResult({
    required this.success,
    required this.message,
    this.uploadedCount = 0,
    this.downloadedCount = 0,
  });
}

/// Backup info
class BackupInfo {
  final String path;
  final String name;
  final DateTime createdAt;
  final int size;
  
  BackupInfo({
    required this.path,
    required this.name,
    required this.createdAt,
    required this.size,
  });
  
  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
