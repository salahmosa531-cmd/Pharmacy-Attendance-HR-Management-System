import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/services/financial_service.dart';
import '../../core/services/supplier_service.dart';
import '../../data/repositories/shift_closure_repository.dart';
import '../../data/models/shift_closure_model.dart';

/// Financial Reports Screen
/// 
/// Generates various financial reports:
/// - Daily shift closures report
/// - Monthly summary report
/// - Supplier balances report
/// - Discrepancy report
class FinancialReportsScreen extends StatefulWidget {
  const FinancialReportsScreen({super.key});

  @override
  State<FinancialReportsScreen> createState() => _FinancialReportsScreenState();
}

class _FinancialReportsScreenState extends State<FinancialReportsScreen> {
  final _financialService = FinancialService.instance;
  final _supplierService = SupplierService.instance;
  final _closureRepo = ShiftClosureRepository.instance;
  
  bool _isLoading = false;
  String _selectedReport = 'daily';
  DateTime _selectedDate = DateTime.now();
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  
  // Report data
  List<ShiftClosure> _closures = [];
  Map<String, dynamic> _periodSummary = {};
  List<Map<String, dynamic>> _supplierBalances = [];
  
  final _currencyFormat = NumberFormat.currency(symbol: 'EGP ', decimalDigits: 2);
  final _dateFormat = DateFormat('dd MMM yyyy');
  final _timeFormat = DateFormat('hh:mm a');

  // Hardcoded branch name for single-branch architecture
  static const String _branchName = 'Main Branch';

  @override
  void initState() {
    super.initState();
    _loadReportData();
  }

