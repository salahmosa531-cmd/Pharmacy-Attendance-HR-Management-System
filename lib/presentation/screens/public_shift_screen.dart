import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/financial_service.dart';
import '../../core/services/logging_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/financial_shift_model.dart';
import '../../data/models/shift_sale_model.dart';
import '../../data/models/shift_expense_model.dart';
import '../../data/models/employee_model.dart';
import '../../data/repositories/employee_repository.dart';
import '../widgets/purchase_payment_entry_dialog.dart';
import '../widgets/debt_collection_dialog.dart';

/// Public Financial Shift Screen - Kiosk Mode
/// 
/// Allows employees to perform financial operations without admin login:
/// - Open/close shifts
/// - Record sales, expenses, purchases, debt collections
/// - View real-time summary and timeline
/// 
/// Security:
/// - Requires employee code for all operations
/// - 5-minute temporary session to avoid repeated entry
/// - All operations logged with employeeId, timestamp, source='kiosk'
/// - Auto-close shift after 24 hours
/// 
/// Restrictions:
/// - Cannot edit/delete records
/// - Cannot access settings or reports
/// - Cannot close previous shifts
class PublicShiftScreen extends StatefulWidget {
  const PublicShiftScreen({super.key});

  @override
  State<PublicShiftScreen> createState() => _PublicShiftScreenState();
}

class _PublicShiftScreenState extends State<PublicShiftScreen> with WidgetsBindingObserver {
  final _financialService = FinancialService.instance;
  final _employeeRepo = EmployeeRepository.instance;
  
  // Session management
  Employee? _currentEmployee;
  DateTime? _sessionExpiresAt;
  Timer? _sessionTimer;
  static const _sessionDurationMinutes = 5;
  
  // UI State
  bool _isLoading = true;
  String? _loadError;
  bool _isProcessing = false;
  
  // Financial data
  FinancialShift? _currentShift;
  ShiftSummary? _shiftSummary;
  ShiftCashFlowSummary? _cashFlowSummary;
  List<ShiftSale> _sales = [];
  List<ShiftExpense> _expenses = [];
  List<_TimelineItem> _timeline = [];
  
  // Employee code entry
  final _codeController = TextEditingController();
  final _codeFocusNode = FocusNode();
  
  // Formatters
  final _currencyFormat = NumberFormat.currency(symbol: '', decimalDigits: 2);
  final _timeFormat = DateFormat('hh:mm a');
  final _dateFormat = DateFormat('dd MMM yyyy');
  
