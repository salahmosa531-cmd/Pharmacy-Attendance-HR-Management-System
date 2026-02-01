import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as excel;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/employee_model.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/attendance_repository.dart';

/// Reports screen with PDF/Excel export
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final AuthService _authService = AuthService.instance;
  final EmployeeRepository _employeeRepository = EmployeeRepository.instance;
  final AttendanceRepository _attendanceRepository = AttendanceRepository.instance;
  
  String _selectedReportType = 'daily';
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  String? _selectedEmployeeId;
  List<Employee> _employees = [];
  bool _isLoading = false;
  List<Map<String, dynamic>> _reportData = [];
  
  final _dateFormat = DateFormat('yyyy-MM-dd');
  final _displayDateFormat = DateFormat('MMM dd, yyyy');
  
  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }
  
  Future<void> _loadEmployees() async {
    final branchId = _authService.currentBranch?.id;
    if (branchId == null) return;
    
    _employees = await _employeeRepository.getByBranch(branchId, activeOnly: false);
    setState(() {});
  }
  
  Future<void> _generateReport() async {
    final branchId = _authService.currentBranch?.id;
    if (branchId == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      switch (_selectedReportType) {
        case 'daily':
          _reportData = await _attendanceRepository.getDailyReport(branchId, _startDate);
          break;
        case 'weekly':
          final weekStart = _startDate.subtract(Duration(days: _startDate.weekday - 1));
          final weekEnd = weekStart.add(const Duration(days: 6));
          _reportData = await _attendanceRepository.getDateRangeReport(branchId, weekStart, weekEnd);
          break;
        case 'monthly':
          final monthStart = DateTime(_startDate.year, _startDate.month, 1);
          final monthEnd = DateTime(_startDate.year, _startDate.month + 1, 0);
          _reportData = await _attendanceRepository.getDateRangeReport(branchId, monthStart, monthEnd);
          break;
        case 'employee':
          if (_selectedEmployeeId != null) {
            _reportData = await _attendanceRepository.getEmployeeReport(
              _selectedEmployeeId!,
              _startDate,
              _endDate,
            );
          }
          break;
      }
      
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to generate report: $e');
    }
  }
  
  Future<void> _exportToPdf() async {
    final pdf = pw.Document();
    
    final branchName = _authService.currentBranch?.name ?? 'Unknown Branch';
    final reportTitle = _getReportTitle();
    
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Pharmacy Attendance System',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(branchName, style: const pw.TextStyle(fontSize: 14)),
                  ],
                ),
                pw.Text(
                  'Generated: ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              reportTitle,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Divider(),
          ],
        ),
        build: (context) => [
          pw.Table.fromTextArray(
            headers: _getTableHeaders(),
            data: _reportData.map((row) => _formatRowForPdf(row)).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellHeight: 30,
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.center,
              2: pw.Alignment.center,
              3: pw.Alignment.center,
              4: pw.Alignment.center,
            },
          ),
        ],
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
    );
    
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'attendance_report_${_dateFormat.format(DateTime.now())}.pdf',
    );
  }
  
  Future<void> _exportToExcel() async {
    final excelDoc = excel.Excel.createExcel();
    final sheet = excelDoc['Attendance Report'];
    
    // Add headers
    final headers = _getTableHeaders();
    for (var i = 0; i < headers.length; i++) {
      sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value =
          excel.TextCellValue(headers[i]);
    }
    
    // Add data
    for (var rowIndex = 0; rowIndex < _reportData.length; rowIndex++) {
      final rowData = _formatRowForExcel(_reportData[rowIndex]);
      for (var colIndex = 0; colIndex < rowData.length; colIndex++) {
        sheet.cell(excel.CellIndex.indexByColumnRow(
          columnIndex: colIndex, 
          rowIndex: rowIndex + 1,
        )).value = excel.TextCellValue(rowData[colIndex]);
      }
    }
    
    // Save file
    final bytes = excelDoc.encode();
    if (bytes == null) return;
    
    final fileName = 'attendance_report_${_dateFormat.format(DateTime.now())}.xlsx';
    
    // Show save dialog
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Excel Report',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    
    if (result != null) {
      final file = File(result);
      await file.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Report saved to $result'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    }
  }
  
  List<String> _getTableHeaders() {
    switch (_selectedReportType) {
      case 'daily':
        return ['Employee', 'Status', 'Clock In', 'Clock Out', 'Hours', 'Late (min)'];
      case 'weekly':
      case 'monthly':
        return ['Employee', 'Days Present', 'Days Late', 'Days Absent', 'Total Hours', 'Late (min)'];
      case 'employee':
        return ['Date', 'Status', 'Clock In', 'Clock Out', 'Hours', 'Late (min)'];
      default:
        return [];
    }
  }
  
  List<String> _formatRowForPdf(Map<String, dynamic> row) {
    switch (_selectedReportType) {
      case 'daily':
        return [
          row['employee_name'] ?? '',
          row['status'] ?? '',
          row['clock_in'] ?? '-',
          row['clock_out'] ?? '-',
          (row['worked_hours'] ?? 0).toStringAsFixed(1),
          (row['late_minutes'] ?? 0).toString(),
        ];
      case 'weekly':
      case 'monthly':
        return [
          row['employee_name'] ?? '',
          (row['present_count'] ?? 0).toString(),
          (row['late_count'] ?? 0).toString(),
          (row['absent_count'] ?? 0).toString(),
          (row['total_hours'] ?? 0).toStringAsFixed(1),
          (row['total_late_minutes'] ?? 0).toString(),
        ];
      case 'employee':
        return [
          row['date'] != null ? _displayDateFormat.format(DateTime.parse(row['date'])) : '',
          row['status'] ?? '',
          row['clock_in'] ?? '-',
          row['clock_out'] ?? '-',
          (row['worked_hours'] ?? 0).toStringAsFixed(1),
          (row['late_minutes'] ?? 0).toString(),
        ];
      default:
        return [];
    }
  }
  
  List<String> _formatRowForExcel(Map<String, dynamic> row) {
    return _formatRowForPdf(row);
  }
  
  String _getReportTitle() {
    switch (_selectedReportType) {
      case 'daily':
        return 'Daily Attendance Report - ${_displayDateFormat.format(_startDate)}';
      case 'weekly':
        final weekStart = _startDate.subtract(Duration(days: _startDate.weekday - 1));
        final weekEnd = weekStart.add(const Duration(days: 6));
        return 'Weekly Attendance Report - ${_displayDateFormat.format(weekStart)} to ${_displayDateFormat.format(weekEnd)}';
      case 'monthly':
        return 'Monthly Attendance Report - ${DateFormat('MMMM yyyy').format(_startDate)}';
      case 'employee':
        final employee = _employees.firstWhere(
          (e) => e.id == _selectedEmployeeId,
          orElse: () => _employees.first,
        );
        return 'Employee Report - ${employee.fullName} (${_displayDateFormat.format(_startDate)} to ${_displayDateFormat.format(_endDate)})';
      default:
        return 'Attendance Report';
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reports',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          
          // Report Type Selection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Generate Report',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Report Type
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Report Type'),
                            const SizedBox(height: 8),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'daily', label: Text('Daily')),
                                ButtonSegment(value: 'weekly', label: Text('Weekly')),
                                ButtonSegment(value: 'monthly', label: Text('Monthly')),
                                ButtonSegment(value: 'employee', label: Text('Employee')),
                              ],
                              selected: {_selectedReportType},
                              onSelectionChanged: (Set<String> newSelection) {
                                setState(() {
                                  _selectedReportType = newSelection.first;
                                  _reportData = [];
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      // Date Selection
                      if (_selectedReportType != 'employee') ...[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Select Date'),
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _startDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                  );
                                  if (picked != null) {
                                    setState(() => _startDate = picked);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.calendar_today),
                                      const SizedBox(width: 8),
                                      Text(_displayDateFormat.format(_startDate)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // Employee Selection and Date Range
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Select Employee'),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                value: _selectedEmployeeId,
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.person),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                                hint: const Text('Select employee'),
                                items: _employees.map((e) => DropdownMenuItem(
                                  value: e.id,
                                  child: Text('${e.fullName} (${e.employeeCode})'),
                                )).toList(),
                                onChanged: (value) {
                                  setState(() => _selectedEmployeeId = value);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Date Range'),
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () async {
                                  final picked = await showDateRangePicker(
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
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.date_range),
                                      const SizedBox(width: 8),
                                      Text('${_displayDateFormat.format(_startDate)} - ${_displayDateFormat.format(_endDate)}'),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(width: 16),
                      
                      // Generate Button
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(' '),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.analytics),
                            label: const Text('Generate'),
                            onPressed: _generateReport,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Report Results
          Expanded(
            child: Card(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _reportData.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.assessment_outlined,
                                size: 64,
                                color: AppTheme.textDisabled,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Select options and click Generate',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            // Report Header with Export Buttons
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _getReportTitle(),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.picture_as_pdf),
                                    label: const Text('Export PDF'),
                                    onPressed: _exportToPdf,
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.table_chart),
                                    label: const Text('Export Excel'),
                                    onPressed: _exportToExcel,
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            
                            // Report Table
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SingleChildScrollView(
                                  child: DataTable(
                                    headingRowColor: WidgetStateProperty.all(
                                      AppTheme.backgroundColor,
                                    ),
                                    columns: _getTableHeaders()
                                        .map((h) => DataColumn(
                                              label: Text(
                                                h,
                                                style: const TextStyle(fontWeight: FontWeight.bold),
                                              ),
                                            ))
                                        .toList(),
                                    rows: _reportData.map((row) {
                                      final cells = _formatRowForPdf(row);
                                      return DataRow(
                                        cells: cells.map((c) => DataCell(Text(c))).toList(),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
            ),
          ),
        ],
      ),
    );
  }
}
