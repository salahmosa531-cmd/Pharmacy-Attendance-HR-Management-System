import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'core/services/database_service.dart';
import 'core/services/settings_service.dart';
import 'core/services/logging_service.dart';
import 'core/services/auth_service.dart';
import 'app.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize logging service first for error tracking
  await LoggingService.instance.initialize();
  LoggingService.instance.info('App', 'Application starting...');
  
  // Set up Flutter error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    LoggingService.instance.error(
      'Flutter', 
      'Flutter error caught',
      details.exception,
      details.stack,
    );
    // In debug mode, still print to console
    if (kDebugMode) {
      FlutterError.presentError(details);
    }
  };
  
  // Initialize window manager for desktop
  await windowManager.ensureInitialized();
  LoggingService.instance.info('App', 'Window manager initialized');
  
  // Initialize database FFI for desktop platforms
  DatabaseService.initializeFfi();
  LoggingService.instance.info('App', 'Database FFI initialized');
  
  // Initialize database (this also creates default branch with id='1')
  await DatabaseService.instance.database;
  LoggingService.instance.database('Database opened');
  
  // Log migration info if any
  final migrationLog = DatabaseService.migrationLog;
  if (migrationLog.isNotEmpty) {
    for (final log in migrationLog) {
      LoggingService.instance.info('Migration', log);
    }
  }
  
  // Clean up old log files
  await LoggingService.instance.cleanupOldLogs();
  
  // SINGLE-BRANCH ARCHITECTURE: No branch context service needed
  // Default branch with id='1' is automatically created in database
  
  // Initialize settings service (no branch context needed)
  await SettingsService.instance.initialize();
  LoggingService.instance.info('App', 'Settings service initialized');
  
  // Restore persisted admin session per auth policy
  await AuthService.instance.initializeSession();
  LoggingService.instance.info('App', 'Auth session policy evaluated');

  LoggingService.instance.info('App', 'Application startup complete (Single-Branch Mode)');
  
  // Run the app
  runApp(const PharmacyAttendanceApp());
}
