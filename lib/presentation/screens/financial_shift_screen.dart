import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/services/financial_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/employee_resolver_service.dart';
import '../../core/services/logging_service.dart';
import '../../core/services/notifications_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/financial_shift_model.dart';
import '../../data/models/shift_sale_model.dart';
import '../../data/models/shift_expense_model.dart';
import '../../data/models/employee_model.dart';
import '../../data/repositories/employee_repository.dart';
import '../widgets/purchase_payment_entry_dialog.dart';
import '../widgets/debt_collection_dialog.dart';

/// Financial Shift Management Screen - Intelligence Dashboard
/// 
/// Features:
/// - Real-time cash flow summary at top (Opening → Sales → Purchases → Expenses → Collections → Balance)
/// - Transaction timeline (all operations chronologically)
/// - Smart alerts (high expenses vs sales, no sales, negative balance)
/// - Professional UX with loading states, error handling, and functional buttons
/// 
/// Example flow:
/// Start 1,000 EGP → +3,500 Sales → -1,200 Purchases → -300 Expenses → +400 Collection = 3,400 EGP
class FinancialShiftScreen extends StatefulWidget {
  const FinancialShiftScreen({super.key});

  @override
  State<FinancialShiftScreen> createState() => _FinancialShiftScreenState();
}

class _FinancialShiftScreenState extends State<FinancialShiftScreen> with SingleTickerProviderStateMixin {
  final _financialService = FinancialService.instance;
  final _authService = AuthService.instance;
  final _employeeResolver = EmployeeResolverService.instance;
  final _employeeRepo = EmployeeRepository.instance;
  final _notificationsService = NotificationsService.instance;
  
  late TabController _tabController;
  
  bool _isLoading = true;
  String? _loadError;
  FinancialShift? _currentShift;
  ShiftSummary? _shiftSummary;
  List<ShiftSale> _sales = [];
  List<ShiftExpense> _expenses = [];
  String? _employeeName;
  Employee? _resolvedEmployee;
  
  // Timeline - combined and sorted transactions
  List<_TimelineItem> _timeline = [];
  
  // Cash flow summary (enhanced)
  ShiftCashFlowSummary? _cashFlowSummary;
  
  // Debt collections (for this shift)
  List<_DebtCollection> _debtCollections = [];
  
