import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/employee_model.dart';
import '../../data/repositories/employee_repository.dart';

/// Employees list screen
class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  final EmployeeRepository _employeeRepository = EmployeeRepository.instance;
  final AuthService _authService = AuthService.instance;
  final TextEditingController _searchController = TextEditingController();
  
  List<Employee> _employees = [];
  bool _isLoading = true;
  String _searchQuery = '';
  EmployeeStatus? _statusFilter;
  
  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  Future<void> _loadEmployees() async {
    final branchId = '1';
    if (branchId == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      List<Employee> employees;
      if (_searchQuery.isNotEmpty) {
        employees = await _employeeRepository.search(branchId, _searchQuery);
      } else {
        employees = await _employeeRepository.getByBranch(branchId, activeOnly: false);
      }
      
      if (_statusFilter != null) {
        employees = employees.where((e) => e.status == _statusFilter).toList();
      }
      
      setState(() {
        _employees = employees;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_employees.length} Employees',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  // Search
                  SizedBox(
                    width: 300,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search employees...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                  _loadEmployees();
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      ),
                      onChanged: (value) {
                        setState(() => _searchQuery = value);
                        _loadEmployees();
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // Filter
                  PopupMenuButton<EmployeeStatus?>(
                    icon: Badge(
                      isLabelVisible: _statusFilter != null,
                      child: const Icon(Icons.filter_list),
                    ),
                    onSelected: (value) {
                      setState(() => _statusFilter = value);
                      _loadEmployees();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: null,
                        child: Text('All'),
                      ),
                      ...EmployeeStatus.values.map((status) => PopupMenuItem(
                        value: status,
                        child: Text(status.displayName),
                      )),
                    ],
                  ),
                  const SizedBox(width: 16),
                  
                  // Add button
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add Employee'),
                    onPressed: () => context.go('/employees/new'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Employees list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _employees.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 64,
                              color: AppTheme.textDisabled,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'No employees found'
                                  : 'No employees yet',
                              style: TextStyle(
                                fontSize: 18,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Add your first employee to get started',
                              style: TextStyle(color: AppTheme.textDisabled),
                            ),
                          ],
                        ),
                      )
                    : Card(
                        child: ListView.separated(
                          itemCount: _employees.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final employee = _employees[index];
                            return _buildEmployeeRow(employee);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEmployeeRow(Employee employee) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: _getStatusColor(employee.status).withOpacity(0.1),
        child: Text(
          employee.initials,
          style: TextStyle(
            color: _getStatusColor(employee.status),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Row(
        children: [
          Text(
            employee.fullName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _getStatusColor(employee.status).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              employee.status.displayName,
              style: TextStyle(
                fontSize: 12,
                color: _getStatusColor(employee.status),
              ),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              Text(employee.employeeCode),
              if (employee.jobTitle != null) ...[
                const Text(' • '),
                Text(employee.jobTitle!),
              ],
            ],
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Salary info
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${employee.salaryValue.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                employee.salaryType.displayName,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          
          // Attendance score
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _getScoreColor(employee.attendanceScore).withOpacity(0.1),
            ),
            child: Center(
              child: Text(
                '${employee.attendanceScore.toInt()}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _getScoreColor(employee.attendanceScore),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          
          // Actions
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => context.go('/employees/${employee.id}'),
          ),
          PopupMenuButton<String>(
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'view',
                child: Row(
                  children: [
                    Icon(Icons.visibility_outlined),
                    SizedBox(width: 8),
                    Text('View Details'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'history',
                child: Row(
                  children: [
                    Icon(Icons.history),
                    SizedBox(width: 8),
                    Text('Attendance History'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: AppTheme.errorColor),
                    const SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: AppTheme.errorColor)),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              switch (value) {
                case 'view':
                  context.go('/employees/${employee.id}');
                  break;
                case 'history':
                  // TODO: Show history
                  break;
                case 'delete':
                  _confirmDelete(employee);
                  break;
              }
            },
          ),
        ],
      ),
      onTap: () => context.go('/employees/${employee.id}'),
    );
  }
  
  Color _getStatusColor(EmployeeStatus status) {
    switch (status) {
      case EmployeeStatus.active:
        return AppTheme.successColor;
      case EmployeeStatus.inactive:
        return AppTheme.textSecondary;
      case EmployeeStatus.suspended:
        return AppTheme.warningColor;
      case EmployeeStatus.terminated:
        return AppTheme.errorColor;
    }
  }
  
  Color _getScoreColor(double score) {
    if (score >= 90) return AppTheme.successColor;
    if (score >= 70) return AppTheme.warningColor;
    return AppTheme.errorColor;
  }
  
  Future<void> _confirmDelete(Employee employee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Employee'),
        content: Text('Are you sure you want to delete ${employee.fullName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _employeeRepository.delete(employee.id);
      _loadEmployees();
    }
  }
}
