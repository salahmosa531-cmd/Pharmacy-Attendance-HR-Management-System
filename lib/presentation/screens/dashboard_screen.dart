import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/services.dart';
import '../../core/utils/app_localizations.dart';
import '../../data/repositories/repositories.dart';

/// Dashboard screen with overview and statistics
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final AttendanceService _attendanceService = AttendanceService.instance;
  final EmployeeRepository _employeeRepository = EmployeeRepository.instance;
  final AuthService _authService = AuthService.instance;
  
  bool _isLoading = true;
  String? _loadError;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _currentlyWorking = [];
  List<Map<String, dynamic>> _lateArrivals = [];
  List<Map<String, dynamic>> _absentees = [];
  int _totalEmployees = 0;
  
  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }
  
  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    
    setState(() => _isLoading = true);
    
    try {
      final branchId = '1';
      if (branchId == null) return;
      
      final results = await Future.wait([
        _attendanceService.getTodaySummary(),
        _attendanceService.getCurrentlyClockedIn(),
        _attendanceService.getTodayLateArrivals(),
        _attendanceService.getTodayAbsentees(),
        _employeeRepository.getCountByBranch(branchId),
      ]);
      
      if (!mounted) return;
      
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        _currentlyWorking = results[1] as List<Map<String, dynamic>>;
        _lateArrivals = results[2] as List<Map<String, dynamic>>;
        _absentees = results[3] as List<Map<String, dynamic>>;
        _totalEmployees = results[4] as int;
        _isLoading = false;
      });
    } catch (e) {
      LoggingService.instance.error('Dashboard', 'Failed to load dashboard data', e, StackTrace.current);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Failed to load dashboard data. Please try again.';
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _buildErrorView()
              : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome section
                  _buildWelcomeSection(),
                  const SizedBox(height: 24),
                  
                  // Statistics cards
                  _buildStatisticsCards(),
                  const SizedBox(height: 24),
                  
                  // Charts and lists row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Attendance chart
                      Expanded(
                        flex: 2,
                        child: _buildAttendanceChart(),
                      ),
                      const SizedBox(width: 24),
                      
                      // Currently working
                      Expanded(
                        flex: 1,
                        child: _buildCurrentlyWorkingCard(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Late arrivals and absentees
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildLateArrivalsCard(),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: _buildAbsenteesCard(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
  
  Widget _buildWelcomeSection() {
    final now = DateTime.now();
    final greeting = _getGreeting(now.hour);
    final dateFormat = DateFormat('EEEE, MMMM d, yyyy');
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$greeting, ${_authService.currentUser?.username ?? "User"}!',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              dateFormat.format(now),
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        
        // Quick actions - linked to real navigation/actions
        Row(
          children: [
            _buildQuickActionButton(
              icon: Icons.qr_code,
              label: 'Attendance',
              onTap: () => context.go('/attendance'),
            ),
            const SizedBox(width: 12),
            _buildQuickActionButton(
              icon: Icons.person_add,
              label: 'Add Employee',
              onTap: () => context.go('/employees/new'),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppTheme.primaryColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildStatisticsCards() {
    final clockedIn = (_summary['clocked_in'] as num?)?.toInt() ?? 0;
    final lateCount = (_summary['late_count'] as num?)?.toInt() ?? 0;
    final absentCount = (_summary['absent_count'] as num?)?.toInt() ?? 0;
    final attendanceRate = _totalEmployees > 0 
        ? ((clockedIn / _totalEmployees) * 100).toStringAsFixed(1)
        : '0';
    
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            title: context.tr('total_employees'),
            value: _totalEmployees.toString(),
            icon: Icons.people,
            color: AppTheme.primaryColor,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            title: context.tr('currently_working'),
            value: clockedIn.toString(),
            icon: Icons.work,
            color: AppTheme.successColor,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            title: context.tr('late_today'),
            value: lateCount.toString(),
            icon: Icons.schedule,
            color: AppTheme.warningColor,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            title: context.tr('absent_today'),
            value: absentCount.toString(),
            icon: Icons.person_off,
            color: AppTheme.errorColor,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            title: context.tr('attendance_rate'),
            value: '$attendanceRate%',
            icon: Icons.trending_up,
            color: AppTheme.infoColor,
          ),
        ),
      ],
    );
  }
  
  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAttendanceChart() {
    final clockedIn = (_summary['clocked_in'] as num?)?.toDouble() ?? 0;
    final lateCount = (_summary['late_count'] as num?)?.toDouble() ?? 0;
    final absentCount = (_summary['absent_count'] as num?)?.toDouble() ?? 0;
    final onTimeCount = clockedIn - lateCount;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Today\'s Attendance Breakdown',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  // Pie chart
                  Expanded(
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                        sections: [
                          PieChartSectionData(
                            value: onTimeCount > 0 ? onTimeCount : 0.1,
                            color: AppTheme.successColor,
                            title: onTimeCount > 0 ? '${onTimeCount.toInt()}' : '',
                            titleStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            radius: 50,
                          ),
                          PieChartSectionData(
                            value: lateCount > 0 ? lateCount : 0.1,
                            color: AppTheme.warningColor,
                            title: lateCount > 0 ? '${lateCount.toInt()}' : '',
                            titleStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            radius: 50,
                          ),
                          PieChartSectionData(
                            value: absentCount > 0 ? absentCount : 0.1,
                            color: AppTheme.errorColor,
                            title: absentCount > 0 ? '${absentCount.toInt()}' : '',
                            titleStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            radius: 50,
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Legend
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLegendItem('On Time', onTimeCount.toInt(), AppTheme.successColor),
                      const SizedBox(height: 12),
                      _buildLegendItem('Late', lateCount.toInt(), AppTheme.warningColor),
                      const SizedBox(height: 12),
                      _buildLegendItem('Absent', absentCount.toInt(), AppTheme.errorColor),
                    ],
                  ),
                  const SizedBox(width: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLegendItem(String label, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$label ($count)',
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
  }
  
  Widget _buildCurrentlyWorkingCard() {
    return Card(
      child: Container(
        height: 280,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.tr('currently_working'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_currentlyWorking.length}',
                    style: const TextStyle(
                      color: AppTheme.successColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            Expanded(
              child: _currentlyWorking.isEmpty
                  ? Center(
                      child: Text(
                        'No employees currently working',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _currentlyWorking.length,
                      itemBuilder: (context, index) {
                        final employee = _currentlyWorking[index];
                        final clockIn = employee['clock_in_time'] != null
                            ? DateFormat('hh:mm a').format(
                                DateTime.parse(employee['clock_in_time']),
                              )
                            : '--';
                        
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                            child: Text(
                              (employee['full_name'] as String?)
                                  ?.substring(0, 1)
                                  .toUpperCase() ?? '?',
                              style: const TextStyle(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            employee['full_name'] ?? 'Unknown',
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            'Clocked in: $clockIn',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          trailing: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppTheme.successColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLateArrivalsCard() {
    return Card(
      child: Container(
        height: 300,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.tr('late_today'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_lateArrivals.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.warningColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_lateArrivals.length}',
                      style: const TextStyle(
                        color: AppTheme.warningColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            
            Expanded(
              child: _lateArrivals.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 48,
                            color: AppTheme.successColor.withOpacity(0.5),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No late arrivals today!',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _lateArrivals.length,
                      itemBuilder: (context, index) {
                        final employee = _lateArrivals[index];
                        final lateMinutes = employee['late_minutes'] ?? 0;
                        
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppTheme.warningColor.withOpacity(0.1),
                            child: Text(
                              (employee['full_name'] as String?)
                                  ?.substring(0, 1)
                                  .toUpperCase() ?? '?',
                              style: const TextStyle(
                                color: AppTheme.warningColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            employee['full_name'] ?? 'Unknown',
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            'Late by $lateMinutes minutes',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.warningColor,
                            ),
                          ),
                          trailing: TextButton(
                            onPressed: () {
                              // TODO: Forgive lateness
                            },
                            child: const Text('Forgive'),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAbsenteesCard() {
    return Card(
      child: Container(
        height: 300,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.tr('absent_today'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_absentees.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_absentees.length}',
                      style: const TextStyle(
                        color: AppTheme.errorColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            
            Expanded(
              child: _absentees.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.celebration,
                            size: 48,
                            color: AppTheme.successColor.withOpacity(0.5),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'All employees present!',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _absentees.length,
                      itemBuilder: (context, index) {
                        final employee = _absentees[index];
                        
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppTheme.errorColor.withOpacity(0.1),
                            child: Text(
                              (employee['full_name'] as String?)
                                  ?.substring(0, 1)
                                  .toUpperCase() ?? '?',
                              style: const TextStyle(
                                color: AppTheme.errorColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            employee['full_name'] ?? 'Unknown',
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            employee['shift_name'] ?? 'No shift assigned',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
  
  String _getGreeting(int hour) {
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
  
  /// Build error view with retry option
  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppTheme.errorColor),
            const SizedBox(height: 16),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.errorColor),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _loadError = null;
                  _isLoading = true;
                });
                _loadDashboardData();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
