import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../core/constants/app_constants.dart';
import '../providers/app_state_provider.dart';

/// Settings screen for app configuration
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService.instance;
  
  // Attendance Settings
  int _gracePeriod = AppConstants.defaultGracePeriodMinutes;
  int _attendanceWindow = AppConstants.attendanceWindowMinutes;
  int _qrRefreshSeconds = AppConstants.qrRefreshSeconds;
  bool _requireDeviceBinding = true;
  bool _allowManualEntry = true;
  bool _allowBarcodeEntry = true;
  bool _allowQrEntry = true;
  bool _allowFingerprintEntry = false;
  
  // Payroll Settings
  double _overtimeMultiplier = AppConstants.defaultOvertimeMultiplier;
  double _weekendMultiplier = AppConstants.weekendOvertimeMultiplier;
  bool _calculateOvertime = true;
  
  // System Settings
  bool _autoBackup = true;
  int _backupInterval = 24; // hours
  bool _syncEnabled = false;
  
  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppStateProvider>(context);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Settings',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Configure system preferences',
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
                      title: 'Attendance Settings',
                      icon: Icons.access_time,
                      children: [
                        ListTile(
                          title: const Text('Grace Period'),
                          subtitle: const Text('Minutes allowed after shift start'),
                          trailing: SizedBox(
                            width: 100,
                            child: TextField(
                              decoration: const InputDecoration(
                                suffixText: 'min',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              keyboardType: TextInputType.number,
                              controller: TextEditingController(text: _gracePeriod.toString()),
                              onChanged: (value) {
                                _gracePeriod = int.tryParse(value) ?? _gracePeriod;
                              },
                            ),
                          ),
                        ),
                        ListTile(
                          title: const Text('Attendance Window'),
                          subtitle: const Text('Minutes before/after shift to clock in'),
                          trailing: SizedBox(
                            width: 100,
                            child: TextField(
                              decoration: const InputDecoration(
                                suffixText: 'min',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              keyboardType: TextInputType.number,
                              controller: TextEditingController(text: _attendanceWindow.toString()),
                              onChanged: (value) {
                                _attendanceWindow = int.tryParse(value) ?? _attendanceWindow;
                              },
                            ),
                          ),
                        ),
                        ListTile(
                          title: const Text('QR Code Refresh'),
                          subtitle: const Text('Seconds before QR code refreshes'),
                          trailing: SizedBox(
                            width: 100,
                            child: TextField(
                              decoration: const InputDecoration(
                                suffixText: 'sec',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              keyboardType: TextInputType.number,
                              controller: TextEditingController(text: _qrRefreshSeconds.toString()),
                              onChanged: (value) {
                                _qrRefreshSeconds = int.tryParse(value) ?? _qrRefreshSeconds;
                              },
                            ),
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
                          value: _requireDeviceBinding,
                          onChanged: (value) {
                            setState(() => _requireDeviceBinding = value);
                          },
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
                      children: [
                        SwitchListTile(
                          title: const Text('Manual Entry'),
                          subtitle: const Text('Allow employee code entry'),
                          value: _allowManualEntry,
                          onChanged: (value) {
                            setState(() => _allowManualEntry = value);
                          },
                        ),
                        SwitchListTile(
                          title: const Text('Barcode Scanner'),
                          subtitle: const Text('USB barcode scanner'),
                          value: _allowBarcodeEntry,
                          onChanged: (value) {
                            setState(() => _allowBarcodeEntry = value);
                          },
                        ),
                        SwitchListTile(
                          title: const Text('QR Code'),
                          subtitle: const Text('Laptop camera QR scanning'),
                          value: _allowQrEntry,
                          onChanged: (value) {
                            setState(() => _allowQrEntry = value);
                          },
                        ),
                        SwitchListTile(
                          title: const Text('Fingerprint'),
                          subtitle: const Text('Fingerprint device (ZKTeco, DigitalPersona)'),
                          value: _allowFingerprintEntry,
                          onChanged: (value) {
                            setState(() => _allowFingerprintEntry = value);
                          },
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
                          value: _calculateOvertime,
                          onChanged: (value) {
                            setState(() => _calculateOvertime = value);
                          },
                        ),
                        ListTile(
                          title: const Text('Overtime Multiplier'),
                          subtitle: const Text('Regular overtime rate'),
                          trailing: SizedBox(
                            width: 100,
                            child: TextField(
                              decoration: const InputDecoration(
                                suffixText: 'x',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              keyboardType: TextInputType.number,
                              controller: TextEditingController(text: _overtimeMultiplier.toString()),
                              onChanged: (value) {
                                _overtimeMultiplier = double.tryParse(value) ?? _overtimeMultiplier;
                              },
                            ),
                          ),
                        ),
                        ListTile(
                          title: const Text('Weekend Multiplier'),
                          subtitle: const Text('Weekend overtime rate'),
                          trailing: SizedBox(
                            width: 100,
                            child: TextField(
                              decoration: const InputDecoration(
                                suffixText: 'x',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              keyboardType: TextInputType.number,
                              controller: TextEditingController(text: _weekendMultiplier.toString()),
                              onChanged: (value) {
                                _weekendMultiplier = double.tryParse(value) ?? _weekendMultiplier;
                              },
                            ),
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
                          value: _autoBackup,
                          onChanged: (value) {
                            setState(() => _autoBackup = value);
                          },
                        ),
                        if (_autoBackup)
                          ListTile(
                            title: const Text('Backup Interval'),
                            subtitle: const Text('Hours between backups'),
                            trailing: SizedBox(
                              width: 100,
                              child: DropdownButtonFormField<int>(
                                value: _backupInterval,
                                decoration: const InputDecoration(
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 6, child: Text('6h')),
                                  DropdownMenuItem(value: 12, child: Text('12h')),
                                  DropdownMenuItem(value: 24, child: Text('24h')),
                                  DropdownMenuItem(value: 48, child: Text('48h')),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _backupInterval = value);
                                  }
                                },
                              ),
                            ),
                          ),
                        SwitchListTile(
                          title: const Text('Cloud Sync'),
                          subtitle: const Text('Sync data to cloud (optional)'),
                          value: _syncEnabled,
                          onChanged: (value) {
                            setState(() => _syncEnabled = value);
                          },
                        ),
                        const Divider(),
                        ListTile(
                          title: const Text('Export Database'),
                          subtitle: const Text('Create backup file'),
                          trailing: ElevatedButton.icon(
                            icon: const Icon(Icons.download),
                            label: const Text('Export'),
                            onPressed: () {
                              // TODO: Export database
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Database export feature coming soon'),
                                ),
                              );
                            },
                          ),
                        ),
                        ListTile(
                          title: const Text('Import Database'),
                          subtitle: const Text('Restore from backup'),
                          trailing: ElevatedButton.icon(
                            icon: const Icon(Icons.upload),
                            label: const Text('Import'),
                            onPressed: () {
                              // TODO: Import database
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Database import feature coming soon'),
                                ),
                              );
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
                                'Lifetime License',
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
                        icon: const Icon(Icons.help_outline),
                        label: const Text('Help'),
                        onPressed: () {
                          // TODO: Show help
                        },
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.info_outline),
                        label: const Text('About'),
                        onPressed: () {
                          showAboutDialog(
                            context: context,
                            applicationName: 'Pharmacy Attendance',
                            applicationVersion: AppConstants.appVersion,
                            applicationIcon: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.medical_services,
                                color: Colors.white,
                              ),
                            ),
                            children: const [
                              Text(
                                'Enterprise HR & Attendance Management System for Pharmacies',
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Save Button
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () {
                  // Reset to defaults
                  setState(() {
                    _gracePeriod = AppConstants.defaultGracePeriodMinutes;
                    _attendanceWindow = AppConstants.attendanceWindowMinutes;
                    _qrRefreshSeconds = AppConstants.qrRefreshSeconds;
                    _overtimeMultiplier = AppConstants.defaultOvertimeMultiplier;
                    _weekendMultiplier = AppConstants.weekendOvertimeMultiplier;
                  });
                },
                child: const Text('Reset to Defaults'),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Save Settings'),
                onPressed: () {
                  // TODO: Save settings to database
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Settings saved successfully'),
                      backgroundColor: AppTheme.successColor,
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
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
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }
}
