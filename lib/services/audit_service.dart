import 'package:hive_flutter/hive_flutter.dart';

import '../models/audit_entry.dart';
import '../models/scan_result.dart';
import 'app_log.dart';
import 'error_handler.dart';
import 'hive_box_mixin.dart';

/// Audit trail service — records every grade change with who/when/what/why.
///
/// Answers "parent disputes a grade" by providing a complete history:
/// - Who entered the original grade
/// - When it was entered
/// - What the original score/grade was
/// - Who modified it and when
/// - What it was changed to and why
///
/// All entries stored in the encrypted Hive `audit_trail` box.
class AuditService with HiveBoxMixin {
  static final AuditService _instance = AuditService._();
  factory AuditService() => _instance;
  AuditService._();

  static const String _boxName = 'audit_trail';

  /// Record a new audit entry.
  Future<void> record(AuditEntry entry) async {
    try {
      final box = await openBox(_boxName);
      await box.put(entry.id, entry.toMap());
      AppLog.info(this, 'record', '${entry.action} on ${entry.scanResultId}');
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'record', e, st);
      // Never crash on audit failure — grading must continue
    }
  }

  /// Record grade creation.
  Future<void> recordCreated({
    required ScanResult result,
    required String teacherId,
    required String teacherName,
  }) async {
    await record(
      AuditEntry(
        scanResultId: result.id,
        action: 'created',
        teacherId: teacherId,
        teacherName: teacherName,
        newValues: {
          'totalScore': result.totalScore,
          'percentage': result.percentage,
          'grade': result.grade,
        },
      ),
    );
  }

  /// Record a score override (teacher manually changes a score).
  Future<void> recordScoreOverride({
    required String scanResultId,
    required String teacherId,
    required String teacherName,
    required double oldScore,
    required double newScore,
    required double oldPercentage,
    required double newPercentage,
    required String oldGrade,
    required String newGrade,
    String? reason,
  }) async {
    await record(
      AuditEntry(
        scanResultId: scanResultId,
        action: 'score_override',
        teacherId: teacherId,
        teacherName: teacherName,
        previousValues: {
          'totalScore': oldScore,
          'percentage': oldPercentage,
          'grade': oldGrade,
        },
        newValues: {
          'totalScore': newScore,
          'percentage': newPercentage,
          'grade': newGrade,
        },
        reason: reason,
      ),
    );
  }

  /// Record a student reassignment.
  Future<void> recordReassignment({
    required String scanResultId,
    required String teacherId,
    required String teacherName,
    required String oldStudentId,
    required String oldStudentName,
    required String newStudentId,
    required String newStudentName,
  }) async {
    await record(
      AuditEntry(
        scanResultId: scanResultId,
        action: 'reassigned',
        teacherId: teacherId,
        teacherName: teacherName,
        previousValues: {
          'studentId': oldStudentId,
          'studentName': oldStudentName,
        },
        newValues: {'studentId': newStudentId, 'studentName': newStudentName},
      ),
    );
  }

  /// Record a comment addition.
  Future<void> recordComment({
    required String scanResultId,
    required String teacherId,
    required String teacherName,
    required String comment,
  }) async {
    await record(
      AuditEntry(
        scanResultId: scanResultId,
        action: 'comment_added',
        teacherId: teacherId,
        teacherName: teacherName,
        newValues: {'comment': comment},
      ),
    );
  }

  /// Record a grading scale change.
  ///
  /// Uses a synthetic scanResultId ('scale:<scaleId>') because scale changes
  /// are not tied to a specific scan result — they affect future grading.
  Future<void> recordScaleChange({
    required String scaleId,
    required String scaleName,
    required String teacherId,
    required String teacherName,
    required List<Map<String, dynamic>> previousRanges,
    required List<Map<String, dynamic>> newRanges,
    String? reason,
  }) async {
    await record(
      AuditEntry(
        scanResultId: 'scale:$scaleId',
        action: 'scale_change',
        teacherId: teacherId,
        teacherName: teacherName,
        previousValues: {'name': scaleName, 'ranges': previousRanges},
        newValues: {'name': scaleName, 'ranges': newRanges},
        reason: reason,
      ),
    );
  }

  /// Get the full audit trail for a scan result, oldest first.
  List<AuditEntry> getTrail(String scanResultId) {
    try {
      // Note: openBox is async but this method is sync for API compatibility.
      // The box is expected to be pre-opened at startup.
      final box = Hive.box(_boxName);
      final entries =
          box.values
              .map(
                (v) => AuditEntry.fromMap(Map<String, dynamic>.from(v as Map)),
              )
              .where((e) => e.scanResultId == scanResultId)
              .toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return entries;
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'getTrail', e, st);
      return [];
    }
  }

  /// Get the original (first creation) entry for a scan result.
  AuditEntry? getOriginalEntry(String scanResultId) {
    final trail = getTrail(scanResultId);
    try {
      return trail.firstWhere((e) => e.action == 'created');
    } catch (_) {
      return trail.isNotEmpty ? trail.first : null;
    }
  }

  /// Get the most recent entry for a scan result.
  AuditEntry? getLatestEntry(String scanResultId) {
    final trail = getTrail(scanResultId);
    return trail.isNotEmpty ? trail.last : null;
  }

  /// Check if a scan result has been modified since creation.
  bool hasBeenModified(String scanResultId) {
    return getTrail(scanResultId).length > 1;
  }

  /// Get all entries for a student across all assessments.
  List<AuditEntry> getStudentTrail(String studentId) {
    try {
      final box = Hive.box(_boxName);
      return box.values
          .map((v) => AuditEntry.fromMap(Map<String, dynamic>.from(v as Map)))
          .where(
            (e) =>
                e.newValues['studentId'] == studentId ||
                e.previousValues['studentId'] == studentId,
          )
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'getStudentTrail', e, st);
      return [];
    }
  }

  /// Clear all audit entries (used in clear-all-data).
  Future<void> clearAll() async {
    try {
      final box = await openBox(_boxName);
      await box.clear();
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'clearAll', e, st);
    }
  }
}
