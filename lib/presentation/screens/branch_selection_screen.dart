import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/branch_context_service.dart';
import '../../core/services/logging_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/branch_model.dart';

/// Screen for selecting the active branch
/// This screen is shown when:
/// 1. No branch is currently selected
/// 2. User wants to switch branches (admin only)
class BranchSelectionScreen extends StatefulWidget {
  final bool allowBack;
  final String? redirectTo;
  
  const BranchSelectionScreen({
    super.key,
    this.allowBack = false,
    this.redirectTo,
  });

  @override
  State<BranchSelectionScreen> createState() => _BranchSelectionScreenState();
}

class _BranchSelectionScreenState extends State<BranchSelectionScreen> {
  final BranchContextService _branchService = BranchContextService.instance;
  
  StreamSubscription<BranchContextState>? _subscription;
  BranchContextState _state = const BranchContextState(isLoading: true);
  Branch? _selectedBranch;
  bool _isSubmitting = false;

  static const Set<String> _allowedRedirectRoutes = {
    '/kiosk',
    '/dashboard',
    '/attendance',
    '/employees',
    '/shifts',
    '/reports',
    '/payroll',
    '/settings',
    '/audit-log',
    '/branches',
    '/select-branch',
    '/login',
  };

  String _resolveRedirectTarget(String? rawTarget) {
    final target = rawTarget?.trim();
    if (target == null || target.isEmpty) return '/kiosk';
    final normalized = target.startsWith('/') ? target : '/$target';
    final isAllowed = _allowedRedirectRoutes.any((allowed) =>
        normalized == allowed || normalized.startsWith('$allowed/'));
    if (!isAllowed) {
      LoggingService.instance.warning(
        'BranchSelection',
        'Blocked invalid redirect target: $normalized',
      );
      return '/kiosk';
    }
    return normalized;
  }
  
  @override
  void initState() {
    super.initState();
    _state = _branchService.state;
    _subscription = _branchService.stateStream.listen((state) {
      if (mounted) {
        setState(() => _state = state);
      }
    });
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
  
  Future<void> _selectBranch() async {
    if (_selectedBranch == null) return;
    
    setState(() => _isSubmitting = true);
    
    try {
      await _branchService.setActiveBranch(_selectedBranch!);
      
      LoggingService.instance.info('BranchSelection', 'Branch selected: ${_selectedBranch!.name}');
      
      if (mounted) {
        final redirectTo = _resolveRedirectTarget(widget.redirectTo);
        context.go(redirectTo);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to select branch: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: widget.allowBack ? AppBar(
        title: const Text('Select Branch'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ) : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: _buildContent(),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildContent() {
    if (_state.isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading branches...'),
          ],
        ),
      );
    }
    
    if (_state.error != null) {
      return _buildErrorState();
    }
    
    if (_state.availableBranches.isEmpty) {
      return _buildNoBranchesState();
    }
    
    return _buildBranchSelectionForm();
  }
  
  Widget _buildErrorState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.error_outline,
          size: 64,
          color: Colors.red,
        ),
        const SizedBox(height: 16),
        Text(
          'Error Loading Branches',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          _state.error ?? 'Unknown error',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => _branchService.refreshBranches(),
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    );
  }
  
  Widget _buildNoBranchesState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.store_outlined,
          size: 64,
          color: AppTheme.primaryColor,
        ),
        const SizedBox(height: 16),
        Text(
          'No Branches Available',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'No active branches are available for this device.\nPlease contact your administrator to configure a branch.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => _branchService.refreshBranches(),
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => context.go('/login'),
          icon: const Icon(Icons.admin_panel_settings),
          label: const Text('Admin Login'),
        ),

      ],
    );
  }
  
  Widget _buildBranchSelectionForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        const Icon(
          Icons.local_pharmacy,
          size: 64,
          color: AppTheme.primaryColor,
        ),
        const SizedBox(height: 16),
        Text(
          'Select Your Branch',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Choose the pharmacy branch for this device',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Colors.grey[600],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        
        // Branch List
        Container(
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _state.availableBranches.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final branch = _state.availableBranches[index];
              final isSelected = _selectedBranch?.id == branch.id;
              
              return ListTile(
                leading: Icon(
                  branch.isMainBranch ? Icons.star : Icons.store,
                  color: isSelected ? AppTheme.primaryColor : Colors.grey,
                ),
                title: Text(
                  branch.name,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: branch.address != null 
                    ? Text(branch.address!, maxLines: 1, overflow: TextOverflow.ellipsis)
                    : null,
                trailing: isSelected 
                    ? const Icon(Icons.check_circle, color: AppTheme.primaryColor)
                    : null,
                selected: isSelected,
                selectedTileColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                onTap: () {
                  setState(() => _selectedBranch = branch);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        
        // Submit Button
        ElevatedButton(
          onPressed: _selectedBranch != null && !_isSubmitting 
              ? _selectBranch 
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text(
                  'Continue',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
        ),
        
        // Info text
        const SizedBox(height: 16),
        Text(
          'This device will be configured for the selected branch.\nYou can change this later from Admin settings.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey[500],
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
