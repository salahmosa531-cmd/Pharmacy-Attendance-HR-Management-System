import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'logging_service.dart';

/// Notifications Service - Manages smart warnings and system alerts
/// 
/// Features:
/// - Local storage of notifications (no cloud dependency)
/// - Integration with Smart Warnings
/// - Read/unread status tracking
/// - Badge count for unread notifications
/// - Critical alerts that cannot be dismissed
class NotificationsService {
  static final NotificationsService _instance = NotificationsService._();
  static NotificationsService get instance => _instance;
  
  static const String _storageKey = 'app_notifications';
  static const int _maxNotifications = 100;
  
  final List<AppNotification> _notifications = [];
  final List<void Function()> _listeners = [];
  
  NotificationsService._();

  /// Initialize and load notifications from local storage
  Future<void> initialize() async {
    await _loadFromStorage();
    LoggingService.instance.info('NotificationsService', 'Initialized with ${_notifications.length} notifications');
  }

  /// Get all notifications (newest first)
  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  /// Get unread notifications
  List<AppNotification> get unreadNotifications => 
      _notifications.where((n) => !n.isRead).toList();

  /// Get unread count (for badge)
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  /// Check if there are any unread notifications
  bool get hasUnread => unreadCount > 0;

  /// Add a listener for notification changes
  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  /// Remove a listener
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  /// Notify all listeners
  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  /// Add a new notification
  Future<void> addNotification(AppNotification notification) async {
    // Check for duplicate (same type and message within last hour)
    final isDuplicate = _notifications.any((n) => 
        n.type == notification.type && 
        n.message == notification.message &&
        DateTime.now().difference(n.createdAt).inHours < 1
    );
    
    if (isDuplicate) return;
    
    _notifications.insert(0, notification);
    
    // Trim old notifications
    while (_notifications.length > _maxNotifications) {
      _notifications.removeLast();
    }
    
    await _saveToStorage();
    _notifyListeners();
    
    LoggingService.instance.info('NotificationsService', 
        'Added notification: ${notification.type.value} - ${notification.title}');
  }

  /// Add a smart warning notification
  Future<void> addSmartWarning({
    required String title,
    required String message,
    NotificationSeverity severity = NotificationSeverity.warning,
    String? shiftId,
    Map<String, dynamic>? metadata,
  }) async {
    await addNotification(AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: NotificationType.smartWarning,
      title: title,
      message: message,
      severity: severity,
      shiftId: shiftId,
      metadata: metadata,
      createdAt: DateTime.now(),
    ));
  }

  /// Add a shift alert notification
  Future<void> addShiftAlert({
    required String title,
    required String message,
    required String shiftId,
    NotificationSeverity severity = NotificationSeverity.info,
  }) async {
    await addNotification(AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: NotificationType.shiftAlert,
      title: title,
      message: message,
      severity: severity,
      shiftId: shiftId,
      createdAt: DateTime.now(),
    ));
  }

  /// Add a system alert notification
  Future<void> addSystemAlert({
    required String title,
    required String message,
    NotificationSeverity severity = NotificationSeverity.info,
    bool isCritical = false,
  }) async {
    await addNotification(AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: NotificationType.systemAlert,
      title: title,
      message: message,
      severity: severity,
      isCritical: isCritical,
      createdAt: DateTime.now(),
    ));
  }

  /// Mark a notification as read
  Future<void> markAsRead(String notificationId) async {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index != -1) {
      _notifications[index] = _notifications[index].copyWith(isRead: true);
      await _saveToStorage();
      _notifyListeners();
    }
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    bool changed = false;
    for (int i = 0; i < _notifications.length; i++) {
      if (!_notifications[i].isRead) {
        _notifications[i] = _notifications[i].copyWith(isRead: true);
        changed = true;
      }
    }
    if (changed) {
      await _saveToStorage();
      _notifyListeners();
    }
  }

  /// Dismiss a notification (non-critical only)
  Future<void> dismiss(String notificationId) async {
    final notification = _notifications.firstWhere(
      (n) => n.id == notificationId,
      orElse: () => throw Exception('Notification not found'),
    );
    
    if (notification.isCritical) {
      throw Exception('Cannot dismiss critical notifications');
    }
    
    _notifications.removeWhere((n) => n.id == notificationId);
    await _saveToStorage();
    _notifyListeners();
  }

  /// Clear all non-critical notifications
  Future<void> clearNonCritical() async {
    _notifications.removeWhere((n) => !n.isCritical);
    await _saveToStorage();
    _notifyListeners();
  }

  /// Clear all notifications (admin only)
  Future<void> clearAll() async {
    _notifications.clear();
    await _saveToStorage();
    _notifyListeners();
  }

  /// Load notifications from local storage
  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      
      if (jsonString != null) {
        final List<dynamic> jsonList = json.decode(jsonString);
        _notifications.clear();
        _notifications.addAll(
          jsonList.map((j) => AppNotification.fromJson(j as Map<String, dynamic>)),
        );
        
        // Sort by date (newest first)
        _notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
    } catch (e) {
      LoggingService.instance.error('NotificationsService', 'Error loading notifications: $e');
    }
  }

  /// Save notifications to local storage
  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = json.encode(
        _notifications.map((n) => n.toJson()).toList(),
      );
      await prefs.setString(_storageKey, jsonString);
    } catch (e) {
      LoggingService.instance.error('NotificationsService', 'Error saving notifications: $e');
    }
  }
}