  Future<void> _loadReportData() async {
    setState(() => _isLoading = true);
    
    try {
      // All repository calls now use hardcoded branch_id = '1'
      switch (_selectedReport) {
        case 'daily':
          final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
          final endOfDay = startOfDay.add(const Duration(days: 1));
          _closures = await _closureRepo.getByDateRange('1', startOfDay, endOfDay);
          _periodSummary = await _closureRepo.getPeriodSummary('1', startOfDay, endOfDay);
          break;
          
        case 'monthly':
          final startOfMonth = DateTime(_selectedYear, _selectedMonth, 1);
          final endOfMonth = DateTime(_selectedYear, _selectedMonth + 1, 0, 23, 59, 59);
          _closures = await _closureRepo.getByDateRange('1', startOfMonth, endOfMonth);
          _periodSummary = await _closureRepo.getPeriodSummary('1', startOfMonth, endOfMonth);
          break;
          
        case 'suppliers':
          _supplierBalances = await _supplierService.getSuppliersWithBalances();
          break;
          
        case 'discrepancies':
          _closures = await _closureRepo.getClosuresWithDiscrepancies('1', limit: 100);
          break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading report: $e'), backgroundColor: Colors.red),
        );
      }
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportToPdf() async {
    final pdf = pw.Document();
    
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => _buildPdfContent(_branchName),
      ),
    );
    
    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'financial_report_${_selectedReport}_${DateTime.now().toIso8601String()}',
    );
  }

  List<pw.Widget> _buildPdfContent(String branchName) {
    final widgets = <pw.Widget>[];
    
    // Header
    widgets.add(
      pw.Header(
        level: 0,
        child: pw.Text(
          _getReportTitle(),
          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
        ),
      ),
    );
    
    widgets.add(pw.SizedBox(height: 10));
    widgets.add(pw.Text('Branch: $branchName'));
    widgets.add(pw.Text('Generated: ${_dateFormat.format(DateTime.now())} at ${_timeFormat.format(DateTime.now())}'));
    widgets.add(pw.SizedBox(height: 20));
    
    switch (_selectedReport) {
      case 'daily':
      case 'monthly':
        widgets.addAll(_buildPeriodReportPdf());
        break;
      case 'suppliers':
        widgets.addAll(_buildSuppliersReportPdf());
        break;
      case 'discrepancies':
        widgets.addAll(_buildDiscrepanciesReportPdf());
        break;
    }
    
    return widgets;
  }

  List<pw.Widget> _buildPeriodReportPdf() {
    final widgets = <pw.Widget>[];
    
    // Summary
    widgets.add(pw.Header(level: 1, child: pw.Text('Summary')));
    widgets.add(
      pw.TableHelper.fromTextArray(
        headers: ['Metric', 'Value'],
        data: [
          ['Total Sales', _currencyFormat.format(_periodSummary['total_sales'] ?? 0)],
          ['Cash Sales', _currencyFormat.format(_periodSummary['total_cash'] ?? 0)],
          ['Card Sales', _currencyFormat.format(_periodSummary['total_card'] ?? 0)],
          ['Wallet Sales', _currencyFormat.format(_periodSummary['total_wallet'] ?? 0)],
          ['Total Expenses', _currencyFormat.format(_periodSummary['total_expenses'] ?? 0)],
          ['Net Profit', _currencyFormat.format(
            ((_periodSummary['total_sales'] ?? 0) as num).toDouble() - 
            ((_periodSummary['total_expenses'] ?? 0) as num).toDouble()
          )],
          ['Shortages', _currencyFormat.format(_periodSummary['total_shortages'] ?? 0)],
          ['Overages', _currencyFormat.format(_periodSummary['total_overages'] ?? 0)],
        ],
      ),
    );
    
    // Closures Detail
    if (_closures.isNotEmpty) {
      widgets.add(pw.SizedBox(height: 20));
      widgets.add(pw.Header(level: 1, child: pw.Text('Shift Closures')));
      widgets.add(
        pw.TableHelper.fromTextArray(
          headers: ['Date', 'Sales', 'Expenses', 'Expected', 'Actual', 'Diff'],
          data: _closures.map((c) => [
            _dateFormat.format(c.createdAt),
            _currencyFormat.format(c.totalSales),
            _currencyFormat.format(c.totalExpenses),
            _currencyFormat.format(c.expectedCash),
            _currencyFormat.format(c.actualCash),
            _currencyFormat.format(c.difference),
          ]).toList(),
        ),
      );
    }
    
    return widgets;
  }

  List<pw.Widget> _buildSuppliersReportPdf() {
    final widgets = <pw.Widget>[];
    
    final totalOwed = _supplierBalances.fold<double>(
      0,
      (sum, s) => sum + ((s['balance'] as double?) ?? 0).clamp(0, double.infinity),
    );
    
    widgets.add(pw.Text('Total Amount Owed: ${_currencyFormat.format(totalOwed)}', 
      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)));
    widgets.add(pw.SizedBox(height: 20));
    
    widgets.add(
      pw.TableHelper.fromTextArray(
        headers: ['Supplier', 'Purchases', 'Payments', 'Balance'],
        data: _supplierBalances.map((s) => [
          s['name'] ?? 'Unknown',
          _currencyFormat.format(s['total_purchases'] ?? 0),
          _currencyFormat.format(s['total_payments'] ?? 0),
          _currencyFormat.format(s['balance'] ?? 0),
        ]).toList(),
      ),
    );
    
    return widgets;
  }

  List<pw.Widget> _buildDiscrepanciesReportPdf() {
    final widgets = <pw.Widget>[];
    
    if (_closures.isEmpty) {
      widgets.add(pw.Text('No discrepancies found'));
      return widgets;
    }
    
    widgets.add(
      pw.TableHelper.fromTextArray(
        headers: ['Date', 'Expected', 'Actual', 'Difference', 'Reason'],
        data: _closures.map((c) => [
          _dateFormat.format(c.createdAt),
          _currencyFormat.format(c.expectedCash),
          _currencyFormat.format(c.actualCash),
          _currencyFormat.format(c.difference),
          c.differenceReason ?? '-',
        ]).toList(),
      ),
    );
    
    return widgets;
  }

  String _getReportTitle() {
    switch (_selectedReport) {
      case 'daily':
        return 'Daily Financial Report - ${_dateFormat.format(_selectedDate)}';
      case 'monthly':
        return 'Monthly Financial Report - ${DateFormat('MMMM yyyy').format(DateTime(_selectedYear, _selectedMonth))}';
      case 'suppliers':
        return 'Supplier Balances Report';
      case 'discrepancies':
        return 'Cash Discrepancies Report';
      default:
        return 'Financial Report';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Financial Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _exportToPdf,
            tooltip: 'Export to PDF',
          ),
        ],
      ),
      body: Column(
        children: [
          // Report Type Selector
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildReportTypeChip('daily', 'Daily', Icons.today),
                const SizedBox(width: 8),
                _buildReportTypeChip('monthly', 'Monthly', Icons.calendar_month),
                const SizedBox(width: 8),
                _buildReportTypeChip('suppliers', 'Suppliers', Icons.business),
                const SizedBox(width: 8),
                _buildReportTypeChip('discrepancies', 'Discrepancies', Icons.warning),
              ],
            ),
          ),
          
          // Date/Period Selector
          if (_selectedReport == 'daily' || _selectedReport == 'monthly')
            _buildDateSelector(),
          
          const Divider(),
          
          // Report Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildReportContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildReportTypeChip(String value, String label, IconData icon) {
    final isSelected = _selectedReport == value;
    return FilterChip(
      selected: isSelected,
      showCheckmark: false,
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onSelected: (_) {
        setState(() => _selectedReport = value);
        _loadReportData();
      },
    );
  }

  Widget _buildDateSelector() {
    if (_selectedReport == 'daily') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
                _loadReportData();
              },
            ),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (date != null) {
                    setState(() => _selectedDate = date);
                    _loadReportData();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _dateFormat.format(_selectedDate),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _selectedDate.isBefore(DateTime.now().subtract(const Duration(days: 1)))
                  ? () {
                      setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
                      _loadReportData();
                    }
                  : null,
            ),
          ],
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _selectedMonth,
                decoration: const InputDecoration(
                  labelText: 'Month',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12),
                ),
                items: List.generate(12, (i) => DropdownMenuItem(
                  value: i + 1,
                  child: Text(DateFormat('MMMM').format(DateTime(2000, i + 1))),
                )),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selectedMonth = v);
                    _loadReportData();
                  }
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _selectedYear,
                decoration: const InputDecoration(
                  labelText: 'Year',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12),
                ),
                items: List.generate(5, (i) => DropdownMenuItem(
                  value: DateTime.now().year - i,
                  child: Text('${DateTime.now().year - i}'),
                )),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selectedYear = v);
                    _loadReportData();
                  }
                },
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildReportContent() {
    switch (_selectedReport) {
      case 'daily':
      case 'monthly':
        return _buildPeriodReport();
      case 'suppliers':
        return _buildSuppliersReport();
      case 'discrepancies':
        return _buildDiscrepanciesReport();
      default:
        return const Center(child: Text('Select a report type'));
    }
  }

  Widget _buildPeriodReport() {
    final totalSales = (_periodSummary['total_sales'] as num?)?.toDouble() ?? 0;
    final totalExpenses = (_periodSummary['total_expenses'] as num?)?.toDouble() ?? 0;
    final netProfit = totalSales - totalExpenses;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Summary Cards
          Row(
            children: [
              Expanded(child: _buildSummaryCard('Total Sales', totalSales, Colors.green)),
              const SizedBox(width: 12),
              Expanded(child: _buildSummaryCard('Total Expenses', totalExpenses, Colors.red)),
              const SizedBox(width: 12),
              Expanded(child: _buildSummaryCard('Net Profit', netProfit, Colors.blue)),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Payment Breakdown
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sales by Payment Method', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  _buildPaymentRow('Cash', (_periodSummary['total_cash'] as num?)?.toDouble() ?? 0, Icons.payments),
                  _buildPaymentRow('Card', (_periodSummary['total_card'] as num?)?.toDouble() ?? 0, Icons.credit_card),
                  _buildPaymentRow('Wallet', (_periodSummary['total_wallet'] as num?)?.toDouble() ?? 0, Icons.account_balance_wallet),
                  _buildPaymentRow('Insurance', (_periodSummary['total_insurance'] as num?)?.toDouble() ?? 0, Icons.health_and_safety),
                  _buildPaymentRow('Credit', (_periodSummary['total_credit'] as num?)?.toDouble() ?? 0, Icons.receipt_long),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Discrepancies Summary
          Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Text('Shortages', style: Theme.of(context).textTheme.titleSmall),
                        Text(
                          _currencyFormat.format((_periodSummary['total_shortages'] as num?)?.toDouble() ?? 0),
                          style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 40, color: Colors.grey),
                  Expanded(
                    child: Column(
                      children: [
                        Text('Overages', style: Theme.of(context).textTheme.titleSmall),
                        Text(
                          _currencyFormat.format((_periodSummary['total_overages'] as num?)?.toDouble() ?? 0),
                          style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 40, color: Colors.grey),
                  Expanded(
                    child: Column(
                      children: [
                        Text('Discrepancies', style: Theme.of(context).textTheme.titleSmall),
                        Text(
                          '${(_periodSummary['discrepancy_count'] as num?)?.toInt() ?? 0}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Closures List
          if (_closures.isNotEmpty) ...[
            Text('Shift Closures (${_closures.length})', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._closures.map((c) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: c.difference == 0 
                      ? Colors.green.shade100 
                      : c.difference < 0 
                          ? Colors.red.shade100 
                          : Colors.blue.shade100,
                  child: Icon(
                    c.difference == 0 
                        ? Icons.check 
                        : c.difference < 0 
                            ? Icons.arrow_downward 
                            : Icons.arrow_upward,
                    color: c.difference == 0 
                        ? Colors.green 
                        : c.difference < 0 
                            ? Colors.red 
                            : Colors.blue,
                    size: 20,
                  ),
                ),
                title: Text('Sales: ${_currencyFormat.format(c.totalSales)}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Expenses: ${_currencyFormat.format(c.totalExpenses)}'),
                    if (c.difference != 0)
                      Text(
                        'Difference: ${_currencyFormat.format(c.difference)}',
                        style: TextStyle(
                          color: c.difference < 0 ? Colors.red : Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                trailing: Text(
                  _timeFormat.format(c.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            )),
          ] else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.info_outline, size: 48, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 8),
                      const Text('No shift closures for this period'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String label, double value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(
              _currencyFormat.format(value),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentRow(String label, double value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(_currencyFormat.format(value), style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSuppliersReport() {
    final totalOwed = _supplierBalances.fold<double>(
      0,
      (sum, s) => sum + ((s['balance'] as double?) ?? 0).clamp(0, double.infinity),
    );
    
    return Column(
      children: [
        // Total Summary
        Container(
          color: Theme.of(context).colorScheme.primaryContainer,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.account_balance, size: 40),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Owed to Suppliers', style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      _currencyFormat.format(totalOwed),
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Text('${_supplierBalances.length} suppliers', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        
        // Suppliers List
        Expanded(
          child: _supplierBalances.isEmpty
              ? const Center(child: Text('No suppliers found'))
              : ListView.builder(
                  itemCount: _supplierBalances.length,
                  itemBuilder: (context, index) {
                    final s = _supplierBalances[index];
                    final balance = (s['balance'] as double?) ?? 0;
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: balance > 0 ? Colors.red.shade100 : Colors.green.shade100,
                          child: Icon(
                            Icons.business,
                            color: balance > 0 ? Colors.red : Colors.green,
                          ),
                        ),
                        title: Text(s['name'] as String? ?? 'Unknown'),
                        subtitle: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Purchases: ${_currencyFormat.format(s['total_purchases'] ?? 0)}'),
                                  Text('Payments: ${_currencyFormat.format(s['total_payments'] ?? 0)}'),
                                ],
                              ),
                            ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Balance', style: Theme.of(context).textTheme.bodySmall),
                            Text(
                              _currencyFormat.format(balance),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: balance > 0 ? Colors.red : Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDiscrepanciesReport() {
    final totalShortages = _closures.where((c) => c.difference < 0).fold<double>(0, (s, c) => s + c.difference.abs());
    final totalOverages = _closures.where((c) => c.difference > 0).fold<double>(0, (s, c) => s + c.difference);
    
    return Column(
      children: [
        // Summary
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(Icons.arrow_downward, color: Colors.red.shade700),
                        const SizedBox(height: 8),
                        Text('Total Shortages', style: Theme.of(context).textTheme.bodySmall),
                        Text(
                          _currencyFormat.format(totalShortages),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(Icons.arrow_upward, color: Colors.blue.shade700),
                        const SizedBox(height: 8),
                        Text('Total Overages', style: Theme.of(context).textTheme.bodySmall),
                        Text(
                          _currencyFormat.format(totalOverages),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // List
        Expanded(
          child: _closures.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 64, color: Colors.green.shade300),
                      const SizedBox(height: 16),
                      const Text('No discrepancies found!'),
                      const Text('All shifts balanced perfectly.'),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _closures.length,
                  itemBuilder: (context, index) {
                    final c = _closures[index];
                    final isShortage = c.difference < 0;
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: isShortage ? Colors.red.shade100 : Colors.blue.shade100,
                          child: Icon(
                            isShortage ? Icons.arrow_downward : Icons.arrow_upward,
                            color: isShortage ? Colors.red : Colors.blue,
                          ),
                        ),
                        title: Text(
                          '${isShortage ? "Shortage" : "Overage"}: ${_currencyFormat.format(c.difference.abs())}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isShortage ? Colors.red : Colors.blue,
                          ),
                        ),
                        subtitle: Text(_dateFormat.format(c.createdAt)),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildDetailRow('Expected Cash', _currencyFormat.format(c.expectedCash)),
                                _buildDetailRow('Actual Cash', _currencyFormat.format(c.actualCash)),
                                _buildDetailRow('Difference', _currencyFormat.format(c.difference)),
                                if (c.differenceReason != null) ...[
                                  const Divider(),
                                  Text('Reason:', style: Theme.of(context).textTheme.titleSmall),
                                  Text(c.differenceReason!),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
