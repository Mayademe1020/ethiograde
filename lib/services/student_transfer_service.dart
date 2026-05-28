import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/student.dart';
import '../models/scan_result.dart';

/// Service for handling student transfers between classes.
///
/// Handles the "student transfers mid-term" edge case:
/// - Student's grade history follows them to the new class
/// - Original class retains historical records (for class analytics)
/// - Transfer is recorded with timestamp and reason
///
/// Implementation: Uses the student's metadata map to store transfer
/// history, and the existing classIds list for current class membership.
/// No schema changes needed.
class StudentTransferService {
  static final StudentTransferService _instance = StudentTransferService._();
  factory StudentTransferService() => _instance;
  StudentTransferService._();

  static const String _transfersBox = 'student_transfers';

  /// Transfer a student from one class to another.
  ///
  /// - Removes [fromClassId] from student's classIds
  /// - Adds [toClassId] to student's classIds
  /// - Records the transfer in the student's metadata and transfers box
  /// - Grade history is preserved — scan results still reference the
  ///   student ID, so they remain accessible regardless of class
  Future<TransferResult> transferStudent({
    required Student student,
    required String fromClassId,
    required String toClassId,
    String? reason,
    String? teacherId,
    String? teacherName,
  }) async {
    if (fromClassId == toClassId) {
      return TransferResult(
        success: false,
        message: 'Source and destination classes are the same');
    }

    if (!student.classIds.contains(fromClassId)) {
      return TransferResult(
        success: false,
        message: 'Student is not in the source class');
    }

    // Build new classIds
    final newClassIds = List<String>.from(student.classIds)
      ..remove(fromClassId);
    if (!newClassIds.contains(toClassId)) {
      newClassIds.add(toClassId);
    }

    // Record transfer in metadata
    final transfers = List<Map<String, dynamic>>.from(
      student.metadata['transfers'] ?? []);
    transfers.add({
      'fromClassId': fromClassId,
      'toClassId': toClassId,
      'timestamp': DateTime.now().toIso8601String(),
      'reason': reason ?? '',
      'teacherId': teacherId ?? '',
      'teacherName': teacherName ?? '',
    });

    final newMetadata = Map<String, dynamic>.from(student.metadata);
    newMetadata['transfers'] = transfers;

    // Create updated student with transfer history in metadata
    final updatedStudent = student.copyWith(
      classIds: newClassIds,
      metadata: newMetadata);

    // Also persist transfer record separately for querying
    try {
      final box = Hive.box(_transfersBox);
      final transferId = '${student.id}_${DateTime.now().millisecondsSinceEpoch}';
      await box.put(transferId, {
        'studentId': student.id,
        'studentName': student.fullName,
        'fromClassId': fromClassId,
        'toClassId': toClassId,
        'timestamp': DateTime.now().toIso8601String(),
        'reason': reason ?? '',
        'teacherId': teacherId ?? '',
        'teacherName': teacherName ?? '',
      });
    } catch (e) {
      debugPrint('[Transfer] Failed to persist transfer record: $e');
    }

    return TransferResult(
      success: true,
      message: 'Student transferred successfully',
      updatedStudent: updatedStudent,
      transferHistory: transfers);
  }

  /// Get transfer history for a student.
  List<TransferRecord> getTransferHistory(String studentId) {
    try {
      final box = Hive.box(_transfersBox);
      return box.values
          .map((v) => TransferRecord.fromMap(Map<String, dynamic>.from(v as Map)))
          .where((r) => r.studentId == studentId)
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } catch (e) {
      debugPrint('[Transfer] getTransferHistory failed: $e');
      return [];
    }
  }

  /// Get all students who were previously in a class (transferred out).
  List<TransferRecord> getTransfersOutOf(String classId) {
    try {
      final box = Hive.box(_transfersBox);
      return box.values
          .map((v) => TransferRecord.fromMap(Map<String, dynamic>.from(v as Map)))
          .where((r) => r.fromClassId == classId)
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e) {
      debugPrint('[Transfer] getTransfersOutOf failed: $e');
      return [];
    }
  }

  /// Get all students who transferred into a class.
  List<TransferRecord> getTransfersInto(String classId) {
    try {
      final box = Hive.box(_transfersBox);
      return box.values
          .map((v) => TransferRecord.fromMap(Map<String, dynamic>.from(v as Map)))
          .where((r) => r.toClassId == classId)
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e) {
      debugPrint('[Transfer] getTransfersInto failed: $e');
      return [];
    }
  }

  /// Clear all transfer records.
  Future<void> clearAll() async {
    try {
      final box = Hive.box(_transfersBox);
      await box.clear();
    } catch (e) {
      debugPrint('[Transfer] clearAll failed: $e');
    }
  }
}

/// Result of a student transfer operation.
class TransferResult {
  final bool success;
  final String message;
  final Student? updatedStudent;
  final List<Map<String, dynamic>>? transferHistory;

  const TransferResult({
    required this.success,
    required this.message,
    this.updatedStudent,
    this.transferHistory,
  });
}

/// A single transfer record.
class TransferRecord {
  final String studentId;
  final String studentName;
  final String fromClassId;
  final String toClassId;
  final DateTime timestamp;
  final String reason;
  final String teacherId;
  final String teacherName;

  const TransferRecord({
    required this.studentId,
    required this.studentName,
    required this.fromClassId,
    required this.toClassId,
    required this.timestamp,
    this.reason = '',
    this.teacherId = '',
    this.teacherName = '',
  });

  factory TransferRecord.fromMap(Map<String, dynamic> map) => TransferRecord(
    studentId: map['studentId'] ?? '',
    studentName: map['studentName'] ?? '',
    fromClassId: map['fromClassId'] ?? '',
    toClassId: map['toClassId'] ?? '',
    timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
    reason: map['reason'] ?? '',
    teacherId: map['teacherId'] ?? '',
    teacherName: map['teacherName'] ?? '');
}
