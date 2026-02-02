import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'core/services/database_service.dart';
import 'core/services/settings_service.dart';
import 'app.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize window manager for desktop
  await windowManager.ensureInitialized();
  
  // Initialize database FFI for desktop platforms
  DatabaseService.initializeFfi();
  
  // Initialize database
  await DatabaseService.instance.database;
  
  // Initialize settings service (loads settings from DB)
  await SettingsService.instance.initialize();
  
  // Run the app
  runApp(const PharmacyAttendanceApp());
}
