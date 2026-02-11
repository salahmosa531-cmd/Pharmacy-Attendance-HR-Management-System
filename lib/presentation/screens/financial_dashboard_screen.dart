import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../core/services/financial_service.dart';
import '../../core/services/supplier_service.dart';
import '../../data/models/financial_shift_model.dart';
import '../../data/repositories/shift_closure_repository.dart';

/// Financial Dashboard Screen
/// 
/// Displays key financial KPIs:
/// - Today's sales and expenses
/// - Net profit
/// - Open shifts
/// - Supplier balances
/// - Weekly/Monthly trends
class FinancialDashboardScreen extends StatefulWidget {
  const FinancialDashboardScreen({super.key});

  @override
  State<FinancialDashboardScreen> createState() => _FinancialDashboardScreenState();
}

class _FinancialDashboardScreenState extends State<FinancialDashboardScreen> {
  final _financialService = FinancialService.instance;
  final _supplierService = SupplierService.instance;
  final _closureRepo = ShiftClosureRepository.instance;
  
  bool _isLoading = true;
  
  // Today's data
  Map<String, dynamic> _todaySummary = {};
  Map<String, dynamic> _monthSummary = {};
  List<FinancialShift> _openShifts = [];
  double _totalOwedToSuppliers = 0;
  List<Map<String, dynamic>> _topSuppliers = [];
  List<Map<String, dynamic>> _weeklyTotals = [];
  List<Map<String, dynamic>> _recentDiscrepancies = [];
  
  final _currencyFormat = NumberFormat.currency(symbol: 'EGP ', decimalDigits: 2);
  final _compactCurrencyFormat = NumberFormat.compactCurrency(symbol: 'EGP ');
  final _dateFormat = DateFormat('dd MMM');

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final weekAgo = today.subtract(const Duration(days: 7));
      
      // Load all data in parallel - services now use hardcoded branch_id = '1'
      final results = await Future.wait([
        _financialService.getDailySummary(today),
        _financialService.getMonthlySummary(now.year, now.month),
        _financialService.getOpenShiftsForBranch(),
        _supplierService.getTotalOwed(),
        _supplierService.getTopSuppliersByBalance(limit: 5),
        _closureRepo.getDailyTotals('1', weekAgo, today),
        _financialService.getDiscrepancies(limit: 5),
      ]);
      
