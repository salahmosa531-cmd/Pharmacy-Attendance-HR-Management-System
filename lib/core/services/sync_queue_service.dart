import 'dart:async';
import 'package:uuid/uuid.dart';
import '../../data/models/sync_queue_model.dart';
import '../../data/repositories/sync_queue_repository.dart';
import 'logging_service.dart';

/// Sync Queue Service - Manages cloud synchronization queue
/// 
/// OFFLINE-FIRST ARCHITECTURE:
/// - SQLite remains the primary data source
/// - All operations are stored locally first
/// - This service queues operations for eventual cloud sync
/// - Sync worker processes queue when internet is available
/// - No UI changes required - this is transparent to users
class SyncQueueService {
  static final SyncQueueService _instance = SyncQueueService._();
  static SyncQueueService get instance => _instance;
  
  final _syncQueueRepo = SyncQueueRepository.instance;
  final _uuid = const Uuid();
  
  // Sync worker
  Timer? _syncWorker;
  bool _isSyncing = false;
  bool _isOnline = false;
  
  // Callbacks for sync events
  final List<Function(SyncStatus)> _statusListeners = [];
  
  SyncQueueService._();

  // =========================================================================
  // QUEUE OPERATIONS
  // =========================================================================

  /// Queue a financial shift for sync
  Future<void> queueFinancialShift(Map<String, dynamic> shiftData, SyncAction action) async {
    await _queueItem(
      entityType: SyncEntityType.financialShift,
      entityId: shiftData['id'] as String,
      action: action,
      payload: shiftData,
    );
  }

  /// Queue a shift sale for sync
  Future<void> queueShiftSale(Map<String, dynamic> saleData, SyncAction action) async {
    await _queueItem(
      entityType: SyncEntityType.shiftSale,
      entityId: saleData['id'] as String,
      action: action,
      payload: saleData,
    );
  }

  /// Queue a shift expense for sync
  Future<void> queueShiftExpense(Map<String, dynamic> expenseData, SyncAction action) async {
    await _queueItem(
      entityType: SyncEntityType.shiftExpense,
      entityId: expenseData['id'] as String,
      action: action,
      payload: expenseData,
    );
  }

  /// Queue a shift closure for sync
  Future<void> queueShiftClosure(Map<String, dynamic> closureData, SyncAction action) async {
    await _queueItem(
      entityType: SyncEntityType.shiftClosure,
      entityId: closureData['id'] as String,
      action: action,
      payload: closureData,
    );
  }

  /// Queue a safe transaction for sync
  Future<void> queueSafeTransaction(Map<String, dynamic> transactionData, SyncAction action) async {
    await _queueItem(
      entityType: SyncEntityType.safeTransaction,
      entityId: transactionData['id'] as String,
      action: action,
      payload: transactionData,
    );
  }

  /// Queue a safe balance update for sync
  Future<void> queueSafeBalance(Map<String, dynamic> balanceData, SyncAction action) async {
    await _queueItem(
      entityType: SyncEntityType.safeBalance,
      entityId: balanceData['id'] as String,
      action: action,
      payload: balanceData,
    );
  }

  /// Queue a notification for sync
  Future<void> queueNotification(Map<String, dynamic> notificationData, SyncAction action) async {
    await _queueItem(
      entityType: SyncEntityType.notification,
      entityId: notificationData['id'] as String,
      action: action,
      payload: notificationData,
    );
  }

  /// Internal method to queue an item
  Future<void> _queueItem({
    required SyncEntityType entityType,
    required String entityId,
    required SyncAction action,
    required Map<String, dynamic> payload,
  }) async {
    final item = SyncQueueItem(
      id: _uuid.v4(),
      entityType: entityType,
      entityId: entityId,
      action: action,
      payload: payload,
      priority: entityType.defaultPriority,
      createdAt: DateTime.now(),
    );
    
    await _syncQueueRepo.queueItem(item);
    
    LoggingService.instance.debug(
      'SyncQueueService',
      'Queued ${action.displayName} for ${entityType.displayName}: $entityId',
    );
  }

  // =========================================================================
  // SYNC WORKER
  // =========================================================================

  /// Start the background sync worker
  void startSyncWorker({Duration interval = const Duration(minutes: 5)}) {
    _syncWorker?.cancel();
    _syncWorker = Timer.periodic(interval, (_) => _processSyncQueue());
    
    LoggingService.instance.info(
      'SyncQueueService',
      'Sync worker started with ${interval.inMinutes} minute interval',
    );
  }

  /// Stop the background sync worker
  void stopSyncWorker() {
    _syncWorker?.cancel();
    _syncWorker = null;
    
    LoggingService.instance.info(
      'SyncQueueService',
      'Sync worker stopped',
    );
  }

