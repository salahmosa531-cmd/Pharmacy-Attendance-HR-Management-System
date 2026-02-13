import '../models/branch_model.dart';
import 'base_repository.dart';

/// Repository for branch/pharmacy operations
/// 
/// SINGLE-BRANCH ARCHITECTURE:
/// - Only one branch with id='1' is supported
/// - Branch creation/deletion methods throw exceptions
/// - Branch table retained for FK safety
class BranchRepository extends BaseRepository<Branch> {
  // SINGLE-BRANCH: Default branch ID constant
  static const String defaultBranchId = '1';
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
  
  // =========================================
  // SINGLE-BRANCH: DISABLED OPERATIONS
  // =========================================
  
  /// Get the default branch (always branch '1' in single-branch mode)
  Future<Branch?> getDefaultBranch() async {
    return await getById(defaultBranchId);
  }
  
  /// SINGLE-BRANCH: Branch creation is disabled
  /// @deprecated Use getDefaultBranch() instead
  /// @throws Exception always - branch creation not allowed
  @override
  Future<void> insert(Branch item) async {
    // Allow initial seeding of the default branch only
    if (item.id == defaultBranchId) {
      final existing = await getById(defaultBranchId);
      if (existing == null) {
        await super.insert(item);
        return;
      }
    }
    throw Exception('Branch creation is disabled in single-branch mode. Only the default branch (id=$defaultBranchId) is supported.');
  }
  
  /// SINGLE-BRANCH: Branch deletion is disabled
  /// @deprecated Branch deletion not allowed
  /// @throws Exception always - branch deletion not allowed
  @override
  Future<int> delete(String id) async {
    throw Exception('Branch deletion is disabled in single-branch mode. The default branch cannot be deleted.');
  }
  
  /// SINGLE-BRANCH: Bulk operations are disabled
  /// @deprecated Bulk operations not allowed
  /// @throws Exception always
  @override
  Future<int> deleteAll() async {
    throw Exception('Branch deletion is disabled in single-branch mode.');
  }
}
