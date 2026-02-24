import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/sync_queue_model.dart';
import 'base_repository.dart';

/// Repository for sync queue operations
/// 
/// Manages the queue of operations waiting to be synced to the cloud.
/// SQLite remains the primary data source; this enables eventual consistency.
class SyncQueueRepository extends BaseRepository<SyncQueueItem> {
  static SyncQueueRepository? _instance;
  
  SyncQueueRepository._();
  
  static SyncQueueRepository get instance {
    _instance ??= SyncQueueRepository._();
    return _instance!;
  }
  
  @override
  String get tableName => 'sync_queue';
  
  @override
  SyncQueueItem fromMap(Map<String, dynamic> map) => SyncQueueItem.fromMap(map);
  
  @override
  Map<String, dynamic> toMap(SyncQueueItem item) => item.toMap();
  
  /// Get all pending (unsynced) items ordered by priority
  Future<List<SyncQueueItem>> getPendingItems({int? limit}) async {
    return await getAll(
      where: 'is_synced = 0 AND retry_count < 5',
      orderBy: 'priority ASC, created_at ASC',
      limit: limit,
    );
  }
  
  /// Get pending items by entity type
  Future<List<SyncQueueItem>> getPendingByType(
    SyncEntityType type, {
    int? limit,
  }) async {
    return await getAll(
      where: 'is_synced = 0 AND entity_type = ?',
      whereArgs: [type.value],
      orderBy: 'priority ASC, created_at ASC',
      limit: limit,
    );
  }
  
  /// Get count of pending items
  Future<int> getPendingCount() async {
    return await count(
      where: 'is_synced = 0 AND retry_count < 5',
    );
  }
  
  /// Get count of failed items (exceeded retries)
  Future<int> getFailedCount() async {
    return await count(
      where: 'is_synced = 0 AND retry_count >= 5',
    );
  }
  
  /// Mark item as synced
  Future<void> markSynced(String id) async {
    final db = await database;
    await db.update(
      tableName,
      {
        'is_synced': 1,
        'synced_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  /// Mark multiple items as synced
  Future<void> markBatchSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final placeholders = ids.map((_) => '?').join(',');
    
    await db.rawUpdate(
      'UPDATE $tableName SET is_synced = 1, synced_at = ? WHERE id IN ($placeholders)',
      [now, ...ids],
    );
  }
  
  /// Increment retry count and set error
  Future<void> markRetry(String id, String? error) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE $tableName SET retry_count = retry_count + 1, last_error = ? WHERE id = ?',
      [error, id],
    );
  }
  
  /// Queue a new item for sync
  Future<void> queueItem(SyncQueueItem item) async {
    final db = await database;
    
    // Use INSERT OR REPLACE to handle duplicates (same entity_type + entity_id + action)
    await db.insert(
      tableName,
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  
  /// Check if an item is already queued
  Future<bool> isQueued(SyncEntityType type, String entityId, SyncAction action) async {
    final c = await count(
      where: 'entity_type = ? AND entity_id = ? AND action = ? AND is_synced = 0',
      whereArgs: [type.value, entityId, action.value],
    );
    return c > 0;
  }
  
  /// Delete synced items older than specified days
  Future<int> clearOldSyncedItems({int olderThanDays = 30}) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(Duration(days: olderThanDays));
    
    return await db.delete(
      tableName,
      where: 'is_synced = 1 AND synced_at < ?',
      whereArgs: [cutoff.toIso8601String()],
    );
  }
  
  /// Delete all synced items
  Future<int> clearAllSynced() async {
    final db = await database;
    return await db.delete(
      tableName,
      where: 'is_synced = 1',
    );
  }
  
  /// Reset failed items for retry
  Future<void> resetFailedItems() async {
    final db = await database;
    await db.update(
      tableName,
      {
        'retry_count': 0,
        'last_error': null,
      },
      where: 'is_synced = 0 AND retry_count >= 5',
    );
  }
  
  /// Get sync statistics
  Future<Map<String, int>> getSyncStats() async {
    final db = await database;
    
    final pending = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $tableName WHERE is_synced = 0 AND retry_count < 5',
    );
    final synced = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $tableName WHERE is_synced = 1',
    );
    final failed = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $tableName WHERE is_synced = 0 AND retry_count >= 5',
    );
    
    return {
      'pending': (pending.first['count'] as int?) ?? 0,
      'synced': (synced.first['count'] as int?) ?? 0,
      'failed': (failed.first['count'] as int?) ?? 0,
    };
  }
}