      _todaySummary = results[0] as Map<String, dynamic>;
      _monthSummary = results[1] as Map<String, dynamic>;
      _openShifts = results[2] as List<FinancialShift>;
      _totalOwedToSuppliers = results[3] as double;
      _topSuppliers = results[4] as List<Map<String, dynamic>>;
      _weeklyTotals = results[5] as List<Map<String, dynamic>>;
      _recentDiscrepancies = (results[6] as List).map((e) => {
        'difference': (e as dynamic).difference,
        'created_at': e.createdAt,
      }).toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading dashboard: $e'), backgroundColor: Colors.red),
        );
      }
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Financial Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDashboardData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Today's KPIs
                    _buildSectionTitle('Today\'s Performance'),
                    const SizedBox(height: 12),
                    _buildTodayKPIs(),
                    
                    const SizedBox(height: 24),
                    
                    // Open Shifts Alert
                    if (_openShifts.isNotEmpty) ...[
                      _buildOpenShiftsAlert(),
                      const SizedBox(height: 24),
                    ],
                    
                    // Weekly Chart
                    _buildSectionTitle('Weekly Trend'),
                    const SizedBox(height: 12),
                    _buildWeeklyChart(),
                    
                    const SizedBox(height: 24),
                    
                    // Monthly Summary
                    _buildSectionTitle('This Month'),
                    const SizedBox(height: 12),
                    _buildMonthlySummary(),
                    
                    const SizedBox(height: 24),
                    
                    // Suppliers Overview
                    _buildSectionTitle('Suppliers Overview'),
                    const SizedBox(height: 12),
                    _buildSuppliersOverview(),
                    
                    const SizedBox(height: 24),
                    
                    // Recent Discrepancies
                    if (_recentDiscrepancies.isNotEmpty) ...[
                      _buildSectionTitle('Recent Discrepancies'),
                      const SizedBox(height: 12),
                      _buildDiscrepanciesList(),
                    ],
                    
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildTodayKPIs() {
    final totalSales = (_todaySummary['total_sales'] as num?)?.toDouble() ?? 0;
    final totalExpenses = (_todaySummary['total_expenses'] as num?)?.toDouble() ?? 0;
    final netProfit = totalSales - totalExpenses;
    final closureCount = (_todaySummary['total_closures'] as num?)?.toInt() ?? 0;
    
    return Row(
      children: [
        Expanded(
          child: _buildKPICard(
            'Sales',
            _compactCurrencyFormat.format(totalSales),
            Icons.trending_up,
            Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKPICard(
            'Expenses',
            _compactCurrencyFormat.format(totalExpenses),
            Icons.trending_down,
            Colors.red,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKPICard(
            'Net Profit',
            _compactCurrencyFormat.format(netProfit),
            Icons.account_balance,
            netProfit >= 0 ? Colors.blue : Colors.red,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKPICard(
            'Closed Shifts',
            closureCount.toString(),
            Icons.check_circle,
            Colors.purple,
          ),
        ),
      ],
    );
  }

  Widget _buildKPICard(String label, String value, IconData icon, Color color) {
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
                Flexible(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
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

  Widget _buildOpenShiftsAlert() {
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_openShifts.length} Open Shift${_openShifts.length > 1 ? 's' : ''}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  Text(
                    'Remember to close all shifts at the end of the day',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pushNamed(context, '/financial-shift'),
              child: const Text('View'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyChart() {
    if (_weeklyTotals.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              'No data for this week',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      );
    }
    
    // Prepare chart data
    final salesData = <FlSpot>[];
    final expenseData = <FlSpot>[];
    final labels = <String>[];
    
    for (int i = 0; i < _weeklyTotals.length && i < 7; i++) {
      final day = _weeklyTotals[i];
      final sales = (day['total_sales'] as num?)?.toDouble() ?? 0;
      final expenses = (day['total_expenses'] as num?)?.toDouble() ?? 0;
      final date = DateTime.tryParse(day['date'] as String? ?? '');
      
      salesData.add(FlSpot(i.toDouble(), sales / 1000)); // Convert to thousands
      expenseData.add(FlSpot(i.toDouble(), expenses / 1000));
      labels.add(date != null ? _dateFormat.format(date) : '');
    }
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < labels.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                labels[index],
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          }
                          return const Text('');
                        },
                        reservedSize: 30,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) => Text(
                          '${value.toInt()}K',
                          style: const TextStyle(fontSize: 10),
                        ),
                        reservedSize: 40,
                      ),
                    ),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: salesData,
                      isCurved: true,
                      color: Colors.green,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                    ),
                    LineChartBarData(
                      spots: expenseData,
                      isCurved: true,
                      color: Colors.red,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('Sales', Colors.green),
                const SizedBox(width: 24),
                _buildLegendItem('Expenses', Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildMonthlySummary() {
    final totalSales = (_monthSummary['total_sales'] as num?)?.toDouble() ?? 0;
    final totalExpenses = (_monthSummary['total_expenses'] as num?)?.toDouble() ?? 0;
    final totalCash = (_monthSummary['total_cash'] as num?)?.toDouble() ?? 0;
    final totalCard = (_monthSummary['total_card'] as num?)?.toDouble() ?? 0;
    final totalWallet = (_monthSummary['total_wallet'] as num?)?.toDouble() ?? 0;
    final shortages = (_monthSummary['total_shortages'] as num?)?.toDouble() ?? 0;
    final overages = (_monthSummary['total_overages'] as num?)?.toDouble() ?? 0;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Main Summary
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Sales', style: Theme.of(context).textTheme.bodySmall),
                      Text(
                        _currencyFormat.format(totalSales),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Expenses', style: Theme.of(context).textTheme.bodySmall),
                      Text(
                        _currencyFormat.format(totalExpenses),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Net Profit', style: Theme.of(context).textTheme.bodySmall),
                      Text(
                        _currencyFormat.format(totalSales - totalExpenses),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: totalSales >= totalExpenses ? Colors.blue : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            
            // Payment Method Breakdown
            Text('Sales by Payment Method', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildPaymentMethodChip('Cash', totalCash, Colors.green)),
                Expanded(child: _buildPaymentMethodChip('Card', totalCard, Colors.blue)),
                Expanded(child: _buildPaymentMethodChip('Wallet', totalWallet, Colors.orange)),
              ],
            ),
            
            if (shortages > 0 || overages > 0) ...[
              const Divider(height: 32),
              Row(
                children: [
                  if (shortages > 0)
                    Expanded(
                      child: ListTile(
                        leading: Icon(Icons.arrow_downward, color: Colors.red.shade700),
                        title: const Text('Total Shortages'),
                        subtitle: Text(
                          _currencyFormat.format(shortages),
                          style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  if (overages > 0)
                    Expanded(
                      child: ListTile(
                        leading: Icon(Icons.arrow_upward, color: Colors.blue.shade700),
                        title: const Text('Total Overages'),
                        subtitle: Text(
                          _currencyFormat.format(overages),
                          style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodChip(String label, double value, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _compactCurrencyFormat.format(value),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildSuppliersOverview() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Total Owed
            Row(
              children: [
                Icon(Icons.account_balance, color: Colors.red.shade700, size: 40),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Owed to Suppliers', style: Theme.of(context).textTheme.bodySmall),
                      Text(
                        _currencyFormat.format(_totalOwedToSuppliers),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: () => Navigator.pushNamed(context, '/suppliers'),
                  child: const Text('View All'),
                ),
              ],
            ),
            
            if (_topSuppliers.isNotEmpty) ...[
              const Divider(height: 32),
              Text('Top Suppliers by Balance', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ..._topSuppliers.take(5).map((s) => ListTile(
                dense: true,
                leading: const CircleAvatar(child: Icon(Icons.business, size: 16)),
                title: Text(s['name'] as String? ?? 'Unknown'),
                trailing: Text(
                  _currencyFormat.format((s['balance'] as num?)?.toDouble() ?? 0),
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiscrepanciesList() {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Text(
                  'Cash Discrepancies',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._recentDiscrepancies.map((d) {
              final difference = (d['difference'] as num?)?.toDouble() ?? 0;
              final isShortage = difference < 0;
              final date = d['created_at'] as DateTime?;
              
              return ListTile(
                dense: true,
                leading: Icon(
                  isShortage ? Icons.arrow_downward : Icons.arrow_upward,
                  color: isShortage ? Colors.red : Colors.blue,
                ),
                title: Text(
                  '${isShortage ? "Shortage" : "Overage"}: ${_currencyFormat.format(difference.abs())}',
                  style: TextStyle(
                    color: isShortage ? Colors.red.shade700 : Colors.blue.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: date != null ? Text(_dateFormat.format(date)) : null,
              );
            }),
          ],
        ),
      ),
    );
  }
}
