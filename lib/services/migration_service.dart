import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// A single schema migration.
class _Migration {
  final int version;
  final String description;
  final Future<void> Function() run;

  const _Migration({
    required this.version,
    required this.description,
    required this.run,
  });
}

/// Manages data schema versions and runs migrations on app start.
///
/// Each migration transforms data from one schema version to the next.
/// Migrations run in order, are idempotent, and never crash the app.
///
/// Usage in main.dart:
/// ```dart
/// await Hive.initFlutter();
/// await _openBoxes(…);
/// await MigrationService.runMigrations();
/// runApp(…);
/// ```
class MigrationService {
  MigrationService._();
  static final MigrationService instance = MigrationService._();

  /// The current schema version. Bump this when adding a migration.
  static const int currentVersion = 1;

  static const String _metadataBoxName = 'metadata';
  static const String _versionKey = 'schema_version';

  /// Ordered list of migrations. Each version must appear exactly once.
  /// Version 1 is the baseline — no migration needed.
  static final List<_Migration> _migrations = [
    // _Migration(
    //   version: 2,
    //   description: 'Add studentId field to ScanResult metadata',
    //   run: () async { /* TODO: implement when needed */ },
    // ),
  ];

  /// Compare stored schema version with [currentVersion] and run any
  /// pending migrations. Safe to call on every app start.
  static Future<void> runMigrations() async {
    try {
      final metaBox = Hive.box(_metadataBoxName);
      final storedVersion = metaBox.get(_versionKey, defaultValue: 0) as int;

      if (storedVersion == currentVersion) {
        debugPrint('[Migration] Schema up to date (v$currentVersion)');
        return;
      }

      if (storedVersion > currentVersion) {
        debugPrint('[Migration] WARNING: stored v$storedVersion > '
            'current v$currentVersion — downgrades not supported');
        return;
      }

      debugPrint('[Migration] Migrating v$storedVersion → v$currentVersion');

      for (final migration in _migrations) {
        if (migration.version <= storedVersion) continue;
        if (migration.version > currentVersion) break;

        debugPrint('[Migration] Running v${migration.version}: '
            '${migration.description}');
        try {
          await migration.run();
          debugPrint('[Migration] v${migration.version} complete');
        } catch (e) {
          debugPrint('[Migration] v${migration.version} FAILED: $e');
          // Continue — don't let one broken migration block the app
        }
      }

      await metaBox.put(_versionKey, currentVersion);
      debugPrint('[Migration] Schema version updated to v$currentVersion');
    } catch (e) {
      debugPrint('[Migration] Migration framework error: $e');
      // Never crash — app starts regardless
    }
  }

  /// Manually get the stored schema version (for debugging/settings).
  static int getStoredVersion() {
    try {
      final metaBox = Hive.box(_metadataBoxName);
      return metaBox.get(_versionKey, defaultValue: 0) as int;
    } catch (_) {
      return 0;
    }
  }
}
