import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../../core/theme/app_theme.dart';
import '../../core/services/services.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/attendance_model.dart';
import '../../data/repositories/repositories.dart';

/// Attendance screen for clock in/out operations
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final AttendanceService _attendanceService = AttendanceService.instance;
  final QrService _qrService = QrService.instance;
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocusNode = FocusNode();
  
  bool _isClockIn = true;
  bool _isProcessing = false;
  String? _message;
  bool _isError = false;
  String? _qrCode;
  Timer? _qrTimer;
  int _qrSecondsRemaining = 0;
  String? _qrErrorMessage;
  
  @override
  void initState() {
    super.initState();
    _codeFocusNode.requestFocus();
    _generateQrCode();
  }
  
  @override
  void dispose() {
    _codeController.dispose();
    _codeFocusNode.dispose();
    _qrTimer?.cancel();
    super.dispose();
  }
  
  Future<void> _generateQrCode() async {
    try {
      final data = await _qrService.generateQrDisplayData();
      setState(() {
        _qrCode = data['token'] as String?;
        _qrSecondsRemaining = AppConstants.qrRefreshSeconds;
        _qrErrorMessage = null;
      });
      
      _qrTimer?.cancel();
      _qrTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_qrSecondsRemaining > 0) {
          setState(() => _qrSecondsRemaining--);
        } else {
          _generateQrCode();
        }
      });
    } catch (e, stack) {
      LoggingService.instance.error('AttendanceScreen', 'Failed to generate QR code', e, stack);
      setState(() {
        _qrCode = null;
        _qrErrorMessage = 'Unable to generate QR code.';
      });
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
        
        setState(() {
          _message = 'Clock in successful!';
          _isError = false;
        });
      } else {
        final record = await _attendanceService.clockOut(
          employeeIdentifier: code,
          method: AttendanceMethod.manual,
        );
        
        setState(() {
          _message = 'Clock out successful!';
          _isError = false;
        });
      }
    } catch (e, stack) {
      LoggingService.instance.error('AttendanceScreen', 'Clock action failed', e, stack);
      setState(() {
        _message = e.toString().replaceAll('Exception: ', '');
        _isError = true;
      });
    } finally {
      setState(() => _isProcessing = false);
      _codeController.clear();
      _codeFocusNode.requestFocus();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left side - Manual entry
          Expanded(
            flex: 2,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Clock In/Out toggle
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildToggleButton(
                            label: 'Clock In',
                            icon: Icons.login,
                            isSelected: _isClockIn,
                            onTap: () => setState(() => _isClockIn = true),
                          ),
                          _buildToggleButton(
                            label: 'Clock Out',
                            icon: Icons.logout,
                            isSelected: !_isClockIn,
                            onTap: () => setState(() => _isClockIn = false),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 48),
                    
                    // Icon
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: (_isClockIn ? AppTheme.successColor : AppTheme.primaryColor).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isClockIn ? Icons.login : Icons.logout,
                        size: 56,
                        color: _isClockIn ? AppTheme.successColor : AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    Text(
                      _isClockIn ? 'Clock In' : 'Clock Out',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter employee code or scan barcode',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // Input field
                    SizedBox(
                      width: 400,
                      child: TextField(
                        controller: _codeController,
                        focusNode: _codeFocusNode,
                        decoration: InputDecoration(
                          hintText: 'Employee Code / Barcode',
                          prefixIcon: const Icon(Icons.badge),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.send),
                            onPressed: () => _processAttendance(_codeController.text.trim()),
                          ),
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 2,
                        ),
                        onSubmitted: (value) => _processAttendance(value.trim()),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Status message
                    if (_message != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: (_isError ? AppTheme.errorColor : AppTheme.successColor).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isError ? Icons.error_outline : Icons.check_circle,
                              color: _isError ? AppTheme.errorColor : AppTheme.successColor,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _message!,
                              style: TextStyle(
                                color: _isError ? AppTheme.errorColor : AppTheme.successColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                    if (_isProcessing) ...[
                      const SizedBox(height: 24),
                      const CircularProgressIndicator(),
                    ],
                    
                    const Spacer(),
                    
                    // Instructions
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.infoColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.info_outline, color: AppTheme.infoColor),
                          const SizedBox(width: 12),
                          Text(
                            'USB barcode scanners work automatically',
                            style: TextStyle(color: AppTheme.infoColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
          
          // Right side - QR Code and methods
          Expanded(
            child: Column(
              children: [
                // QR Code card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Text(
                          'QR Code Attendance',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // QR Code placeholder
                        Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.dividerColor),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _qrCode != null
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.qr_code_2, size: 100),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Refreshes in ${_qrSecondsRemaining}s',
                                        style: TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : _qrErrorMessage != null
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.error_outline, color: AppTheme.errorColor),
                                          const SizedBox(height: 8),
                                          Text(
                                            _qrErrorMessage!,
                                            style: const TextStyle(color: AppTheme.errorColor, fontSize: 12),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 8),
                                          TextButton.icon(
                                            onPressed: _generateQrCode,
                                            icon: const Icon(Icons.refresh),
                                            label: const Text('Retry'),
                                          ),
                                        ],
                                      ),
                                    )
                                  : const Center(child: CircularProgressIndicator()),
                        ),
                        const SizedBox(height: 16),
                        
                        LinearProgressIndicator(
                          value: _qrSecondsRemaining / AppConstants.qrRefreshSeconds,
                          backgroundColor: AppTheme.dividerColor,
                          valueColor: AlwaysStoppedAnimation(
                            _qrSecondsRemaining < 10 ? AppTheme.warningColor : AppTheme.primaryColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Dynamic QR - Auto refreshes for security',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Other methods
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Other Methods',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildMethodTile(
                          icon: Icons.camera_alt,
                          title: 'Camera Scanner',
                          subtitle: 'Scan QR with laptop camera',
                          onTap: () {
                            // TODO: Open camera scanner
                          },
                        ),
                        _buildMethodTile(
                          icon: Icons.fingerprint,
                          title: 'Fingerprint',
                          subtitle: 'Use fingerprint device',
                          onTap: () {
                            // TODO: Open fingerprint scanner
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : AppTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMethodTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppTheme.primaryColor),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
