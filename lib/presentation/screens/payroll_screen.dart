import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/employee_model.dart';
import '../../data/models/payroll_model.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/attendance_repository.dart';

/// Payroll management screen
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  final AuthService _authService = AuthService.instance;
  final EmployeeRepository _employeeRepository = EmployeeRepository.instance;
  final AttendanceRepository _attendanceRepository = AttendanceRepository.instance;
  
  bool _isLoading = true;
  List<Employee> _employees = [];
  List<PayrollSummary> _payrollSummaries = [];
  
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  
  final _dateFormat = DateFormat('MMM dd, yyyy');
  final _currencyFormat = NumberFormat.currency(symbol: '\$');
  
  @override
  void initState() {
    super.initState();
    // Set to first day of current month
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month + 1, 0);
    _loadData();
  }
  
  Future<void> _loadData() async {
    final branchId = _authService.currentBranch?.id;
    if (branchId == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      _employees = await _employeeRepository.getByBranch(branchId, activeOnly: false);
      _payrollSummaries = await _calculatePayroll();
      
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }
  
  Future<List<PayrollSummary>> _calculatePayroll() async {
    final summaries = <PayrollSummary>[];
    
    for (final employee in _employees) {
      final summary = await _attendanceRepository.getEmployeeSummary(
        employee.id,
        _startDate,
        _endDate,
      );
      
      double baseSalary = 0;
      double deductions = 0;
      double overtime = 0;
      
      switch (employee.salaryType) {
        case SalaryType.monthly:
          baseSalary = employee.salaryValue;
          // Deduct for absent days
          final workingDays = _calculateWorkingDays(_startDate, _endDate);
          final absentDays = summary['absent_count'] ?? 0;
          final dailyRate = employee.salaryValue / workingDays;
          deductions = dailyRate * absentDays;
          break;
        case SalaryType.hourly:
          final workedHours = (summary['total_worked_hours'] ?? 0).toDouble();
          baseSalary = workedHours * employee.salaryValue;
          // Overtime calculation
          final regularHours = 8.0 * _calculateWorkingDays(_startDate, _endDate);
          if (workedHours > regularHours) {
            overtime = (workedHours - regularHours) * employee.salaryValue * (AppConstants.defaultOvertimeMultiplier - 1);
          }
          break;
        case SalaryType.perShift:
          final shiftsWorked = (summary['present_count'] ?? 0) + (summary['late_count'] ?? 0);
          baseSalary = shiftsWorked * employee.salaryValue;
          break;
      }
      
      // Late penalty (example: 1% of daily rate per late)
      final lateCount = summary['late_count'] ?? 0;
      final latePenalty = employee.salaryType == SalaryType.monthly 
          ? (employee.salaryValue / 30) * 0.01 * lateCount 
          : 0.0;
      
      summaries.add(PayrollSummary(
        employee: employee,
        startDate: _startDate,
        endDate: _endDate,
        baseSalary: baseSalary,
        overtime: overtime,
        deductions: deductions + latePenalty,
        netSalary: baseSalary + overtime - deductions - latePenalty,
        daysWorked: (summary['present_count'] ?? 0) + (summary['late_count'] ?? 0),
        daysAbsent: summary['absent_count'] ?? 0,
        lateCount: lateCount,
        totalHours: (summary['total_worked_hours'] ?? 0).toDouble(),
      ));
    }
    
    return summaries;
  }
  
  int _calculateWorkingDays(DateTime start, DateTime end) {
    int count = 0;
    DateTime current = start;
    while (current.isBefore(end) || current.isAtSameMomentAs(end)) {
      if (current.weekday != DateTime.saturday && current.weekday != DateTime.sunday) {
        count++;
      }
      current = current.add(const Duration(days: 1));
    }
    return count;
  }
  
  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadData();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Payroll',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Period: ${_dateFormat.format(_startDate)} - ${_dateFormat.format(_endDate)}',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range),
                label: const Text('Change Period'),
                onPressed: _selectDateRange,
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Export'),
                onPressed: () {
                  // TODO: Export payroll
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Summary Cards
          Row(
            children: [
              _buildSummaryCard(
                'Total Payroll',
                _currencyFormat.format(
                  _payrollSummaries.fold(0.0, (sum, s) => sum + s.netSalary),
                ),
                Icons.account_balance_wallet,
                AppTheme.primaryColor,
              ),
              const SizedBox(width: 16),
              _buildSummaryCard(
                'Total Base',
                _currencyFormat.format(
                  _payrollSummaries.fold(0.0, (sum, s) => sum + s.baseSalary),
                ),
                Icons.payments,
                AppTheme.successColor,
              ),
              const SizedBox(width: 16),
              _buildSummaryCard(
                'Total Overtime',
                _currencyFormat.format(
                  _payrollSummaries.fold(0.0, (sum, s) => sum + s.overtime),
                ),
                Icons.schedule,
                AppTheme.warningColor,
              ),
              const SizedBox(width: 16),
              _buildSummaryCard(
                'Total Deductions',
                _currencyFormat.format(
                  _payrollSummaries.fold(0.0, (sum, s) => sum + s.deductions),
                ),
                Icons.remove_circle_outline,
                AppTheme.errorColor,
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Payroll Table
          Expanded(
            child: Card(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _payrollSummaries.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.payment,
                                size: 64,
                                color: AppTheme.textDisabled,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No payroll data available',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _buildPayrollTable(),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildPayrollTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppTheme.backgroundColor),
          columns: const [
            DataColumn(label: Text('Employee', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Type', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Days Worked', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('Absent', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('Late', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('Hours', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('Base Salary', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('Overtime', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('Deductions', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('Net Salary', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: _payrollSummaries.map((summary) {
            return DataRow(
              cells: [
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                        child: Text(
                          summary.employee.initials,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            summary.employee.fullName,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            summary.employee.employeeCode,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      summary.employee.salaryType.displayName,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                DataCell(Text(summary.daysWorked.toString())),
                DataCell(Text(
                  summary.daysAbsent.toString(),
                  style: TextStyle(
                    color: summary.daysAbsent > 0 ? AppTheme.errorColor : null,
                  ),
                )),
                DataCell(Text(
                  summary.lateCount.toString(),
                  style: TextStyle(
                    color: summary.lateCount > 0 ? AppTheme.warningColor : null,
                  ),
                )),
                DataCell(Text(summary.totalHours.toStringAsFixed(1))),
                DataCell(Text(_currencyFormat.format(summary.baseSalary))),
                DataCell(Text(
                  _currencyFormat.format(summary.overtime),
                  style: TextStyle(
                    color: summary.overtime > 0 ? AppTheme.successColor : null,
                  ),
                )),
                DataCell(Text(
                  '-${_currencyFormat.format(summary.deductions)}',
                  style: const TextStyle(color: AppTheme.errorColor),
                )),
                DataCell(Text(
                  _currencyFormat.format(summary.netSalary),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                )),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.visibility, size: 20),
                        tooltip: 'View Details',
                        onPressed: () => _showPayrollDetails(summary),
                      ),
                      IconButton(
                        icon: const Icon(Icons.print, size: 20),
                        tooltip: 'Print Payslip',
                        onPressed: () {
                          // TODO: Print payslip
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
  
  void _showPayrollDetails(PayrollSummary summary) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
              child: Text(
                summary.employee.initials,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(summary.employee.fullName),
                Text(
                  summary.employee.employeeCode,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Period', '${_dateFormat.format(_startDate)} - ${_dateFormat.format(_endDate)}'),
              _buildDetailRow('Salary Type', summary.employee.salaryType.displayName),
              const Divider(),
              _buildDetailRow('Days Worked', summary.daysWorked.toString()),
              _buildDetailRow('Days Absent', summary.daysAbsent.toString()),
              _buildDetailRow('Times Late', summary.lateCount.toString()),
              _buildDetailRow('Total Hours', summary.totalHours.toStringAsFixed(1)),
              const Divider(),
              _buildDetailRow('Base Salary', _currencyFormat.format(summary.baseSalary)),
              if (summary.overtime > 0)
                _buildDetailRow('Overtime', _currencyFormat.format(summary.overtime), isGreen: true),
              if (summary.deductions > 0)
                _buildDetailRow('Deductions', '-${_currencyFormat.format(summary.deductions)}', isRed: true),
              const Divider(),
              _buildDetailRow('Net Salary', _currencyFormat.format(summary.netSalary), isBold: true),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.print),
            label: const Text('Print Payslip'),
            onPressed: () {
              Navigator.pop(context);
              // TODO: Print payslip
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value, {bool isBold = false, bool isRed = false, bool isGreen = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: isBold ? FontWeight.bold : null,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isRed ? AppTheme.errorColor : isGreen ? AppTheme.successColor : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Payroll summary for an employee
class PayrollSummary {
  final Employee employee;
  final DateTime startDate;
  final DateTime endDate;
  final double baseSalary;
  final double overtime;
  final double deductions;
  final double netSalary;
  final int daysWorked;
  final int daysAbsent;
  final int lateCount;
  final double totalHours;
  
  PayrollSummary({
    required this.employee,
    required this.startDate,
    required this.endDate,
    required this.baseSalary,
    required this.overtime,
    required this.deductions,
    required this.netSalary,
    required this.daysWorked,
    required this.daysAbsent,
    required this.lateCount,
    required this.totalHours,
  });
}
