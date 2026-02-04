import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_localizations.dart';
import '../../core/constants/app_constants.dart';
import '../providers/app_state_provider.dart';

/// Main shell with navigation rail for the application
class MainShell extends StatefulWidget {
  final Widget child;
  
  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  bool _isRailExtended = true;
  
  int _getSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    
    if (location.startsWith('/dashboard')) return 0;
    if (location.startsWith('/attendance')) return 1;
    if (location.startsWith('/employees')) return 2;
    if (location.startsWith('/shifts')) return 3;
    if (location.startsWith('/reports')) return 4;
    if (location.startsWith('/payroll')) return 5;
    if (location.startsWith('/settings')) return 6;
    if (location.startsWith('/audit-log')) return 7;
    if (location.startsWith('/branches')) return 8;
    
    return 0;
  }
  
  void _onItemSelected(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/dashboard');
        break;
      case 1:
        context.go('/attendance');
        break;
      case 2:
        context.go('/employees');
        break;
      case 3:
        context.go('/shifts');
        break;
      case 4:
        context.go('/reports');
        break;
      case 5:
        context.go('/payroll');
        break;
      case 6:
        context.go('/settings');
        break;
      case 7:
        context.go('/audit-log');
        break;
      case 8:
        context.go('/branches');
        break;
    }
  }
  
  // Navigation rail width constants
  static const double _collapsedRailWidth = 72.0;
  static const double _expandedRailWidth = 240.0;
  
  @override
  Widget build(BuildContext context) {
    final authService = AuthService.instance;
    final selectedIndex = _getSelectedIndex(context);
    final railWidth = _isRailExtended ? _expandedRailWidth : _collapsedRailWidth;
    
    return Scaffold(
      body: Row(
        children: [
          // Navigation Rail - FIXED: explicit width constraint to prevent RenderFlex errors
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: railWidth,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(2, 0),
                ),
              ],
            ),
            child: Column(
              children: [
                // Header
                Container(
                  height: 80,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.medical_services,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      if (_isRailExtended) ...[
                        const SizedBox(width: 12),
                        // FIXED: Use Flexible instead of Expanded to prevent RenderFlex overflow
                        Flexible(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Pharmacy',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              Text(
                                authService.currentBranch?.name ?? 'Attendance',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                const Divider(height: 1),
                
                // Navigation items
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        _buildNavItem(
                          context,
                          index: 0,
                          icon: Icons.dashboard_outlined,
                          selectedIcon: Icons.dashboard,
                          label: context.tr('dashboard'),
                          isSelected: selectedIndex == 0,
                        ),
                        _buildNavItem(
                          context,
                          index: 1,
                          icon: Icons.access_time_outlined,
                          selectedIcon: Icons.access_time_filled,
                          label: context.tr('attendance'),
                          isSelected: selectedIndex == 1,
                        ),
                        _buildNavItem(
                          context,
                          index: 2,
                          icon: Icons.people_outline,
                          selectedIcon: Icons.people,
                          label: context.tr('employees'),
                          isSelected: selectedIndex == 2,
                        ),
                        _buildNavItem(
                          context,
                          index: 3,
                          icon: Icons.schedule_outlined,
                          selectedIcon: Icons.schedule,
                          label: context.tr('shifts'),
                          isSelected: selectedIndex == 3,
                        ),
                        
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Divider(),
                        ),
                        
                        _buildNavItem(
                          context,
                          index: 4,
                          icon: Icons.assessment_outlined,
                          selectedIcon: Icons.assessment,
                          label: context.tr('reports'),
                          isSelected: selectedIndex == 4,
                        ),
                        _buildNavItem(
                          context,
                          index: 5,
                          icon: Icons.payment_outlined,
                          selectedIcon: Icons.payment,
                          label: context.tr('payroll'),
                          isSelected: selectedIndex == 5,
                        ),
                        
                        if (authService.hasPermission('view_reports')) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(),
                          ),
                          _buildNavItem(
                            context,
                            index: 7,
                            icon: Icons.history_outlined,
                            selectedIcon: Icons.history,
                            label: context.tr('audit_log'),
                            isSelected: selectedIndex == 7,
                          ),
                        ],
                        
                        if (authService.isSuperAdmin) ...[
                          _buildNavItem(
                            context,
                            index: 8,
                            icon: Icons.business_outlined,
                            selectedIcon: Icons.business,
                            label: context.tr('branches'),
                            isSelected: selectedIndex == 8,
                          ),
                        ],
                        
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Divider(),
                        ),
                        
                        _buildNavItem(
                          context,
                          index: 6,
                          icon: Icons.settings_outlined,
                          selectedIcon: Icons.settings,
                          label: context.tr('settings'),
                          isSelected: selectedIndex == 6,
                        ),
                      ],
                    ),
                  ),
                ),
                
                const Divider(height: 1),
                
                // User section
                InkWell(
                  onTap: () => _showUserMenu(context),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: AppTheme.primaryColor,
                          child: Text(
                            authService.currentUser?.username.substring(0, 1).toUpperCase() ?? 'U',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (_isRailExtended) ...[
                          const SizedBox(width: 12),
                          // FIXED: Use Flexible instead of Expanded
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  authService.currentUser?.username ?? 'User',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                Text(
                                  authService.currentUser?.role.displayName ?? '',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.expand_more, size: 20),
                        ],
                      ],
                    ),
                  ),
                ),
                
                // Toggle rail button
                InkWell(
                  onTap: () {
                    setState(() {
                      _isRailExtended = !_isRailExtended;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isRailExtended 
                              ? Icons.keyboard_double_arrow_left 
                              : Icons.keyboard_double_arrow_right,
                          size: 20,
                          color: AppTheme.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Main content
          Expanded(
            child: Column(
              children: [
                // Top bar
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 2,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Breadcrumb / Title
                      Text(
                        _getPageTitle(selectedIndex, context),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      
                      const Spacer(),
                      
                      // Quick actions
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh',
                        onPressed: () {
                          // Refresh current page
                          setState(() {});
                        },
                      ),
                      
                      // Theme toggle
                      Consumer<AppStateProvider>(
                        builder: (context, appState, _) {
                          return IconButton(
                            icon: Icon(
                              appState.themeMode == ThemeMode.dark
                                  ? Icons.light_mode
                                  : Icons.dark_mode,
                            ),
                            tooltip: 'Toggle theme',
                            onPressed: () => appState.toggleTheme(),
                          );
                        },
                      ),
                      
                      // Language toggle
                      Consumer<AppStateProvider>(
                        builder: (context, appState, _) {
                          return IconButton(
                            icon: const Icon(Icons.language),
                            tooltip: 'Toggle language',
                            onPressed: () => appState.toggleLocale(),
                          );
                        },
                      ),
                      
                      const SizedBox(width: 8),
                      
                      // Notifications (placeholder)
                      IconButton(
                        icon: Badge(
                          label: const Text('3'),
                          child: const Icon(Icons.notifications_outlined),
                        ),
                        tooltip: 'Notifications',
                        onPressed: () {
                          // TODO: Show notifications
                        },
                      ),
                    ],
                  ),
                ),
                
                // Page content
                Expanded(
                  child: widget.child,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildNavItem(
    BuildContext context, {
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required bool isSelected,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: EdgeInsets.symmetric(
        horizontal: _isRailExtended ? 12 : 8,
        vertical: 2,
      ),
      child: Material(
        color: isSelected
            ? AppTheme.primaryColor.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _onItemSelected(context, index),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: _isRailExtended ? 16 : 12,
              vertical: 12,
            ),
            child: Row(
              children: [
                Icon(
                  isSelected ? selectedIcon : icon,
                  color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
                  size: 22,
                ),
                if (_isRailExtended) ...[
                  const SizedBox(width: 12),
                  // FIXED: Use Flexible instead of Expanded
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  String _getPageTitle(int index, BuildContext context) {
    switch (index) {
      case 0:
        return context.tr('dashboard');
      case 1:
        return context.tr('attendance');
      case 2:
        return context.tr('employees');
      case 3:
        return context.tr('shifts');
      case 4:
        return context.tr('reports');
      case 5:
        return context.tr('payroll');
      case 6:
        return context.tr('settings');
      case 7:
        return context.tr('audit_log');
      case 8:
        return context.tr('branches');
      default:
        return '';
    }
  }
  
  void _showUserMenu(BuildContext context) {
    final authService = AuthService.instance;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppTheme.primaryColor,
              child: Text(
                authService.currentUser?.username.substring(0, 1).toUpperCase() ?? 'U',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(authService.currentUser?.username ?? 'User'),
                Text(
                  authService.currentUser?.role.displayName ?? '',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(context.tr('change_password')),
              onTap: () {
                Navigator.pop(context);
                // TODO: Show change password dialog
              },
            ),
            if (authService.isSuperAdmin) ...[
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Switch Branch'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Show branch switcher
                },
              ),
            ],
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: AppTheme.errorColor),
              title: Text(
                context.tr('logout'),
                style: const TextStyle(color: AppTheme.errorColor),
              ),
              onTap: () async {
                Navigator.pop(context);
                await authService.logout();
                if (context.mounted) {
                  context.go('/login');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
