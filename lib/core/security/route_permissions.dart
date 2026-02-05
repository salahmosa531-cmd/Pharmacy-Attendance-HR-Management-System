/// Central permission matrix for admin routes.
///
/// Keys are route prefixes, values are required permissions.
class RoutePermissions {
  static const Map<String, String> matrix = {
    '/branches': 'manage_branches',
    '/settings': 'manage_settings',
    '/shifts': 'manage_shifts',
    '/employees': 'manage_employees',
    '/reports': 'view_reports',
    '/payroll': 'view_reports',
    '/audit-log': 'view_reports',
    '/dashboard': 'view_reports',
    '/attendance': 'approve_overrides',
  };

  static String? requiredPermission(String path) {
    for (final entry in matrix.entries) {
      if (path.startsWith(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }
}
