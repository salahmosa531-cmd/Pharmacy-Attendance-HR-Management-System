import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/services.dart';
import '../../core/services/settings_service.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/attendance_model.dart';
import '../../data/repositories/repositories.dart';

/// Kiosk Mode - Default screen for employee attendance
/// 
/// This is the PUBLIC screen employees see when they come to clock in/out.
/// It provides:
/// - Simple clock in/out functionality
/// - Multiple input methods based on settings
/// - Clear feedback on success/failure
/// - No access to admin features
/// - Hidden admin access via keyboard shortcut (Ctrl+Shift+A)
class KioskScreen extends StatefulWidget {
  const KioskScreen({super.key});

  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> {
  final AttendanceService _attendanceService = AttendanceService.instance;
  final SettingsService _settingsService = SettingsService.instance;
  final QrService _qrService = QrService.instance;
  final EmployeeRepository _employeeRepository = EmployeeRepository.instance;
  final AttendanceRepository _attendanceRepository = AttendanceRepository.instance;
  
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocusNode = FocusNode();
  
  bool _isClockIn = true;
  bool _isProcessing = false;
  String? _message;
  bool _isError = false;
  String? _lastEmployeeName;
  DateTime? _lastActionTime;
  
  // QR Code
  String? _qrCode;
  Timer? _qrTimer;
  int _qrSecondsRemaining = 0;
  
  // Clock
  Timer? _clockTimer;
  DateTime _currentTime = DateTime.now();
  
  // Settings stream subscription
  StreamSubscription<SettingsState>? _settingsSubscription;
  SettingsState _settings = const SettingsState();
  
  // Recent attendance records
  List<Map<String, dynamic>> _recentRecords = [];
  
  // Admin access
  final _adminPasswordController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _initializeKiosk();
  }
  
