import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Shift model
class Shift extends Equatable {
  final String id;
  final String branchId;
  final String name;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final int gracePeriodMinutes;
  final bool isCrossMidnight;
  final bool isActive;
  final Color? color;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? syncedAt;

  const Shift({
    required this.id,
    required this.branchId,
    required this.name,
    required this.startTime,
    required this.endTime,
    this.gracePeriodMinutes = 15,
    this.isCrossMidnight = false,
    this.isActive = true,
    this.color,
    required this.createdAt,
    required this.updatedAt,
    this.syncedAt,
  });

  factory Shift.fromMap(Map<String, dynamic> map) {
    final startTimeParts = (map['start_time'] as String).split(':');
    final endTimeParts = (map['end_time'] as String).split(':');
    
    Color? color;
    if (map['color'] != null) {
      final colorValue = int.tryParse(map['color'] as String);
      if (colorValue != null) {
        color = Color(colorValue);
      }
    }
    
    return Shift(
      id: map['id'] as String,
      branchId: map['branch_id'] as String,
      name: map['name'] as String,
      startTime: TimeOfDay(
        hour: int.parse(startTimeParts[0]),
        minute: int.parse(startTimeParts[1]),
      ),
      endTime: TimeOfDay(
        hour: int.parse(endTimeParts[0]),
        minute: int.parse(endTimeParts[1]),
      ),
      gracePeriodMinutes: (map['grace_period_minutes'] as int?) ?? 15,
      isCrossMidnight: (map['is_cross_midnight'] as int?) == 1,
      isActive: (map['is_active'] as int?) == 1,
      color: color,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      syncedAt: map['synced_at'] != null
          ? DateTime.parse(map['synced_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'branch_id': branchId,
      'name': name,
      'start_time': '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
      'end_time': '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
      'grace_period_minutes': gracePeriodMinutes,
      'is_cross_midnight': isCrossMidnight ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'color': color?.value.toString(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'synced_at': syncedAt?.toIso8601String(),
    };
  }

  Shift copyWith({
    String? id,
    String? branchId,
    String? name,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    int? gracePeriodMinutes,
    bool? isCrossMidnight,
    bool? isActive,
    Color? color,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? syncedAt,
  }) {
    return Shift(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      name: name ?? this.name,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      gracePeriodMinutes: gracePeriodMinutes ?? this.gracePeriodMinutes,
      isCrossMidnight: isCrossMidnight ?? this.isCrossMidnight,
      isActive: isActive ?? this.isActive,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  /// Get formatted time range string
  String get timeRange {
    final startStr = '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
    final endStr = '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';
    return '$startStr - $endStr${isCrossMidnight ? ' (next day)' : ''}';
  }

  /// Get shift duration in minutes
  int get durationMinutes {
    int startMinutes = startTime.hour * 60 + startTime.minute;
    int endMinutes = endTime.hour * 60 + endTime.minute;
    
    if (isCrossMidnight || endMinutes < startMinutes) {
      endMinutes += 24 * 60;
    }
    
    return endMinutes - startMinutes;
  }

  /// Get shift duration in hours
  double get durationHours => durationMinutes / 60;

  /// Check if a given time falls within this shift (considering grace period)
  bool isTimeWithinShift(TimeOfDay time, {bool includeGrace = true}) {
    int timeMinutes = time.hour * 60 + time.minute;
    int startMinutes = startTime.hour * 60 + startTime.minute;
    int endMinutes = endTime.hour * 60 + endTime.minute;
    
    if (includeGrace) {
      startMinutes -= gracePeriodMinutes;
    }
    
    if (isCrossMidnight || endMinutes < startMinutes) {
      // Shift crosses midnight
      return timeMinutes >= startMinutes || timeMinutes <= endMinutes;
    } else {
      return timeMinutes >= startMinutes && timeMinutes <= endMinutes;
    }
  }

  /// Calculate late minutes for a given clock-in time
  int calculateLateMinutes(TimeOfDay clockInTime) {
    int clockInMinutes = clockInTime.hour * 60 + clockInTime.minute;
    int startMinutes = startTime.hour * 60 + startTime.minute;
    int graceEndMinutes = startMinutes + gracePeriodMinutes;
    
    if (isCrossMidnight && clockInMinutes < startMinutes - 12 * 60) {
      clockInMinutes += 24 * 60;
    }
    
    if (clockInMinutes > graceEndMinutes) {
      return clockInMinutes - startMinutes;
    }
    
    return 0;
  }

  /// Calculate early leave minutes for a given clock-out time
  int calculateEarlyLeaveMinutes(TimeOfDay clockOutTime) {
    int clockOutMinutes = clockOutTime.hour * 60 + clockOutTime.minute;
    int endMinutes = endTime.hour * 60 + endTime.minute;
    
    if (isCrossMidnight) {
      if (clockOutMinutes < 12 * 60) {
        clockOutMinutes += 24 * 60;
      }
      endMinutes += 24 * 60;
    }
    
    if (clockOutMinutes < endMinutes) {
      return endMinutes - clockOutMinutes;
    }
    
    return 0;
  }

  @override
  List<Object?> get props => [
        id,
        branchId,
        name,
        startTime,
        endTime,
        gracePeriodMinutes,
        isCrossMidnight,
        isActive,
        color,
        createdAt,
        updatedAt,
        syncedAt,
      ];
}
