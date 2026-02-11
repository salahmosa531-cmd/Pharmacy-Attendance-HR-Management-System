import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../data/models/shift_model.dart';
import '../../data/repositories/shift_repository.dart';

class ShiftsScreen extends StatefulWidget {
  const ShiftsScreen({super.key});

  @override
  State<ShiftsScreen> createState() => _ShiftsScreenState();
}

class _ShiftsScreenState extends State<ShiftsScreen> {
  final ShiftRepository _shiftRepository = ShiftRepository.instance;
  final AuthService _authService = AuthService.instance;
  
  List<Shift> _shifts = [];
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _loadShifts();
  }
  
  Future<void> _loadShifts() async {
    final branchId = '1';
    if (branchId == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      _shifts = await _shiftRepository.getByBranch(branchId, activeOnly: false);
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${_shifts.length} Shifts', 
                style: TextStyle(color: AppTheme.textSecondary)),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add Shift'),
                onPressed: () => context.go('/shifts/new'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _shifts.isEmpty
                    ? const Center(child: Text('No shifts created yet'))
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 1.5,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: _shifts.length,
                        itemBuilder: (context, index) {
                          final shift = _shifts[index];
                          return Card(
                            child: InkWell(
                              onTap: () => context.go('/shifts/${shift.id}'),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: shift.color ?? AppTheme.primaryColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            shift.name,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        if (!shift.isActive)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppTheme.textDisabled.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Text('Inactive', 
                                              style: TextStyle(fontSize: 12)),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        const Icon(Icons.access_time, size: 20),
                                        const SizedBox(width: 8),
                                        Text(shift.timeRange),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(Icons.timer, size: 20),
                                        const SizedBox(width: 8),
                                        Text('${shift.gracePeriodMinutes} min grace'),
                                      ],
                                    ),
                                    if (shift.isCrossMidnight) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Icon(Icons.nights_stay, 
                                            size: 20, color: AppTheme.infoColor),
                                          const SizedBox(width: 8),
                                          Text('Night shift',
                                            style: TextStyle(color: AppTheme.infoColor)),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
