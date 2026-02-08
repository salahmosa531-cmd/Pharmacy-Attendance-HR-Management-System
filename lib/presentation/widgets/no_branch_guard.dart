import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/branch_context_service.dart';

/// A guard widget that blocks UI when no active branch is selected.
/// 
/// This is a SECONDARY protection layer (after route-level guard).
/// It prevents any service calls and shows a blocking informational UI.
/// 
/// Usage:
/// ```dart
/// @override
/// Widget build(BuildContext context) {
///   // GUARD: Check branch context FIRST, before any service calls
///   if (!BranchContextService.instance.hasBranch) {
///     return const NoBranchGuard(screenName: 'Financial Shift');
///   }
///   // ... rest of build
/// }
/// ```
class NoBranchGuard extends StatelessWidget {
  final String screenName;
  
  const NoBranchGuard({
    super.key,
    required this.screenName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(screenName),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.store_outlined,
                  size: 64,
                  color: Colors.orange.shade700,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'No Active Branch',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Please select a branch before accessing $screenName.\n'
                'Financial operations require an active branch context.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => context.go('/select-branch'),
                icon: const Icon(Icons.store),
                label: const Text('Select Branch'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go('/dashboard'),
                child: const Text('Go to Dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Extension to check branch context requirement
extension BranchContextGuard on BranchContextService {
  /// Returns true if branch context is valid for financial operations.
  /// Use this at the top of build() methods in financial screens.
  bool get hasActiveBranch => hasBranch && activeBranch != null;
}