/// App Notification model
class AppNotification {
  final String id;
  final NotificationType type;
  final String title;
  final String message;
  final NotificationSeverity severity;
  final bool isRead;
  final bool isCritical;
  final String? shiftId;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    this.severity = NotificationSeverity.info,
    this.isRead = false,
    this.isCritical = false,
    this.shiftId,
    this.metadata,
    required this.createdAt,
  });

  AppNotification copyWith({
    String? id,
    NotificationType? type,
    String? title,
    String? message,
    NotificationSeverity? severity,
    bool? isRead,
    bool? isCritical,
    String? shiftId,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
  }) {
    return AppNotification(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      severity: severity ?? this.severity,
      isRead: isRead ?? this.isRead,
      isCritical: isCritical ?? this.isCritical,
      shiftId: shiftId ?? this.shiftId,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.value,
      'title': title,
      'message': message,
      'severity': severity.value,
      'isRead': isRead,
      'isCritical': isCritical,
      'shiftId': shiftId,
      'metadata': metadata,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      type: NotificationType.fromString(json['type'] as String),
      title: json['title'] as String,
      message: json['message'] as String,
      severity: NotificationSeverity.fromString(json['severity'] as String? ?? 'info'),
      isRead: json['isRead'] as bool? ?? false,
      isCritical: json['isCritical'] as bool? ?? false,
      shiftId: json['shiftId'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  /// Get time ago string
  String get timeAgo {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${createdAt.day}/${createdAt.month}';
  }
}

/// Notification types
enum NotificationType {
  smartWarning('smart_warning', 'Smart Warning'),
  shiftAlert('shift_alert', 'Shift Alert'),
  systemAlert('system_alert', 'System Alert');

  final String value;
  final String displayName;

  const NotificationType(this.value, this.displayName);

  static NotificationType fromString(String value) {
    return NotificationType.values.firstWhere(
      (t) => t.value == value,
      orElse: () => NotificationType.systemAlert,
    );
  }
}

/// Notification severity
enum NotificationSeverity {
  info('info', 'Info'),
  warning('warning', 'Warning'),
  error('error', 'Error'),
  critical('critical', 'Critical');

  final String value;
  final String displayName;

  const NotificationSeverity(this.value, this.displayName);

  static NotificationSeverity fromString(String value) {
    return NotificationSeverity.values.firstWhere(
      (s) => s.value == value,
      orElse: () => NotificationSeverity.info,
    );
  }
}
