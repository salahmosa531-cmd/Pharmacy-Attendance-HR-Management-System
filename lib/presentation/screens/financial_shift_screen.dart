import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/services/financial_service.dart';
import '../../core/services/branch_context_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/financial_shift_model.dart';
import '../../data/models/shift_sale_model.dart';
import '../../data/models/shift_expense_model.dart';
import '../../data/repositories/employee_repository.dart';
import '../widgets/no_branch_guard.dart';

/// Financial Shift Management Screen
/// 
/// Handles:
/// - Opening new financial shifts
/// - Recording sales and expenses
/// - Viewing shift summary
/// - Closing shifts with cash reconciliation
class FinancialShiftScreen extends StatefulWidget {
  const FinancialShiftScreen({super.key});

  @override
  State<FinancialShiftScreen> createState() => _FinancialShiftScreenState();
}

class _FinancialShiftScreenState extends State<FinancialShiftScreen> with SingleTickerProviderStateMixin {
  final _financialService = FinancialService.instance;
  final _branchContext = BranchContextService.instance;
  final _authService = AuthService.instance;
  final _employeeRepo = EmployeeRepository.instance;
  
  late TabController _tabController;
  
  bool _isLoading = true;
  FinancialShift? _currentShift;
  ShiftSummary? _shiftSummary;
  List<ShiftSale> _sales = [];
  List<ShiftExpense> _expenses = [];
  String? _employeeName;
  
  final _currencyFormat = NumberFormat.currency(symbol: 'EGP ', decimalDigits: 2);
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
    setState(() => _isLoading = true);
    
