import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/branch_context_service.dart';
import '../../data/models/shift_model.dart';
import '../../data/repositories/shift_repository.dart';

/// Shift form screen for add/edit
class ShiftFormScreen extends StatefulWidget {
  final String? shiftId;
  
  const ShiftFormScreen({super.key, this.shiftId});

  @override
  State<ShiftFormScreen> createState() => _ShiftFormScreenState();
}

class _ShiftFormScreenState extends State<ShiftFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final ShiftRepository _shiftRepository = ShiftRepository.instance;
  final AuthService _authService = AuthService.instance;
  final BranchContextService _branchContextService = BranchContextService.instance;
  final Uuid _uuid = const Uuid();
  
  bool _isLoading = true;
  bool _isSaving = false;
  Shift? _shift;
  
  // Form controllers
  final _nameController = TextEditingController();
  final _graceController = TextEditingController(text: '15');
  
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);
  Color _color = AppTheme.shiftColors.first;
  bool _isActive = true;
  
  bool get _isEditing => widget.shiftId != null;
  
  @override
  void initState() {
    super.initState();
    _loadData();
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _graceController.dispose();
    super.dispose();
  }
  
  Future<void> _loadData() async {
    if (_isEditing) {
      try {
        _shift = await _shiftRepository.getById(widget.shiftId!);
        if (_shift != null) {
          _nameController.text = _shift!.name;
          _graceController.text = _shift!.gracePeriodMinutes.toString();
          _startTime = _shift!.startTime;
          _endTime = _shift!.endTime;
          _color = _shift!.color != null ? _shift!.color! : AppTheme.shiftColors.first;
          _isActive = _shift!.isActive;
        }
      } catch (e) {
        // Handle error
      }
    }
    
    setState(() => _isLoading = false);
  }
  
  Future<void> _selectTime(BuildContext context, bool isStart) async {
    final initialTime = isStart ? _startTime : _endTime;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }
  
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    final branchId = _branchContextService.activeBranchId;
    if (branchId == null) return;
    
    setState(() => _isSaving = true);
    
    try {
      final now = DateTime.now();
      
      // Check if name exists
      if (await _shiftRepository.nameExists(
        branchId, 
        _nameController.text.trim(),
        excludeId: widget.shiftId,
      )) {
        _showError('Shift name already exists');
        setState(() => _isSaving = false);
        return;
      }
      
      final shift = Shift(
        id: _shift?.id ?? _uuid.v4(),
        branchId: branchId,
        name: _nameController.text.trim(),
        startTime: _startTime,
        endTime: _endTime,
        gracePeriodMinutes: int.tryParse(_graceController.text) ?? 15,
        color: _color,
        isActive: _isActive,
        createdAt: _shift?.createdAt ?? now,
        updatedAt: now,
      );
      
      if (_isEditing) {
        await _shiftRepository.update(shift, shift.id);
      } else {
        await _shiftRepository.insert(shift);
      }
      
      if (mounted) {
        context.go('/shifts');
      }
    } catch (e) {
      _showError(e.toString());
      setState(() => _isSaving = false);
    }
  }
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.errorColor,
      ),
    );
  }
  
  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.go('/shifts'),
                ),
                const SizedBox(width: 8),
                Text(
                  _isEditing ? 'Edit Shift' : 'Add Shift',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Form
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left column
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Shift Details',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Shift Name *',
                              hintText: 'e.g., Morning Shift',
                              prefixIcon: Icon(Icons.schedule),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Shift name is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),
                          
                          // Time selection
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Start Time',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    InkWell(
                                      onTap: () => _selectTime(context, true),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.grey),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.access_time),
                                            const SizedBox(width: 8),
                                            Text(
                                              _formatTime(_startTime),
                                              style: const TextStyle(fontSize: 16),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Padding(
                                padding: EdgeInsets.only(top: 24),
                                child: Icon(Icons.arrow_forward),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'End Time',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    InkWell(
                                      onTap: () => _selectTime(context, false),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.grey),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.access_time),
                                            const SizedBox(width: 8),
                                            Text(
                                              _formatTime(_endTime),
                                              style: const TextStyle(fontSize: 16),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          
                          // Cross-midnight indicator
                          if (_startTime.hour > _endTime.hour ||
                              (_startTime.hour == _endTime.hour &&
                                  _startTime.minute > _endTime.minute)) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.infoColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.infoColor),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.nightlight, color: AppTheme.infoColor),
                                  SizedBox(width: 8),
                                  Text(
                                    'This is a cross-midnight shift',
                                    style: TextStyle(color: AppTheme.infoColor),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          
                          const SizedBox(height: 24),
                          
                          TextFormField(
                            controller: _graceController,
                            decoration: const InputDecoration(
                              labelText: 'Grace Period (minutes)',
                              hintText: '15',
                              prefixIcon: Icon(Icons.timer),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                
                // Right column
                Expanded(
                  child: Column(
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Appearance',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              
                              const Text(
                                'Shift Color',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 12),
                              
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: AppTheme.shiftColors.map((color) {
                                  final isSelected = _color.toARGB32() == color.toARGB32();
                                  return GestureDetector(
                                    onTap: () => setState(() => _color = color),
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(8),
                                        border: isSelected
                                            ? Border.all(color: Colors.white, width: 3)
                                            : null,
                                        boxShadow: isSelected
                                            ? [
                                                BoxShadow(
                                                  color: color.withValues(alpha: 0.5),
                                                  blurRadius: 8,
                                                  spreadRadius: 2,
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: isSelected
                                          ? const Icon(Icons.check, color: Colors.white, size: 20)
                                          : null,
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Status',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              
                              SwitchListTile(
                                title: const Text('Active'),
                                subtitle: Text(
                                  _isActive 
                                      ? 'Shift is available for scheduling' 
                                      : 'Shift is disabled',
                                ),
                                value: _isActive,
                                onChanged: (value) {
                                  setState(() => _isActive = value);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Preview
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Preview',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _color),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 4,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: _color,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _nameController.text.isNotEmpty 
                                                ? _nameController.text 
                                                : 'Shift Name',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: _color,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${_formatTime(_startTime)} - ${_formatTime(_endTime)}',
                                            style: TextStyle(
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!_isActive)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.textSecondary.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'Inactive',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => context.go('/shifts'),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isEditing ? 'Save Changes' : 'Add Shift'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
