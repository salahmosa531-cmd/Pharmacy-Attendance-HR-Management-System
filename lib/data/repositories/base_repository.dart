import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core/services/database_service.dart';

/// Base repository class with common database operations
abstract class BaseRepository<T> {
  final DatabaseService _databaseService = DatabaseService.instance;
  
  /// Get the table name for this repository
  String get tableName;
  
  /// Convert a map to a model instance
  T fromMap(Map<String, dynamic> map);
  
  /// Convert a model instance to a map
  Map<String, dynamic> toMap(T item);
  
  /// Get the database instance
  Future<Database> get database => _databaseService.database;
  
  /// Insert a new record
  Future<void> insert(T item) async {
    final db = await database;
    await db.insert(
      tableName,
      toMap(item),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  
  /// Insert multiple records in a batch
  Future<void> insertAll(List<T> items) async {
    final db = await database;
    final batch = db.batch();
    for (final item in items) {
      batch.insert(
        tableName,
        toMap(item),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
  
  /// Update an existing record
  Future<int> update(T item, String id) async {
    final db = await database;
    return await db.update(
      tableName,
      toMap(item),
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  /// Delete a record by ID
  Future<int> delete(String id) async {
    final db = await database;
    return await db.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  /// Get a record by ID
  Future<T?> getById(String id) async {
    final db = await database;
    final results = await db.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    
    if (results.isEmpty) return null;
    return fromMap(results.first);
  }
  
  /// Get all records
  Future<List<T>> getAll({
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    final results = await db.query(
      tableName,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    
    return results.map((map) => fromMap(map)).toList();
  }
  
  /// Count records
  Future<int> count({String? where, List<dynamic>? whereArgs}) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $tableName${where != null ? ' WHERE $where' : ''}',
      whereArgs,
    );
    if (result.isEmpty) return 0;
    final value = result.first['count'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
  
  /// Execute a raw query
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<dynamic>? arguments,
  ]) async {
    final db = await database;
    return await db.rawQuery(sql, arguments);
  }
  
  /// Execute a raw update/insert/delete
  Future<int> rawExecute(String sql, [List<dynamic>? arguments]) async {
    final db = await database;
    return await db.rawUpdate(sql, arguments);
  }
  
  /// Check if a record exists
  Future<bool> exists(String id) async {
    final db = await database;
    final result = await db.query(
      tableName,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return result.isNotEmpty;
  }
  
  /// Delete all records (use with caution)
  Future<int> deleteAll() async {
    final db = await database;
    return await db.delete(tableName);
  }
}
