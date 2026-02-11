import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../data/models/audit_log_model.dart';
import '../../data/repositories/audit_repository.dart';

/// Audit log screen showing all system activities
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final AuthService _authService = AuthService.instance;
  final AuditRepository _auditRepository = AuditRepository.instance;
  
  bool _isLoading = true;
  List<AuditLog> _logs = [];
  
  AuditAction? _actionFilter;
  AuditEntityType? _entityFilter;
  DateTime? _startDate;
  DateTime? _endDate;
  
  final _dateFormat = DateFormat('MMM dd, yyyy HH:mm');
  
  @override
  void initState() {
    super.initState();
    _loadLogs();
  }
  
  Future<void> _loadLogs() async {
    final branchId = '1';
    if (branchId == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      _logs = await _auditRepository.getLogs(
        branchId,
        action: _actionFilter,
        entityType: _entityFilter,
        startDate: _startDate,
        endDate: _endDate,
        limit: 500,
      );
      
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }
  
  Color _getActionColor(AuditAction action) {
    switch (action) {
      case AuditAction.create:
        return AppTheme.successColor;
      case AuditAction.update:
        return AppTheme.primaryColor;
      case AuditAction.delete:
        return AppTheme.errorColor;
      case AuditAction.login:
        return AppTheme.infoColor;
      case AuditAction.logout:
        return AppTheme.textSecondary;
      case AuditAction.clockIn:
      case AuditAction.clockOut:
        return AppTheme.accentColor;
      case AuditAction.manualOverride:
      case AuditAction.forgiveLateness:
        return AppTheme.warningColor;
      case AuditAction.sync:
        return AppTheme.primaryLight;
      case AuditAction.deviceAuthorize:
      case AuditAction.deviceRevoke:
        return AppTheme.onLeaveColor;
      default:
        return AppTheme.textSecondary;
    }
  }
  
  IconData _getActionIcon(AuditAction action) {
    switch (action) {
      case AuditAction.create:
        return Icons.add_circle;
      case AuditAction.update:
        return Icons.edit;
      case AuditAction.delete:
        return Icons.delete;
      case AuditAction.login:
        return Icons.login;
      case AuditAction.logout:
        return Icons.logout;
      case AuditAction.clockIn:
        return Icons.login;
      case AuditAction.clockOut:
        return Icons.logout;
      case AuditAction.manualOverride:
        return Icons.admin_panel_settings;
      case AuditAction.forgiveLateness:
        return Icons.thumb_up;
      case AuditAction.sync:
        return Icons.sync;
      case AuditAction.deviceAuthorize:
        return Icons.verified_user;
      case AuditAction.deviceRevoke:
        return Icons.block;
      default:
        return Icons.info;
    }
  }
  
  IconData _getEntityIcon(AuditEntityType entityType) {
    switch (entityType) {
      case AuditEntityType.user:
        return Icons.person;
      case AuditEntityType.employee:
        return Icons.badge;
      case AuditEntityType.shift:
        return Icons.schedule;
      case AuditEntityType.attendance:
        return Icons.access_time;
      case AuditEntityType.branch:
        return Icons.business;
      case AuditEntityType.settings:
        return Icons.settings;
      case AuditEntityType.device:
        return Icons.computer;
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
              const Expanded(
                child: Text(
                  'Audit Log',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadLogs,
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Filters
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Action Filter
                  Expanded(
                    child: DropdownButtonFormField<AuditAction?>(
                      value: _actionFilter,
                      decoration: const InputDecoration(
                        labelText: 'Action',
                        prefixIcon: Icon(Icons.filter_list),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All Actions')),
                        ...AuditAction.values.map((a) => DropdownMenuItem(
                          value: a,
                          child: Text(a.displayName),
                        )),
                      ],
                      onChanged: (value) {
                        setState(() => _actionFilter = value);
                        _loadLogs();
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // Entity Filter
                  Expanded(
                    child: DropdownButtonFormField<AuditEntityType?>(
                      value: _entityFilter,
                      decoration: const InputDecoration(
                        labelText: 'Entity Type',
                        prefixIcon: Icon(Icons.category),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All Entities')),
                        ...AuditEntityType.values.map((e) => DropdownMenuItem(
                          value: e,
                          child: Text(e.displayName),
                        )),
                      ],
                      onChanged: (value) {
                        setState(() => _entityFilter = value);
                        _loadLogs();
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // Date Range
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange: _startDate != null && _endDate != null
                              ? DateTimeRange(start: _startDate!, end: _endDate!)
                              : null,
                        );
                        if (picked != null) {
                          setState(() {
                            _startDate = picked.start;
                            _endDate = picked.end;
                          });
                          _loadLogs();
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date Range',
                          prefixIcon: Icon(Icons.date_range),
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        child: Text(
                          _startDate != null && _endDate != null
                              ? '${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd').format(_endDate!)}'
                              : 'All Time',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // Clear Filters
                  TextButton.icon(
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear'),
                    onPressed: () {
                      setState(() {
                        _actionFilter = null;
                        _entityFilter = null;
                        _startDate = null;
                        _endDate = null;
                      });
                      _loadLogs();
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Log List
          Expanded(
            child: Card(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _logs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.history,
                                size: 64,
                                color: AppTheme.textDisabled,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No audit logs found',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(8),
                          itemCount: _logs.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final log = _logs[index];
                            return _buildLogTile(log);
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLogTile(AuditLog log) {
    final actionColor = _getActionColor(log.action);
    
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: actionColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          _getActionIcon(log.action),
          color: actionColor,
          size: 20,
        ),
      ),
      title: Row(
        children: [
          Text(
            log.action.displayName,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: actionColor,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.textSecondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_getEntityIcon(log.entityType), size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                  log.entityType.displayName,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          if (log.description != null)
            Text(log.description!),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.access_time, size: 14, color: AppTheme.textDisabled),
              const SizedBox(width: 4),
              Text(
                _dateFormat.format(log.createdAt),
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textDisabled,
                ),
              ),
              if (log.userId != null) ...[
                const SizedBox(width: 16),
                Icon(Icons.person, size: 14, color: AppTheme.textDisabled),
                const SizedBox(width: 4),
                Text(
                  'User: ${log.userId}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textDisabled,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.info_outline),
        onPressed: () => _showLogDetails(log),
        tooltip: 'View Details',
      ),
      onTap: () => _showLogDetails(log),
    );
  }
  
  void _showLogDetails(AuditLog log) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _getActionColor(log.action).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getActionIcon(log.action),
                color: _getActionColor(log.action),
              ),
            ),
            const SizedBox(width: 12),
            Text(log.action.displayName),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow('Entity Type', log.entityType.displayName),
                _buildDetailRow('Entity ID', log.entityId),
                _buildDetailRow('Timestamp', _dateFormat.format(log.createdAt)),
                if (log.userId != null)
                  _buildDetailRow('User ID', log.userId!),
                if (log.deviceId != null)
                  _buildDetailRow('Device ID', log.deviceId!),
                if (log.ipAddress != null)
                  _buildDetailRow('IP Address', log.ipAddress!),
                if (log.description != null) ...[
                  const Divider(),
                  const Text(
                    'Description',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(log.description!),
                ],
                if (log.oldValues != null) ...[
                  const Divider(),
                  const Text(
                    'Previous Values',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      log.oldValues.toString(),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ],
                if (log.newValues != null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'New Values',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      log.newValues.toString(),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
