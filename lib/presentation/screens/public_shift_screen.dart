import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/financial_service.dart';
import '../../core/services/logging_service.dart';
import '../../core/services/notifications_service.dart';
import '../../core/services/safe_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/financial_shift_model.dart';
import '../../data/models/shift_model.dart';
import '../../data/models/shift_sale_model.dart';
import '../../data/models/shift_expense_model.dart';
import '../../data/models/employee_model.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/shift_repository.dart';
import '../widgets/purchase_payment_entry_dialog.dart';
import '../widgets/debt_collection_dialog.dart';

/// Public Financial Shift Screen - Kiosk Mode
/// 
/// SCHEDULE-DRIVEN ARCHITECTURE:
/// - Automatically detects current scheduled shift on load
/// - Only scheduled employees can operate (others view-only)
/// - Financial shift is linked to scheduled shift
/// - Prevents duplicate shift opening
/// 
/// DRAWER/SAFE MODEL:
/// - Drawer starts at 0 each shift (opening cash is change float)
/// - Cash sales go to Drawer during shift
/// - On close: Drawer cash transfers to Safe, drawer resets to 0
/// - Supplier payments and debt settlements come from Safe only
/// 
/// STABILITY:
/// - All async operations have loading/error states
/// - No null crashes - all values have fallbacks
/// - Processing overlay prevents duplicate actions
/// - Comprehensive audit logging
class PublicShiftScreen extends StatefulWidget {
  const PublicShiftScreen({super.key});

  @override
  State<PublicShiftScreen> createState() => _PublicShiftScreenState();
}

class _PublicShiftScreenState extends State<PublicShiftScreen> with WidgetsBindingObserver {
  // Services
  final _financialService = FinancialService.instance;
  final _employeeRepo = EmployeeRepository.instance;
  final _shiftRepo = ShiftRepository.instance;
  final _notificationsService = NotificationsService.instance;
  final _safeService = SafeService.instance;
  
  // ═══════════════════════════════════════════════════════════════════════════
  // STATE VARIABLES
  // ═══════════════════════════════════════════════════════════════════════════
  
  // Loading states
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _loadError;
  
  // Session management
  Employee? _currentEmployee;
  DateTime? _sessionExpiresAt;
  Timer? _sessionTimer;
  static const _sessionDurationMinutes = 5;
  
  // Schedule context (detected on load)
  Shift? _currentScheduledShift;
  List<Map<String, String>> _scheduledEmployees = [];
  bool _isEmployeeScheduled = false;
  
  // Financial data
  FinancialShift? _currentFinancialShift;
  ShiftSummary? _shiftSummary;
  ShiftCashFlowSummary? _cashFlowSummary;
  List<ShiftSale> _sales = [];
  List<ShiftExpense> _expenses = [];
  List<_TimelineItem> _timeline = [];
  double _safeBalance = 0;
  
  // Employee code entry
  final _codeController = TextEditingController();
  