  // Tab controller
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCurrentShift();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionTimer?.cancel();
    _codeController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAutoClose();
      _loadCurrentShift();
    }
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // SESSION MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════
  
  bool get _hasActiveSession {
    if (_currentEmployee == null || _sessionExpiresAt == null) return false;
    return DateTime.now().isBefore(_sessionExpiresAt!);
  }
  
  void _startSession(Employee employee) {
    _currentEmployee = employee;
    _sessionExpiresAt = DateTime.now().add(const Duration(minutes: _sessionDurationMinutes));
    
    _sessionTimer?.cancel();
    _sessionTimer = Timer(const Duration(minutes: _sessionDurationMinutes), () {
      if (mounted) {
        setState(() {
          _currentEmployee = null;
          _sessionExpiresAt = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session expired. Please enter your code again.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });
    
    LoggingService.instance.info(
      'PublicShift',
      '[SESSION_START] Employee ${employee.employeeCode} started session, expires at $_sessionExpiresAt',
    );
  }
  
  void _extendSession() {
    if (_currentEmployee != null) {
      _startSession(_currentEmployee!);
    }
  }
  
  void _endSession() {
    _sessionTimer?.cancel();
    _currentEmployee = null;
    _sessionExpiresAt = null;
    if (mounted) setState(() {});
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // DATA LOADING
  // ═══════════════════════════════════════════════════════════════════════════
  
  Future<void> _loadCurrentShift() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    
    try {
      // Check for any open shift (public mode - any employee's shift)
      final openShifts = await _financialService.getOpenShiftsForBranch();
      
      if (openShifts.isNotEmpty) {
        _currentShift = openShifts.first;
        await _refreshShiftData();
        
        // Check for auto-close (24 hours)
        await _checkAutoClose();
      } else {
        _currentShift = null;
        _shiftSummary = null;
        _cashFlowSummary = null;
        _sales = [];
        _expenses = [];
        _timeline = [];
      }
    } catch (e) {
      LoggingService.instance.error('PublicShift', 'Error loading shift', e, StackTrace.current);
      if (mounted) {
        setState(() => _loadError = 'Error loading shift: $e');
      }
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _refreshShiftData() async {
    if (_currentShift == null) return;
    
    try {
      _shiftSummary = await _financialService.getShiftSummary(_currentShift!.id);
      _cashFlowSummary = await _financialService.getShiftCashFlowSummary(_currentShift!.id);
      _sales = await _financialService.getSalesForShift(_currentShift!.id);
      _expenses = await _financialService.getExpensesForShift(_currentShift!.id);
      _buildTimeline();
      
      if (mounted) setState(() {});
    } catch (e) {
      LoggingService.instance.error('PublicShift', 'Error refreshing shift data', e, StackTrace.current);
    }
  }
  
  void _buildTimeline() {
    _timeline = [];
    
    for (final sale in _sales) {
      final isDebtCollection = sale.paymentMethod == PaymentMethod.credit;
      _timeline.add(_TimelineItem(
        type: isDebtCollection ? _TimelineType.debtCollection : _TimelineType.sale,
        amount: sale.amount,
        description: isDebtCollection 
            ? (sale.customerName ?? 'Debt Collection')
            : (sale.description ?? sale.paymentMethod.displayName),
        time: sale.createdAt,
        icon: isDebtCollection ? Icons.payments : _getPaymentMethodIcon(sale.paymentMethod),
        color: isDebtCollection ? Colors.teal : Colors.green,
        subtitle: isDebtCollection 
            ? sale.description
            : (sale.invoiceNumber != null ? 'Invoice: ${sale.invoiceNumber}' : sale.paymentMethod.displayName),
      ));
    }
    
    for (final expense in _expenses) {
      final isPurchase = expense.category == ExpenseCategory.supplies;
      _timeline.add(_TimelineItem(
        type: isPurchase ? _TimelineType.purchase : _TimelineType.expense,
        amount: expense.amount,
        description: expense.description,
        time: expense.createdAt,
        icon: isPurchase ? Icons.inventory_2 : _getExpenseCategoryIcon(expense.category),
        color: isPurchase ? Colors.orange : Colors.red,
        subtitle: expense.category.displayName,
      ));
    }
    
    _timeline.sort((a, b) => b.time.compareTo(a.time));
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // AUTO-CLOSE (24 HOURS)
  // ═══════════════════════════════════════════════════════════════════════════
  
  Future<void> _checkAutoClose() async {
    if (_currentShift == null) return;
    
    final shiftAge = DateTime.now().difference(_currentShift!.openedAt);
    if (shiftAge.inHours >= 24) {
      LoggingService.instance.warning(
        'PublicShift',
        '[AUTO_CLOSE] Shift ${_currentShift!.id} has been open for ${shiftAge.inHours}h, auto-closing',
      );
      
      try {
        // Auto-close with expected cash
        final expectedCash = _shiftSummary?.expectedCash ?? 0;
        await _financialService.closeShift(
          financialShiftId: _currentShift!.id,
          actualCash: expectedCash,
          closedBy: 'SYSTEM_AUTO_CLOSE',
          differenceReason: 'Auto-closed after 24 hours',
          notes: 'Automatic closure due to shift exceeding 24 hours',
        );
        
        await _loadCurrentShift();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Previous shift was auto-closed after 24 hours'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
      } catch (e) {
        LoggingService.instance.error('PublicShift', 'Auto-close failed', e, StackTrace.current);
      }
    }
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // EMPLOYEE VERIFICATION
  // ═══════════════════════════════════════════════════════════════════════════
  
  Future<Employee?> _verifyEmployee() async {
    if (_hasActiveSession) {
      _extendSession();
      return _currentEmployee;
    }
    
    return await _showEmployeeCodeDialog();
  }
  
  Future<Employee?> _showEmployeeCodeDialog() async {
    _codeController.clear();
    
    return showDialog<Employee>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          bool isVerifying = false;
          String? errorMessage;
          
          Future<void> verify() async {
            final code = _codeController.text.trim();
            if (code.isEmpty) {
              setDialogState(() => errorMessage = 'Please enter your employee code');
              return;
            }
            
            setDialogState(() {
              isVerifying = true;
              errorMessage = null;
            });
            
            try {
              final employee = await _employeeRepo.getByCode('1', code);
              
              if (employee == null) {
                setDialogState(() {
                  isVerifying = false;
                  errorMessage = 'Employee code not found';
                });
                return;
              }
              
              if (!employee.isActive) {
                setDialogState(() {
                  isVerifying = false;
                  errorMessage = 'This employee account is inactive';
                });
                return;
              }
              
              _startSession(employee);
              if (context.mounted) Navigator.pop(context, employee);
            } catch (e) {
              setDialogState(() {
                isVerifying = false;
                errorMessage = 'Error verifying code: $e';
              });
            }
          }
          
          return AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.badge, color: AppTheme.primaryColor),
                ),
                const SizedBox(width: 12),
                const Text('Employee Verification'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter your employee code to continue',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _codeController,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 4),
                  decoration: InputDecoration(
                    hintText: 'Employee Code',
                    prefixIcon: const Icon(Icons.person),
                    border: const OutlineInputBorder(),
                    errorText: errorMessage,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                    LengthLimitingTextInputFormatter(20),
                  ],
                  onSubmitted: (_) => verify(),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blue, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Session lasts $_sessionDurationMinutes minutes',
                          style: const TextStyle(fontSize: 12, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isVerifying ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: isVerifying ? null : verify,
                child: isVerifying
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Verify'),
              ),
            ],
          );
        },
      ),
    );
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // SHIFT OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════
  
  Future<void> _openShift() async {
    // Verify employee
    final employee = await _verifyEmployee();
    if (employee == null) return;
    
    // Check if shift already open
    if (_currentShift != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A shift is already open. Close it first to open a new one.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Get opening cash
    final openingCash = await _showOpeningCashDialog();
    if (openingCash == null) return;
    
    setState(() => _isProcessing = true);
    
    try {
      _currentShift = await _financialService.openShift(
        employeeId: employee.id,
        openingCash: openingCash,
        notes: 'Opened from kiosk by ${employee.fullName}',
      );
      
      LoggingService.instance.audit(
        'PublicShift',
        'SHIFT_OPENED',
        'Employee ${employee.employeeCode} opened shift ${_currentShift!.id} with ${openingCash} EGP',
        details: {
          'shift_id': _currentShift!.id,
          'employee_id': employee.id,
          'employee_code': employee.employeeCode,
          'opening_cash': openingCash,
          'source': 'kiosk',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      
      await _refreshShiftData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('Shift opened by ${employee.fullName}'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      LoggingService.instance.error('PublicShift', 'Error opening shift', e, StackTrace.current);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening shift: $e'), backgroundColor: Colors.red),
        );
      }
    }
    
    if (mounted) setState(() => _isProcessing = false);
  }
  
  Future<double?> _showOpeningCashDialog() async {
    final controller = TextEditingController();
    
    return showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.play_circle, color: Colors.green),
            ),
            const SizedBox(width: 12),
            const Text('Open Shift'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Count the cash in the drawer and enter the amount:'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
              autofocus: true,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                labelText: 'Opening Cash (EGP)',
                prefixIcon: Icon(Icons.payments),
                border: OutlineInputBorder(),
                suffixText: 'EGP',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              final value = double.tryParse(controller.text) ?? 0;
              Navigator.pop(context, value);
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Shift'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _closeShift() async {
    if (_currentShift == null) return;
    
    // Verify employee
    final employee = await _verifyEmployee();
    if (employee == null) return;
    
    // Show close dialog
    final result = await _showCloseShiftDialog();
    if (result == null) return;
    
    setState(() => _isProcessing = true);
    
    try {
      await _financialService.closeShift(
        financialShiftId: _currentShift!.id,
        actualCash: result['actualCash'] as double,
        closedBy: employee.id,
        differenceReason: result['reason'] as String?,
        notes: 'Closed from kiosk by ${employee.fullName}',
      );
      
      final difference = (result['actualCash'] as double) - (_shiftSummary?.expectedCash ?? 0);
      
      LoggingService.instance.audit(
        'PublicShift',
        'SHIFT_CLOSED',
        'Employee ${employee.employeeCode} closed shift ${_currentShift!.id}',
        details: {
          'shift_id': _currentShift!.id,
          'employee_id': employee.id,
          'employee_code': employee.employeeCode,
          'actual_cash': result['actualCash'],
          'expected_cash': _shiftSummary?.expectedCash,
          'difference': difference,
          'difference_reason': result['reason'],
          'source': 'kiosk',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('Shift closed by ${employee.fullName}'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      _currentShift = null;
      _shiftSummary = null;
      _cashFlowSummary = null;
      _sales = [];
      _expenses = [];
      _timeline = [];
    } catch (e) {
      LoggingService.instance.error('PublicShift', 'Error closing shift', e, StackTrace.current);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error closing shift: $e'), backgroundColor: Colors.red),
        );
      }
    }
    
    if (mounted) setState(() => _isProcessing = false);
  }
  
  Future<Map<String, dynamic>?> _showCloseShiftDialog() async {
    final actualCashController = TextEditingController();
    final reasonController = TextEditingController();
    double? enteredCash;
    double difference = 0;
    final expectedCash = _shiftSummary?.expectedCash ?? 0;
    
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.stop_circle, color: Colors.orange),
              ),
              const SizedBox(width: 12),
              const Text('Close Shift'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Summary
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _buildCloseDialogRow('Opening Cash', _currentShift?.openingCash ?? 0, Icons.account_balance_wallet),
                      _buildCloseDialogRow('+ Cash Sales', _shiftSummary?.cashSales ?? 0, Icons.add_circle, color: Colors.green),
                      _buildCloseDialogRow('- Expenses', _shiftSummary?.totalExpenses ?? 0, Icons.remove_circle, color: Colors.red),
                      const Divider(height: 20),
                      _buildCloseDialogRow('= Expected', expectedCash, Icons.calculate, isBold: true, color: AppTheme.primaryColor),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                
                // Actual cash
                TextField(
                  controller: actualCashController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  autofocus: true,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'Actual Cash in Drawer (EGP)',
                    prefixIcon: Icon(Icons.point_of_sale),
                    border: OutlineInputBorder(),
                    suffixText: 'EGP',
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      enteredCash = double.tryParse(value);
                      difference = (enteredCash ?? 0) - expectedCash;
                    });
                  },
                ),
                
                // Difference display
                if (enteredCash != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: difference == 0
                          ? Colors.green.withOpacity(0.1)
                          : difference > 0
                              ? Colors.blue.withOpacity(0.1)
                              : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: difference == 0
                            ? Colors.green
                            : difference > 0 ? Colors.blue : Colors.red,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          difference == 0
                              ? Icons.check_circle
                              : difference > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                          color: difference == 0
                              ? Colors.green
                              : difference > 0 ? Colors.blue : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            difference == 0
                                ? 'Cash matches expected!'
                                : difference > 0
                                    ? 'Overage: +${_currencyFormat.format(difference)} EGP'
                                    : 'Shortage: ${_currencyFormat.format(difference)} EGP',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: difference == 0
                                  ? Colors.green
                                  : difference > 0 ? Colors.blue : Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                // Reason (required if difference)
                if (enteredCash != null && difference != 0) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: reasonController,
                    decoration: InputDecoration(
                      labelText: 'Reason for Difference *',
                      prefixIcon: Icon(
                        Icons.warning_amber,
                        color: difference < 0 ? Colors.red : Colors.blue,
                      ),
                      border: const OutlineInputBorder(),
                      hintText: 'Explain the ${difference > 0 ? "overage" : "shortage"}',
                    ),
                    maxLines: 2,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () {
                final actualCash = double.tryParse(actualCashController.text);
                if (actualCash == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter actual cash')),
                  );
                  return;
                }
                
                if (difference != 0 && reasonController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please provide a reason for the difference')),
                  );
                  return;
                }
                
                Navigator.pop(context, {
                  'actualCash': actualCash,
                  'reason': reasonController.text.isEmpty ? null : reasonController.text,
                });
              },
              icon: const Icon(Icons.lock),
              label: const Text('Close Shift'),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCloseDialogRow(String label, double value, IconData icon, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color),
            ),
          ),
          Text(
            '${_currencyFormat.format(value)} EGP',
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
              fontSize: isBold ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // RECORD OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════
  
  Future<void> _recordSale() async {
    if (_currentShift == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please open a shift first'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    final employee = await _verifyEmployee();
    if (employee == null) return;
    
    final result = await _showSaleDialog();
    if (result == null) return;
    
    setState(() => _isProcessing = true);
    
    try {
      await _financialService.recordSale(
        financialShiftId: _currentShift!.id,
        amount: result['amount'] as double,
        paymentMethod: result['method'] as PaymentMethod,
        description: result['description'] as String?,
        invoiceNumber: result['invoice'] as String?,
        recordedBy: employee.id,
      );
      
      LoggingService.instance.info(
        'PublicShift',
        '[SALE_RECORDED] Employee ${employee.employeeCode} recorded sale ${result['amount']} EGP via kiosk',
      );
      
      await _refreshShiftData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('Sale recorded: ${_currencyFormat.format(result['amount'])} EGP'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error recording sale: $e'), backgroundColor: Colors.red),
        );
      }
    }
    
    if (mounted) setState(() => _isProcessing = false);
  }
  
  Future<Map<String, dynamic>?> _showSaleDialog() async {
    final amountController = TextEditingController();
    final descController = TextEditingController();
    final invoiceController = TextEditingController();
    PaymentMethod selectedMethod = PaymentMethod.cash;
    
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add_shopping_cart, color: Colors.green),
              ),
              const SizedBox(width: 12),
              const Text('Record Sale'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  autofocus: true,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'Amount (EGP) *',
                    prefixIcon: Icon(Icons.attach_money),
                    border: OutlineInputBorder(),
                    suffixText: 'EGP',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<PaymentMethod>(
                  value: selectedMethod,
                  decoration: const InputDecoration(
                    labelText: 'Payment Method',
                    prefixIcon: Icon(Icons.payment),
                    border: OutlineInputBorder(),
                  ),
                  items: PaymentMethod.values.map((m) => DropdownMenuItem(
                    value: m,
                    child: Row(
                      children: [
                        Icon(_getPaymentMethodIcon(m), size: 20, color: _getPaymentMethodColor(m)),
                        const SizedBox(width: 8),
                        Text(m.displayName),
                      ],
                    ),
                  )).toList(),
                  onChanged: (v) => setDialogState(() => selectedMethod = v!),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: invoiceController,
                  decoration: const InputDecoration(
                    labelText: 'Invoice Number (optional)',
                    prefixIcon: Icon(Icons.receipt),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    prefixIcon: Icon(Icons.description),
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () {
                final amount = double.tryParse(amountController.text);
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid amount')),
                  );
                  return;
                }
                Navigator.pop(context, {
                  'amount': amount,
                  'method': selectedMethod,
                  'description': descController.text.isEmpty ? null : descController.text,
                  'invoice': invoiceController.text.isEmpty ? null : invoiceController.text,
                });
              },
              icon: const Icon(Icons.check),
              label: const Text('Record'),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _recordExpense() async {
    if (_currentShift == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please open a shift first'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    final employee = await _verifyEmployee();
    if (employee == null) return;
    
    final result = await _showExpenseDialog();
    if (result == null) return;
    
    setState(() => _isProcessing = true);
    
    try {
      await _financialService.recordExpense(
        financialShiftId: _currentShift!.id,
        amount: result['amount'] as double,
        category: result['category'] as ExpenseCategory,
        description: result['description'] as String,
        receiptNumber: result['receipt'] as String?,
        recordedBy: employee.id,
      );
      
      LoggingService.instance.info(
        'PublicShift',
        '[EXPENSE_RECORDED] Employee ${employee.employeeCode} recorded expense ${result['amount']} EGP via kiosk',
      );
      
      await _refreshShiftData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('Expense recorded: ${_currencyFormat.format(result['amount'])} EGP'),
              ],
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error recording expense: $e'), backgroundColor: Colors.red),
        );
      }
    }
    
    if (mounted) setState(() => _isProcessing = false);
  }
  
  Future<Map<String, dynamic>?> _showExpenseDialog() async {
    final amountController = TextEditingController();
    final descController = TextEditingController();
    final receiptController = TextEditingController();
    ExpenseCategory selectedCategory = ExpenseCategory.misc;
    
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.remove_shopping_cart, color: Colors.red),
              ),
              const SizedBox(width: 12),
              const Text('Record Expense'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  autofocus: true,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'Amount (EGP) *',
                    prefixIcon: Icon(Icons.attach_money),
                    border: OutlineInputBorder(),
                    suffixText: 'EGP',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<ExpenseCategory>(
                  value: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(Icons.category),
                    border: OutlineInputBorder(),
                  ),
                  items: ExpenseCategory.values
                      .where((c) => c != ExpenseCategory.supplies) // Supplies = Purchase, separate flow
                      .map((c) => DropdownMenuItem(
                    value: c,
                    child: Row(
                      children: [
                        Icon(_getExpenseCategoryIcon(c), size: 20, color: Colors.red),
                        const SizedBox(width: 8),
                        Text(c.displayName),
                      ],
                    ),
                  )).toList(),
                  onChanged: (v) => setDialogState(() => selectedCategory = v!),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Description *',
                    prefixIcon: Icon(Icons.description),
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: receiptController,
                  decoration: const InputDecoration(
                    labelText: 'Receipt Number (optional)',
                    prefixIcon: Icon(Icons.receipt_long),
                    border: OutlineInputBorder(),
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
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                final amount = double.tryParse(amountController.text);
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid amount')),
                  );
                  return;
                }
                if (descController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a description')),
                  );
                  return;
                }
                Navigator.pop(context, {
                  'amount': amount,
                  'category': selectedCategory,
                  'description': descController.text,
                  'receipt': receiptController.text.isEmpty ? null : receiptController.text,
                });
              },
              icon: const Icon(Icons.check),
              label: const Text('Record'),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _recordPurchase() async {
    if (_currentShift == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please open a shift first'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    final employee = await _verifyEmployee();
    if (employee == null) return;
    
    final result = await PurchasePaymentEntryDialog.show(
      context,
      financialShiftId: _currentShift!.id,
    );
    if (result == null) return;
    
    setState(() => _isProcessing = true);
    
    try {
      await _financialService.recordExpense(
        financialShiftId: _currentShift!.id,
        amount: result['amount'] as double,
        category: ExpenseCategory.supplies,
        description: result['description'] as String,
        receiptNumber: result['invoiceNumber'] as String?,
        recordedBy: employee.id,
      );
      
      LoggingService.instance.info(
        'PublicShift',
        '[PURCHASE_RECORDED] Employee ${employee.employeeCode} recorded purchase ${result['amount']} EGP via kiosk',
      );
      
      await _refreshShiftData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('Purchase recorded: ${_currencyFormat.format(result['amount'])} EGP'),
              ],
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error recording purchase: $e'), backgroundColor: Colors.red),
        );
      }
    }
    
    if (mounted) setState(() => _isProcessing = false);
  }
  
  Future<void> _recordCollection() async {
    if (_currentShift == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please open a shift first'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    final employee = await _verifyEmployee();
    if (employee == null) return;
    
    final result = await DebtCollectionDialog.show(
      context,
      financialShiftId: _currentShift!.id,
    );
    if (result == null) return;
    
    setState(() => _isProcessing = true);
    
    try {
      await _financialService.recordSale(
        financialShiftId: _currentShift!.id,
        amount: result['amount'] as double,
        paymentMethod: PaymentMethod.credit,
        description: result['description'] as String?,
        customerName: result['customerName'] as String?,
        invoiceNumber: result['reference'] as String?,
        recordedBy: employee.id,
      );
      
      LoggingService.instance.info(
        'PublicShift',
        '[COLLECTION_RECORDED] Employee ${employee.employeeCode} recorded collection ${result['amount']} EGP via kiosk',
      );
      
      await _refreshShiftData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('Collection recorded: ${_currencyFormat.format(result['amount'])} EGP'),
              ],
            ),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error recording collection: $e'), backgroundColor: Colors.red),
        );
      }
    }
    
    if (mounted) setState(() => _isProcessing = false);
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // SMART WARNINGS (>40% expenses, no sales 2h, negative balance)
  // ═══════════════════════════════════════════════════════════════════════════
  
  List<_SmartAlert> _getSmartAlerts() {
    if (_shiftSummary == null || _currentShift == null) return [];
    
    final alerts = <_SmartAlert>[];
    final shiftDuration = DateTime.now().difference(_currentShift!.openedAt);
    
    // No sales after 2 hours
    if (_sales.isEmpty && shiftDuration.inHours >= 2) {
      alerts.add(_SmartAlert(
        type: _AlertType.warning,
        title: 'No Sales',
        message: 'No sales recorded in ${shiftDuration.inHours}h',
        icon: Icons.trending_flat,
      ));
    }
    
    // High expenses (>40% of sales)
    if (_shiftSummary!.totalSales > 0) {
      final expenseRatio = _shiftSummary!.totalExpenses / _shiftSummary!.totalSales;
      if (expenseRatio > 0.4) {
        alerts.add(_SmartAlert(
          type: _AlertType.warning,
          title: 'High Expenses',
          message: 'Expenses are ${(expenseRatio * 100).toStringAsFixed(0)}% of sales',
          icon: Icons.trending_down,
        ));
      }
    }
    
    // Negative balance
    if (_shiftSummary!.expectedCash < 0) {
      alerts.add(_SmartAlert(
        type: _AlertType.error,
        title: 'Negative Balance',
        message: '${_currencyFormat.format(_shiftSummary!.expectedCash)} EGP',
        icon: Icons.warning,
      ));
    }
    
    return alerts;
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // UI BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/kiosk'),
          tooltip: 'Back to Attendance',
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.point_of_sale, color: Colors.green, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Financial Shift'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: const Text(
                'KIOSK',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange),
              ),
            ),
          ],
        ),
        actions: [
          // Session indicator
          if (_hasActiveSession) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person, size: 14, color: Colors.green),
                  const SizedBox(width: 4),
                  Text(
                    _currentEmployee!.employeeCode,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                ],
              ),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading || _isProcessing ? null : _loadCurrentShift,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingView()
          : _loadError != null
              ? _buildErrorView()
              : _isProcessing
                  ? _buildProcessingOverlay(child: _buildMainContent())
                  : _buildMainContent(),
    );
  }
  
  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('Loading shift data...', style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }
  
  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline, size: 48, color: Colors.red),
            ),
            const SizedBox(height: 24),
            Text(
              'Error Loading Shift',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadCurrentShift,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildProcessingOverlay({required Widget child}) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(0.3),
            child: const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Processing...'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildMainContent() {
    if (_currentShift == null) {
      return _buildNoShiftView();
    }
    return _buildShiftView();
  }
  
  Widget _buildNoShiftView() {
    return Center(
      child: Card(
        margin: const EdgeInsets.all(32),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.point_of_sale, size: 56, color: AppTheme.primaryColor),
              ),
              const SizedBox(height: 24),
              Text(
                'No Open Shift',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Start a new shift to record sales and expenses',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _openShift,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Open Shift'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildShiftView() {
    return Column(
      children: [
        // Financial Summary
        _buildFinancialSummary(),
        
        // Smart Alerts
        ..._buildSmartAlertsWidgets(),
        
        // Quick Actions
        _buildQuickActions(),
        
        // Timeline (scrollable)
        Expanded(
          child: _buildTimeline(),
        ),
      ],
    );
  }
  
  Widget _buildFinancialSummary() {
    if (_shiftSummary == null) return const SizedBox.shrink();
    
    final openingCash = _currentShift?.openingCash ?? 0;
    final cashSales = _shiftSummary!.cashSales;
    final purchasePayments = _shiftSummary!.expensesByCategory[ExpenseCategory.supplies] ?? 0;
    final otherExpenses = _shiftSummary!.totalExpenses - purchasePayments;
    final currentBalance = _shiftSummary!.expectedCash;
    
    final duration = DateTime.now().difference(_currentShift!.openedAt);
    final durationText = duration.inHours > 0 
        ? '${duration.inHours}h ${duration.inMinutes % 60}m'
        : '${duration.inMinutes}m';
    
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor.withOpacity(0.1),
            Colors.green.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.play_circle, color: Colors.green, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Shift: ${_timeFormat.format(_currentShift!.openedAt)}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      Text(
                        'Duration: $durationText',
                        style: TextStyle(color: Colors.grey[600], fontSize: 11),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _closeShift,
                  icon: const Icon(Icons.stop_circle, size: 16),
                  label: const Text('Close'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.withOpacity(0.15),
                    foregroundColor: Colors.orange[700],
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
              ],
            ),
          ),
          
          // Summary Grid
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _buildSummaryCard('Opening', openingCash, Icons.account_balance_wallet, Colors.blue)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildSummaryCard('+ Sales', cashSales, Icons.trending_up, Colors.green)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildSummaryCard('- Purchases', purchasePayments, Icons.inventory_2, Colors.orange)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildSummaryCard('- Expenses', otherExpenses, Icons.receipt_long, Colors.red)),
                  ],
                ),
                const SizedBox(height: 12),
                // Balance
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: currentBalance >= 0 ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: currentBalance >= 0 ? Colors.green : Colors.red,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        currentBalance >= 0 ? Icons.account_balance : Icons.warning,
                        color: currentBalance >= 0 ? Colors.green : Colors.red,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Balance',
                            style: TextStyle(
                              color: currentBalance >= 0 ? Colors.green[700] : Colors.red[700],
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            '${_currencyFormat.format(currentBalance)} EGP',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: currentBalance >= 0 ? Colors.green[700] : Colors.red[700],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSummaryCard(String label, double value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 10, color: color)),
                Text(
                  '${_currencyFormat.format(value)}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  List<Widget> _buildSmartAlertsWidgets() {
    final alerts = _getSmartAlerts();
    if (alerts.isEmpty) return [];
    
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: alerts.map((alert) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _getAlertColor(alert.type).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _getAlertColor(alert.type).withOpacity(0.5)),
            ),
            child: Row(
              children: [
                Icon(alert.icon, color: _getAlertColor(alert.type), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _getAlertColor(alert.type),
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        alert.message,
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )).toList(),
        ),
      ),
    ];
  }
  
  Color _getAlertColor(_AlertType type) {
    switch (type) {
      case _AlertType.error: return Colors.red;
      case _AlertType.warning: return Colors.orange;
      case _AlertType.info: return Colors.blue;
    }
  }
  
  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: _buildActionButton('Sale', Icons.add_shopping_cart, Colors.green, _recordSale),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildActionButton('Purchase', Icons.inventory_2, Colors.orange, _recordPurchase),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildActionButton('Expense', Icons.receipt_long, Colors.red, _recordExpense),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildActionButton('Collection', Icons.payments, Colors.teal, _recordCollection),
          ),
        ],
      ),
    );
  }
  
  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onPressed) {
    return OutlinedButton.icon(
      onPressed: _isProcessing ? null : onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }
  
  Widget _buildTimeline() {
    if (_timeline.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timeline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('No transactions yet', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _timeline.length,
      itemBuilder: (context, index) {
        final item = _timeline[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: item.color.withOpacity(0.2),
              child: Icon(item.icon, color: item.color, size: 20),
            ),
            title: Text(
              '${item.isCashOut ? "-" : "+"}${_currencyFormat.format(item.amount)} EGP',
              style: TextStyle(fontWeight: FontWeight.bold, color: item.color),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.description),
                if (item.subtitle != null)
                  Text(item.subtitle!, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
            trailing: Text(
              _timeFormat.format(item.time),
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ),
        );
      },
    );
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // HELPER METHODS
  // ═══════════════════════════════════════════════════════════════════════════
  
  IconData _getPaymentMethodIcon(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash: return Icons.payments;
      case PaymentMethod.card: return Icons.credit_card;
      case PaymentMethod.wallet: return Icons.account_balance_wallet;
      case PaymentMethod.insurance: return Icons.health_and_safety;
      case PaymentMethod.credit: return Icons.receipt_long;
    }
  }
  
  Color _getPaymentMethodColor(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash: return Colors.green;
      case PaymentMethod.card: return Colors.blue;
      case PaymentMethod.wallet: return Colors.orange;
      case PaymentMethod.insurance: return Colors.purple;
      case PaymentMethod.credit: return Colors.teal;
    }
  }
  
  IconData _getExpenseCategoryIcon(ExpenseCategory category) {
    switch (category) {
      case ExpenseCategory.utilities: return Icons.bolt;
      case ExpenseCategory.supplies: return Icons.inventory;
      case ExpenseCategory.maintenance: return Icons.build;
      case ExpenseCategory.shortage: return Icons.warning;
      case ExpenseCategory.emergency: return Icons.emergency;
      case ExpenseCategory.transport: return Icons.local_shipping;
      case ExpenseCategory.staff: return Icons.people;
      case ExpenseCategory.misc: return Icons.more_horiz;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER CLASSES
// ═══════════════════════════════════════════════════════════════════════════

enum _TimelineType { sale, expense, purchase, debtCollection }

class _TimelineItem {
  final _TimelineType type;
  final double amount;
  final String description;
  final DateTime time;
  final IconData icon;
  final Color color;
  final String? subtitle;
  
  _TimelineItem({
    required this.type,
    required this.amount,
    required this.description,
    required this.time,
    required this.icon,
    required this.color,
    this.subtitle,
  });
  
  bool get isCashOut => type == _TimelineType.expense || type == _TimelineType.purchase;
}

enum _AlertType { error, warning, info }

class _SmartAlert {
  final _AlertType type;
  final String title;
  final String message;
  final IconData icon;
  
  _SmartAlert({
    required this.type,
    required this.title,
    required this.message,
    required this.icon,
  });
}
