import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ethiograde/services/migration_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ethiograde_migration_test_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    await Hive.openBox('metadata');
  });

  tearDown(() async {
    for (final name in Hive.boxNames) {
      if (Hive.isBoxOpen(name)) {
        try {
          await Hive.box(name).close();
        } catch (_) {}
      }
    }
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('MigrationService', () {
    test('getStoredVersion returns 0 on fresh install', () {
      final version = MigrationService.getStoredVersion();
      expect(version, 0);
    });

    test('runMigrations sets schema version', () async {
      await MigrationService.runMigrations();
      final version = MigrationService.getStoredVersion();
      expect(version, MigrationService.currentVersion);
    });

    test('runMigrations is idempotent', () async {
      await MigrationService.runMigrations();
      final v1 = MigrationService.getStoredVersion();

      await MigrationService.runMigrations();
      final v2 = MigrationService.getStoredVersion();

      expect(v1, v2);
    });

    test('runMigrations never throws even with corrupt metadata', () async {
      final box = Hive.box('metadata');
      // Write invalid data that would crash a naive implementation
      await box.put('schema_version', 'not_a_number');

      // Should not throw
      await MigrationService.runMigrations();
    });

    test('currentVersion is at least 1', () {
      expect(MigrationService.currentVersion, greaterThanOrEqualTo(1));
    });
  });
}
