import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/student.dart';
import '../models/class_info.dart';
import '../models/assessment.dart';
import '../models/scan_result.dart';
import '../models/audit_entry.dart';
import '../models/grading_scale.dart';
import '../models/teacher.dart';
import '../models/weighted_grade.dart';

/// Migrates Hive data from raw Map serialization to typed TypeAdapter format.
///
/// Before this migration, models were stored as Map<dynamic, dynamic> in Hive.
/// With TypeAdapters, they're stored as binary and read back as typed objects.
/// Old Map data cannot be read after adapters are registered, so migration
/// must happen BEFORE adapter registration.
///
/// Flow:
/// 1. Check metadata box for migration flag
/// 2. If not migrated: read all boxes as raw data
/// 3. Convert Maps to model objects using existing fromMap() factories
/// 4. Clear boxes and re-save as typed objects
/// 5. Mark migration complete
class HiveMigrationService {
  static const String _migrationKey = 'hive_typed_adapter_v1';
  static const String _metadataBox = 'metadata';

  /// Whether the typed adapter migration has already run.
  static Future<bool> isMigrationComplete() async {
    try {
      if (!Hive.isBoxOpen(_metadataBox)) {
        await Hive.openBox(_metadataBox);
      }
      final metaBox = Hive.box(_metadataBox);
      return metaBox.get(_migrationKey) == true;
    } catch (_) {
      return false;
    }
  }

  /// Mark migration as complete in the metadata box.
  static Future<void> markComplete() async {
    if (!Hive.isBoxOpen(_metadataBox)) {
      await Hive.openBox(_metadataBox);
    }
    final metaBox = Hive.box(_metadataBox);
    await metaBox.put(_migrationKey, true);
  }

  /// Run the full Map→typed migration.
  ///
  /// IMPORTANT: Call this BEFORE registerHiveAdapters().
  /// After adapters are registered, reading old Map data will fail.
  static Future<void> migrate() async {
    if (await isMigrationComplete()) {
      debugPrint('[HiveMigration] Already migrated — skipping');
      return;
    }

    debugPrint('[HiveMigration] Starting Map → typed migration...');
    final sw = Stopwatch()..start();

    // Migrate each box
    await _migrateBox<Student>(
      'students',
      (map) => Student.fromMap(map));
    await _migrateBox<ClassInfo>(
      'classes',
      (map) => ClassInfo.fromMap(map));
    await _migrateBox<Assessment>(
      'assessments',
      (map) => Assessment.fromMap(map));
    await _migrateLazyBox<ScanResult>(
      'scan_results',
      (map) => ScanResult.fromMap(map));
    await _migrateBox<AuditEntry>(
      'audit_trail',
      (map) => AuditEntry.fromMap(map));
    await _migrateBox<GradingScale>(
      'grading_scales',
      (map) => GradingScale.fromMap(map));
    await _migrateBox<WeightedGradeScale>(
      'weighted_scales',
      (map) => WeightedGradeScale.fromMap(map));

    await markComplete();
    debugPrint('[HiveMigration] Complete in ${sw.elapsedMilliseconds}ms');
  }

  /// Migrate a regular box from Maps to typed objects.
  static Future<void> _migrateBox<T>(
    String boxName,
    T Function(Map<String, dynamic>) fromMap) async {
    try {
      // Check if box exists on disk
      final box = await Hive.openBox(boxName);
      if (box.isEmpty) {
        await box.close();
        debugPrint('[HiveMigration] $boxName: empty — skipping');
        return;
      }

      // Read all entries as Maps
      final entries = <String, Map<String, dynamic>>{};
      for (final key in box.keys) {
        final value = box.get(key);
        if (value is Map) {
          entries[key.toString()] = Map<String, dynamic>.from(value);
        }
      }

      if (entries.isEmpty) {
        await box.close();
        debugPrint('[HiveMigration] $boxName: no Map data — skipping');
        return;
      }

      debugPrint('[HiveMigration] $boxName: migrating ${entries.length} entries');

      // Clear and re-save as typed objects
      await box.clear();
      for (final entry in entries.entries) {
        try {
          final typed = fromMap(entry.value);
          await box.put(entry.key, typed);
        } catch (e) {
          debugPrint('[HiveMigration] $boxName: failed to convert key=${entry.key}: $e');
          // Re-save as raw Map as fallback
          await box.put(entry.key, entry.value);
        }
      }

      await box.close();
      debugPrint('[HiveMigration] $boxName: done');
    } catch (e) {
      debugPrint('[HiveMigration] $boxName: error — $e');
      // Non-fatal: app will work with empty/corrupt box (corruption recovery in main.dart)
    }
  }

  /// Migrate a lazy box from Maps to typed objects.
  static Future<void> _migrateLazyBox<T>(
    String boxName,
    T Function(Map<String, dynamic>) fromMap) async {
    try {
      final box = await Hive.openLazyBox(boxName);
      if (box.isEmpty) {
        await box.close();
        debugPrint('[HiveMigration] $boxName (lazy): empty — skipping');
        return;
      }

      final entries = <String, Map<String, dynamic>>{};
      for (final key in box.keys) {
        final value = await box.get(key);
        if (value is Map) {
          entries[key.toString()] = Map<String, dynamic>.from(value);
        }
      }

      if (entries.isEmpty) {
        await box.close();
        debugPrint('[HiveMigration] $boxName (lazy): no Map data — skipping');
        return;
      }

      debugPrint('[HiveMigration] $boxName (lazy): migrating ${entries.length} entries');

      await box.clear();
      for (final entry in entries.entries) {
        try {
          final typed = fromMap(entry.value);
          await box.put(entry.key, typed);
        } catch (e) {
          debugPrint('[HiveMigration] $boxName (lazy): failed key=${entry.key}: $e');
          await box.put(entry.key, entry.value);
        }
      }

      await box.close();
      debugPrint('[HiveMigration] $boxName (lazy): done');
    } catch (e) {
      debugPrint('[HiveMigration] $boxName (lazy): error — $e');
    }
  }
}
