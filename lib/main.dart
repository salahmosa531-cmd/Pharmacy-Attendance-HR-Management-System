import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'core/services/database_service.dart';
import 'core/services/settings_service.dart';
import 'core/services/logging_service.dart';
import 'core/services/branch_context_service.dart';
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
  
  // Initialize database
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
  
  // Initialize branch context service (handles branch selection and auto-selection)
  // This will also initialize SettingsService if a branch is already selected
  await BranchContextService.instance.initialize();
  LoggingService.instance.info('App', 'Branch context service initialized');
  
  // Restore persisted admin session per auth policy
  await AuthService.instance.initializeSession();
  LoggingService.instance.info('App', 'Auth session policy evaluated');

  // Log branch context state
  final branchState = BranchContextService.instance.state;
  if (branchState.hasBranch) {
    LoggingService.instance.info('App', 'Active branch: ${branchState.activeBranch!.name}');
  } else if (branchState.availableBranches.isEmpty) {
    LoggingService.instance.info('App', 'No branches available - needs setup');
  } else {
    LoggingService.instance.info('App', 'Branch selection required - ${branchState.availableBranches.length} branches available');
  }
  
  LoggingService.instance.info('App', 'Application startup complete');
  
  // Run the app
  runApp(const PharmacyAttendanceApp());
}
