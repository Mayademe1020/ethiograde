import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:ethiograde/config/hive_adapters.dart';
import 'package:ethiograde/services/hive_migration.dart';
import 'package:ethiograde/models/student.dart';

/// Data-integrity test for the production Hive migration.
///
/// Contract being guarded (NOT a bug-hunt — production is fine here):
///   main.dart runs `HiveMigrationService.migrate()` BEFORE
///   `registerHiveAdapters()` (main.dart:170 -> :173). Because the adapter
///   isn't registered when `migrate()` does `box.put(key, typedStudent)`, Hive
///   cannot serialize the typed object and `_migrateBox`'s try/catch falls back
///   to re-storing the raw `Map` (see hive_migration.dart:127-131).
///
/// This is *read-compatible* because `StudentProvider.loadStudents` always
/// rehydrates via `Student.fromMap(Map<String,dynamic>.from(data))` — it never
/// uses Hive's typed boxing. So leaving an upgrader's data as a Map is fine,
/// AS LONG AS that Map-based read path survives. This test pins exactly that:
/// an upgrader's v0 Map-stored Student must (a) still be present after
/// migrate(), and (b) be re-readable through the provider's own fromMap path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_migration_test_');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('upgrader v0 Map-stored Student survives migrate() and is re-readable via fromMap',
      () async {
    // Seed a pre-migration (v0) install: student stored as a raw Map, exactly
    // the way StudentProvider.addStudent writes it (`student.toMap()`).
    final original = Student(
      studentId: 'S001',
      firstName: 'Abebu',
      lastName: 'Kebede',
      gender: 'M',
      classIds: ['class-1'],
      grade: 5,
    );
    final v0Map = original.toMap();

    final box = await Hive.openBox('students');
    await box.put('student-1', v0Map);
    await box.close();

    // Mirror production ordering: migrate FIRST, then register adapters.
    await HiveMigrationService.migrate();
    registerHiveAdapters();

    final reopened = await Hive.openBox('students');

    // (a) The key survives — migrate must not drop data.
    final stored = reopened.get('student-1');
    expect(stored, isNotNull, reason: 'migrate() must not drop student data');

    // (b) Re-readable through the provider's actual read path
    //     (StudentProvider.loadStudents: Student.fromMap(Map.from(data))).
    final restored =
        Student.fromMap(Map<String, dynamic>.from(stored as Map));
    expect(restored.id, original.id);
    expect(restored.studentId, 'S001');
    expect(restored.firstName, 'Abebu');
    expect(restored.lastName, 'Kebede');
    expect(restored.gender, 'M');
    expect(restored.classIds, ['class-1']);
    expect(restored.grade, 5);

    // (c) Idempotent: a second migrate() (flag is set) must not wipe anything.
    await HiveMigrationService.migrate();
    expect(reopened.get('student-1'), isNotNull,
        reason: 'second migrate() must not drop already-migrated data');
  });
}