  // Formatters
  final _currencyFormat = NumberFormat.currency(symbol: '', decimalDigits: 2);
  final _timeFormat = DateFormat('hh:mm a');
  final _dateFormat = DateFormat('dd MMM yyyy');
  
  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeScreen();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAutoClose();
      _refreshAllData();
    }
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// Initialize screen - detect schedule context and load data
  Future<void> _initializeScreen() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    
    try {
      // Step 1: Detect current scheduled shift
      await _detectScheduleContext();
      
      // Step 2: Load Safe balance
      _safeBalance = await _safeService.getCurrentBalance();
      
      // Step 3: Check for open financial shift
      await _loadCurrentFinancialShift();
      
      // Step 4: Check for auto-close if shift is open too long
      if (_currentFinancialShift != null) {
        await _checkAutoClose();
      }
      
      LoggingService.instance.info(
        'PublicShift',
        '[INIT] Screen initialized. Schedule: ${_currentScheduledShift?.name ?? "None"}, '
        'Shift open: ${_currentFinancialShift != null}, Safe: $_safeBalance',
      );
    } catch (e, stack) {
      LoggingService.instance.error('PublicShift', 'Initialization error', e, stack);
      if (mounted) {
        setState(() => _loadError = 'Failed to initialize: ${e.toString()}');
      }
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
  
  /// Detect current scheduled shift context
  Future<void> _detectScheduleContext() async {
    try {
      final now = DateTime.now();
      final currentTime = TimeOfDay.fromDateTime(now);
      
      // Get current scheduled shift based on time
      _currentScheduledShift = await _shiftRepo.getCurrentShift('1', currentTime);
      
      // Get scheduled employees for this shift
      if (_currentScheduledShift != null) {
        _scheduledEmployees = await _shiftRepo.getScheduledEmployeesWithDetails('1');
      } else {
        _scheduledEmployees = [];
      }
      
      LoggingService.instance.info(
        'PublicShift',
        '[SCHEDULE_DETECT] Current shift: ${_currentScheduledShift?.name ?? "None"}, '
        'Scheduled employees: ${_scheduledEmployees.length}',
      );
    } catch (e) {
      LoggingService.instance.warning('PublicShift', 'Failed to detect schedule: $e');
      _currentScheduledShift = null;
      _scheduledEmployees = [];
    }
  }
  
  /// Load current financial shift and related data
  Future<void> _loadCurrentFinancialShift() async {
    final openShifts = await _financialService.getOpenShiftsForBranch();
    
    if (openShifts.isNotEmpty) {
      _currentFinancialShift = openShifts.first;
      await _refreshShiftData();
    } else {
      _currentFinancialShift = null;
      _shiftSummary = null;
      _cashFlowSummary = null;
      _sales = [];
      _expenses = [];
      _timeline = [];
    }
  }
  
  /// Refresh all data
  Future<void> _refreshAllData() async {
    if (_isProcessing) return;
    
    setState(() => _isLoading = true);
    
    try {
      await _detectScheduleContext();
      _safeBalance = await _safeService.getCurrentBalance();
      await _loadCurrentFinancialShift();
    } catch (e) {
      LoggingService.instance.error('PublicShift', 'Refresh error', e, StackTrace.current);
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
  
  /// Refresh shift-specific data (sales, expenses, summary)
  Future<void> _refreshShiftData() async {
    if (_currentFinancialShift == null) return;
    
    try {
      _shiftSummary = await _financialService.getShiftSummary(_currentFinancialShift!.id);
      _cashFlowSummary = await _financialService.getShiftCashFlowSummary(_currentFinancialShift!.id);
      _sales = await _financialService.getSalesForShift(_currentFinancialShift!.id);
      _expenses = await _financialService.getExpensesForShift(_currentFinancialShift!.id);
      _safeBalance = await _safeService.getCurrentBalance();
      _buildTimeline();
      
      if (mounted) setState(() {});
    } catch (e) {
      LoggingService.instance.error('PublicShift', 'Error refreshing shift data', e, StackTrace.current);
    }
  }
  
  /// Build timeline from sales and expenses
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
    if (_currentFinancialShift == null) return;
    
    final shiftAge = DateTime.now().difference(_currentFinancialShift!.openedAt);
    if (shiftAge.inHours >= 24) {
      LoggingService.instance.warning(
        'PublicShift',
        '[AUTO_CLOSE] Shift has been open for ${shiftAge.inHours}h, auto-closing',
      );
      
      try {
        final expectedCash = _shiftSummary?.expectedCash ?? 0;
        await _financialService.closeShift(
          financialShiftId: _currentFinancialShift!.id,
          actualCash: expectedCash,
          closedBy: 'SYSTEM_AUTO_CLOSE',
          differenceReason: 'Auto-closed after 24 hours',
          notes: 'Automatic closure due to shift exceeding 24 hours',
          source: 'system',
        );
        
        await _refreshAllData();
        
        if (mounted) {
          _showSnackBar(
            'Previous shift was auto-closed after 24 hours',
            Colors.orange,
            duration: const Duration(seconds: 5),
          );
        }
      } catch (e) {
        LoggingService.instance.error('PublicShift', 'Auto-close failed', e, StackTrace.current);
      }
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
    
    // Check if employee is scheduled
    _isEmployeeScheduled = _scheduledEmployees.any((e) => e['id'] == employee.id);
    
    _sessionTimer?.cancel();
    _sessionTimer = Timer(const Duration(minutes: _sessionDurationMinutes), () {
      if (mounted) {
        setState(() {
          _currentEmployee = null;
          _sessionExpiresAt = null;
          _isEmployeeScheduled = false;
        });
        _showSnackBar('Session expired. Please enter your code again.', Colors.orange);
      }
    });
    
    LoggingService.instance.info(
      'PublicShift',
      '[SESSION_START] Employee ${employee.employeeCode} started session. '
      'Scheduled: $_isEmployeeScheduled',
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
    _isEmployeeScheduled = false;
    if (mounted) setState(() {});
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // EMPLOYEE VERIFICATION
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// Verify employee for operations
  /// Returns null if verification failed or cancelled
  Future<Employee?> _verifyEmployee({bool requireScheduled = false}) async {
    if (_hasActiveSession) {
      _extendSession();
      
      // Check if scheduled employee is required
      if (requireScheduled && !_isEmployeeScheduled && _currentScheduledShift != null) {
        final confirmed = await _showUnscheduledAccessDialog(_currentEmployee!);
        if (confirmed != true) return null;
      }
      
      return _currentEmployee;
    }
    
    return await _showEmployeeCodeDialog(requireScheduled: requireScheduled);
  }
  
  /// Show employee code verification dialog
  Future<Employee?> _showEmployeeCodeDialog({bool requireScheduled = false}) async {
    _codeController.clear();
    
    final result = await showDialog<Employee>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
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
              
              // Check if employee is scheduled (when required)
              final isScheduled = _scheduledEmployees.any((e) => e['id'] == employee.id);
              
              if (requireScheduled && !isScheduled && _currentScheduledShift != null) {
                // Show warning but allow with confirmation
                setDialogState(() => isVerifying = false);
                
                // Close current dialog first
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
                
                // Show unscheduled access warning dialog
                final confirmed = await _showUnscheduledAccessDialog(employee);
                if (confirmed == true) {
                  _startSession(employee);
                  // The showDialog already returned null since we popped it.
                  // The employee is now in _currentEmployee via _startSession.
                  // Caller should check _currentEmployee if result is null.
                }
                return;
              }
              
              _startSession(employee);
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext, employee);
              }
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
                // Show schedule info
                if (_currentScheduledShift != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.schedule, color: Colors.blue, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Current Shift: ${_currentScheduledShift!.name}',
                            style: const TextStyle(fontSize: 12, color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No scheduled shift detected',
                            style: TextStyle(fontSize: 12, color: Colors.orange),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer, color: Colors.grey, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Session lasts $_sessionDurationMinutes minutes',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isVerifying ? null : () => Navigator.pop(dialogContext),
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
    
    // If result is null, check if employee was set via _startSession
    // (happens when unscheduled employee confirms access)
    if (result == null && _currentEmployee != null && _hasActiveSession) {
      return _currentEmployee;
    }
    
    return result;
  }
  
  /// Show dialog when unscheduled employee tries to access
  Future<bool?> _showUnscheduledAccessDialog(Employee employee) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.warning_amber, color: Colors.orange),
            ),
            const SizedBox(width: 12),
            const Text('Not Scheduled'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${employee.fullName} is not scheduled for "${_currentScheduledShift?.name ?? "current shift"}".',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action will be logged for admin review.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Do you want to continue?',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              // Log unscheduled access
              LoggingService.instance.audit(
                'PublicShift',
                'UNSCHEDULED_ACCESS',
                '[SCHEDULE_CHECK] Unscheduled employee accessing shift',
                details: {
                  'employee_id': employee.id,
                  'employee_code': employee.employeeCode,
                  'employee_name': employee.fullName,
                  'scheduled_shift': _currentScheduledShift?.name,
                  'timestamp': DateTime.now().toIso8601String(),
                },
              );
              
              _notificationsService.addSmartWarning(
                title: 'Unscheduled Access',
                message: '${employee.fullName} accessed shift outside schedule',
                severity: NotificationSeverity.warning,
              );
              
              // Note: _startSession is called by the caller after this dialog returns true
              Navigator.pop(context, true);
            },
            child: const Text('Continue Anyway'),
          ),
        ],
      ),
    );
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // SHIFT OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// Open a new financial shift
  Future<void> _openShift() async {
    // Prevent duplicate shift
    if (_currentFinancialShift != null) {
      _showSnackBar('A shift is already open. Close it first.', Colors.orange);
      return;
    }
    
    // Verify employee (require scheduled for opening)
    final employee = await _verifyEmployee(requireScheduled: true);
    if (employee == null) return;
    
    // Log schedule check
    LoggingService.instance.info(
      'PublicShift',
      '[SCHEDULE_CHECK] Employee ${employee.employeeCode} attempting to open shift. '
      'Scheduled: $_isEmployeeScheduled, Shift: ${_currentScheduledShift?.name}',
    );
    
    // Get opening cash (change float)
    final openingCash = await _showOpeningCashDialog();
    if (openingCash == null) return;
    
    setState(() => _isProcessing = true);
    
    try {
      // Build notes with schedule context
      final notesParts = <String>[
        'Opened from kiosk by ${employee.fullName}',
        if (_currentScheduledShift != null)
          'Scheduled: ${_currentScheduledShift!.name} (${_currentScheduledShift!.timeRange})',
        if (!_isEmployeeScheduled && _currentScheduledShift != null)
          'WARNING: Employee not scheduled',
        '[DRAWER_START] Drawer initialized with ${openingCash.toStringAsFixed(2)} EGP change float',
      ];
      
      _currentFinancialShift = await _financialService.openShift(
        employeeId: employee.id,
        employeeName: employee.fullName,
        shiftId: _currentScheduledShift?.id,
        scheduledShiftId: _currentScheduledShift?.id,
        scheduledShiftName: _currentScheduledShift?.name,
        openingCash: openingCash,
        notes: notesParts.join('. '),
      );
      
      LoggingService.instance.audit(
        'PublicShift',
        'SHIFT_OPENED',
        '[DRAWER_START] [SCHEDULE_CHECK] Shift opened',
        details: {
          'shift_id': _currentFinancialShift!.id,
          'employee_id': employee.id,
          'employee_code': employee.employeeCode,
          'employee_name': employee.fullName,
          'opening_cash': openingCash,
          'drawer_initial_balance': 0,
          'change_float': openingCash,
          'scheduled_shift_id': _currentScheduledShift?.id,
          'scheduled_shift_name': _currentScheduledShift?.name,
          'is_scheduled': _isEmployeeScheduled,
          'source': 'kiosk',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      
      await _refreshShiftData();
      
      _showSnackBar('Shift opened by ${employee.fullName}', Colors.green);
    } catch (e) {
      LoggingService.instance.error('PublicShift', 'Error opening shift', e, StackTrace.current);
      _showSnackBar('Error opening shift: $e', Colors.red);
    }
    
    if (mounted) setState(() => _isProcessing = false);
  }
  
  /// Close the current financial shift
  Future<void> _closeShift() async {
    if (_currentFinancialShift == null) {
      _showSnackBar('No shift is currently open', Colors.orange);
      return;
    }
    
    // Verify employee
    final employee = await _verifyEmployee();
    if (employee == null) return;
    
    // Get Safe balance for display
    final safeBalanceBefore = await _safeService.getCurrentBalance();
    
    // Show close dialog with all details
    final result = await _showCloseShiftDialog(safeBalanceBefore: safeBalanceBefore);
    if (result == null) return;
    
    setState(() => _isProcessing = true);
    
    try {
      final actualCash = result['actualCash'] as double;
      
      // Close shift - this transfers to Safe and resets drawer
      final closure = await _financialService.closeShift(
        financialShiftId: _currentFinancialShift!.id,
        actualCash: actualCash,
        closedBy: employee.id,
        differenceReason: result['reason'] as String?,
        notes: 'Closed from kiosk by ${employee.fullName}',
        source: 'kiosk',
      );
      
      final difference = actualCash - (_shiftSummary?.expectedCash ?? 0);
      
      // Log Safe transfer
      LoggingService.instance.audit(
        'PublicShift',
        'SAFE_TRANSFER',
        '[SAFE_TRANSFER] Transferred ${closure.transferredToSafe.toStringAsFixed(2)} EGP from Drawer to Safe',
        details: {
          'shift_id': _currentFinancialShift!.id,
          'employee_id': employee.id,
          'transferred_amount': closure.transferredToSafe,
          'safe_balance_before': closure.safeBalanceBefore,
          'safe_balance_after': closure.safeBalanceAfter,
          'payment_source': 'drawer_to_safe',
          'source': 'kiosk',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      
      // Log drawer reset
      LoggingService.instance.audit(
        'PublicShift',
        'DRAWER_RESET',
        '[DRAWER_RESET] Drawer reset to 0 after shift close',
        details: {
          'shift_id': _currentFinancialShift!.id,
          'employee_id': employee.id,
          'drawer_final_cash': actualCash,
          'drawer_reset_to': 0,
          'expected_cash': _shiftSummary?.expectedCash,
          'difference': difference,
          'source': 'kiosk',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      
      // Log shift closure
      LoggingService.instance.audit(
        'PublicShift',
        'SHIFT_CLOSED',
        'Shift closed successfully',
        details: {
          'shift_id': _currentFinancialShift!.id,
          'employee_id': employee.id,
          'employee_code': employee.employeeCode,
          'actual_cash': actualCash,
          'expected_cash': _shiftSummary?.expectedCash,
          'difference': difference,
          'difference_reason': result['reason'],
          'total_sales': closure.totalSales,
          'total_expenses': closure.totalExpenses,
          'safe_balance_before': closure.safeBalanceBefore,
          'safe_balance_after': closure.safeBalanceAfter,
          'transferred_to_safe': closure.transferredToSafe,
          'source': 'kiosk',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      
      _showSnackBar(
        'Shift closed. ${closure.transferredToSafe.toStringAsFixed(2)} EGP transferred to Safe.',
        Colors.green,
        duration: const Duration(seconds: 4),
      );
      
      // Reset state
      _currentFinancialShift = null;
      _shiftSummary = null;
      _cashFlowSummary = null;
      _sales = [];
      _expenses = [];
      _timeline = [];
      _safeBalance = await _safeService.getCurrentBalance();
    } catch (e) {
      LoggingService.instance.error('PublicShift', 'Error closing shift', e, StackTrace.current);
      _showSnackBar('Error closing shift: $e', Colors.red);
    }
    
    if (mounted) setState(() => _isProcessing = false);
  }
  
  /// Show opening cash dialog
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
                color: Colors.green.withOpacity(0.1),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Schedule context
            if (_currentScheduledShift != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _currentScheduledShift!.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                          ),
                          Text(
                            _currentScheduledShift!.timeRange,
                            style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            // Safe balance display
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lock, size: 18, color: Colors.grey),
                      SizedBox(width: 8),
                      Text('Safe Balance:'),
                    ],
                  ),
                  Text(
                    '${_currencyFormat.format(_safeBalance)} EGP',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            const Text('Enter the change float for the drawer:'),
            const SizedBox(height: 8),
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
                helperText: 'Drawer starts at 0, this is the change float',
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
  
  /// Show close shift dialog with comprehensive summary
  Future<Map<String, dynamic>?> _showCloseShiftDialog({double safeBalanceBefore = 0}) async {
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Shift info
                if (_currentFinancialShift?.scheduledShiftName != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.schedule, size: 16, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          _currentFinancialShift!.scheduledShiftName!,
                          style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                
                // Drawer Summary
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Drawer Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 8),
                      _buildDialogRow('Opening Cash (Float)', _currentFinancialShift?.openingCash ?? 0, Icons.account_balance_wallet),
                      _buildDialogRow('+ Cash Sales', _shiftSummary?.cashSales ?? 0, Icons.add_circle, color: Colors.green),
                      _buildDialogRow('- Expenses', _shiftSummary?.totalExpenses ?? 0, Icons.remove_circle, color: Colors.red),
                      const Divider(height: 20),
                      _buildDialogRow('= Expected in Drawer', expectedCash, Icons.calculate, isBold: true, color: AppTheme.primaryColor),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                
                // Safe Summary
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.lock, size: 16, color: Colors.blue),
                          SizedBox(width: 6),
                          Text('Safe (Vault)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Current Balance:', style: TextStyle(fontSize: 12)),
                          Text(
                            '${_currencyFormat.format(safeBalanceBefore)} EGP',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ],
                      ),
                      if (enteredCash != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('After Transfer:', style: TextStyle(fontSize: 12)),
                            Text(
                              '${_currencyFormat.format(safeBalanceBefore + enteredCash!)} EGP',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Actual cash input
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
                    helperText: 'This amount will be transferred to Safe',
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
                
                // Drawer reset notice
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Drawer will be reset to 0 after closing. Cash transfers to Safe.',
                          style: TextStyle(fontSize: 11, color: Colors.orange),
                        ),
                      ),
                    ],
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
  
  Widget _buildDialogRow(String label, double value, IconData icon, {bool isBold = false, Color? color}) {
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
  
  /// Record a sale
  Future<void> _recordSale() async {
    if (_currentFinancialShift == null) {
      _showSnackBar('Please open a shift first', Colors.orange);
      return;
    }
    
    final employee = await _verifyEmployee();
    if (employee == null) return;
    
    final result = await _showSaleDialog();
    if (result == null) return;
    
    setState(() => _isProcessing = true);
    
    try {
      await _financialService.recordSale(
        financialShiftId: _currentFinancialShift!.id,
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
      
      _showSnackBar('Sale recorded: ${_currencyFormat.format(result['amount'])} EGP', Colors.green);
    } catch (e) {
      _showSnackBar('Error recording sale: $e', Colors.red);
    }
    
    if (mounted) setState(() => _isProcessing = false);
  }
  
  /// Show sale dialog
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
  
  /// Record an expense
  Future<void> _recordExpense() async {
    if (_currentFinancialShift == null) {
      _showSnackBar('Please open a shift first', Colors.orange);
      return;
    }
    
    final employee = await _verifyEmployee();
    if (employee == null) return;
    
    final result = await _showExpenseDialog();
    if (result == null) return;
    
    setState(() => _isProcessing = true);
    
    try {
      await _financialService.recordExpense(
        financialShiftId: _currentFinancialShift!.id,
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
      
      _showSnackBar('Expense recorded: ${_currencyFormat.format(result['amount'])} EGP', Colors.orange);
    } catch (e) {
      _showSnackBar('Error recording expense: $e', Colors.red);
    }
    
    if (mounted) setState(() => _isProcessing = false);
  }
  
  /// Show expense dialog
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
                      .where((c) => c != ExpenseCategory.supplies)
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
  
  /// Record a purchase
  Future<void> _recordPurchase() async {
    if (_currentFinancialShift == null) {
      _showSnackBar('Please open a shift first', Colors.orange);
      return;
    }
    
    final employee = await _verifyEmployee();
    if (employee == null) return;
    
    final result = await PurchasePaymentEntryDialog.show(
      context,
      financialShiftId: _currentFinancialShift!.id,
    );
    if (result == null) return;
    
    setState(() => _isProcessing = true);
    
    try {
      await _financialService.recordExpense(
        financialShiftId: _currentFinancialShift!.id,
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
      
      _showSnackBar('Purchase recorded: ${_currencyFormat.format(result['amount'])} EGP', Colors.orange);
    } catch (e) {
      _showSnackBar('Error recording purchase: $e', Colors.red);
    }
    
    if (mounted) setState(() => _isProcessing = false);
  }
  
  /// Record a debt collection
  Future<void> _recordCollection() async {
    if (_currentFinancialShift == null) {
      _showSnackBar('Please open a shift first', Colors.orange);
      return;
    }
    
    final employee = await _verifyEmployee();
    if (employee == null) return;
    
    final result = await DebtCollectionDialog.show(
      context,
      financialShiftId: _currentFinancialShift!.id,
    );
    if (result == null) return;
    
    setState(() => _isProcessing = true);
    
    try {
      await _financialService.recordSale(
        financialShiftId: _currentFinancialShift!.id,
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
      
      _showSnackBar('Collection recorded: ${_currencyFormat.format(result['amount'])} EGP', Colors.teal);
    } catch (e) {
      _showSnackBar('Error recording collection: $e', Colors.red);
    }
    
    if (mounted) setState(() => _isProcessing = false);
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // SMART WARNINGS
  // ═══════════════════════════════════════════════════════════════════════════
  
  List<_SmartAlert> _getSmartAlerts() {
    if (_shiftSummary == null || _currentFinancialShift == null) return [];
    
    final alerts = <_SmartAlert>[];
    final shiftDuration = DateTime.now().difference(_currentFinancialShift!.openedAt);
    
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
    
    // Purchases exceed sales
    final purchases = _shiftSummary!.expensesByCategory[ExpenseCategory.supplies] ?? 0;
    if (purchases > _shiftSummary!.totalSales && _shiftSummary!.totalSales > 0) {
      alerts.add(_SmartAlert(
        type: _AlertType.warning,
        title: 'High Purchases',
        message: 'Purchases exceed sales by ${_currencyFormat.format(purchases - _shiftSummary!.totalSales)} EGP',
        icon: Icons.inventory_2,
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
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }
  
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
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
              color: _isEmployeeScheduled 
                  ? Colors.green.withOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isEmployeeScheduled 
                    ? Colors.green.withOpacity(0.3)
                    : Colors.orange.withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.person, 
                  size: 14, 
                  color: _isEmployeeScheduled ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 4),
                Text(
                  _currentEmployee!.employeeCode,
                  style: TextStyle(
                    fontSize: 11, 
                    fontWeight: FontWeight.bold, 
                    color: _isEmployeeScheduled ? Colors.green : Colors.orange,
                  ),
                ),
                if (!_isEmployeeScheduled) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.warning_amber, size: 12, color: Colors.orange),
                ],
              ],
            ),
          ),
        ],
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _isLoading || _isProcessing ? null : _refreshAllData,
          tooltip: 'Refresh',
        ),
      ],
    );
  }
  
  Widget _buildBody() {
    if (_isLoading) {
      return _buildLoadingView();
    }
    
    if (_loadError != null) {
      return _buildErrorView();
    }
    
    if (_isProcessing) {
      return _buildProcessingOverlay(child: _buildMainContent());
    }
    
    return _buildMainContent();
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
              'Error Loading Data',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              _loadError ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _initializeScreen,
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
    return Column(
      children: [
        // Schedule context header
        _buildScheduleHeader(),
        
        // Main content
        Expanded(
          child: _currentFinancialShift == null
              ? _buildNoShiftView()
              : _buildShiftView(),
        ),
      ],
    );
  }
  
  /// Build schedule context header
  Widget _buildScheduleHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _currentScheduledShift != null
            ? Colors.blue.withOpacity(0.05)
            : Colors.orange.withOpacity(0.05),
        border: Border(
          bottom: BorderSide(
            color: _currentScheduledShift != null
                ? Colors.blue.withOpacity(0.2)
                : Colors.orange.withOpacity(0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          // Shift info
          Icon(
            Icons.schedule,
            size: 18,
            color: _currentScheduledShift != null ? Colors.blue : Colors.orange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _currentScheduledShift != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentScheduledShift!.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        _currentScheduledShift!.timeRange,
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  )
                : const Text(
                    'No scheduled shift detected',
                    style: TextStyle(color: Colors.orange, fontSize: 13),
                  ),
          ),
          
          // Scheduled employees count
          if (_scheduledEmployees.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.people, size: 14, color: Colors.blue),
                  const SizedBox(width: 4),
                  Text(
                    '${_scheduledEmployees.length}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                  ),
                ],
              ),
            ),
          ],
          
          // Safe balance
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  '${_currencyFormat.format(_safeBalance)}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
    
    final openingCash = _currentFinancialShift?.openingCash ?? 0;
    final cashSales = _shiftSummary!.cashSales;
    final purchasePayments = _shiftSummary!.expensesByCategory[ExpenseCategory.supplies] ?? 0;
    final otherExpenses = _shiftSummary!.totalExpenses - purchasePayments;
    final currentBalance = _shiftSummary!.expectedCash;
    
    final duration = DateTime.now().difference(_currentFinancialShift!.openedAt);
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
                      Row(
                        children: [
                          Text(
                            'Shift: ${_timeFormat.format(_currentFinancialShift!.openedAt)}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          if (_currentFinancialShift!.scheduledShiftName != null) ...[
                            const Text(' | ', style: TextStyle(color: Colors.grey)),
                            Text(
                              _currentFinancialShift!.scheduledShiftName!,
                              style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                            ),
                          ],
                        ],
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
                            'Expected in Drawer',
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
                  _currencyFormat.format(value),
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
  
  void _showSnackBar(String message, Color color, {Duration duration = const Duration(seconds: 3)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: duration,
      ),
    );
  }
  
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