    try {
      final currentUser = _authService.currentUser;
      final branch = _branchContext.state.activeBranch;
      
      // IMPORTANT: Require both branch and employee to load shift
      // This ensures we only load shifts for the current branch
      if (branch != null && currentUser?.employeeId != null) {
        _currentShift = await _financialService.getOpenShiftForEmployee(branch.id, currentUser!.employeeId!);
        
        if (_currentShift != null) {
          _shiftSummary = await _financialService.getShiftSummary(_currentShift!.id);
          _sales = await _financialService.getSalesForShift(_currentShift!.id);
          _expenses = await _financialService.getExpensesForShift(_currentShift!.id);
          
          // Get employee name
          final employee = await _employeeRepo.getById(_currentShift!.employeeId);
          _employeeName = employee?.fullName;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading shift: $e'), backgroundColor: Colors.red),
        );
      }
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openShift() async {
    final openingCash = await _showOpeningCashDialog();
    if (openingCash == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      final branch = _branchContext.state.activeBranch;
      final currentUser = _authService.currentUser;
      
      if (branch == null || currentUser?.employeeId == null) {
        throw FinancialException('No active branch or employee', code: 'NO_CONTEXT');
      }
      
      _currentShift = await _financialService.openShift(
        branchId: branch.id,
        employeeId: currentUser!.employeeId!,
        openingCash: openingCash,
      );
      
      _shiftSummary = await _financialService.getShiftSummary(_currentShift!.id);
      _sales = [];
      _expenses = [];
      
      final employee = await _employeeRepo.getById(_currentShift!.employeeId);
      _employeeName = employee?.fullName;
      
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
        title: const Text('Open Financial Shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
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
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text) ?? 0;
              Navigator.pop(context, value);
            },
            child: const Text('Open Shift'),
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
        branchId: _currentShift!.branchId,
        amount: result['amount'] as double,
        paymentMethod: result['method'] as PaymentMethod,
        description: result['description'] as String?,
        invoiceNumber: result['invoice'] as String?,
        recordedBy: _currentShift!.employeeId,
      );
      
      await _refreshShiftData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sale recorded'), backgroundColor: Colors.green),
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
          title: const Text('Record Sale'),
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
                  ),
                  autofocus: true,
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
                    child: Text(m.displayName),
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
            FilledButton(
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
              child: const Text('Record Sale'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _recordExpense() async {
    if (_currentShift == null) return;
    
    final result = await _showExpenseDialog();
    if (result == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      await _financialService.recordExpense(
        financialShiftId: _currentShift!.id,
        branchId: _currentShift!.branchId,
        amount: result['amount'] as double,
        category: result['category'] as ExpenseCategory,
        description: result['description'] as String,
        receiptNumber: result['receipt'] as String?,
        recordedBy: _currentShift!.employeeId,
      );
      
      await _refreshShiftData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense recorded'), backgroundColor: Colors.green),
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
          title: const Text('Record Expense'),
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
                  ),
                  autofocus: true,
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
                    child: Text(c.displayName),
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
            FilledButton(
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
              child: const Text('Record Expense'),
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
    
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final expectedCash = _shiftSummary?.expectedCash ?? 0;
          
          return AlertDialog(
            title: const Text('Close Shift'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary Card
                  Card(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSummaryRow('Opening Cash', _currentShift?.openingCash ?? 0),
                          _buildSummaryRow('Cash Sales', _shiftSummary?.cashSales ?? 0),
                          _buildSummaryRow('Expenses', _shiftSummary?.totalExpenses ?? 0, isNegative: true),
                          const Divider(),
                          _buildSummaryRow('Expected Cash', expectedCash, isBold: true),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Actual Cash Input
                  TextField(
                    controller: actualCashController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                    decoration: const InputDecoration(
                      labelText: 'Actual Cash in Drawer (EGP) *',
                      prefixIcon: Icon(Icons.point_of_sale),
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
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
                            ? Colors.green.withValues(alpha: 0.1)
                            : difference > 0 
                                ? Colors.blue.withValues(alpha: 0.1)
                                : Colors.red.withValues(alpha: 0.1),
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
                                      ? 'Overage: ${_currencyFormat.format(difference)}'
                                      : 'Shortage: ${_currencyFormat.format(difference.abs())}',
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
                      decoration: const InputDecoration(
                        labelText: 'Reason for Difference *',
                        prefixIcon: Icon(Icons.warning_amber),
                        border: OutlineInputBorder(),
                        hintText: 'Explain the shortage or overage',
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
              FilledButton(
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
                child: const Text('Close Shift'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryRow(String label, double value, {bool isNegative = false, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(
            '${isNegative ? "-" : ""}${_currencyFormat.format(value)}',
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isNegative ? Colors.red : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshShiftData() async {
    if (_currentShift == null) return;
    
    _shiftSummary = await _financialService.getShiftSummary(_currentShift!.id);
    _sales = await _financialService.getSalesForShift(_currentShift!.id);
    _expenses = await _financialService.getExpensesForShift(_currentShift!.id);
    
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // GUARD: Check branch context FIRST, before any service calls
    // This is SECONDARY protection (after route-level guard)
    if (!_branchContext.hasActiveBranch) {
      return const NoBranchGuard(screenName: 'Financial Shift');
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Financial Shift'),
        actions: [
          if (_currentShift != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadCurrentShift,
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentShift == null
              ? _buildNoShiftView()
              : _buildShiftView(),
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
              Icon(
                Icons.point_of_sale,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'No Open Shift',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Start a new financial shift to begin recording sales and expenses.',
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
        // Shift Header
        Container(
          color: Theme.of(context).colorScheme.primaryContainer,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shift Active',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Opened: ${_dateFormat.format(_currentShift!.openedAt)} at ${_timeFormat.format(_currentShift!.openedAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                      ),
                    ),
                    if (_employeeName != null)
                      Text(
                        'By: $_employeeName',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                        ),
                      ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _closeShift,
                icon: const Icon(Icons.stop),
                label: const Text('Close Shift'),
              ),
            ],
          ),
        ),
        
        // Tab Bar
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.dashboard),
              text: 'Summary',
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
              _buildSummaryTab(),
              _buildSalesTab(),
              _buildExpensesTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryTab() {
    if (_shiftSummary == null) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Key Metrics Row
          Row(
            children: [
              Expanded(child: _buildMetricCard('Total Sales', _shiftSummary!.totalSales, Icons.trending_up, Colors.green)),
              const SizedBox(width: 16),
              Expanded(child: _buildMetricCard('Total Expenses', _shiftSummary!.totalExpenses, Icons.trending_down, Colors.red)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildMetricCard('Net Profit', _shiftSummary!.netProfit, Icons.account_balance, AppTheme.primaryColor)),
              const SizedBox(width: 16),
              Expanded(child: _buildMetricCard('Expected Cash', _shiftSummary!.expectedCash, Icons.payments, Colors.orange)),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Sales by Payment Method
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sales by Payment Method', style: Theme.of(context).textTheme.titleMedium),
                  const Divider(),
                  ..._shiftSummary!.salesByMethod.entries.map((e) => ListTile(
                    leading: Icon(_getPaymentMethodIcon(e.key)),
                    title: Text(e.key.displayName),
                    trailing: Text(_currencyFormat.format(e.value)),
                  )),
                  if (_shiftSummary!.salesByMethod.isEmpty)
                    const ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('No sales recorded yet'),
                    ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Expenses by Category
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Expenses by Category', style: Theme.of(context).textTheme.titleMedium),
                  const Divider(),
                  ..._shiftSummary!.expensesByCategory.entries.map((e) => ListTile(
                    leading: Icon(_getExpenseCategoryIcon(e.key)),
                    title: Text(e.key.displayName),
                    trailing: Text('-${_currencyFormat.format(e.value)}', style: const TextStyle(color: Colors.red)),
                  )),
                  if (_shiftSummary!.expensesByCategory.isEmpty)
                    const ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('No expenses recorded yet'),
                    ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Opening Cash Info
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet),
              title: const Text('Opening Cash'),
              trailing: Text(_currencyFormat.format(_currentShift?.openingCash ?? 0)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String label, double value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _currencyFormat.format(value),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesTab() {
    return Column(
      children: [
        // Add Sale Button
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _recordSale,
              icon: const Icon(Icons.add),
              label: const Text('Record Sale'),
            ),
          ),
        ),
        
        // Sales List
        Expanded(
          child: _sales.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.point_of_sale, size: 64, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 16),
                      Text('No sales recorded', style: Theme.of(context).textTheme.bodyLarge),
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
                        title: Text(_currencyFormat.format(sale.amount)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(sale.paymentMethod.displayName),
                            if (sale.description != null)
                              Text(sale.description!, style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                        trailing: Text(
                          _timeFormat.format(sale.createdAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
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
        // Add Expense Button
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _recordExpense,
              icon: const Icon(Icons.add),
              label: const Text('Record Expense'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
            ),
          ),
        ),
        
        // Expenses List
        Expanded(
          child: _expenses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.money_off, size: 64, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 16),
                      Text('No expenses recorded', style: Theme.of(context).textTheme.bodyLarge),
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
                        title: Text('-${_currencyFormat.format(expense.amount)}', style: const TextStyle(color: Colors.red)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(expense.category.displayName),
                            Text(expense.description, style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                        trailing: Text(
                          _timeFormat.format(expense.createdAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
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
      case PaymentMethod.cash:
        return Icons.payments;
      case PaymentMethod.card:
        return Icons.credit_card;
      case PaymentMethod.wallet:
        return Icons.account_balance_wallet;
      case PaymentMethod.insurance:
        return Icons.health_and_safety;
      case PaymentMethod.credit:
        return Icons.receipt_long;
    }
  }

  Color _getPaymentMethodColor(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return Colors.green;
      case PaymentMethod.card:
        return Colors.blue;
      case PaymentMethod.wallet:
        return Colors.orange;
      case PaymentMethod.insurance:
        return Colors.purple;
      case PaymentMethod.credit:
        return Colors.grey;
    }
  }

  IconData _getExpenseCategoryIcon(ExpenseCategory category) {
    switch (category) {
      case ExpenseCategory.utilities:
        return Icons.bolt;
      case ExpenseCategory.supplies:
        return Icons.inventory;
      case ExpenseCategory.maintenance:
        return Icons.build;
      case ExpenseCategory.shortage:
        return Icons.warning;
      case ExpenseCategory.emergency:
        return Icons.emergency;
      case ExpenseCategory.transport:
        return Icons.local_shipping;
      case ExpenseCategory.staff:
        return Icons.people;
      case ExpenseCategory.misc:
        return Icons.more_horiz;
    }
  }
}
