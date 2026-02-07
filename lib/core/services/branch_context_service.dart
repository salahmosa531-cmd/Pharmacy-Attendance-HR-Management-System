import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/branch_model.dart';
import '../../data/models/shift_model.dart';
import '../../data/repositories/branch_repository.dart';
import '../../data/repositories/shift_repository.dart';
import 'logging_service.dart';
import 'settings_service.dart';

/// Keys for persistent storage
class _StorageKeys {
  static const String activeBranchId = 'active_branch_id';
  static const String deviceId = 'device_id';
  static const String isDeviceBound = 'is_device_bound';
}

/// Branch context state for global access
class BranchContextState {
  final Branch? activeBranch;
  final String? deviceId;
  final bool isDeviceBound;
  final bool isLoading;
  final String? error;
  final List<Branch> availableBranches;

  const BranchContextState({
    this.activeBranch,
    this.deviceId,
    this.isDeviceBound = false,
    this.isLoading = false,
    this.error,
    this.availableBranches = const [],
  });

  bool get hasBranch => activeBranch != null;
  bool get needsBranchSelection => !hasBranch && availableBranches.isNotEmpty;
  bool get needsSetup => availableBranches.isEmpty;

  BranchContextState copyWith({
    Branch? activeBranch,
    String? deviceId,
    bool? isDeviceBound,
    bool? isLoading,
    String? error,
    List<Branch>? availableBranches,
    bool clearActiveBranch = false,
    bool clearError = false,
  }) {
    return BranchContextState(
      activeBranch: clearActiveBranch ? null : (activeBranch ?? this.activeBranch),
      deviceId: deviceId ?? this.deviceId,
      isDeviceBound: isDeviceBound ?? this.isDeviceBound,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      availableBranches: availableBranches ?? this.availableBranches,
    );
  }

  @override
  String toString() {
    return 'BranchContextState(branch: ${activeBranch?.name}, deviceId: $deviceId, bound: $isDeviceBound, loading: $isLoading, branches: ${availableBranches.length})';
  }
}

/// Global service for managing branch context across the application
/// This is the single source of truth for the active branch
class BranchContextService {
  static BranchContextService? _instance;
  
  final BranchRepository _branchRepository = BranchRepository.instance;
  final ShiftRepository _shiftRepository = ShiftRepository.instance;
  final Uuid _uuid = const Uuid();
  
  final StreamController<BranchContextState> _stateController = 
      StreamController<BranchContextState>.broadcast();
  
  BranchContextState _state = const BranchContextState(isLoading: true);
  
  BranchContextService._();
  
  static BranchContextService get instance {
    _instance ??= BranchContextService._();
    return _instance!;
  }
  
  /// Stream of branch context state changes
  Stream<BranchContextState> get stateStream => _stateController.stream;
  
  /// Current state
  BranchContextState get state => _state;
  
  /// Quick access to active branch
  Branch? get activeBranch => _state.activeBranch;
  
  /// Quick access to active branch ID (for attendance service)
  String? get activeBranchId => _state.activeBranch?.id;
  
  /// Check if we have a valid branch context
  bool get hasBranch => _state.hasBranch;
  
  /// Check if device is bound to a branch
  bool get isDeviceBound => _state.isDeviceBound;
  
  /// Get device ID
  String? get deviceId => _state.deviceId;
  
