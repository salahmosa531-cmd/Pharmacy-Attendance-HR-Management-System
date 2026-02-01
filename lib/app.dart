import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'core/theme/app_theme.dart';
import 'core/utils/app_localizations.dart';
import 'core/services/services.dart';
import 'presentation/providers/app_state_provider.dart';
import 'router/app_router.dart';

/// Main application widget
class PharmacyAttendanceApp extends StatefulWidget {
  const PharmacyAttendanceApp({super.key});

  @override
  State<PharmacyAttendanceApp> createState() => _PharmacyAttendanceAppState();
}

class _PharmacyAttendanceAppState extends State<PharmacyAttendanceApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initWindow();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _initWindow() async {
    await windowManager.ensureInitialized();
    
    const windowOptions = WindowOptions(
      size: Size(1400, 900),
      minimumSize: Size(1024, 768),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'Pharmacy Attendance - HR Management System',
    );
    
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppStateProvider()),
      ],
      child: Consumer<AppStateProvider>(
        builder: (context, appState, _) {
          return MaterialApp.router(
            title: 'Pharmacy Attendance',
            debugShowCheckedModeBanner: false,
            
            // Theme
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: appState.themeMode,
            
            // Localization
            locale: appState.locale,
            supportedLocales: const [
              Locale('en', ''),
              Locale('ar', ''),
            ],
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            
            // Router
            routerConfig: AppRouter.router,
            
            // Builder for global error handling
            builder: (context, child) {
              return Directionality(
                textDirection: appState.locale.languageCode == 'ar' 
                    ? TextDirection.rtl 
                    : TextDirection.ltr,
                child: child ?? const SizedBox.shrink(),
              );
            },
          );
        },
      ),
    );
  }

  @override
  void onWindowClose() async {
    // Save any pending data before closing
    await DatabaseService.instance.close();
    await windowManager.destroy();
  }

  @override
  void onWindowFocus() {
    // Refresh data when window gains focus
    setState(() {});
  }
}
