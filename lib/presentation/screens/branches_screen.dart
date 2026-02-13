import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../data/models/branch_model.dart';
import '../../data/repositories/branch_repository.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/shift_repository.dart';

/// Branches management screen (enterprise feature)
/// 
/// SINGLE-BRANCH ARCHITECTURE: This screen is deprecated.
/// In single-branch mode, only the default branch (id='1') is used.
/// New branch creation and modification are disabled.
class BranchesScreen extends StatefulWidget {
  const BranchesScreen({super.key});

  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> {
  final AuthService _authService = AuthService.instance;
  final BranchRepository _branchRepository = BranchRepository.instance;
  final EmployeeRepository _employeeRepository = EmployeeRepository.instance;
  final ShiftRepository _shiftRepository = ShiftRepository.instance;
  
  bool _isLoading = true;
  List<Branch> _branches = [];
  Map<String, int> _employeeCounts = {};
  Map<String, int> _shiftCounts = {};
  
  final _dateFormat = DateFormat('MMM dd, yyyy');
  
  @override
  void initState() {
    super.initState();
    _loadBranches();
  }
  
  Future<void> _loadBranches() async {
    setState(() => _isLoading = true);
    
    try {
      _branches = await _branchRepository.getAll();
      
      // Get employee and shift counts
      for (final branch in _branches) {
        final empCount = await _employeeRepository.getCountByBranch(branch.id);
        _employeeCounts[branch.id] = empCount;
        
        final shiftCount = await _shiftRepository.getCountByBranch(branch.id);
        _shiftCounts[branch.id] = shiftCount;
      }
      
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }
  
  void _showBranchDialog({Branch? branch}) {
    final isEditing = branch != null;
    final nameController = TextEditingController(text: branch?.name ?? '');
    final addressController = TextEditingController(text: branch?.address ?? '');
    final phoneController = TextEditingController(text: branch?.phone ?? '');
    final emailController = TextEditingController(text: branch?.email ?? '');
    bool isActive = branch?.isActive ?? true;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Edit Branch' : 'Add Branch'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Branch Name *',
                    prefixIcon: Icon(Icons.business),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    prefixIcon: Icon(Icons.location_on),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: phoneController,
                        decoration: const InputDecoration(
                          labelText: 'Phone',
                          prefixIcon: Icon(Icons.phone),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Active'),
                  value: isActive,
                  onChanged: branch?.isMainBranch == true
                      ? null
                      : (value) {
                          setDialogState(() => isActive = value);
                        },
                ),
                if (branch?.isMainBranch == true)
                  Text(
                    'Main branch cannot be deactivated',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Branch name is required'),
                      backgroundColor: AppTheme.errorColor,
                    ),
                  );
                  return;
                }
                
                try {
                  if (isEditing) {
                    // Update existing branch
                    final now = DateTime.now();
                    final updatedBranch = branch!.copyWith(
                      name: nameController.text.trim(),
                      address: addressController.text.trim().isNotEmpty
                          ? addressController.text.trim()
                          : null,
                      phone: phoneController.text.trim().isNotEmpty
                          ? phoneController.text.trim()
                          : null,
                      email: emailController.text.trim().isNotEmpty
                          ? emailController.text.trim()
                          : null,
                      isActive: isActive,
                      updatedAt: now,
                    );
                    await _branchRepository.update(updatedBranch, updatedBranch.id);
                  } else {
                    // SINGLE-BRANCH: Creating additional branches is disabled
                    // In single-branch mode, only the default branch (id=1) is used
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Creating additional branches is disabled in single-branch mode'),
                          backgroundColor: AppTheme.warningColor,
                        ),
                      );
                      Navigator.pop(context);
                    }
                    return;
                  }
                  
                  if (context.mounted) Navigator.pop(context);
                  _loadBranches();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: AppTheme.errorColor,
                      ),
                    );
                  }
                }
              },
              child: Text(isEditing ? 'Save' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _confirmDelete(Branch branch) async {
    if (branch.isMainBranch) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete main branch'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }
    
    final employeeCount = _employeeCounts[branch.id] ?? 0;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Branch'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete "${branch.name}"?'),
            if (employeeCount > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.warningColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.warningColor),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: AppTheme.warningColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This branch has $employeeCount employees. They will need to be reassigned.',
                        style: const TextStyle(color: AppTheme.warningColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
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
      try {
        await _branchRepository.delete(branch.id);
        _loadBranches();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
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
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Branches',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Manage pharmacy branches',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              // SINGLE-BRANCH: Add Branch button disabled
              Tooltip(
                message: 'Branch creation is disabled in single-branch mode',
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Branch'),
                  onPressed: null, // Disabled
                  style: ElevatedButton.styleFrom(
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Summary Cards
          Row(
            children: [
              _buildSummaryCard(
                'Total Branches',
                _branches.length.toString(),
                Icons.business,
                AppTheme.primaryColor,
              ),
              const SizedBox(width: 16),
              _buildSummaryCard(
                'Active Branches',
                _branches.where((b) => b.isActive).length.toString(),
                Icons.check_circle,
                AppTheme.successColor,
              ),
              const SizedBox(width: 16),
              _buildSummaryCard(
                'Total Employees',
                _employeeCounts.values.fold(0, (a, b) => a + b).toString(),
                Icons.people,
                AppTheme.accentColor,
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Branches List
          Expanded(
            child: Card(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _branches.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.business_outlined,
                                size: 64,
                                color: AppTheme.textDisabled,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No branches yet',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(8),
                          itemCount: _branches.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final branch = _branches[index];
                            return _buildBranchTile(branch);
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildBranchTile(Branch branch) {
    final employeeCount = _employeeCounts[branch.id] ?? 0;
    final shiftCount = _shiftCounts[branch.id] ?? 0;
    // SINGLE-BRANCH: Only allow viewing, not editing or deleting
    final bool isEditingDisabled = true;
    
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: branch.isMainBranch
              ? AppTheme.primaryColor.withValues(alpha: 0.1)
              : AppTheme.textSecondary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          branch.isMainBranch ? Icons.home_work : Icons.business,
          color: branch.isMainBranch ? AppTheme.primaryColor : AppTheme.textSecondary,
        ),
      ),
      title: Row(
        children: [
          Text(
            branch.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          if (branch.isMainBranch)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Main',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: branch.isActive
                  ? AppTheme.successColor.withValues(alpha: 0.1)
                  : AppTheme.errorColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              branch.isActive ? 'Active' : 'Inactive',
              style: TextStyle(
                fontSize: 12,
                color: branch.isActive ? AppTheme.successColor : AppTheme.errorColor,
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
              Icon(Icons.people, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 4),
              Text(
                '$employeeCount employees',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(width: 16),
              Icon(Icons.schedule, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 4),
              Text(
                '$shiftCount shifts',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(width: 16),
              Icon(Icons.calendar_today, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 4),
              Text(
                'Created ${_dateFormat.format(branch.createdAt)}',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
          if (branch.address != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.location_on, size: 16, color: AppTheme.textDisabled),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    branch.address!,
                    style: TextStyle(color: AppTheme.textDisabled, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // SINGLE-BRANCH: Edit button disabled
          Tooltip(
            message: 'Branch editing is disabled in single-branch mode',
            child: IconButton(
              icon: Icon(Icons.edit, color: Colors.grey.shade400),
              onPressed: null, // Disabled
              tooltip: 'Edit',
            ),
          ),
          // SINGLE-BRANCH: Delete button removed for all branches
          /* if (!branch.isMainBranch)
            IconButton(
              icon: const Icon(Icons.delete, color: AppTheme.errorColor),
              onPressed: () => _confirmDelete(branch),
              tooltip: 'Delete',
            ), */
        ],
      ),
      // SINGLE-BRANCH: Tap to edit disabled
      onTap: null, // Disabled
    );
  }
}