  /// Initialize the service - called at app startup
  Future<void> initialize() async {
    LoggingService.instance.info('BranchContext', 'Initializing...');
    
    _updateState(_state.copyWith(isLoading: true, clearError: true));
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get or generate device ID
      String? deviceId = prefs.getString(_StorageKeys.deviceId);
      if (deviceId == null) {
        deviceId = _uuid.v4();
        await prefs.setString(_StorageKeys.deviceId, deviceId);
        LoggingService.instance.info('BranchContext', 'Generated new device ID: $deviceId');
      }
      
      // Load available branches
      final branches = await _branchRepository.getActiveBranches();
      LoggingService.instance.info('BranchContext', 'Found ${branches.length} branches');
      
      // Try to restore active branch
      final savedBranchId = prefs.getString(_StorageKeys.activeBranchId);
      final isDeviceBound = prefs.getBool(_StorageKeys.isDeviceBound) ?? false;
      
      Branch? activeBranch;
      
      if (savedBranchId != null) {
        // Try to find the saved branch
        activeBranch = branches.where((b) => b.id == savedBranchId).firstOrNull;
        
        if (activeBranch != null) {
          LoggingService.instance.info('BranchContext', 'Restored active branch: ${activeBranch.name}');
        } else {
          LoggingService.instance.warning('BranchContext', 'Saved branch not found, clearing...');
          await prefs.remove(_StorageKeys.activeBranchId);
        }
      }
      
      // Do not auto-select a branch; require explicit admin action.
      if (activeBranch == null && branches.isNotEmpty) {
        LoggingService.instance.info(
          'BranchContext',
          'Branch selection required (no active branch set)',
        );
      }
      
      // Initialize settings if branch is set
      if (activeBranch != null) {
        await SettingsService.instance.initialize();
      }
      
      _updateState(BranchContextState(
        activeBranch: activeBranch,
        deviceId: deviceId,
        isDeviceBound: isDeviceBound,
        isLoading: false,
        availableBranches: branches,
      ));
      
      LoggingService.instance.info('BranchContext', 'Initialized - $_state');
      
    } catch (e, stack) {
      LoggingService.instance.error('BranchContext', 'Initialization failed', e, stack);
      _updateState(_state.copyWith(
        isLoading: false,
        error: 'Failed to initialize branch context: $e',
      ));
    }
  }
  
  /// Set the active branch
  Future<void> setActiveBranch(Branch branch) async {
    LoggingService.instance.info('BranchContext', 'Setting active branch to: ${branch.name}');
    
    try {
      await _persistActiveBranch(branch.id);
      
      // Reinitialize settings for new branch
      await SettingsService.instance.initialize();
      
      _updateState(_state.copyWith(
        activeBranch: branch,
        clearError: true,
      ));
      
      LoggingService.instance.info('BranchContext', 'Active branch set successfully');
      
    } catch (e, stack) {
      LoggingService.instance.error('BranchContext', 'Failed to set active branch', e, stack);
      _updateState(_state.copyWith(error: 'Failed to set active branch: $e'));
    }
  }
  
  /// Bind device to current branch
  Future<void> bindDeviceToBranch() async {
    if (_state.activeBranch == null || _state.deviceId == null) {
      throw Exception('Cannot bind device: no active branch or device ID');
    }
    
    try {
      await _branchRepository.bindDevice(_state.activeBranch!.id, _state.deviceId!);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_StorageKeys.isDeviceBound, true);
      
      _updateState(_state.copyWith(isDeviceBound: true));
      
      LoggingService.instance.info('BranchContext', 'Device bound to branch ${_state.activeBranch!.name}');
      
    } catch (e, stack) {
      LoggingService.instance.error('BranchContext', 'Failed to bind device', e, stack);
      throw Exception('Failed to bind device: $e');
    }
  }
  
  /// Clear active branch (for switching)
  Future<void> clearActiveBranch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_StorageKeys.activeBranchId);
    
    _updateState(_state.copyWith(clearActiveBranch: true));
    
    LoggingService.instance.info('BranchContext', 'Active branch cleared');
  }
  
  /// Refresh branches from database
  Future<void> refreshBranches() async {
    try {
      final branches = await _branchRepository.getActiveBranches();
      
      // Check if current active branch still exists
      Branch? activeBranch = _state.activeBranch;
      if (activeBranch != null) {
        final stillExists = branches.any((b) => b.id == activeBranch!.id);
        if (!stillExists) {
          activeBranch = null;
          await clearActiveBranch();
        }
      }
      
      _updateState(_state.copyWith(
        availableBranches: branches,
        activeBranch: activeBranch,
      ));
      
    } catch (e, stack) {
      LoggingService.instance.error('BranchContext', 'Failed to refresh branches', e, stack);
    }
  }
  
  /// Create a new branch with default configuration
  Future<Branch> createBranchWithDefaults({
    required String name,
    String? address,
    String? phone,
    String? email,
    bool setAsActive = true,
  }) async {
    LoggingService.instance.info('BranchContext', 'Creating branch: $name');
    
    final now = DateTime.now();
    final isFirstBranch = _state.availableBranches.isEmpty;
    
    // Create the branch
    final branch = Branch(
      id: _uuid.v4(),
      name: name,
      address: address,
      phone: phone,
      email: email,
      isMainBranch: isFirstBranch,
      deviceId: _state.deviceId,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
    
    await _branchRepository.insert(branch);
    LoggingService.instance.info('BranchContext', 'Branch created with ID: ${branch.id}');
    
    // Create default shifts for the branch
    await _createDefaultShifts(branch.id);
    
    // Refresh branches list
    await refreshBranches();
    
    // Set as active if requested
    if (setAsActive) {
      await setActiveBranch(branch);
    }
    
    return branch;
  }
  
  /// Create default shifts for a branch
  Future<void> _createDefaultShifts(String branchId) async {
    LoggingService.instance.info('BranchContext', 'Creating default shifts for branch');
    
    final now = DateTime.now();
    
    // Default shifts for a typical pharmacy
    final defaultShifts = [
      Shift(
        id: _uuid.v4(),
        branchId: branchId,
        name: 'Morning Shift',
        startTime: const TimeOfDay(hour: 8, minute: 0),
        endTime: const TimeOfDay(hour: 16, minute: 0),
        gracePeriodMinutes: 15,
        isCrossMidnight: false,
        isActive: true,
        color: const Color(0xFF4CAF50), // Green
        createdAt: now,
        updatedAt: now,
      ),
      Shift(
        id: _uuid.v4(),
        branchId: branchId,
        name: 'Evening Shift',
        startTime: const TimeOfDay(hour: 16, minute: 0),
        endTime: const TimeOfDay(hour: 0, minute: 0),
        gracePeriodMinutes: 15,
        isCrossMidnight: true,
        isActive: true,
        color: const Color(0xFF2196F3), // Blue
        createdAt: now,
        updatedAt: now,
      ),
      Shift(
        id: _uuid.v4(),
        branchId: branchId,
        name: 'Night Shift',
        startTime: const TimeOfDay(hour: 0, minute: 0),
        endTime: const TimeOfDay(hour: 8, minute: 0),
        gracePeriodMinutes: 15,
        isCrossMidnight: false,
        isActive: true,
        color: const Color(0xFF9C27B0), // Purple
        createdAt: now,
        updatedAt: now,
      ),
    ];
    
    for (final shift in defaultShifts) {
      await _shiftRepository.insert(shift);
    }
    
    LoggingService.instance.info('BranchContext', 'Created ${defaultShifts.length} default shifts');
  }
  
  /// Persist active branch ID to storage
  Future<void> _persistActiveBranch(String branchId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_StorageKeys.activeBranchId, branchId);
  }
  
  /// Update state and notify listeners
  void _updateState(BranchContextState newState) {
    _state = newState;
    _stateController.add(_state);
  }
  
  /// Dispose resources
  void dispose() {
    _stateController.close();
  }
}
