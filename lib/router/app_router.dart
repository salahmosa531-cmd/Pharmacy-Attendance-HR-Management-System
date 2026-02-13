import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/services/auth_service.dart';
import '../core/services/logging_service.dart';
import '../presentation/screens/splash_screen.dart';
import '../presentation/screens/setup_screen.dart';
import '../presentation/screens/login_screen.dart';
import '../presentation/screens/kiosk_screen.dart';
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
import '../core/security/route_permissions.dart';
import '../presentation/screens/financial_dashboard_screen.dart';
import '../presentation/screens/financial_shift_screen.dart';
import '../presentation/screens/financial_reports_screen.dart';
import '../presentation/screens/suppliers_screen.dart';


/// Application router configuration
/// 
/// SINGLE-BRANCH ARCHITECTURE - Simplified Navigation Flow:
/// 1. Splash Screen - Initial loading
/// 2. Setup Screen - First-time setup (if no users exist)
/// 3. Kiosk Screen - DEFAULT screen for employee attendance (PUBLIC)
/// 4. Login Screen - Admin access (accessed via hidden shortcut in Kiosk)
/// 5. Admin Dashboard - Full admin features (requires login)
/// 
/// NOTE: Branch selection has been removed. App operates in single-branch mode.
/// All data is scoped to the default branch (id='1').
class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();
  static final _shellNavigatorKey = GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    debugLogDiagnostics: false, // Disable in production
    redirect: (context, state) async {
      final authService = AuthService.instance;
      final isLoggedIn = authService.isLoggedIn;
      final needsSetup = await authService.needsInitialSetup();
      
      final currentPath = state.matchedLocation;
      final isSplash = currentPath == '/';
      final isSetup = currentPath == '/setup';
      final isLogin = currentPath == '/login';
      final isKiosk = currentPath == '/kiosk';
      final isAdminRoute = currentPath.startsWith('/admin') || 
                          currentPath.startsWith('/dashboard') ||
                          currentPath.startsWith('/employees') ||
                          currentPath.startsWith('/shifts') ||
                          currentPath.startsWith('/reports') ||
                          currentPath.startsWith('/payroll') ||
                          currentPath.startsWith('/settings') ||
                          currentPath.startsWith('/audit-log') ||
                          currentPath.startsWith('/branches') ||
                          currentPath.startsWith('/attendance') ||
                          currentPath.startsWith('/financial') ||
                          currentPath.startsWith('/suppliers');
      
      // Log navigation attempt
      final logger = LoggingService.instance;
      
      // 1. First check if system needs setup (no users = first time)
      if (needsSetup && !isSetup && !isSplash) {
        logger.navigation(currentPath, '/setup', 'needs initial setup');
        return '/setup';
      }
      
      // If needs setup and on splash, allow navigation to setup
      if (needsSetup) {
        return null;
      }

      // Prevent setup route access after initial setup is complete
      if (!needsSetup && isSetup) {
        logger.navigation(currentPath, '/kiosk', 'setup already completed');
        return '/kiosk';
      }
      
      // 2. Let splash handle its own navigation
      if (isSplash) {
        return null;
      }
      
      // 3. Admin routes require login
      if (isAdminRoute && !isLoggedIn) {
        logger.navigation(currentPath, '/login', 'admin route requires login');
        return '/login';
      }

      // 4. Enforce route-level permissions for admin routes
      if (isAdminRoute && isLoggedIn) {
        final requiredPermission = RoutePermissions.requiredPermission(currentPath);
        if (requiredPermission != null && !authService.hasPermission(requiredPermission)) {
          logger.navigation(currentPath, '/kiosk', 'missing permission: $requiredPermission');
          return '/kiosk';
        }
      }
      
      // 5. If logged in and trying to access login, redirect to dashboard
      if (isLoggedIn && isLogin) {
        final defaultRoute = authService.hasPermission('view_reports') ? '/dashboard' : '/kiosk';
        logger.navigation(currentPath, defaultRoute, 'already logged in');
        return defaultRoute;
      }
      
      return null;
    },
    routes: [
      // Splash screen - Initial loading
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      
      // Initial setup - First-time configuration
      GoRoute(
        path: '/setup',
        builder: (context, state) => const SetupScreen(),
      ),
      
      // Kiosk Mode - PUBLIC employee attendance screen (DEFAULT)
      GoRoute(
        path: '/kiosk',
        builder: (context, state) => const KioskScreen(),
      ),
      
      // Login - Admin access
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      
      // Admin shell with navigation (REQUIRES LOGIN)
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
          
          // Attendance Management (Admin view)
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
          
          // SINGLE-BRANCH: Branches route disabled
          // Branch management UI is inaccessible in single-branch mode
          // Uncomment to enable multi-branch support in future
          /* GoRoute(
            path: '/branches',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: BranchesScreen(),
            ),
          ), */
          
          // =========================================
          // FINANCIAL MANAGEMENT ROUTES
          // =========================================
          
          // Financial Dashboard
          GoRoute(
            path: '/financial-dashboard',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: FinancialDashboardScreen(),
            ),
          ),
          
          // Financial Shift Management
          GoRoute(
            path: '/financial-shift',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: FinancialShiftScreen(),
            ),
          ),
          
          // Financial Reports
          GoRoute(
            path: '/financial-reports',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: FinancialReportsScreen(),
            ),
          ),
          
          // Supplier Management
          GoRoute(
            path: '/suppliers',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SuppliersScreen(),
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
              'We couldnot find that page',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'The link might be outdated or invalid. Requested: ${state.uri}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/kiosk'),
              child: const Text('Go to Kiosk'),
            ),
          ],
        ),
      ),
    ),
  );
}
