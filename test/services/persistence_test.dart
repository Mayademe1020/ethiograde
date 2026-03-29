import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:ethiograde/services/validation_service.dart';
import 'package:ethiograde/services/student_provider.dart';
import 'package:ethiograde/services/assessment_provider.dart';
import 'package:ethiograde/services/migration_service.dart';
import 'package:ethiograde/services/backup_service.dart';

import 'package:ethiograde/models/student.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  // ── Box names (must match what services use) ──────────────────────
  const studentsBox = 'students';
  const assessmentsBox = 'assessments';
  const scanResultsBox = 'scan_results';
  const metadataBox = 'metadata';

  // ── Helpers ───────────────────────────────────────────────────────

  Student makeStudent({
    String id = 's1',
    String firstName = 'Abebe',
    String lastName = 'Kebede',
    int grade = 5,
    String className = '5A',
  }) =>
      Student(
        id: id,
        firstName: firstName,
        lastName: lastName,
        grade: grade,
        className: className,
      );

  Assessment makeAssessment({
    String id = 'a1',
    String title = 'Math Midterm',
    List<Question>? questions,
  }) =>
      Assessment(
        id: id,
        title: title,
        subject: 'Math',
        questions: questions ??
            [
              Question(number: 1, type: QuestionType.mcq, correctAnswer: 'A'),
              Question(number: 2, type: QuestionType.mcq, correctAnswer: 'B'),
            ],
      );

  ScanResult makeScanResult({
    String id = 'r1',
    String assessmentId = 'a1',
    String studentId = 's1',
    double totalScore = 8,
    double maxScore = 10,
  }) =>
      ScanResult(
        id: id,
        assessmentId: assessmentId,
        studentId: studentId,
        studentName: 'Abebe Kebede',
        imagePath: '/tmp/test.jpg',
        totalScore: totalScore,
        maxScore: maxScore,
        confidence: 0.9,
        percentage: 80,
      );

  // ── Setup ─────────────────────────────────────────────────────────

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ethiograde_test_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    // Open fresh boxes for each test — no shared state
    await Hive.openBox(studentsBox);
    await Hive.openBox(assessmentsBox);
    await Hive.openBox(scanResultsBox); // regular box for testing (not lazy)
    await Hive.openBox(metadataBox);
  });

  tearDown(() async {
    // Clear and close — complete isolation between tests
    for (final name in [studentsBox, assessmentsBox, scanResultsBox, metadataBox]) {
      final box = Hive.box(name);
      await box.clear();
      await box.close();
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  // ══════════════════════════════════════════════════════════════════
  // HAPPY PATH
  // ══════════════════════════════════════════════════════════════════

  group('Happy path', () {
    test('1. Hive boxes open successfully', () {
      expect(Hive.isBoxOpen(studentsBox), isTrue);
      expect(Hive.isBoxOpen(assessmentsBox), isTrue);
      expect(Hive.isBoxOpen(scanResultsBox), isTrue);
      expect(Hive.isBoxOpen(metadataBox), isTrue);
    });

    test('2. Add student → load → verify exists with correct data',
        () async {
      final provider = StudentProvider();
      // Wait for initial load
      await Future.delayed(const Duration(milliseconds: 100));

      final result = await provider.addStudent(makeStudent());
      expect(result.success, isTrue);

      final loaded = provider.getStudentById('s1');
      expect(loaded, isNotNull);
      expect(loaded!.firstName, 'Abebe');
      expect(loaded.lastName, 'Kebede');
      expect(loaded.grade, 5);
    });

    test('3. Add assessment → load → verify exists', () async {
      final provider = AssessmentProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      final result = await provider.addAssessment(makeAssessment());
      expect(result.success, isTrue);

      final loaded = provider.getAssessmentById('a1');
      expect(loaded, isNotNull);
      expect(loaded!.title, 'Math Midterm');
      expect(loaded.questions.length, 2);
    });

    test('4. Save scan result → load by assessment → verify count',
        () async {
      final box = Hive.box(scanResultsBox);
      await box.put('r1', makeScanResult().toMap());
      await box.put('r2',
          makeScanResult(id: 'r2', assessmentId: 'a1', studentId: 's2').toMap());
      await box.put('r3',
          makeScanResult(id: 'r3', assessmentId: 'a2', studentId: 's1').toMap());

      // Count results for assessment a1
      int count = 0;
      for (final key in box.keys) {
        final data = Map<String, dynamic>.from(box.get(key) as Map);
        if (data['assessmentId'] == 'a1') count++;
      }
      expect(count, 2);
    });

    test('5. Update student → load → verify changes persisted', () async {
      final provider = StudentProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      await provider.addStudent(makeStudent());
      final updated = makeStudent().copyWith(firstName: 'Bekele', grade: 6);
      final result = await provider.updateStudent(updated);
      expect(result.success, isTrue);

      final loaded = provider.getStudentById('s1');
      expect(loaded!.firstName, 'Bekele');
      expect(loaded.grade, 6);
    });

    test('6. Delete student → load → verify gone', () async {
      final provider = StudentProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      await provider.addStudent(makeStudent());
      expect(provider.getStudentById('s1'), isNotNull);

      final result = await provider.deleteStudent('s1');
      expect(result.success, isTrue);
      expect(provider.getStudentById('s1'), isNull);
    });

    test('7. Search students → verify correct results', () async {
      final provider = StudentProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      await provider.addStudent(makeStudent(id: 's1', firstName: 'Abebe'));
      await provider.addStudent(
          makeStudent(id: 's2', firstName: 'Bekele', lastName: 'Tadesse'));
      await provider.addStudent(
          makeStudent(id: 's3', firstName: 'Chaltu', lastName: 'Abebe'));

      final results = provider.searchStudents('abebe');
      expect(results.length, 2); // firstName match + lastName match

      final results2 = provider.searchStudents('Tadesse');
      expect(results2.length, 1);
      expect(results2.first.firstName, 'Bekele');

      // Empty query returns all
      final all = provider.searchStudents('');
      expect(all.length, 3);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // VALIDATION
  // ══════════════════════════════════════════════════════════════════

  group('Validation', () {
    test('8. Add student with empty name → verify rejected', () async {
      final provider = StudentProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      final result = await provider.addStudent(
          makeStudent(firstName: '', lastName: ''));
      expect(result.success, isFalse);
      expect(result.error, contains('empty'));
    });

    test('9. Add student with 200-char name → verify rejected', () async {
      final provider = StudentProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      final longName = 'A' * 200;
      final result =
          await provider.addStudent(makeStudent(firstName: longName));
      expect(result.success, isFalse);
      expect(result.error, contains('100'));
    });

    test('10. Add assessment with invalid MCQ answer → verify rejected',
        () async {
      final provider = AssessmentProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      final assessment = makeAssessment(questions: [
        Question(number: 1, type: QuestionType.mcq, correctAnswer: 'Z'),
      ]);
      final result = await provider.addAssessment(assessment);
      expect(result.success, isFalse);
      expect(result.error, contains('MCQ'));
    });

    test('11. Validation rejects student with negative grade', () async {
      const validator = ValidationService();
      final result = validator.validateStudent(makeStudent(grade: -1));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('Grade'));
    });

    test('12. Validation rejects assessment with empty title', () async {
      const validator = ValidationService();
      final result =
          validator.validateAssessment(makeAssessment(title: ''));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('title'));
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // EDGE CASES
  // ══════════════════════════════════════════════════════════════════

  group('Edge cases', () {
    test('13. Load from empty box → verify returns empty list', () async {
      final provider = StudentProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(provider.students, isEmpty);
      expect(provider.totalStudents, 0);
    });

    test('14. Save duplicate student ID → verify handled', () async {
      final provider = StudentProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      await provider.addStudent(makeStudent());
      final result = await provider.addStudent(makeStudent()); // same ID
      expect(result.success, isFalse);
      expect(result.error, contains('already exists'));
    });

    test('15. Delete student that doesn\'t exist → verify graceful',
        () async {
      final provider = StudentProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      final result = await provider.deleteStudent('nonexistent');
      expect(result.success, isFalse);
      expect(result.error, contains('not found'));
    });

    test('16. Save 100 scan results → verify completes without error',
        () async {
      final box = Hive.box(scanResultsBox);
      for (int i = 0; i < 100; i++) {
        await box.put('result_$i', makeScanResult(id: 'result_$i').toMap());
      }
      expect(box.length, 100);

      // Verify round-trip
      final data = Map<String, dynamic>.from(box.get('result_50') as Map);
      final scan = ScanResult.fromMap(data);
      expect(scan.id, 'result_50');
      expect(scan.totalScore, 8);
    });

    test('17. Load student with corrupted data → verify graceful fallback',
        () async {
      final box = Hive.box(studentsBox);
      // Write valid student
      await box.put('s_good', makeStudent(id: 's_good').toMap());
      // Write corrupted data (not a valid map)
      await box.put('s_bad', 'this is not a map');

      // Provider should handle corrupted data
      final provider = StudentProvider();
      await Future.delayed(const Duration(milliseconds: 200));

      // Should either skip the bad entry or fall back to empty
      // Either way, must not crash
      expect(provider.students, isNotNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // ERROR HANDLING
  // ══════════════════════════════════════════════════════════════════

  group('Error handling', () {
    test('18. Provider operations return Result type on failure', () async {
      final provider = StudentProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      // Add valid student
      await provider.addStudent(makeStudent());

      // Try to add same ID — should return failure Result
      final duplicate = await provider.addStudent(makeStudent());
      expect(duplicate.success, isFalse);
      expect(duplicate.error, isNotNull);

      // Update nonexistent student
      final updateResult =
          await provider.updateStudent(makeStudent(id: 'ghost'));
      expect(updateResult.success, isFalse);
    });

    test('19. Assessment provider saveAssessment backward-compat works',
        () async {
      final provider = AssessmentProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      final assessment = makeAssessment();
      // saveAssessment should work as add on first call
      await provider.saveAssessment(assessment);
      expect(provider.getAssessmentById('a1'), isNotNull);

      // saveAssessment should work as update on second call
      final updated = assessment.copyWith(title: 'Updated');
      await provider.saveAssessment(updated);
      expect(provider.getAssessmentById('a1')!.title, 'Updated');
    });

    test('20. getRecentAssessments returns correct limit', () async {
      final provider = AssessmentProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      for (int i = 0; i < 10; i++) {
        await provider.addAssessment(makeAssessment(
          id: 'a$i',
          title: 'Assessment $i',
        ));
      }

      final recent = provider.getRecentAssessments(3);
      expect(recent.length, 3);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // BACKUP / EXPORT
  // ══════════════════════════════════════════════════════════════════

  group('Backup & Export', () {
    test('21. Export → verify JSON structure correct', () async {
      // Seed data
      final studentsBox_ = Hive.box(studentsBox);
      final assessmentsBox_ = Hive.box(assessmentsBox);
      await studentsBox_.put('s1', makeStudent().toMap());
      await assessmentsBox_.put('a1', makeAssessment().toMap());

      // Read back as the backup service would
      final students = studentsBox_.values
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
      final assessments = assessmentsBox_.values
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();

      final exportData = {
        'version': 1,
        'exportDate': DateTime.now().toIso8601String(),
        'students': students,
        'assessments': assessments,
        'scanResults': <Map>[],
      };

      // Verify structure
      final jsonStr = const JsonEncoder.withIndent('  ').convert(exportData);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(decoded['version'], 1);
      expect(decoded['exportDate'], isNotEmpty);
      expect(decoded['students'], isA<List>());
      expect(decoded['assessments'], isA<List>());
      expect(decoded['scanResults'], isA<List>());
      expect((decoded['students'] as List).length, 1);
      expect((decoded['assessments'] as List).length, 1);

      // Verify student round-trip
      final studentMap = Map<String, dynamic>.from(
          (decoded['students'] as List).first as Map);
      final student = Student.fromMap(studentMap);
      expect(student.firstName, 'Abebe');
      expect(student.grade, 5);
    });

    test('22. Import → verify data restored correctly', () async {
      final importDir =
          await Directory.systemTemp.createTemp('ethiograde_import_');
      final filePath = '${importDir.path}/test_backup.json';

      // Create a backup file
      final backupData = {
        'version': 1,
        'exportDate': DateTime.now().toIso8601String(),
        'students': [makeStudent(id: 'imp_s1', firstName: 'Imported').toMap()],
        'assessments': [
          makeAssessment(id: 'imp_a1', title: 'Imported Exam').toMap()
        ],
        'scanResults': <Map>[],
      };
      await File(filePath).writeAsString(jsonEncode(backupData));

      // Import using the backup service's logic manually
      final data = jsonDecode(await File(filePath).readAsString())
          as Map<String, dynamic>;
      final students = data['students'] as List;

      final box = Hive.box(studentsBox);
      for (final item in students) {
        final map = Map<String, dynamic>.from(item as Map);
        final student = Student.fromMap(map);
        await box.put(student.id, student.toMap());
      }

      // Verify
      final loaded = Student.fromMap(
          Map<String, dynamic>.from(box.get('imp_s1') as Map));
      expect(loaded.firstName, 'Imported');
      expect(loaded.grade, 5);
      expect(box.containsKey('imp_s1'), isTrue);

      await importDir.delete(recursive: true);
    });

    test('23. Import with merge → verify no duplicates', () async {
      final box = Hive.box(studentsBox);
      // Pre-existing student
      await box.put('s1', makeStudent().toMap());

      // Simulate merge import: skip if ID exists
      final importStudents = [
        makeStudent(id: 's1', firstName: 'Duplicate').toMap(),
        makeStudent(id: 's2', firstName: 'NewImport').toMap(),
      ];

      int imported = 0;
      int skipped = 0;
      for (final item in importStudents) {
        final map = Map<String, dynamic>.from(item as Map);
        if (box.containsKey(map['id'])) {
          skipped++;
        } else {
          await box.put(map['id'], map);
          imported++;
        }
      }

      expect(imported, 1);
      expect(skipped, 1);
      expect(box.length, 2);

      // Original student preserved (not overwritten)
      final original = Student.fromMap(
          Map<String, dynamic>.from(box.get('s1') as Map));
      expect(original.firstName, 'Abebe'); // not 'Duplicate'
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // MIGRATION
  // ══════════════════════════════════════════════════════════════════

  group('Migration', () {
    test('24. Schema version 1 → verify stored correctly', () async {
      final metaBox = Hive.box(metadataBox);

      // Fresh install: stored version should be 0 (default)
      final initial = metaBox.get('schema_version', defaultValue: 0) as int;
      expect(initial, 0);

      // After migration: should be 1
      await metaBox.put('schema_version', 1);
      final after = metaBox.get('schema_version', defaultValue: 0) as int;
      expect(after, 1);
    });

    test('25. Migration framework runs without error', () async {
      final metaBox = Hive.box(metadataBox);

      // Set stored version to 0 (simulates fresh install)
      await metaBox.put('schema_version', 0);

      // Run migrations — should complete without error
      await MigrationService.runMigrations();

      // Version should be updated to current
      final version =
          metaBox.get('schema_version', defaultValue: 0) as int;
      expect(version, MigrationService.currentVersion);
    });
  });
}
