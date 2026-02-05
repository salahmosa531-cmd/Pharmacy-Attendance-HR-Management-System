import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/branch_context_service.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/employee_model.dart';
import '../../data/models/shift_model.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/shift_repository.dart';

/// Employee form screen for add/edit
class EmployeeFormScreen extends StatefulWidget {
  final String? employeeId;
  
  const EmployeeFormScreen({super.key, this.employeeId});

  @override
  State<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends State<EmployeeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final EmployeeRepository _employeeRepository = EmployeeRepository.instance;
  final ShiftRepository _shiftRepository = ShiftRepository.instance;
  final AuthService _authService = AuthService.instance;
  final BranchContextService _branchContextService = BranchContextService.instance;
  final Uuid _uuid = const Uuid();
  
  bool _isLoading = true;
  bool _isSaving = false;
  Employee? _employee;
  List<Shift> _shifts = [];
  
  // Form controllers
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _salaryController = TextEditingController();
  final _notesController = TextEditingController();
  
  String? _selectedShiftId;
  SalaryType _salaryType = SalaryType.monthly;
  EmployeeStatus _status = EmployeeStatus.active;
  
  bool get _isEditing => widget.employeeId != null;
  
  @override
  void initState() {
    super.initState();
    _loadData();
  }
  
  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _jobTitleController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _barcodeController.dispose();
    _salaryController.dispose();
    _notesController.dispose();
    super.dispose();
  }
  
  Future<void> _loadData() async {
    final branchId = _branchContextService.activeBranchId;
    if (branchId == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      _shifts = await _shiftRepository.getByBranch(branchId);
      
      if (_isEditing) {
        _employee = await _employeeRepository.getById(widget.employeeId!);
        if (_employee != null) {
          _codeController.text = _employee!.employeeCode;
          _nameController.text = _employee!.fullName;
          _jobTitleController.text = _employee!.jobTitle ?? '';
          _emailController.text = _employee!.email ?? '';
          _phoneController.text = _employee!.phone ?? '';
          _barcodeController.text = _employee!.barcodeSerial ?? '';
          _salaryController.text = _employee!.salaryValue.toString();
          _notesController.text = _employee!.notes ?? '';
          _selectedShiftId = _employee!.assignedShiftId;
          _salaryType = _employee!.salaryType;
          _status = _employee!.status;
        }
      }
      
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    final branchId = _branchContextService.activeBranchId;
    if (branchId == null) return;
    
    setState(() => _isSaving = true);
    
    try {
      final now = DateTime.now();
      
      // Check if code exists
      if (await _employeeRepository.codeExists(
        branchId, 
        _codeController.text.trim(),
        excludeId: widget.employeeId,
      )) {
        _showError('Employee code already exists');
        setState(() => _isSaving = false);
        return;
      }
      
      // Check if barcode exists
      if (_barcodeController.text.trim().isNotEmpty) {
        if (await _employeeRepository.barcodeExists(
          branchId,
          _barcodeController.text.trim(),
          excludeId: widget.employeeId,
        )) {
          _showError('Barcode already assigned to another employee');
          setState(() => _isSaving = false);
          return;
        }
      }
      
      final employee = Employee(
        id: _employee?.id ?? _uuid.v4(),
        branchId: branchId,
        employeeCode: _codeController.text.trim(),
        fullName: _nameController.text.trim(),
        jobTitle: _jobTitleController.text.trim().isNotEmpty 
            ? _jobTitleController.text.trim() 
            : null,
        email: _emailController.text.trim().isNotEmpty 
            ? _emailController.text.trim() 
            : null,
        phone: _phoneController.text.trim().isNotEmpty 
            ? _phoneController.text.trim() 
            : null,
        barcodeSerial: _barcodeController.text.trim().isNotEmpty 
            ? _barcodeController.text.trim() 
            : null,
        assignedShiftId: _selectedShiftId,
        salaryType: _salaryType,
        salaryValue: double.tryParse(_salaryController.text) ?? 0,
        status: _status,
        notes: _notesController.text.trim().isNotEmpty 
            ? _notesController.text.trim() 
            : null,
        hireDate: _employee?.hireDate ?? now,
        createdAt: _employee?.createdAt ?? now,
        updatedAt: now,
      );
      
      if (_isEditing) {
        await _employeeRepository.update(employee, employee.id);
      } else {
        await _employeeRepository.insert(employee);
      }
      
      if (mounted) {
        context.go('/employees');
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
                  onPressed: () => context.go('/employees'),
                ),
                const SizedBox(width: 8),
                Text(
                  _isEditing ? 'Edit Employee' : 'Add Employee',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
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
                            'Basic Information',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          TextFormField(
                            controller: _codeController,
                            decoration: const InputDecoration(
                              labelText: 'Employee Code *',
                              hintText: 'e.g., EMP001',
                              prefixIcon: Icon(Icons.badge),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Employee code is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Full Name *',
                              prefixIcon: Icon(Icons.person),
                            ),
                            textCapitalization: TextCapitalization.words,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Full name is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          TextFormField(
                            controller: _jobTitleController,
                            decoration: const InputDecoration(
                              labelText: 'Job Title',
                              prefixIcon: Icon(Icons.work),
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          TextFormField(
                            controller: _emailController,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email),
                            ),
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 16),
                          
                          TextFormField(
                            controller: _phoneController,
                            decoration: const InputDecoration(
                              labelText: 'Phone',
                              prefixIcon: Icon(Icons.phone),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 16),
                          
                          DropdownButtonFormField<EmployeeStatus>(
                            value: _status,
                            decoration: const InputDecoration(
                              labelText: 'Status',
                              prefixIcon: Icon(Icons.toggle_on),
                            ),
                            items: EmployeeStatus.values.map((status) {
                              return DropdownMenuItem(
                                value: status,
                                child: Text(status.displayName),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _status = value);
                              }
                            },
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
                                'Attendance & Salary',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 24),
                              
                              TextFormField(
                                controller: _barcodeController,
                                decoration: const InputDecoration(
                                  labelText: 'Barcode / Badge Serial',
                                  prefixIcon: Icon(Icons.qr_code),
                                  hintText: 'Scan or enter barcode',
                                ),
                              ),
                              const SizedBox(height: 16),
                              
                              DropdownButtonFormField<String?>(
                                value: _selectedShiftId,
                                decoration: const InputDecoration(
                                  labelText: 'Assigned Shift',
                                  prefixIcon: Icon(Icons.schedule),
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('No shift assigned'),
                                  ),
                                  ..._shifts.map((shift) => DropdownMenuItem(
                                    value: shift.id,
                                    child: Text('${shift.name} (${shift.timeRange})'),
                                  )),
                                ],
                                onChanged: (value) {
                                  setState(() => _selectedShiftId = value);
                                },
                              ),
                              const SizedBox(height: 16),
                              
                              DropdownButtonFormField<SalaryType>(
                                value: _salaryType,
                                decoration: const InputDecoration(
                                  labelText: 'Salary Type',
                                  prefixIcon: Icon(Icons.payment),
                                ),
                                items: SalaryType.values.map((type) {
                                  return DropdownMenuItem(
                                    value: type,
                                    child: Text(type.displayName),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _salaryType = value);
                                  }
                                },
                              ),
                              const SizedBox(height: 16),
                              
                              TextFormField(
                                controller: _salaryController,
                                decoration: InputDecoration(
                                  labelText: 'Salary Amount',
                                  prefixIcon: const Icon(Icons.attach_money),
                                  suffixText: _salaryType == SalaryType.hourly 
                                      ? '/hour' 
                                      : _salaryType == SalaryType.perShift 
                                          ? '/shift' 
                                          : '/month',
                                ),
                                keyboardType: TextInputType.number,
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
                                'Notes',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              
                              TextFormField(
                                controller: _notesController,
                                decoration: const InputDecoration(
                                  hintText: 'Any additional notes...',
                                  border: OutlineInputBorder(),
                                ),
                                maxLines: 4,
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
                  onPressed: () => context.go('/employees'),
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
                      : Text(_isEditing ? 'Save Changes' : 'Add Employee'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
