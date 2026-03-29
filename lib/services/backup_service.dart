import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/student.dart';
import '../models/assessment.dart';
import '../models/scan_result.dart';
import 'validation_service.dart';

/// Import result with counts and error details.
class ImportResult {
  final int imported;
  final int skipped;
  final List<String> errors;

  const ImportResult({
    required this.imported,
    required this.skipped,
    required this.errors,
  });

  bool get hasErrors => errors.isNotEmpty;

  @override
  String toString() =>
      'ImportResult(imported: $imported, skipped: $skipped, errors: ${errors.length})';
}

/// Export / import / auto-backup for all EthioGrade data.
///
/// Exports are human-readable JSON files. Imports validate every record
/// via [ValidationService] before writing.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const ValidationService _validator = ValidationService();
  static const String _studentsBox = 'students';
  static const String _assessmentsBox = 'assessments';
  static const String _scanResultsBox = 'scan_results';
  static const String _metadataBox = 'metadata';
  static const String _autoBackupCountKey = 'auto_backup_scan_count';

  static const int _autoBackupInterval = 10; // every N scans
  static const int _maxAutoBackups = 3;

  // ── Export ─────────────────────────────────────────────────────────

  /// Export all data to a timestamped JSON file.
  /// Returns the file path on success, null on failure.
  Future<String?> exportAllData() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final filePath = '${dir.path}/ethiograde_backup_$timestamp.json';

      final data = await _collectAllData();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      await File(filePath).writeAsString(jsonStr);

      debugPrint('[Backup] Exported to $filePath');
      return filePath;
    } catch (e) {
      debugPrint('[Backup] Export failed: $e');
      return null;
    }
  }

  /// Export and open the system share sheet.
  Future<void> exportAndShare() async {
    final filePath = await exportAllData();
    if (filePath == null) return;

    try {
      await Share.shareXFiles(
        [XFile(filePath)],
        subject: 'EthioGrade Backup',
        text: 'EthioGrade data backup',
      );
    } catch (e) {
      debugPrint('[Backup] Share failed: $e');
    }
  }

  // ── Import ─────────────────────────────────────────────────────────

  /// Import data from a JSON backup file.
  ///
  /// [replace] — if true, clears all existing data before importing.
  ///             if false, merges (skips duplicates by ID).
  Future<ImportResult> importData(
    String filePath, {
    bool replace = false,
  }) async {
    final errors = <String>[];
    int imported = 0;
    int skipped = 0;

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return const ImportResult(
          imported: 0, skipped: 0, errors: ['File not found: $filePath'],
        );
      }

      final jsonStr = await file.readAsString();
      final Map<String, dynamic> data;
      try {
        data = jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (e) {
        return ImportResult(
          imported: 0, skipped: 0, errors: ['Invalid JSON: $e'],
        );
      }

      // Version check
      final version = data['version'] as int? ?? 0;
      if (version < 1) {
        return ImportResult(
          imported: 0, skipped: 0,
          errors: ['Unsupported backup version: $version'],
        );
      }

      // Clear existing data if replace mode
      if (replace) {
        await _clearAllBoxes();
      }

      // Import students
      final students = data['students'] as List? ?? [];
      for (final item in students) {
        try {
          final map = Map<String, dynamic>.from(item as Map);
          final student = Student.fromMap(map);
          final validation = _validator.validateStudent(student);
          if (!validation.isValid) {
            errors.add('Student ${student.id}: ${validation.errors.join("; ")}');
            skipped++;
            continue;
          }

          final box = Hive.box(_studentsBox);
          if (!replace && box.containsKey(student.id)) {
            skipped++;
            continue;
          }
          await box.put(student.id, student.toMap());
          imported++;
        } catch (e) {
          errors.add('Student record: $e');
          skipped++;
        }
      }

      // Import assessments
      final assessments = data['assessments'] as List? ?? [];
      for (final item in assessments) {
        try {
          final map = Map<String, dynamic>.from(item as Map);
          final assessment = Assessment.fromMap(map);
          final validation = _validator.validateAssessment(assessment);
          if (!validation.isValid) {
            errors.add('Assessment ${assessment.id}: ${validation.errors.join("; ")}');
            skipped++;
            continue;
          }

          final box = Hive.box(_assessmentsBox);
          if (!replace && box.containsKey(assessment.id)) {
            skipped++;
            continue;
          }
          await box.put(assessment.id, assessment.toMap());
          imported++;
        } catch (e) {
          errors.add('Assessment record: $e');
          skipped++;
        }
      }

      // Import scan results
      final scanResults = data['scanResults'] as List? ?? [];
      for (final item in scanResults) {
        try {
          final map = Map<String, dynamic>.from(item as Map);
          final scan = ScanResult.fromMap(map);
          final validation = _validator.validateScanResult(scan);
          if (!validation.isValid) {
            errors.add('ScanResult ${scan.id}: ${validation.errors.join("; ")}');
            skipped++;
            continue;
          }

          final box = Hive.lazyBox(_scanResultsBox);
          if (!replace) {
            final existing = await box.get(scan.id);
            if (existing != null) {
              skipped++;
              continue;
            }
          }
          await box.put(scan.id, scan.toMap());
          imported++;
        } catch (e) {
          errors.add('ScanResult record: $e');
          skipped++;
        }
      }

      debugPrint('[Backup] Import done: $imported imported, $skipped skipped, '
          '${errors.length} errors');
      return ImportResult(imported: imported, skipped: skipped, errors: errors);
    } catch (e) {
      debugPrint('[Backup] Import failed: $e');
      return ImportResult(
        imported: 0, skipped: 0, errors: ['Import failed: $e'],
      );
    }
  }

  // ── Auto-backup ───────────────────────────────────────────────────

  /// Call after every scan. Auto-backs up every [_autoBackupInterval] scans.
  Future<void> recordScanAndMaybeBackup() async {
    try {
      final metaBox = Hive.box(_metadataBox);
      final count = (metaBox.get(_autoBackupCountKey, defaultValue: 0) as int) + 1;

      if (count >= _autoBackupInterval) {
        await metaBox.put(_autoBackupCountKey, 0);
        await _autoBackup();
      } else {
        await metaBox.put(_autoBackupCountKey, count);
      }
    } catch (e) {
      debugPrint('[Backup] recordScanAndMaybeBackup failed: $e');
    }
  }

  /// Create a timestamped auto-backup and prune old ones.
  Future<void> _autoBackup() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final filePath = '${dir.path}/ethiograde_auto_$timestamp.json';

      final data = await _collectAllData();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      await File(filePath).writeAsString(jsonStr);

      debugPrint('[Backup] Auto-backup saved to $filePath');

      // Prune: keep only last N auto-backups
      final autoBackups = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('ethiograde_auto_'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path)); // newest first

      for (int i = _maxAutoBackups; i < autoBackups.length; i++) {
        try {
          await autoBackups[i].delete();
          debugPrint('[Backup] Pruned old auto-backup: ${autoBackups[i].path}');
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[Backup] Auto-backup failed: $e');
    }
  }

  // ── List backups ──────────────────────────────────────────────────

  /// List all backup files (manual + auto) with metadata.
  Future<List<BackupInfo>> listBackups() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final backups = <BackupInfo>[];

      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        if (!entity.path.contains('ethiograde_')) continue;
        if (!entity.path.endsWith('.json')) continue;

        try {
          final stat = await entity.stat();
          final name = entity.path.split('/').last;
          final isAuto = name.contains('_auto_');
          backups.add(BackupInfo(
            filePath: entity.path,
            fileName: name,
            date: stat.modified,
            sizeBytes: stat.size,
            isAutoBackup: isAuto,
          ));
        } catch (_) {}
      }

      backups.sort((a, b) => b.date.compareTo(a.date));
      return backups;
    } catch (e) {
      debugPrint('[Backup] listBackups failed: $e');
      return [];
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  /// Collect all data from all boxes into a single JSON-serialisable map.
  Future<Map<String, dynamic>> _collectAllData() async {
    final studentsBox = Hive.box(_studentsBox);
    final assessmentsBox = Hive.box(_assessmentsBox);
    final scanResultsBox = Hive.lazyBox(_scanResultsBox);

    final students = studentsBox.values
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();

    final assessments = assessmentsBox.values
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();

    final scanResults = <Map<String, dynamic>>[];
    for (final key in scanResultsBox.keys) {
      final data = await scanResultsBox.get(key);
      if (data != null) {
        scanResults.add(Map<String, dynamic>.from(data as Map));
      }
    }

    return {
      'version': 1,
      'exportDate': DateTime.now().toIso8601String(),
      'students': students,
      'assessments': assessments,
      'scanResults': scanResults,
    };
  }

  /// Clear all data boxes (used in replace-mode import).
  Future<void> _clearAllBoxes() async {
    try {
      await Hive.box(_studentsBox).clear();
      await Hive.box(_assessmentsBox).clear();
      await Hive.lazyBox(_scanResultsBox).clear();
      debugPrint('[Backup] All boxes cleared for replace import');
    } catch (e) {
      debugPrint('[Backup] clearAllBoxes failed: $e');
    }
  }
}

/// Metadata about a backup file.
class BackupInfo {
  final String filePath;
  final String fileName;
  final DateTime date;
  final int sizeBytes;
  final bool isAutoBackup;

  const BackupInfo({
    required this.filePath,
    required this.fileName,
    required this.date,
    required this.sizeBytes,
    required this.isAutoBackup,
  });

  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
