import 'dart:convert';
import 'package:equatable/equatable.dart';

/// Represents a queued operation for cloud synchronization
/// 
/// OFFLINE-FIRST ARCHITECTURE:
/// - All financial operations are stored locally first (SQLite)
/// - Operations are queued here for eventual cloud sync when online
/// - No UI changes - this is a background process
class SyncQueueItem extends Equatable {
  final String id;
  final SyncEntityType entityType;
  final String entityId;
  final SyncAction action;
  final Map<String, dynamic> payload;
  final int priority;
  final bool isSynced;
  final int retryCount;
  final String? lastError;
  final DateTime createdAt;
  final DateTime? syncedAt;

  const SyncQueueItem({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.payload,
    this.priority = 0,
    this.isSynced = false,
    this.retryCount = 0,
    this.lastError,
    required this.createdAt,
    this.syncedAt,
  });

  /// Create from database map
  factory SyncQueueItem.fromMap(Map<String, dynamic> map) {
    return SyncQueueItem(
      id: map['id'] as String,
      entityType: SyncEntityType.fromString(map['entity_type'] as String),
      entityId: map['entity_id'] as String,
      action: SyncAction.fromString(map['action'] as String),
      payload: jsonDecode(map['payload'] as String) as Map<String, dynamic>,
      priority: (map['priority'] as int?) ?? 0,
      isSynced: (map['is_synced'] as int?) == 1,
      retryCount: (map['retry_count'] as int?) ?? 0,
      lastError: map['last_error'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      syncedAt: map['synced_at'] != null 
          ? DateTime.parse(map['synced_at'] as String)
          : null,
    );
  }

  /// Convert to database map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entity_type': entityType.value,
      'entity_id': entityId,
      'action': action.value,
      'payload': jsonEncode(payload),
      'priority': priority,
      'is_synced': isSynced ? 1 : 0,
      'retry_count': retryCount,
      'last_error': lastError,
      'created_at': createdAt.toIso8601String(),
      'synced_at': syncedAt?.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  SyncQueueItem copyWith({
    String? id,
    SyncEntityType? entityType,
    String? entityId,
    SyncAction? action,
    Map<String, dynamic>? payload,
    int? priority,
    bool? isSynced,
    int? retryCount,
    String? lastError,
    DateTime? createdAt,
    DateTime? syncedAt,
  }) {
    return SyncQueueItem(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      action: action ?? this.action,
      payload: payload ?? this.payload,
      priority: priority ?? this.priority,
      isSynced: isSynced ?? this.isSynced,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  /// Check if item has exceeded max retries
  bool get hasExceededRetries => retryCount >= 5;

  /// Check if item needs retry
  bool get needsRetry => !isSynced && !hasExceededRetries;

  @override
  List<Object?> get props => [
    id, entityType, entityId, action, payload, priority,
    isSynced, retryCount, lastError, createdAt, syncedAt,
  ];
}

/// Entity types that can be synced
enum SyncEntityType {
  financialShift('financial_shift', 'Financial Shift', 1),
  shiftSale('shift_sale', 'Shift Sale', 2),
  shiftExpense('shift_expense', 'Shift Expense', 2),
  shiftClosure('shift_closure', 'Shift Closure', 1),
  safeTransaction('safe_transaction', 'Safe Transaction', 1),
  safeBalance('safe_balance', 'Safe Balance', 0),
  notification('notification', 'Notification', 3);

  final String value;
  final String displayName;
  final int defaultPriority; // Lower = higher priority

  const SyncEntityType(this.value, this.displayName, this.defaultPriority);

  static SyncEntityType fromString(String value) {
    return SyncEntityType.values.firstWhere(
      (t) => t.value == value,
      orElse: () => SyncEntityType.notification,
    );
  }
}

/// Actions that can be synced
enum SyncAction {
  create('create', 'Create'),
  update('update', 'Update'),
  delete('delete', 'Delete');

  final String value;
  final String displayName;

  const SyncAction(this.value, this.displayName);

  static SyncAction fromString(String value) {
    return SyncAction.values.firstWhere(
      (a) => a.value == value,
      orElse: () => SyncAction.create,
    );
  }
}