  Future<void> _initializeKiosk() async {
    // Load settings
    await _settingsService.initialize();
    _settings = _settingsService.currentState;
    
    // Subscribe to settings changes
    _settingsSubscription = _settingsService.settingsStream.listen((state) {
      setState(() => _settings = state);
    });
    
    // Start clock timer
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _currentTime = DateTime.now());
    });
    
    // Generate QR code if enabled
    if (_settings.allowQrEntry) {
      _generateQrCode();
    }
    
    // Load recent records
    _loadRecentRecords();
    
    // Request focus on input
    _codeFocusNode.requestFocus();
    
    setState(() {});
  }
  
  @override
  void dispose() {
    _codeController.dispose();
    _codeFocusNode.dispose();
    _adminPasswordController.dispose();
    _qrTimer?.cancel();
    _clockTimer?.cancel();
    _settingsSubscription?.cancel();
    super.dispose();
  }
  
  Future<void> _generateQrCode() async {
    try {
      final data = await _qrService.generateQrDisplayData();
      setState(() {
        _qrCode = data['token'] as String?;
        _qrSecondsRemaining = _settings.qrRefreshSeconds;
      });
      
      _qrTimer?.cancel();
      _qrTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_qrSecondsRemaining > 0) {
          setState(() => _qrSecondsRemaining--);
        } else {
          _generateQrCode();
        }
      });
    } catch (e) {
      // Handle error silently
    }
  }
  
  Future<void> _loadRecentRecords() async {
    if (!_settings.showLastAttendance) return;
    
    try {
      final branchId = AuthService.instance.currentBranch?.id;
      if (branchId == null) return;
      
      final records = await _attendanceRepository.getByBranchDate(branchId, DateTime.now());
      final recentWithNames = <Map<String, dynamic>>[];
      
      for (final record in records.take(5)) {
        final employee = await _employeeRepository.getById(record.employeeId);
        if (employee != null) {
          recentWithNames.add({
            'name': employee.fullName,
            'time': record.clockInTime,
            'type': 'in',
          });
          if (record.clockOutTime != null) {
            recentWithNames.add({
              'name': employee.fullName,
              'time': record.clockOutTime,
              'type': 'out',
            });
          }
        }
      }
      
      // Sort by time descending
      recentWithNames.sort((a, b) => (b['time'] as DateTime).compareTo(a['time'] as DateTime));
      
      setState(() {
        _recentRecords = recentWithNames.take(3).toList();
      });
    } catch (e) {
      // Ignore errors
    }
  }
  
  Future<void> _processAttendance(String code) async {
    if (code.isEmpty || _isProcessing) return;
    
    setState(() {
      _isProcessing = true;
      _message = null;
    });
    
    try {
      if (_isClockIn) {
        final record = await _attendanceService.clockIn(
          employeeIdentifier: code,
          method: AttendanceMethod.manual,
        );
        
        // Get employee name
        final employee = await _employeeRepository.getById(record.employeeId);
        
        setState(() {
          _message = 'Welcome, ${employee?.fullName ?? "Employee"}! Clock in successful.';
          _lastEmployeeName = employee?.fullName;
          _lastActionTime = DateTime.now();
          _isError = false;
        });
        
        // Play success sound
        if (_settings.soundEnabled) {
          _playSound(true);
        }
      } else {
        final record = await _attendanceService.clockOut(
          employeeIdentifier: code,
          method: AttendanceMethod.manual,
        );
        
        // Get employee name
        final employee = await _employeeRepository.getById(record.employeeId);
        
        // Calculate worked hours
        final workedMinutes = record.workedMinutes ?? 0;
        final hours = workedMinutes ~/ 60;
        final minutes = workedMinutes % 60;
        
        setState(() {
          _message = 'Goodbye, ${employee?.fullName ?? "Employee"}! Worked: ${hours}h ${minutes}m';
          _lastEmployeeName = employee?.fullName;
          _lastActionTime = DateTime.now();
          _isError = false;
        });
        
        // Play success sound
        if (_settings.soundEnabled) {
          _playSound(true);
        }
      }
      
      // Reload recent records
      _loadRecentRecords();
    } catch (e) {
      setState(() {
        _message = e.toString().replaceAll('Exception: ', '');
        _isError = true;
      });
      
      // Play error sound
      if (_settings.soundEnabled) {
        _playSound(false);
      }
    } finally {
      setState(() => _isProcessing = false);
      _codeController.clear();
      _codeFocusNode.requestFocus();
      
      // Clear message after delay
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() => _message = null);
        }
      });
    }
  }
  
  void _playSound(bool success) {
    // TODO: Implement actual sound playback
    // For now, use system beep
    SystemSound.play(success ? SystemSoundType.click : SystemSoundType.alert);
  }
  
  void _showAdminAccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.admin_panel_settings, color: AppTheme.primaryColor),
            const SizedBox(width: 12),
            const Text('Admin Access'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter admin password to access the dashboard.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _adminPasswordController,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _validateAdminAccess(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _adminPasswordController.clear();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _validateAdminAccess,
            child: const Text('Login'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _validateAdminAccess() async {
    final password = _adminPasswordController.text;
    _adminPasswordController.clear();
    
    // Check if password matches stored admin password
    // For now, redirect to login screen
    Navigator.pop(context);
    context.go('/login');
  }
  
  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        // Hidden admin access: Ctrl+Shift+A
        if (event is KeyDownEvent &&
            HardwareKeyboard.instance.isControlPressed &&
            HardwareKeyboard.instance.isShiftPressed &&
            event.logicalKey == LogicalKeyboardKey.keyA) {
          _showAdminAccessDialog();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              // Header with clock and pharmacy info
              _buildHeader(),
              
              // Main content
              Expanded(
                child: Row(
                  children: [
                    // Left side - Clock In/Out
                    Expanded(
                      flex: 3,
                      child: _buildAttendanceSection(),
                    ),
                    
                    // Right side - QR Code and recent records
                    if (_settings.allowQrEntry || _settings.showLastAttendance)
                      Expanded(
                        flex: 2,
                        child: _buildSidePanel(),
                      ),
                  ],
                ),
              ),
              
              // Footer with instructions
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo and name
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.medical_services,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AuthService.instance.currentBranch?.name ?? 'Pharmacy Attendance',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Employee Attendance System',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          const Spacer(),
          
          // Current time
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                DateFormat('EEEE, MMMM d, yyyy').format(_currentTime),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              Text(
                DateFormat('hh:mm:ss a').format(_currentTime),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildAttendanceSection() {
    return Container(
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Clock In/Out toggle
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildToggleButton(
                  label: 'Clock In',
                  icon: Icons.login,
                  isSelected: _isClockIn,
                  color: AppTheme.successColor,
                  onTap: () => setState(() => _isClockIn = true),
                ),
                _buildToggleButton(
                  label: 'Clock Out',
                  icon: Icons.logout,
                  isSelected: !_isClockIn,
                  color: AppTheme.primaryColor,
                  onTap: () => setState(() => _isClockIn = false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),
          
          // Large icon
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: (_isClockIn ? AppTheme.successColor : AppTheme.primaryColor).withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: (_isClockIn ? AppTheme.successColor : AppTheme.primaryColor).withValues(alpha: 0.3),
                width: 3,
              ),
            ),
            child: Icon(
              _isClockIn ? Icons.login : Icons.logout,
              size: 72,
              color: _isClockIn ? AppTheme.successColor : AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 32),
          
          // Title
          Text(
            _isClockIn ? 'Clock In' : 'Clock Out',
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          
          // Instructions
          Text(
            _getInstructionText(),
            style: TextStyle(
              fontSize: 16,
              color: AppTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          
          // Input field (if manual entry enabled)
          if (_settings.allowManualEntry) ...[
            SizedBox(
              width: 400,
              child: TextField(
                controller: _codeController,
                focusNode: _codeFocusNode,
                decoration: InputDecoration(
                  hintText: 'Enter Employee Code',
                  prefixIcon: const Icon(Icons.badge, size: 28),
                  suffixIcon: IconButton(
                    icon: Icon(
                      Icons.arrow_forward_rounded,
                      color: _isClockIn ? AppTheme.successColor : AppTheme.primaryColor,
                    ),
                    onPressed: () => _processAttendance(_codeController.text.trim()),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.dividerColor, width: 2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _isClockIn ? AppTheme.successColor : AppTheme.primaryColor,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 2,
                ),
                onSubmitted: (value) => _processAttendance(value.trim()),
              ),
            ),
            const SizedBox(height: 24),
          ],
          
          // Status message
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: _message != null ? null : 0,
            child: _message != null
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    decoration: BoxDecoration(
                      color: (_isError ? AppTheme.errorColor : AppTheme.successColor).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isError ? AppTheme.errorColor : AppTheme.successColor,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isError ? Icons.error_outline : Icons.check_circle,
                          color: _isError ? AppTheme.errorColor : AppTheme.successColor,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            _message!,
                            style: TextStyle(
                              color: _isError ? AppTheme.errorColor : AppTheme.successColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          
          if (_isProcessing) ...[
            const SizedBox(height: 24),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(
                _isClockIn ? AppTheme.successColor : AppTheme.primaryColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildSidePanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // QR Code section
          if (_settings.allowQrEntry) ...[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text(
                      'Scan QR Code',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use your phone to scan',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // QR Code
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: AppTheme.dividerColor, width: 2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: _qrCode != null
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Expanded(
                                        child: Icon(Icons.qr_code_2, size: 150),
                                      ),
                                      const SizedBox(height: 8),
                                      LinearProgressIndicator(
                                        value: _qrSecondsRemaining / _settings.qrRefreshSeconds,
                                        backgroundColor: AppTheme.dividerColor,
                                        valueColor: AlwaysStoppedAnimation(
                                          _qrSecondsRemaining < 10
                                              ? AppTheme.warningColor
                                              : AppTheme.primaryColor,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Refreshes in ${_qrSecondsRemaining}s',
                                        style: TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  )
                                : const Center(child: CircularProgressIndicator()),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          
          // Recent records
          if (_settings.showLastAttendance && _recentRecords.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recent Activity',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._recentRecords.map((record) => _buildRecentRecord(record)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildRecentRecord(Map<String, dynamic> record) {
    final isIn = record['type'] == 'in';
    final time = record['time'] as DateTime;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isIn ? AppTheme.successColor : AppTheme.primaryColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              record['name'] as String,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            DateFormat('hh:mm a').format(time),
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            isIn ? Icons.login : Icons.logout,
            size: 14,
            color: isIn ? AppTheme.successColor : AppTheme.primaryColor,
          ),
        ],
      ),
    );
  }
  
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Available methods
          Row(
            children: [
              if (_settings.allowManualEntry)
                _buildMethodChip(Icons.keyboard, 'Manual Entry'),
              if (_settings.allowBarcodeEntry)
                _buildMethodChip(Icons.qr_code_scanner, 'Barcode'),
              if (_settings.allowQrEntry)
                _buildMethodChip(Icons.qr_code_2, 'QR Code'),
              if (_settings.allowFingerprintEntry)
                _buildMethodChip(Icons.fingerprint, 'Fingerprint'),
            ],
          ),
          const Spacer(),
          
          // Version info
          Text(
            'v${AppConstants.appVersion}',
            style: TextStyle(
              color: AppTheme.textDisabled,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMethodChip(IconData icon, String label) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildToggleButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : AppTheme.textSecondary,
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  String _getInstructionText() {
    final methods = <String>[];
    if (_settings.allowManualEntry) methods.add('enter your employee code');
    if (_settings.allowBarcodeEntry) methods.add('scan your barcode');
    if (_settings.allowQrEntry) methods.add('scan the QR code');
    if (_settings.allowFingerprintEntry) methods.add('use your fingerprint');
    
    if (methods.isEmpty) {
      return 'Please contact your administrator';
    }
    
    return 'Please ${methods.join(" or ")}';
  }
}