  /// Set online status (called when network status changes)
  void setOnlineStatus(bool isOnline) {
    final wasOnline = _isOnline;
    _isOnline = isOnline;
    
    if (!wasOnline && isOnline) {
      // Just came online - trigger immediate sync
      LoggingService.instance.info(
        'SyncQueueService',
        'Network restored - triggering immediate sync',
      );
      _processSyncQueue();
    }
    
    _notifyStatusChange();
  }

  /// Process the sync queue
  Future<void> _processSyncQueue() async {
    if (_isSyncing) {
      LoggingService.instance.debug(
        'SyncQueueService',
        'Sync already in progress, skipping',
      );
      return;
    }
    
    if (!_isOnline) {
      LoggingService.instance.debug(
        'SyncQueueService',
        'Offline - skipping sync',
      );
      return;
    }
    
    _isSyncing = true;
    _notifyStatusChange();
    
    try {
      final pendingItems = await _syncQueueRepo.getPendingItems(limit: 50);
      
      if (pendingItems.isEmpty) {
        LoggingService.instance.debug(
          'SyncQueueService',
          'No pending items to sync',
        );
        return;
      }
      
      LoggingService.instance.info(
        'SyncQueueService',
        'Processing ${pendingItems.length} pending items',
      );
      
      final syncedIds = <String>[];
      
      for (final item in pendingItems) {
        try {
          // TODO: Implement actual cloud sync here
          // For now, we just mark items as synced after a simulated delay
          // In production, this would call the cloud API
          
          // Simulate cloud sync
          // await _syncToCloud(item);
          
          syncedIds.add(item.id);
        } catch (e) {
          LoggingService.instance.warning(
            'SyncQueueService',
            'Failed to sync ${item.entityType.displayName} ${item.entityId}: $e',
          );
          await _syncQueueRepo.markRetry(item.id, e.toString());
        }
      }
      
      if (syncedIds.isNotEmpty) {
        await _syncQueueRepo.markBatchSynced(syncedIds);
        LoggingService.instance.info(
          'SyncQueueService',
          'Successfully synced ${syncedIds.length} items',
        );
      }
    } catch (e) {
      LoggingService.instance.error(
        'SyncQueueService',
        'Error processing sync queue',
        e,
        StackTrace.current,
      );
    } finally {
      _isSyncing = false;
      _notifyStatusChange();
    }
  }

  /// Force an immediate sync
  Future<void> forceSyncNow() async {
    _isOnline = true; // Assume online for manual sync
    await _processSyncQueue();
  }

  // =========================================================================
  // STATUS & LISTENERS
  // =========================================================================

  /// Get current sync status
  Future<SyncStatus> getStatus() async {
    final stats = await _syncQueueRepo.getSyncStats();
    
    return SyncStatus(
      isOnline: _isOnline,
      isSyncing: _isSyncing,
      pendingCount: stats['pending'] ?? 0,
      syncedCount: stats['synced'] ?? 0,
      failedCount: stats['failed'] ?? 0,
    );
  }

  /// Add a status listener
  void addStatusListener(Function(SyncStatus) listener) {
    _statusListeners.add(listener);
  }

  /// Remove a status listener
  void removeStatusListener(Function(SyncStatus) listener) {
    _statusListeners.remove(listener);
  }

  /// Notify all listeners of status change
  void _notifyStatusChange() async {
    final status = await getStatus();
    for (final listener in _statusListeners) {
      listener(status);
    }
  }

  // =========================================================================
  // MAINTENANCE
  // =========================================================================

  /// Clear old synced items
  Future<int> clearOldItems({int olderThanDays = 30}) async {
    return await _syncQueueRepo.clearOldSyncedItems(olderThanDays: olderThanDays);
  }

  /// Reset failed items for retry
  Future<void> resetFailedItems() async {
    await _syncQueueRepo.resetFailedItems();
    LoggingService.instance.info(
      'SyncQueueService',
      'Reset failed items for retry',
    );
  }

  /// Get pending count
  Future<int> getPendingCount() async {
    return await _syncQueueRepo.getPendingCount();
  }
}

/// Sync status for UI display
class SyncStatus {
  final bool isOnline;
  final bool isSyncing;
  final int pendingCount;
  final int syncedCount;
  final int failedCount;

  SyncStatus({
    required this.isOnline,
    required this.isSyncing,
    required this.pendingCount,
    required this.syncedCount,
    required this.failedCount,
  });

  int get totalCount => pendingCount + syncedCount + failedCount;
  
  bool get hasPending => pendingCount > 0;
  bool get hasFailed => failedCount > 0;
  bool get isFullySynced => pendingCount == 0 && failedCount == 0;
}
