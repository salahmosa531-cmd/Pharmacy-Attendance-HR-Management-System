import '../models/branch_model.dart';
import 'base_repository.dart';

/// Repository for branch/pharmacy operations
class BranchRepository extends BaseRepository<Branch> {
  static BranchRepository? _instance;
  
  BranchRepository._();
  
  static BranchRepository get instance {
    _instance ??= BranchRepository._();
    return _instance!;
  }
  
  @override
  String get tableName => 'branches';
  
  @override
  Branch fromMap(Map<String, dynamic> map) => Branch.fromMap(map);
  
  @override
  Map<String, dynamic> toMap(Branch item) => item.toMap();
  
  /// Get main branch
  Future<Branch?> getMainBranch() async {
    final results = await getAll(
      where: 'is_main_branch = 1 AND is_active = 1',
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }
  
  /// Get all active branches
  Future<List<Branch>> getActiveBranches() async {
    return await getAll(
      where: 'is_active = 1',
      orderBy: 'name ASC',
    );
  }
  
  /// Get branch by device ID
  Future<Branch?> getByDeviceId(String deviceId) async {
    final results = await getAll(
      where: 'device_id = ?',
      whereArgs: [deviceId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }
  
  /// Set branch as main
  Future<void> setAsMainBranch(String branchId) async {
    final db = await database;
    
    // First, unset all main branches
    await db.update(
      tableName,
      {'is_main_branch': 0, 'updated_at': DateTime.now().toIso8601String()},
    );
    
    // Then set the specified branch as main
    await db.update(
      tableName,
      {'is_main_branch': 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [branchId],
    );
  }
  
  /// Update branch device binding
  Future<void> bindDevice(String branchId, String deviceId) async {
    final db = await database;
    await db.update(
      tableName,
      {
        'device_id': deviceId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [branchId],
    );
  }
  
  /// Update branch location
  Future<void> updateLocation(String branchId, double lat, double lng, double radius) async {
    final db = await database;
    await db.update(
      tableName,
      {
        'location_lat': lat,
        'location_lng': lng,
        'location_radius': radius,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [branchId],
    );
  }
  
  /// Get branches by owner
  Future<List<Branch>> getByOwner(String ownerId) async {
    return await getAll(
      where: 'owner_id = ? AND is_active = 1',
      whereArgs: [ownerId],
      orderBy: 'name ASC',
    );
  }
  
  /// Check if branch name exists
  Future<bool> nameExists(String name, {String? excludeId}) async {
    String where = 'LOWER(name) = LOWER(?)';
    List<dynamic> whereArgs = [name];
    
    if (excludeId != null) {
      where += ' AND id != ?';
      whereArgs.add(excludeId);
    }
    
    final count = await this.count(where: where, whereArgs: whereArgs);
    return count > 0;
  }
}
