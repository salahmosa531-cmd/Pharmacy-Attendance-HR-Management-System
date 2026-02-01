import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/services/auth_service.dart';
import '../presentation/screens/splash_screen.dart';
import '../presentation/screens/setup_screen.dart';
import '../presentation/screens/login_screen.dart';
import '../presentation/screens/main_shell.dart';
import '../presentation/screens/dashboard_screen.dart';
import '../presentation/screens/attendance_screen.dart';
import '../presentation/screens/employees_screen.dart';
import '../presentation/screens/employee_form_screen.dart';
import '../presentation/screens/shifts_screen.dart';
import '../presentation/screens/shift_form_screen.dart';
import '../presentation/screens/reports_screen.dart';
import '../presentation/screens/payroll_screen.dart';
import '../presentation/screens/settings_screen.dart';
import '../presentation/screens/audit_log_screen.dart';
import '../presentation/screens/branches_screen.dart';

/// Application router configuration
class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();
  static final _shellNavigatorKey = GlobalKey<NavigatorState>();
  
  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    debugLogDiagnostics: true,
    redirect: (context, state) async {
      final authService = AuthService.instance;
      final isLoggedIn = authService.isLoggedIn;
      final needsSetup = await authService.needsInitialSetup();
      
      final isSplash = state.matchedLocation == '/';
      final isSetup = state.matchedLocation == '/setup';
      final isLogin = state.matchedLocation == '/login';
      
      // First check if system needs setup
      if (needsSetup && !isSetup && !isSplash) {
        return '/setup';
      }
      
      // If needs setup and trying to access other routes
      if (needsSetup) {
        return null; // Allow splash or setup
      }
      
      // If not logged in, redirect to login
      if (!isLoggedIn && !isLogin && !isSplash) {
        return '/login';
      }
      
      // If logged in and trying to access login, redirect to dashboard
      if (isLoggedIn && isLogin) {
        return '/dashboard';
      }
      
      return null;
    },
    routes: [
      // Splash screen
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      
      // Initial setup
      GoRoute(
        path: '/setup',
        builder: (context, state) => const SetupScreen(),
      ),
      
      // Login
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      
      // Main shell with navigation
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          // Dashboard
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DashboardScreen(),
            ),
          ),
          
          // Attendance
          GoRoute(
            path: '/attendance',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: AttendanceScreen(),
            ),
          ),
          
          // Employees
          GoRoute(
            path: '/employees',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: EmployeesScreen(),
            ),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const EmployeeFormScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) => EmployeeFormScreen(
                  employeeId: state.pathParameters['id'],
                ),
              ),
            ],
          ),
          
          // Shifts
          GoRoute(
            path: '/shifts',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ShiftsScreen(),
            ),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const ShiftFormScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) => ShiftFormScreen(
                  shiftId: state.pathParameters['id'],
                ),
              ),
            ],
          ),
          
          // Reports
          GoRoute(
            path: '/reports',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ReportsScreen(),
            ),
          ),
          
          // Payroll
          GoRoute(
            path: '/payroll',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: PayrollScreen(),
            ),
          ),
          
          // Settings
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsScreen(),
            ),
          ),
          
          // Audit Log
          GoRoute(
            path: '/audit-log',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: AuditLogScreen(),
            ),
          ),
          
          // Branches (Enterprise)
          GoRoute(
            path: '/branches',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: BranchesScreen(),
            ),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Page not found',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              state.uri.toString(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/dashboard'),
              child: const Text('Go to Dashboard'),
            ),
          ],
        ),
      ),
    ),
  );
}
