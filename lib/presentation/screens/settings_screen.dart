import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/services.dart';
import '../../core/services/settings_service.dart';
import '../../core/constants/app_constants.dart';
import '../providers/app_state_provider.dart';

/// Settings screen for app configuration
/// 
/// All settings are persisted immediately to SQLite and broadcast
/// to all screens via SettingsService streams
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settingsService = SettingsService.instance;
  final AuthService _authService = AuthService.instance;
  
  // Settings state
  SettingsState _settings = const SettingsState();
  StreamSubscription<SettingsState>? _subscription;
  
  bool _isLoading = true;
  bool _isSaving = false;
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
  
  Future<void> _loadSettings() async {
    await _settingsService.initialize();
    
    // Subscribe to settings changes
    _subscription = _settingsService.settingsStream.listen((state) {
      if (mounted) {
        setState(() => _settings = state);
      }
    });
    
    setState(() {
      _settings = _settingsService.currentState;
      _isLoading = false;
    });
  }
  
  /// Save a single setting
  Future<void> _saveSetting(String key, dynamic value) async {
    setState(() => _isSaving = true);
    try {
      await _settingsService.setValue(key, value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Setting saved'),
            duration: Duration(seconds: 1),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
  
  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Settings'),
        content: const Text('Are you sure you want to reset all settings to defaults? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _settingsService.resetToDefaults();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings reset to defaults'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppStateProvider>(context);
    
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Text(
                'Settings',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_isSaving) ...[
                const SizedBox(width: 16),
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Configure system preferences. Changes are saved automatically.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column
              Expanded(
                child: Column(
                  children: [
                    // Appearance
                    _buildSection(
                      title: 'Appearance',
                      icon: Icons.palette,
                      children: [
                        ListTile(
                          title: const Text('Theme'),
                          subtitle: Text(
                            appState.themeMode == ThemeMode.system
                                ? 'System default'
                                : appState.themeMode == ThemeMode.dark
                                    ? 'Dark'
                                    : 'Light',
                          ),
                          trailing: SegmentedButton<ThemeMode>(
                            segments: const [
                              ButtonSegment(
                                value: ThemeMode.light,
                                icon: Icon(Icons.light_mode),
                              ),
                              ButtonSegment(
                                value: ThemeMode.system,
                                icon: Icon(Icons.brightness_auto),
                              ),
                              ButtonSegment(
                                value: ThemeMode.dark,
                                icon: Icon(Icons.dark_mode),
                              ),
                            ],
                            selected: {appState.themeMode},
                            onSelectionChanged: (Set<ThemeMode> selected) {
                              appState.setThemeMode(selected.first);
                            },
                          ),
                        ),
                        ListTile(
                          title: const Text('Language'),
                          subtitle: Text(
                            appState.locale.languageCode == 'ar' ? 'Arabic' : 'English',
                          ),
                          trailing: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'en', label: Text('EN')),
                              ButtonSegment(value: 'ar', label: Text('AR')),
                            ],
                            selected: {appState.locale.languageCode},
                            onSelectionChanged: (Set<String> selected) {
                              appState.setLocale(Locale(selected.first));
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Attendance Settings
                    _buildSection(
                      title: 'Attendance Rules',
                      icon: Icons.access_time,
                      children: [
                        _buildNumberSetting(
                          title: 'Grace Period',
                          subtitle: 'Minutes allowed after shift start',
                          value: _settings.gracePeriodMinutes,
                          suffix: 'min',
                          onChanged: (value) => _saveSetting(
                            SettingKeys.gracePeriodMinutes,
                            value,
                          ),
                        ),
                        _buildNumberSetting(
                          title: 'Attendance Window',
                          subtitle: 'Minutes before/after shift to clock in',
                          value: _settings.attendanceWindowMinutes,
                          suffix: 'min',
                          onChanged: (value) => _saveSetting(
                            SettingKeys.attendanceWindowMinutes,
                            value,
                          ),
                        ),
                        _buildNumberSetting(
                          title: 'QR Code Refresh',
                          subtitle: 'Seconds before QR code refreshes (anti-fraud)',
                          value: _settings.qrRefreshSeconds,
                          suffix: 'sec',
                          onChanged: (value) => _saveSetting(
                            SettingKeys.qrRefreshSeconds,
                            value,
                          ),
                        ),
                        _buildNumberSetting(
                          title: 'Duplicate Scan Protection',
                          subtitle: 'Minimum seconds between scans',
                          value: _settings.duplicateScanProtectionSeconds,
                          suffix: 'sec',
                          onChanged: (value) => _saveSetting(
                            SettingKeys.duplicateScanProtectionSeconds,
                            value,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Anti-Fraud Settings
                    _buildSection(
                      title: 'Security & Anti-Fraud',
                      icon: Icons.security,
                      children: [
                        SwitchListTile(
                          title: const Text('Device Binding'),
                          subtitle: const Text('Only allow registered devices'),
                          value: _settings.requireDeviceBinding,
                          onChanged: (value) => _saveSetting(
                            SettingKeys.requireDeviceBinding,
                            value,
                          ),
                        ),
                        SwitchListTile(
                          title: const Text('Location Verification'),
                          subtitle: const Text('Verify attendance location (requires GPS)'),
                          value: _settings.enableLocationVerification,
                          onChanged: (value) => _saveSetting(
                            SettingKeys.enableLocationVerification,
                            value,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              
              // Right Column
              Expanded(
                child: Column(
                  children: [
                    // Attendance Methods
                    _buildSection(
                      title: 'Attendance Methods',
                      icon: Icons.fingerprint,
                      description: 'Enable/disable attendance input methods',
                      children: [
                        SwitchListTile(
                          title: const Text('Manual Entry'),
                          subtitle: const Text('Allow employee code entry'),
                          value: _settings.allowManualEntry,
                          onChanged: (value) => _saveSetting(
                            SettingKeys.allowManualEntry,
                            value,
                          ),
                        ),
                        SwitchListTile(
                          title: const Text('Barcode Scanner'),
                          subtitle: const Text('USB barcode scanner input'),
                          value: _settings.allowBarcodeEntry,
                          onChanged: (value) => _saveSetting(
                            SettingKeys.allowBarcodeEntry,
                            value,
                          ),
                        ),
                        SwitchListTile(
                          title: const Text('QR Code'),
                          subtitle: const Text('Dynamic QR code with auto-refresh'),
                          value: _settings.allowQrEntry,
                          onChanged: (value) => _saveSetting(
                            SettingKeys.allowQrEntry,
                            value,
                          ),
                        ),
                        SwitchListTile(
                          title: const Text('Fingerprint'),
                          subtitle: const Text('Fingerprint device (ZKTeco, DigitalPersona)'),
                          value: _settings.allowFingerprintEntry,
                          onChanged: (value) => _saveSetting(
                            SettingKeys.allowFingerprintEntry,
                            value,
                          ),
                        ),
                        if (!_settings.hasAnyAttendanceMethod)
                          Container(
                            margin: const EdgeInsets.all(16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.warningColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.warningColor),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.warning, color: AppTheme.warningColor),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Warning: No attendance method is enabled! Employees will not be able to clock in/out.',
                                    style: TextStyle(color: AppTheme.warningColor),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Payroll Settings
                    _buildSection(
                      title: 'Payroll Settings',
                      icon: Icons.payment,
                      children: [
                        SwitchListTile(
                          title: const Text('Calculate Overtime'),
                          subtitle: const Text('Automatically calculate overtime pay'),
                          value: _settings.calculateOvertime,
                          onChanged: (value) => _saveSetting(
                            SettingKeys.calculateOvertime,
                            value,
                          ),
                        ),
                        _buildNumberSetting(
                          title: 'Overtime Multiplier',
                          subtitle: 'Regular overtime rate',
                          value: _settings.overtimeMultiplier,
                          suffix: 'x',
                          isDouble: true,
                          onChanged: (value) => _saveSetting(
                            SettingKeys.overtimeMultiplier,
                            value,
                          ),
                        ),
                        _buildNumberSetting(
                          title: 'Weekend Multiplier',
                          subtitle: 'Weekend overtime rate',
                          value: _settings.weekendMultiplier,
                          suffix: 'x',
                          isDouble: true,
                          onChanged: (value) => _saveSetting(
                            SettingKeys.weekendMultiplier,
                            value,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Kiosk Settings
                    _buildSection(
                      title: 'Kiosk Mode',
                      icon: Icons.tv,
                      children: [
                        SwitchListTile(
                          title: const Text('Sound Feedback'),
                          subtitle: const Text('Play sounds on attendance success/failure'),
                          value: _settings.soundEnabled,
                          onChanged: (value) => _saveSetting(
                            SettingKeys.soundEnabled,
                            value,
                          ),
                        ),
                        SwitchListTile(
                          title: const Text('Show Recent Activity'),
                          subtitle: const Text('Display last 3 attendance records'),
                          value: _settings.showLastAttendance,
                          onChanged: (value) => _saveSetting(
                            SettingKeys.showLastAttendance,
                            value,
                          ),
                        ),
                        _buildNumberSetting(
                          title: 'Kiosk Timeout',
                          subtitle: 'Seconds before clearing input',
                          value: _settings.kioskModeTimeout,
                          suffix: 'sec',
                          onChanged: (value) => _saveSetting(
                            SettingKeys.kioskModeTimeout,
                            value,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Data Management
                    _buildSection(
                      title: 'Data Management',
                      icon: Icons.storage,
                      children: [
                        SwitchListTile(
                          title: const Text('Auto Backup'),
                          subtitle: const Text('Automatic local backup'),
                          value: _settings.autoBackup,
                          onChanged: (value) => _saveSetting(
                            SettingKeys.autoBackup,
                            value,
                          ),
                        ),
                        if (_settings.autoBackup)
                          ListTile(
                            title: const Text('Backup Interval'),
                            subtitle: const Text('Hours between backups'),
                            trailing: DropdownButton<int>(
                              value: _settings.backupIntervalHours,
                              items: const [
                                DropdownMenuItem(value: 6, child: Text('6 hours')),
                                DropdownMenuItem(value: 12, child: Text('12 hours')),
                                DropdownMenuItem(value: 24, child: Text('24 hours')),
                                DropdownMenuItem(value: 48, child: Text('48 hours')),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  _saveSetting(SettingKeys.backupIntervalHours, value);
                                }
                              },
                            ),
                          ),
                        SwitchListTile(
                          title: const Text('Cloud Sync'),
                          subtitle: const Text('Sync data to cloud (optional)'),
                          value: _settings.cloudSyncEnabled,
                          onChanged: (value) => _saveSetting(
                            SettingKeys.cloudSyncEnabled,
                            value,
                          ),
                        ),
                        const Divider(),
                        ListTile(
                          title: const Text('Export Database'),
                          subtitle: const Text('Create backup file'),
                          trailing: ElevatedButton.icon(
                            icon: const Icon(Icons.download),
                            label: const Text('Export'),
                            onPressed: () async {
                              try {
                                final path = await DatabaseService.instance.exportDatabase();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Database exported to: $path'),
                                      backgroundColor: AppTheme.successColor,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Export failed: $e'),
                                      backgroundColor: AppTheme.errorColor,
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // About Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.medical_services,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pharmacy Attendance System',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Version ${AppConstants.appVersion} (Build ${AppConstants.appBuildNumber})',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.successColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Enterprise Edition',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.successColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Offline-First',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.restore),
                        label: const Text('Reset'),
                        onPressed: _resetToDefaults,
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.tv),
                        label: const Text('Kiosk Mode'),
                        onPressed: () => context.go('/kiosk'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
    String? description,
  }) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }
  
  Widget _buildNumberSetting({
    required String title,
    required String subtitle,
    required num value,
    required String suffix,
    bool isDouble = false,
    required Function(num) onChanged,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: SizedBox(
        width: 100,
        child: TextField(
          decoration: InputDecoration(
            suffixText: suffix,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            isDense: true,
          ),
          keyboardType: TextInputType.number,
          controller: TextEditingController(
            text: isDouble ? value.toStringAsFixed(1) : value.toString(),
          ),
          onSubmitted: (text) {
            final newValue = isDouble 
                ? double.tryParse(text)
                : int.tryParse(text);
            if (newValue != null) {
              onChanged(newValue);
            }
          },
        ),
      ),
    );
  }
}
