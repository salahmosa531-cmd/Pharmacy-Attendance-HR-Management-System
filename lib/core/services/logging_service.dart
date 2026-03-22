import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Centralized logging service for runtime exceptions, navigation, and debugging
/// 
/// Logs are stored locally in the app's documents directory under logs/
/// This allows debugging issues even when the app is running offline
class LoggingService {
  static LoggingService? _instance;
  
  final List<LogEntry> _inMemoryLogs = [];
  static const int _maxInMemoryLogs = 500;
  
  File? _logFile;
  bool _initialized = false;
  
  LoggingService._();
  
  static LoggingService get instance {
    _instance ??= LoggingService._();
    return _instance!;
  }
  
  /// Initialize the logging service
  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final logDir = Directory(p.join(appDocDir.path, 'PharmacyAttendance', 'logs'));
      
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      
      // Create daily log file
      final today = DateTime.now();
      final fileName = 'app_${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}.log';
      _logFile = File(p.join(logDir.path, fileName));
      
      _initialized = true;
      log(LogLevel.info, 'LoggingService', 'Logging service initialized');
    } catch (e) {
      // Fallback: only use in-memory logging
      _initialized = true;
    }
  }
  
  /// Log a message
  void log(LogLevel level, String source, String message, [Object? error, StackTrace? stackTrace]) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      source: source,
      message: message,
      error: error?.toString(),
      stackTrace: stackTrace?.toString(),
    );
    
    // Add to in-memory buffer
    _inMemoryLogs.add(entry);
    if (_inMemoryLogs.length > _maxInMemoryLogs) {
      _inMemoryLogs.removeAt(0);
    }
    
    // Write to file
    _writeToFile(entry);
    
    // Print to console in debug mode
    // ignore: avoid_print
    print('[${entry.level.name.toUpperCase()}] ${entry.source}: ${entry.message}');
    if (error != null) {
      // ignore: avoid_print
      print('  Error: $error');
    }
  }
  
  /// Log an info message
  void info(String source, String message) {
    log(LogLevel.info, source, message);
  }
  
  /// Log a debug message
  void debug(String source, String message, [Object? error, StackTrace? stackTrace]) {
    log(LogLevel.debug, source, message, error, stackTrace);
  }
  
  /// Log a warning message
  void warning(String source, String message, [Object? error]) {
    log(LogLevel.warning, source, message, error);
  }
  
  /// Log an error message
  void error(String source, String message, [Object? error, StackTrace? stackTrace]) {
    log(LogLevel.error, source, message, error, stackTrace);
  }
  
  /// Log navigation event
  void navigation(String from, String to, [String? reason]) {
    final message = reason != null 
        ? 'Navigation: $from -> $to (reason: $reason)'
        : 'Navigation: $from -> $to';
    log(LogLevel.info, 'Navigation', message);
  }
  
  /// Log navigation failure
  void navigationError(String route, Object error, [StackTrace? stackTrace]) {
    log(LogLevel.error, 'Navigation', 'Failed to navigate to $route', error, stackTrace);
  }
  
  /// Log database operation
  void database(String operation, [String? details]) {
    final message = details != null ? '$operation: $details' : operation;
    log(LogLevel.info, 'Database', message);
  }
  
  /// Log authentication event
  void auth(String event, [String? userId]) {
    final message = userId != null ? '$event (user: $userId)' : event;
    log(LogLevel.info, 'Auth', message);
  }
  
  /// Log attendance action
  void attendance(String action, String employeeId, [String? details]) {
    final message = details != null 
        ? '$action for employee $employeeId: $details'
        : '$action for employee $employeeId';
    log(LogLevel.info, 'Attendance', message);
  }
  /// جديد 
  /// Log an audit event
  void audit(String module, String action, String messageText, {Map<String, dynamic>? details}) {
    final String detailsString = details != null ? ' | Details: $details' : '';
    final String fullMessage = 'Audit: [$module] $action - $messageText$detailsString';
    
    // تسجيل في الملف النصي والكونسول
    log(LogLevel.info, 'Audit', fullMessage);
  }

  /// Write log entry to file
  Future<void> _writeToFile(LogEntry entry) async {
    if (_logFile == null) return;
    
    try {
      final line = entry.toLogLine();
      await _logFile!.writeAsString('$line\n', mode: FileMode.append);
    } catch (e) {
      // Ignore file write errors to prevent infinite loops
    }
  }
  
  /// Get recent logs
  List<LogEntry> getRecentLogs({int count = 50, LogLevel? minLevel}) {
    var logs = _inMemoryLogs.reversed.toList();
    
    if (minLevel != null) {
      logs = logs.where((l) => l.level.index >= minLevel.index).toList();
    }
    
    return logs.take(count).toList();
  }
  
  /// Get errors only
  List<LogEntry> getErrors({int count = 20}) {
    return getRecentLogs(count: count, minLevel: LogLevel.error);
  }
  
  /// Export logs to string
  String exportLogs({LogLevel? minLevel}) {
    final logs = _inMemoryLogs.where((l) => 
      minLevel == null || l.level.index >= minLevel.index
    ).toList();
    
    return logs.map((l) => l.toLogLine()).join('\n');
  }
  
  /// Clear in-memory logs
  void clearMemoryLogs() {
    _inMemoryLogs.clear();
  }
  
  /// Get log file path
  String? get logFilePath => _logFile?.path;
  
  /// Clean up old log files (keep last 7 days)
  Future<void> cleanupOldLogs({int keepDays = 7}) async {
    try {
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final logDir = Directory(p.join(appDocDir.path, 'PharmacyAttendance', 'logs'));
      
      if (!await logDir.exists()) return;
      
      final cutoffDate = DateTime.now().subtract(Duration(days: keepDays));
      
      await for (final entity in logDir.list()) {
        if (entity is File && entity.path.endsWith('.log')) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoffDate)) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      // Ignore cleanup errors
    }
  }
}

/// Log levels
enum LogLevel {
  debug,
  info,
  warning,
  error,
  fatal,
}

/// Log entry
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String source;
  final String message;
  final String? error;
  final String? stackTrace;
  
  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
    this.error,
    this.stackTrace,
  });
  
  String toLogLine() {
    final ts = timestamp.toIso8601String();
    final lvl = level.name.toUpperCase().padRight(7);
    var line = '[$ts] $lvl $source: $message';
    if (error != null) {
      line += '\n  Error: $error';
    }
    if (stackTrace != null) {
      line += '\n  Stack: ${stackTrace!.split('\n').first}';
    }
    return line;
  }
  
  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
      'source': source,
      'message': message,
      'error': error,
      'stackTrace': stackTrace,
    };
  }
}