  final _currencyFormat = NumberFormat.currency(symbol: '', decimalDigits: 2);
  final _timeFormat = DateFormat('hh:mm a');
  final _dateFormat = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadCurrentShift();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentShift() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    
    try {
      final currentUser = _authService.currentUser;
      
      if (currentUser == null) {
        throw Exception('Not logged in');
      }
      
      // EMPLOYEE RESOLUTION
      try {
        _resolvedEmployee = await _employeeResolver.getEmployeeForUser(currentUser);
        LoggingService.instance.info(
          'FinancialShift',
          '[EMPLOYEE_RESOLVED] Resolved employee ${_resolvedEmployee!.id} for user ${currentUser.username}',
        );
      } catch (e) {
        LoggingService.instance.error(
          'FinancialShift',
          'Failed to resolve employee for user ${currentUser.username}',
          e,
          StackTrace.current,
        );
        _resolvedEmployee = null;
      }
      
      if (_resolvedEmployee != null) {
        _currentShift = await _financialService.getOpenShiftForEmployee(_resolvedEmployee!.id);
        
        if (_currentShift != null) {
          _shiftSummary = await _financialService.getShiftSummary(_currentShift!.id);
          _cashFlowSummary = await _financialService.getShiftCashFlowSummary(_currentShift!.id);
          _sales = await _financialService.getSalesForShift(_currentShift!.id);
          _expenses = await _financialService.getExpensesForShift(_currentShift!.id);
          _employeeName = _resolvedEmployee!.fullName;
          await _loadDebtCollections();
          _buildTimeline();
        }
      }
    } on FinancialException catch (e) {
      LoggingService.instance.error('FinancialShift', 'FinancialException loading shift', e, StackTrace.current);
      if (mounted) {
        setState(() => _loadError = 'Error: ${e.message}');
      }
    } catch (e) {
      LoggingService.instance.error('FinancialShift', 'Error loading shift', e, StackTrace.current);
      if (mounted) {
        setState(() => _loadError = 'Error loading shift: $e');
      }
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
  
  /// Load debt collections for this shift (credit sales payments received)
  Future<void> _loadDebtCollections() async {
    // Get credit/account sales as debt collections
    // In a pharmacy, this tracks customer accounts and insurance reimbursements
    _debtCollections = _sales
        .where((s) => s.paymentMethod == PaymentMethod.credit)
        .map((s) => _DebtCollection(
          id: s.id,
          amount: s.amount,
          customerName: s.customerName ?? 'Customer Account',
          description: s.description ?? 'Account payment',
          time: s.createdAt,
        ))
        .toList();
  }

  /// Build timeline from sales, expenses, and purchase payments
  void _buildTimeline() {
    _timeline = [];
    
    // Add sales (excluding credit sales which are shown separately as debt collections)
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
    
    // Add expenses (separate purchase payments visually)
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
    
    // Sort by time descending (newest first)
    _timeline.sort((a, b) => b.time.compareTo(a.time));
  }
  
  /// Get smart alerts based on current shift state
  /// Also pushes alerts to the Notifications service for persistence
  List<_ShiftAlert> _getSmartAlerts() {
    if (_shiftSummary == null || _currentShift == null) return [];
    
    final alerts = <_ShiftAlert>[];
    final shiftDuration = DateTime.now().difference(_currentShift!.openedAt);
    
    // Alert 1: No sales after 1 hour
    if (_sales.isEmpty && shiftDuration.inHours >= 1) {
      final alert = _ShiftAlert(
        type: _AlertType.warning,
        title: 'No Sales Recorded',
        message: 'Shift has been open for ${shiftDuration.inHours}h without any sales',
        icon: Icons.trending_flat,
      );
      alerts.add(alert);
      _pushAlertToNotifications(alert, _currentShift!.id);
    }
    
    // Alert 2: High expenses ratio (> 50% of sales)
    if (_shiftSummary!.totalSales > 0) {
      final expenseRatio = _shiftSummary!.totalExpenses / _shiftSummary!.totalSales;
      if (expenseRatio > 0.5) {
        final alert = _ShiftAlert(
          type: _AlertType.warning,
          title: 'High Expenses',
          message: 'Expenses are ${(expenseRatio * 100).toStringAsFixed(0)}% of sales',
          icon: Icons.trending_down,
        );
        alerts.add(alert);
        _pushAlertToNotifications(alert, _currentShift!.id);
      }
    }
    
    // Alert 3: Negative expected cash
    if (_shiftSummary!.expectedCash < 0) {
      final alert = _ShiftAlert(
        type: _AlertType.error,
        title: 'Negative Balance',
        message: 'Expected cash is negative: ${_currencyFormat.format(_shiftSummary!.expectedCash)} EGP',
        icon: Icons.warning,
      );
      alerts.add(alert);
      _pushAlertToNotifications(alert, _currentShift!.id, isCritical: true);
    }
    
    // Alert 4: Cash only warning (no card sales)
    final hasCardSales = _shiftSummary!.salesByMethod.entries.any(
      (e) => e.key != PaymentMethod.cash && e.value > 0
    );
    if (_sales.length > 5 && !hasCardSales) {
      alerts.add(_ShiftAlert(
        type: _AlertType.info,
        title: 'Cash Only',
        message: 'All sales are in cash - consider offering card payment',
        icon: Icons.credit_card_off,
      ));
    }
    
    return alerts;
  }
  
  /// Push an alert to the notifications service
  void _pushAlertToNotifications(_ShiftAlert alert, String shiftId, {bool isCritical = false}) {
    NotificationSeverity severity;
    switch (alert.type) {
      case _AlertType.info:
        severity = NotificationSeverity.info;
        break;
      case _AlertType.warning:
        severity = NotificationSeverity.warning;
        break;
      case _AlertType.error:
        severity = isCritical ? NotificationSeverity.critical : NotificationSeverity.error;
        break;
    }
    
    _notificationsService.addSmartWarning(
      title: alert.title,
      message: alert.message,
      severity: severity,
      shiftId: shiftId,
    );
  }

  Future<void> _openShift() async {
    final openingCash = await _showOpeningCashDialog();
    if (openingCash == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      if (_resolvedEmployee == null) {
        final currentUser = _authService.currentUser;
        if (currentUser != null) {
          _resolvedEmployee = await _employeeResolver.getEmployeeForUser(currentUser);
        }
      }
      
      if (_resolvedEmployee == null) {
        throw FinancialException('Could not resolve employee profile', code: 'EMPLOYEE_RESOLUTION_FAILED');
      }
      
      _currentShift = await _financialService.openShift(
        employeeId: _resolvedEmployee!.id,
        openingCash: openingCash,
      );
      
      _shiftSummary = await _financialService.getShiftSummary(_currentShift!.id);
      _sales = [];
      _expenses = [];
      _timeline = [];
      _employeeName = _resolvedEmployee?.fullName;
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shift opened successfully'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening shift: $e'), backgroundColor: Colors.red),
        );
      }
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
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
              child: const Icon(Icons.play_circle, color: AppTheme.primaryColor),
            ),
            const SizedBox(width: 12),
            const Text('Open Shift'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter the opening cash in the drawer:'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
              decoration: const InputDecoration(
                labelText: 'Opening Cash (EGP)',
                prefixIcon: Icon(Icons.payments),
                border: OutlineInputBorder(),
                suffixText: 'EGP',
              ),
              autofocus: true,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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

  Future<void> _recordSale() async {
    if (_currentShift == null) return;
    
    final result = await _showSaleDialog();
    if (result == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      await _financialService.recordSale(
        financialShiftId: _currentShift!.id,
        amount: result['amount'] as double,
        paymentMethod: result['method'] as PaymentMethod,
        description: result['description'] as String?,
        invoiceNumber: result['invoice'] as String?,
        recordedBy: _currentShift!.employeeId,
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
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
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
                  decoration: const InputDecoration(
                    labelText: 'Amount (EGP) *',
                    prefixIcon: Icon(Icons.attach_money),
                    border: OutlineInputBorder(),
                    suffixText: 'EGP',
                  ),
                  autofocus: true,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

  Future<void> _recordPurchasePayment() async {
    if (_currentShift == null) return;
    
    final result = await PurchasePaymentEntryDialog.show(
      context,
      financialShiftId: _currentShift!.id,
    );
    
    if (result == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      await _financialService.recordExpense(
        financialShiftId: _currentShift!.id,
        amount: result['amount'] as double,
        category: result['category'] as ExpenseCategory,
        description: result['description'] as String,
        receiptNumber: result['invoiceNumber'] as String?,
        recordedBy: _currentShift!.employeeId,
      );
      
      await _refreshShiftData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase payment recorded'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error recording payment: $e'), backgroundColor: Colors.red),
        );
      }
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
  
  /// Record a debt collection (payment received from customer account/insurance)
  Future<void> _recordDebtCollection() async {
    if (_currentShift == null) return;
    
    final result = await DebtCollectionDialog.show(
      context,
      financialShiftId: _currentShift!.id,
    );
    
    if (result == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      // Record as a credit sale (payment received on account)
      await _financialService.recordSale(
        financialShiftId: _currentShift!.id,
        amount: result['amount'] as double,
        paymentMethod: PaymentMethod.credit, // Credit = account payment
        description: result['description'] as String?,
        customerName: result['customerName'] as String?,
        invoiceNumber: result['reference'] as String?,
        recordedBy: _currentShift!.employeeId,
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
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _recordExpense() async {
    if (_currentShift == null) return;
    
    final result = await _showExpenseDialog();
    if (result == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      await _financialService.recordExpense(
        financialShiftId: _currentShift!.id,
        amount: result['amount'] as double,
        category: result['category'] as ExpenseCategory,
        description: result['description'] as String,
        receiptNumber: result['receipt'] as String?,
        recordedBy: _currentShift!.employeeId,
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
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
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
                  decoration: const InputDecoration(
                    labelText: 'Amount (EGP) *',
                    prefixIcon: Icon(Icons.attach_money),
                    border: OutlineInputBorder(),
                    suffixText: 'EGP',
                  ),
                  autofocus: true,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<ExpenseCategory>(
                  value: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(Icons.category),
                    border: OutlineInputBorder(),
                  ),
                  items: ExpenseCategory.values.map((c) => DropdownMenuItem(
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

  Future<void> _closeShift() async {
    if (_currentShift == null || _shiftSummary == null) return;
    
    final result = await _showCloseShiftDialog();
    if (result == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      await _financialService.closeShift(
        financialShiftId: _currentShift!.id,
        actualCash: result['actualCash'] as double,
        closedBy: _currentShift!.employeeId,
        differenceReason: result['reason'] as String?,
        notes: result['notes'] as String?,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shift closed successfully'), backgroundColor: Colors.green),
        );
      }
      
      _currentShift = null;
      _shiftSummary = null;
      _sales = [];
      _expenses = [];
      _timeline = [];
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error closing shift: $e'), backgroundColor: Colors.red),
        );
      }
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<Map<String, dynamic>?> _showCloseShiftDialog() async {
    final actualCashController = TextEditingController();
    final reasonController = TextEditingController();
    final notesController = TextEditingController();
    double? enteredCash;
    double difference = 0;
    double safeBalance = 0;
    
    // Get current Safe balance
    try {
      safeBalance = await _financialService.getSafeBalance();
    } catch (e) {
      // Safe balance fetch failed, continue with 0
    }
    
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final expectedCash = _shiftSummary?.expectedCash ?? 0;
          final expectedSafeAfter = safeBalance + (enteredCash ?? 0);
          
          return AlertDialog(
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
                  // Summary Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildDialogSummaryRow('Opening Cash', _currentShift?.openingCash ?? 0, Icons.account_balance_wallet),
                        _buildDialogSummaryRow('+ Cash Sales', _shiftSummary?.cashSales ?? 0, Icons.add_circle, color: Colors.green),
                        _buildDialogSummaryRow('- Expenses', _shiftSummary?.totalExpenses ?? 0, Icons.remove_circle, color: Colors.red),
                        const Divider(height: 24),
                        _buildDialogSummaryRow('= Expected', expectedCash, Icons.calculate, isBold: true, color: AppTheme.primaryColor),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Safe Balance Info Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.indigo.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lock, size: 18, color: Colors.indigo[700]),
                            const SizedBox(width: 8),
                            Text(
                              'Safe (Vault)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo[700],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Current Balance:'),
                            Text(
                              '${_currencyFormat.format(safeBalance)} EGP',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        if (enteredCash != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('After Transfer:'),
                              Text(
                                '${_currencyFormat.format(expectedSafeAfter)} EGP',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo[700],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Cash will be transferred to Safe, Drawer resets to 0',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Actual Cash Input
                  TextField(
                    controller: actualCashController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                    decoration: const InputDecoration(
                      labelText: 'Actual Cash in Drawer (EGP) *',
                      prefixIcon: Icon(Icons.point_of_sale),
                      border: OutlineInputBorder(),
                      suffixText: 'EGP',
                    ),
                    autofocus: true,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    onChanged: (value) {
                      setDialogState(() {
                        enteredCash = double.tryParse(value);
                        difference = (enteredCash ?? 0) - expectedCash;
                      });
                    },
                  ),
                  
                  // Difference Display
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
                                : difference > 0 
                                    ? Icons.arrow_upward 
                                    : Icons.arrow_downward,
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
                        prefixIcon: Icon(Icons.warning_amber, color: difference < 0 ? Colors.red : Colors.blue),
                        border: const OutlineInputBorder(),
                        hintText: 'Explain the ${difference > 0 ? "overage" : "shortage"}',
                      ),
                      maxLines: 2,
                    ),
                  ],
                  
                  const SizedBox(height: 16),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      prefixIcon: Icon(Icons.note),
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
                    'notes': notesController.text.isEmpty ? null : notesController.text,
                  });
                },
                icon: const Icon(Icons.lock),
                label: const Text('Close Shift'),
              ),
            ],
          );
        },
      ),
    );
  }
  
  Widget _buildDialogSummaryRow(String label, double value, IconData icon, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: color,
              ),
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

  Future<void> _refreshShiftData() async {
    if (_currentShift == null) return;
    
    try {
      _shiftSummary = await _financialService.getShiftSummary(_currentShift!.id);
      _cashFlowSummary = await _financialService.getShiftCashFlowSummary(_currentShift!.id);
      _sales = await _financialService.getSalesForShift(_currentShift!.id);
      _expenses = await _financialService.getExpensesForShift(_currentShift!.id);
      await _loadDebtCollections();
      _buildTimeline();
      
      if (mounted) setState(() {});
    } catch (e) {
      LoggingService.instance.error('FinancialShift', 'Error refreshing shift data', e, StackTrace.current);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing data: $e'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _refreshShiftData,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.point_of_sale, color: AppTheme.primaryColor, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Financial Shift'),
          ],
        ),
        actions: [
          if (_currentShift != null) ...[
            // Shift duration indicator
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer_outlined, size: 14, color: Colors.green),
                  const SizedBox(width: 4),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.green[700],
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isLoading ? null : _loadCurrentShift,
              tooltip: 'Refresh',
            ),
          ],
        ],
      ),
      body: _isLoading
          ? _buildLoadingView()
          : _loadError != null
              ? _buildErrorView()
              : _currentShift == null
                  ? _buildNoShiftView()
                  : _buildShiftView(),
    );
  }
  
  /// Professional loading skeleton view
  Widget _buildLoadingView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header skeleton
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Loading shift data...',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Skeleton cards
          Row(
            children: [
              Expanded(child: _buildSkeletonCard()),
              const SizedBox(width: 8),
              Expanded(child: _buildSkeletonCard()),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildSkeletonCard()),
              const SizedBox(width: 8),
              Expanded(child: _buildSkeletonCard()),
            ],
          ),
          const SizedBox(height: 16),
          // Balance skeleton
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSkeletonCard() {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(10),
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
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(40),
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
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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

  bool get _hasEmployeeContext => _resolvedEmployee != null;
  
  Widget _buildNoShiftView() {
    if (!_hasEmployeeContext) {
      return _buildNoEmployeeContextView();
    }
    
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
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Icon(
                  Icons.point_of_sale,
                  size: 56,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'No Open Shift',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Start a new financial shift to begin recording\nsales, expenses and track cash flow.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _openShift,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Open New Shift'),
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
  
  Widget _buildNoEmployeeContextView() {
    return Center(
      child: Card(
        margin: const EdgeInsets.all(32),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Icon(
                  Icons.person_off,
                  size: 48,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Employee Profile Required',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).colorScheme.error.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber, color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 12),
                    const Flexible(
                      child: Text('This account is not linked to an employee profile.'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Contact your administrator to link your account.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        // ═══════════════════════════════════════════════════════════
        // LIVE FINANCIAL SUMMARY - Always visible at top
        // ═══════════════════════════════════════════════════════════
        _buildLiveFinancialSummary(),
        
        // Smart Alerts
        ..._buildSmartAlerts(),
        
        // Tab Bar
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.timeline),
              text: 'Timeline',
            ),
            Tab(
              icon: Badge(
                label: Text('${_sales.length}'),
                isLabelVisible: _sales.isNotEmpty,
                child: const Icon(Icons.point_of_sale),
              ),
              text: 'Sales',
            ),
            Tab(
              icon: Badge(
                label: Text('${_expenses.length}'),
                isLabelVisible: _expenses.isNotEmpty,
                child: const Icon(Icons.money_off),
              ),
              text: 'Expenses',
            ),
          ],
        ),
        
        // Tab Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildTimelineTab(),
              _buildSalesTab(),
              _buildExpensesTab(),
            ],
          ),
        ),
      ],
    );
  }
  
  /// ═══════════════════════════════════════════════════════════════════
  /// LIVE FINANCIAL SUMMARY WIDGET - ENHANCED VERSION
  /// Shows: Opening → Sales → Purchases → Expenses → Debt Collection → Balance
  /// Example: Start 1,000 ج → +3,500 Sales → -1,200 Purchases → -300 Expenses → +400 Collection = 3,400 ج
  /// ═══════════════════════════════════════════════════════════════════
  Widget _buildLiveFinancialSummary() {
    if (_shiftSummary == null) return const SizedBox.shrink();
    
    // Use ShiftCashFlowSummary for accurate calculations
    final openingCash = _cashFlowSummary?.openingCash ?? _currentShift?.openingCash ?? 0;
    final cashSales = _cashFlowSummary?.cashSales ?? _shiftSummary!.cashSales;
    final totalSales = _shiftSummary!.totalSales;
    
    // Separate purchases (supplies) from other expenses
    final purchasePayments = _shiftSummary!.expensesByCategory[ExpenseCategory.supplies] ?? 0;
    final otherExpenses = _shiftSummary!.totalExpenses - purchasePayments;
    
    // Debt collections (credit sales = customer account payments received)
    final debtCollections = _shiftSummary!.salesByMethod[PaymentMethod.credit] ?? 0;
    
    // Calculate current balance (cash in drawer)
    // Opening + Cash Sales - Purchases - Expenses + Debt Collections (if cash)
    final currentBalance = _cashFlowSummary?.expectedCash ?? _shiftSummary!.expectedCash;
    
    // Calculate shift duration
    final duration = DateTime.now().difference(_currentShift!.openedAt);
    final durationText = duration.inHours > 0 
        ? '${duration.inHours}h ${duration.inMinutes % 60}m'
        : '${duration.inMinutes}m';
    
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor.withOpacity(0.12),
            Colors.green.withOpacity(0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header with shift info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.15),
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
                  child: const Icon(Icons.play_circle, color: Colors.green, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Shift Started: ${_timeFormat.format(_currentShift!.openedAt)}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      Text(
                        'Duration: $durationText • ${_employeeName ?? "Unknown"}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 11),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _closeShift,
                  icon: const Icon(Icons.stop_circle, size: 18),
                  label: const Text('Close Shift'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.withOpacity(0.15),
                    foregroundColor: Colors.orange[700],
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
          
          // Financial Flow - Visual Cash Flow
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Cash Flow Formula Display
                _buildCashFlowFormula(
                  opening: openingCash,
                  sales: cashSales,
                  purchases: purchasePayments,
                  expenses: otherExpenses,
                  collections: debtCollections,
                  balance: currentBalance,
                ),
                
                const SizedBox(height: 16),
                
                // Detailed Grid
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryItem(
                        'Opening Cash',
                        openingCash,
                        Icons.account_balance_wallet,
                        Colors.blue,
                        prefix: '',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildSummaryItem(
                        'Cash Sales',
                        cashSales,
                        Icons.trending_up,
                        Colors.green,
                        prefix: '+',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryItem(
                        'Purchases',
                        purchasePayments,
                        Icons.inventory_2,
                        Colors.orange,
                        prefix: '-',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildSummaryItem(
                        'Expenses',
                        otherExpenses,
                        Icons.receipt_long,
                        Colors.red,
                        prefix: '-',
                      ),
                    ),
                  ],
                ),
                
                // Debt Collection Row (if any)
                if (debtCollections > 0) ...[
                  const SizedBox(height: 8),
                  _buildSummaryItem(
                    'Debt Collections',
                    debtCollections,
                    Icons.payments,
                    Colors.teal,
                    prefix: '+',
                    fullWidth: true,
                  ),
                ],
                
                // Divider with arrow
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: [
                      Expanded(child: Divider(color: AppTheme.primaryColor.withOpacity(0.3), thickness: 1.5)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.arrow_downward, color: AppTheme.primaryColor, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              'RESULT',
                              style: TextStyle(
                                color: AppTheme.primaryColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(child: Divider(color: AppTheme.primaryColor.withOpacity(0.3), thickness: 1.5)),
                    ],
                  ),
                ),
                
                // Current Balance - Large Display
                _buildCurrentBalanceCard(currentBalance),
                
                // Quick Actions - Row 1
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _recordSale,
                        icon: const Icon(Icons.add_shopping_cart, size: 18),
                        label: const Text('Sale'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.green,
                          side: const BorderSide(color: Colors.green),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _recordPurchasePayment,
                        icon: const Icon(Icons.inventory_2, size: 18),
                        label: const Text('Purchase'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          side: const BorderSide(color: Colors.orange),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
                // Quick Actions - Row 2
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _recordExpense,
                        icon: const Icon(Icons.receipt_long, size: 18),
                        label: const Text('Expense'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _recordDebtCollection,
                        icon: const Icon(Icons.payments, size: 18),
                        label: const Text('Collection'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.teal,
                          side: const BorderSide(color: Colors.teal),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  /// Build visual cash flow formula
  /// Example: 1,000 + 3,500 - 1,200 - 300 + 400 = 3,400
  Widget _buildCashFlowFormula({
    required double opening,
    required double sales,
    required double purchases,
    required double expenses,
    required double collections,
    required double balance,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildFormulaItem('${_formatCompact(opening)}', Colors.blue, ''),
            _buildFormulaOperator('+'),
            _buildFormulaItem('${_formatCompact(sales)}', Colors.green, '+'),
            _buildFormulaOperator('-'),
            _buildFormulaItem('${_formatCompact(purchases)}', Colors.orange, '-'),
            _buildFormulaOperator('-'),
            _buildFormulaItem('${_formatCompact(expenses)}', Colors.red, '-'),
            if (collections > 0) ...[
              _buildFormulaOperator('+'),
              _buildFormulaItem('${_formatCompact(collections)}', Colors.teal, '+'),
            ],
            _buildFormulaOperator('='),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: balance >= 0 ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: balance >= 0 ? Colors.green : Colors.red,
                  width: 2,
                ),
              ),
              child: Text(
                '${_formatCompact(balance)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: balance >= 0 ? Colors.green[700] : Colors.red[700],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFormulaItem(String value, Color color, String prefix) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        value,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: color,
        ),
      ),
    );
  }
  
  Widget _buildFormulaOperator(String op) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        op,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: Colors.grey[600],
        ),
      ),
    );
  }
  
  String _formatCompact(double value) {
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toStringAsFixed(0);
  }
  
  /// Build current balance card with visual emphasis
  Widget _buildCurrentBalanceCard(double balance) {
    final isPositive = balance >= 0;
    final color = isPositive ? Colors.green : Colors.red;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.15),
            color.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPositive ? Icons.account_balance : Icons.warning_amber,
              color: color,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Expected Cash in Drawer',
                style: TextStyle(
                  color: color.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _currencyFormat.format(balance),
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: color.shade700,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'EGP',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: color.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildSummaryItem(
    String label,
    double value,
    IconData icon,
    Color color, {
    String prefix = '',
    bool fullWidth = false,
  }) {
    final content = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: color.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$prefix${_currencyFormat.format(value)} EGP',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color.shade700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    
    return fullWidth ? content : content;
  }
  
  /// Build smart alerts list
  List<Widget> _buildSmartAlerts() {
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
                Icon(alert.icon, color: _getAlertColor(alert.type), size: 20),
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
      case _AlertType.error:
        return Colors.red;
      case _AlertType.warning:
        return Colors.orange;
      case _AlertType.info:
        return Colors.blue;
    }
  }
  
  /// ═══════════════════════════════════════════════════════════════════
  /// TIMELINE TAB - All transactions chronologically
  /// ═══════════════════════════════════════════════════════════════════
  Widget _buildTimelineTab() {
    if (_timeline.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timeline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No transactions yet', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 8),
            Text('Record a sale or expense to see it here', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _timeline.length,
      itemBuilder: (context, index) {
        final item = _timeline[index];
        final isFirst = index == 0;
        final isLast = index == _timeline.length - 1;
        
        return IntrinsicHeight(
          child: Row(
            children: [
              // Timeline line and dot
              SizedBox(
                width: 40,
                child: Column(
                  children: [
                    // Line above
                    if (!isFirst)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: Colors.grey[300],
                        ),
                      ),
                    // Dot
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: item.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: item.color.withOpacity(0.3),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    // Line below
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: Colors.grey[300],
                        ),
                      ),
                  ],
                ),
              ),
              
              // Content
              Expanded(
                child: Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: item.color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(item.icon, color: item.color, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.description,
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              if (item.subtitle != null)
                                Text(
                                  item.subtitle!,
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${item.sign}${_currencyFormat.format(item.amount)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: item.color,
                              ),
                            ),
                            Text(
                              _timeFormat.format(item.time),
                              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSalesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _recordSale,
              icon: const Icon(Icons.add),
              label: const Text('Record Sale'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ),
        Expanded(
          child: _sales.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.point_of_sale, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('No sales recorded', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _sales.length,
                  itemBuilder: (context, index) {
                    final sale = _sales[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getPaymentMethodColor(sale.paymentMethod),
                          child: Icon(_getPaymentMethodIcon(sale.paymentMethod), color: Colors.white, size: 20),
                        ),
                        title: Text(
                          '+${_currencyFormat.format(sale.amount)} EGP',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(sale.paymentMethod.displayName),
                            if (sale.description != null)
                              Text(sale.description!, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                        trailing: Text(_timeFormat.format(sale.createdAt), style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildExpensesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _recordPurchasePayment,
                  icon: const Icon(Icons.inventory_2),
                  label: const Text('Purchase'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _recordExpense,
                  icon: const Icon(Icons.add),
                  label: const Text('Expense'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _expenses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.money_off, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('No expenses recorded', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _expenses.length,
                  itemBuilder: (context, index) {
                    final expense = _expenses[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.red,
                          child: Icon(_getExpenseCategoryIcon(expense.category), color: Colors.white, size: 20),
                        ),
                        title: Text(
                          '-${_currencyFormat.format(expense.amount)} EGP',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(expense.category.displayName),
                            Text(expense.description, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                        trailing: Text(_timeFormat.format(expense.createdAt), style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  IconData _getPaymentMethodIcon(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash: return Icons.payments;
      case PaymentMethod.visa: return Icons.credit_card;
      case PaymentMethod.wallet: return Icons.account_balance_wallet;
      case PaymentMethod.insurance: return Icons.health_and_safety;
      case PaymentMethod.credit: return Icons.receipt_long;
    }
  }

  Color _getPaymentMethodColor(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash: return Colors.green;
      case PaymentMethod.visa: return Colors.blue;
      case PaymentMethod.wallet: return Colors.orange;
      case PaymentMethod.insurance: return Colors.purple;
      case PaymentMethod.credit: return Colors.grey;
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

enum _TimelineType { 
  sale,        // Regular sales (cash, card, wallet, insurance)
  expense,     // Regular expenses
  purchase,    // Purchase payments (supplies category)
  debtCollection, // Debt/credit collections
}

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
  
  /// Check if this is a cash-out transaction
  bool get isCashOut => type == _TimelineType.expense || type == _TimelineType.purchase;
  
  /// Get sign for display
  String get sign => isCashOut ? '-' : '+';
}

enum _AlertType { error, warning, info }

class _ShiftAlert {
  final _AlertType type;
  final String title;
  final String message;
  final IconData icon;
  
  _ShiftAlert({
    required this.type,
    required this.title,
    required this.message,
    required this.icon,
  });
}

/// Represents a debt collection (credit sale payment received)
class _DebtCollection {
  final String id;
  final double amount;
  final String customerName;
  final String description;
  final DateTime time;
  
  _DebtCollection({
    required this.id,
    required this.amount,
    required this.customerName,
    required this.description,
    required this.time,
  });
}

/// Extension to get shade colors from any Color
extension ColorShade on Color {
  Color get shade700 {
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness((hsl.lightness - 0.1).clamp(0.0, 1.0)).toColor();
  }
  
  Color get shade600 {
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness((hsl.lightness - 0.05).clamp(0.0, 1.0)).toColor();
  }
}
