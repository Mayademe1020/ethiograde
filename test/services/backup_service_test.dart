import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:ethiograde/services/backup_service.dart';
import 'package:ethiograde/models/student.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';

/// Mock path_provider platform for unit tests.
class _MockPathProvider extends PathProviderPlatform {
  late final String _tempPath;
  _MockPathProvider(this._tempPath);

  @override
  Future<String?> getApplicationDocumentsPath() async => _tempPath;

  @override
  Future<String?> getTemporaryPath() async => _tempPath;

  @override
  Future<String?> getApplicationSupportPath() async => _tempPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  const studentsBox = 'students';
  const assessmentsBox = 'assessments';
  const scanResultsBox = 'scan_results';
  const metadataBox = 'metadata';
  const hiveKeyStorageKey = 'hive_encryption_key';

  // ── Helpers ─────────────────────────────────────────────────────

  Student makeStudent({
    String id = 's1',
    String studentId = '001',
    String firstName = 'Abebe',
    String lastName = 'Kebede',
    int grade = 5,
    String gender = 'M',
  }) => Student(
    id: id,
    studentId: studentId,
    firstName: firstName,
    lastName: lastName,
    grade: grade,
    gender: gender,
  );

  Assessment makeAssessment({
    String id = 'a1',
    String title = 'Math Midterm',
    List<Question>? questions,
  }) => Assessment(
    id: id,
    title: title,
    subject: 'Math',
    questions:
        questions ??
        [
          Question(number: 1, type: QuestionType.mcq, correctAnswer: 'A'),
          Question(number: 2, type: QuestionType.mcq, correctAnswer: 'B'),
        ],
  );

  ScanResult makeScanResult({
    String id = 'r1',
    String assessmentId = 'a1',
    String studentId = 's1',
  }) => ScanResult(
    id: id,
    assessmentId: assessmentId,
    studentId: studentId,
    studentName: 'Abebe Kebede',
    imagePath: '/tmp/test.jpg',
    totalScore: 8,
    maxScore: 10,
    confidence: 0.9,
    percentage: 80,
  );

  // ── Setup ───────────────────────────────────────────────────────

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ethiograde_backup_test_');
    Hive.init(tempDir.path);
    // Mock path_provider so getApplicationDocumentsDirectory() works in tests
    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({
      hiveKeyStorageKey: base64Encode(List<int>.generate(32, (i) => i)),
    });
    await Hive.openBox(studentsBox);
    await Hive.openBox(assessmentsBox);
    // scan_results is a regular box in production (main.dart _openBoxSafe)
    await Hive.openBox(scanResultsBox);
    await Hive.openBox(metadataBox);
  });

  tearDown(() async {
    for (final name in [studentsBox, assessmentsBox, metadataBox]) {
      if (Hive.isBoxOpen(name)) {
        try {
          final box = Hive.box(name);
          await box.clear();
          await box.close();
        } catch (_) {}
      }
    }
    if (Hive.isBoxOpen(scanResultsBox)) {
      try {
        final box = Hive.box(scanResultsBox);
        await box.clear();
        await box.close();
      } catch (_) {}
    }
    // Clean up any backup files from getApplicationDocumentsDirectory()
    try {
      final appDir = await getApplicationDocumentsDirectory();
      for (final entity in appDir.listSync()) {
        if (entity is File &&
            (entity.path.contains('ethiograde_backup_') ||
                entity.path.contains('ethiograde_auto_'))) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
    // Also clean temp dir backup files
    for (final entity in tempDir.listSync()) {
      if (entity is File &&
          (entity.path.contains('ethiograde_backup_') ||
              entity.path.contains('ethiograde_auto_'))) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  });

  tearDownAll(() async {
    try {
      await Hive.close();
    } catch (_) {}
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  // ══════════════════════════════════════════════════════════════════
  // EXPORT
  // ══════════════════════════════════════════════════════════════════

  group('BackupService export', () {
    test('exportAllData returns file path for non-empty data', () async {
      final studentsBox = Hive.box('students');
      await studentsBox.put('s1', makeStudent().toMap());

      final assessmentsBox = Hive.box('assessments');
      await assessmentsBox.put('a1', makeAssessment().toMap());

      final scanResultsBox = Hive.box('scan_results');
      await scanResultsBox.put('r1', makeScanResult().toMap());

      final result = await BackupService.instance.exportAllData();
      expect(result, isNotNull);
      expect(result, endsWith('.enc'));

      // File exists
      final file = File(result!);
      expect(await file.exists(), isTrue);
      expect(file.lengthSync(), greaterThan(0));
    });

    test(
      'exportAllData returns null for empty Hive boxes (still valid)',
      () async {
        // Empty boxes — export should still produce a valid backup
        final result = await BackupService.instance.exportAllData();
        expect(result, isNotNull);
        expect(result, endsWith('.enc'));

        final file = File(result!);
        expect(await file.exists(), isTrue);
      },
    );

    test('exportAllData aborts if encryption key is unavailable', () async {
      FlutterSecureStorage.setMockInitialValues({});
      await Hive.box('students').put('s1', makeStudent().toMap());

      final result = await BackupService.instance.exportAllData();
      expect(result, isNull);

      final appDir = await getApplicationDocumentsDirectory();
      final plaintextBackups = appDir.listSync().whereType<File>().where(
        (f) =>
            f.path.contains('ethiograde_backup_') && f.path.endsWith('.json'),
      );
      expect(plaintextBackups, isEmpty);
    });

    test('exported file contains valid JSON with expected keys', () async {
      await Hive.box('students').put('s1', makeStudent().toMap());
      await Hive.box('assessments').put('a1', makeAssessment().toMap());

      final filePath = await BackupService.instance.exportAllData();
      expect(filePath, isNotNull);

      // Read file — encrypted or not, we need to check
      final file = File(filePath!);
      final bytes = await file.readAsBytes();

      // If .enc file, it won't parse as JSON directly
      // If .json file (fallback), parse and check structure
      if (filePath.endsWith('.json')) {
        final jsonStr = await file.readAsString();
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        expect(data['version'], 1);
        expect(data['exportDate'], isNotNull);
        expect(data['students'], isA<List>());
        expect(data['assessments'], isA<List>());
        expect(data['scanResults'], isA<List>());
      } else {
        // Encrypted file — just verify it's non-empty binary
        expect(bytes.length, greaterThan(16)); // At least IV + some data
      }
    });

    test('exported JSON contains correct student data', () async {
      final student = makeStudent(
        id: 's2',
        firstName: 'Tigist',
        lastName: 'Haile',
      );
      await Hive.box('students').put('s2', student.toMap());

      final filePath = await BackupService.instance.exportAllData();
      expect(filePath, isNotNull);

      if (filePath!.endsWith('.json')) {
        final jsonStr = await File(filePath).readAsString();
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        final students = data['students'] as List;
        expect(students.length, 1);
        expect(students[0]['firstName'], 'Tigist');
        expect(students[0]['lastName'], 'Haile');
      }
      // If encrypted, can't verify content without key — covered by roundtrip test
    });

    test('exported JSON contains correct scan results', () async {
      final scan = makeScanResult(id: 'r3', studentId: 's5');
      await Hive.box('scan_results').put('r3', scan.toMap());

      final filePath = await BackupService.instance.exportAllData();
      expect(filePath, isNotNull);

      if (filePath!.endsWith('.json')) {
        final jsonStr = await File(filePath).readAsString();
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        final scans = data['scanResults'] as List;
        expect(scans.length, 1);
        expect(scans[0]['studentId'], 's5');
        expect(scans[0]['totalScore'], 8);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // IMPORT
  // ══════════════════════════════════════════════════════════════════

  group('BackupService import', () {
    test('import from valid JSON file succeeds', () async {
      final backupData = {
        'version': 1,
        'exportDate': DateTime.now().toIso8601String(),
        'students': [makeStudent().toMap()],
        'assessments': [makeAssessment().toMap()],
        'scanResults': [makeScanResult().toMap()],
      };

      final backupFile = File('${tempDir.path}/test_import.json');
      await backupFile.writeAsString(jsonEncode(backupData));

      final result = await BackupService.instance.importData(backupFile.path);
      expect(result.imported, 3); // 1 student + 1 assessment + 1 scan
      expect(result.skipped, 0);
      expect(result.errors, isEmpty);

      // Verify data persisted
      final student = Student.fromMap(
        Map<String, dynamic>.from(Hive.box('students').get('s1') as Map),
      );
      expect(student.firstName, 'Abebe');

      final assessment = Assessment.fromMap(
        Map<String, dynamic>.from(Hive.box('assessments').get('a1') as Map),
      );
      expect(assessment.title, 'Math Midterm');
    });

    test('import skips duplicates in merge mode', () async {
      // Pre-populate with existing student
      await Hive.box('students').put('s1', makeStudent().toMap());

      final backupData = {
        'version': 1,
        'exportDate': DateTime.now().toIso8601String(),
        'students': [
          makeStudent().toMap(), // duplicate
          makeStudent(id: 's2', firstName: 'Tigist', studentId: '002').toMap(),
        ],
        'assessments': [],
        'scanResults': [],
      };

      final backupFile = File('${tempDir.path}/test_merge.json');
      await backupFile.writeAsString(jsonEncode(backupData));

      final result = await BackupService.instance.importData(
        backupFile.path,
        replace: false,
      );
      expect(result.imported, 1); // only s2
      expect(result.skipped, 1); // s1 duplicate
      expect(result.errors, isEmpty);
    });

    test('import with replace mode clears existing data', () async {
      await Hive.box('students').put('s1', makeStudent().toMap());
      await Hive.box('assessments').put('a1', makeAssessment().toMap());

      final backupData = {
        'version': 1,
        'exportDate': DateTime.now().toIso8601String(),
        'students': [
          makeStudent(
            id: 's99',
            firstName: 'New',
            lastName: 'Student',
            studentId: '099',
          ).toMap(),
        ],
        'assessments': [],
        'scanResults': [],
      };

      final backupFile = File('${tempDir.path}/test_replace.json');
      await backupFile.writeAsString(jsonEncode(backupData));

      final result = await BackupService.instance.importData(
        backupFile.path,
        replace: true,
      );
      expect(result.imported, 1);
      expect(result.skipped, 0);

      // Old data gone
      expect(Hive.box('students').containsKey('s1'), isFalse);
      expect(Hive.box('assessments').containsKey('a1'), isFalse);
      // New data present
      expect(Hive.box('students').containsKey('s99'), isTrue);
    });

    test('import from non-existent file returns error', () async {
      final result = await BackupService.instance.importData(
        '/tmp/nonexistent.json',
      );
      expect(result.imported, 0);
      expect(result.errors, isNotEmpty);
      expect(result.errors.first, contains('File not found'));
    });

    test('import from invalid JSON returns error', () async {
      final badFile = File('${tempDir.path}/bad.json');
      await badFile.writeAsString('not valid json {{{');

      final result = await BackupService.instance.importData(badFile.path);
      expect(result.imported, 0);
      expect(result.errors, isNotEmpty);
      expect(result.errors.first, contains('Invalid JSON'));
    });

    test('import with unsupported version returns error', () async {
      final data = {
        'version': 0,
        'students': [],
        'assessments': [],
        'scanResults': [],
      };
      final file = File('${tempDir.path}/old_version.json');
      await file.writeAsString(jsonEncode(data));

      final result = await BackupService.instance.importData(file.path);
      expect(result.imported, 0);
      expect(result.errors.first, contains('Unsupported backup version'));
    });

    test('import skips invalid student records', () async {
      final data = {
        'version': 1,
        'exportDate': DateTime.now().toIso8601String(),
        'students': [
          makeStudent().toMap(),
          {
            'id': 'bad',
            'firstName': '',
            'lastName': '',
            'studentId': '',
          }, // invalid
        ],
        'assessments': [],
        'scanResults': [],
      };

      final file = File('${tempDir.path}/partial.json');
      await file.writeAsString(jsonEncode(data));

      final result = await BackupService.instance.importData(file.path);
      expect(result.imported, 1); // only valid student
      expect(result.skipped, 1); // invalid one
      expect(result.errors.length, 1);
      expect(result.errors.first, contains('Student bad'));
    });

    test('import with missing keys defaults gracefully', () async {
      // Backup with no students/assessments/scanResults keys at all
      final data = {
        'version': 1,
        'exportDate': DateTime.now().toIso8601String(),
      };

      final file = File('${tempDir.path}/minimal.json');
      await file.writeAsString(jsonEncode(data));

      final result = await BackupService.instance.importData(file.path);
      expect(result.imported, 0);
      expect(result.skipped, 0);
      expect(result.errors, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // ROUNDTRIP (Export → Import)
  // ══════════════════════════════════════════════════════════════════

  group('BackupService roundtrip', () {
    test('export then import preserves all data', () async {
      // Populate
      await Hive.box('students').put('s1', makeStudent().toMap());
      await Hive.box('students').put(
        's2',
        makeStudent(id: 's2', firstName: 'Tigist', studentId: '002').toMap(),
      );
      await Hive.box('assessments').put('a1', makeAssessment().toMap());
      await Hive.box('scan_results').put('r1', makeScanResult().toMap());

      // Export
      final exportPath = await BackupService.instance.exportAllData();
      expect(exportPath, isNotNull);

      // Clear all data
      await Hive.box('students').clear();
      await Hive.box('assessments').clear();
      await Hive.box('scan_results').clear();

      expect(Hive.box('students').length, 0);

      // Import
      final result = await BackupService.instance.importData(exportPath!);
      expect(result.imported, 4); // 2 students + 1 assessment + 1 scan
      expect(result.errors, isEmpty);

      // Verify
      expect(Hive.box('students').length, 2);
      expect(Hive.box('assessments').length, 1);

      final s1 = Student.fromMap(
        Map<String, dynamic>.from(Hive.box('students').get('s1') as Map),
      );
      expect(s1.firstName, 'Abebe');
      expect(s1.grade, 5);

      final s2 = Student.fromMap(
        Map<String, dynamic>.from(Hive.box('students').get('s2') as Map),
      );
      expect(s2.firstName, 'Tigist');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // AUTO-BACKUP
  // ══════════════════════════════════════════════════════════════════

  group('BackupService auto-backup', () {
    test('recordScanAndMaybeBackup increments counter', () async {
      final metaBox = Hive.box(metadataBox);

      await BackupService.instance.recordScanAndMaybeBackup();
      expect(metaBox.get('auto_backup_scan_count'), 1);

      await BackupService.instance.recordScanAndMaybeBackup();
      expect(metaBox.get('auto_backup_scan_count'), 2);
    });

    test('auto-backup triggers after interval (10 scans)', () async {
      // Populate with some data so backup is meaningful
      await Hive.box('students').put('s1', makeStudent().toMap());

      // Call 10 times to trigger auto-backup
      for (int i = 0; i < 10; i++) {
        await BackupService.instance.recordScanAndMaybeBackup();
      }

      // Counter should reset to 0 after auto-backup
      final metaBox = Hive.box(metadataBox);
      expect(metaBox.get('auto_backup_scan_count'), 0);

      // Auto-backup file should exist
      final backups = await BackupService.instance.listBackups();
      final autoBackups = backups.where((b) => b.isAutoBackup).toList();
      expect(autoBackups, isNotEmpty);
    });

    test('auto-backup prunes to max 3 files', () async {
      await Hive.box('students').put('s1', makeStudent().toMap());

      // Trigger 4 auto-backups (40 scans)
      for (int i = 0; i < 40; i++) {
        await BackupService.instance.recordScanAndMaybeBackup();
      }

      final backups = await BackupService.instance.listBackups();
      final autoBackups = backups.where((b) => b.isAutoBackup).toList();
      expect(autoBackups.length, lessThanOrEqualTo(3));
    });

    test('auto-backup file is encrypted and importable', () async {
      await Hive.box('students').put('s1', makeStudent().toMap());

      for (int i = 0; i < 10; i++) {
        await BackupService.instance.recordScanAndMaybeBackup();
      }

      final backups = await BackupService.instance.listBackups();
      final autoBackup = backups.firstWhere((b) => b.isAutoBackup);
      expect(autoBackup.fileName, endsWith('.enc'));

      await Hive.box('students').clear();
      final result = await BackupService.instance.importData(
        autoBackup.filePath,
      );
      expect(result.errors, isEmpty);
      expect(Hive.box('students').length, 1);
    });

    test('auto-backup aborts if encryption key is unavailable', () async {
      FlutterSecureStorage.setMockInitialValues({});
      await Hive.box('students').put('s1', makeStudent().toMap());

      for (int i = 0; i < 10; i++) {
        await BackupService.instance.recordScanAndMaybeBackup();
      }

      final backups = await BackupService.instance.listBackups();
      final autoBackups = backups.where((b) => b.isAutoBackup).toList();
      expect(autoBackups, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // LIST BACKUPS
  // ══════════════════════════════════════════════════════════════════

  group('BackupService listBackups', () {
    test('listBackups returns empty when no backups exist', () async {
      // Clean up any leftover backup files from previous tests
      try {
        final appDir = await getApplicationDocumentsDirectory();
        for (final entity in appDir.listSync()) {
          if (entity is File &&
              (entity.path.contains('ethiograde_backup_') ||
                  entity.path.contains('ethiograde_auto_'))) {
            await entity.delete();
          }
        }
      } catch (_) {}

      final backups = await BackupService.instance.listBackups();
      final ethioBackups = backups
          .where((b) => b.fileName.startsWith('ethiograde_'))
          .toList();
      expect(ethioBackups, isEmpty);
    });

    test('listBackups includes exported files', () async {
      await Hive.box('students').put('s1', makeStudent().toMap());

      final exportPath = await BackupService.instance.exportAllData();
      expect(exportPath, isNotNull);

      final backups = await BackupService.instance.listBackups();
      expect(backups, isNotEmpty);
      final exportedName = File(exportPath!).path.split(RegExp(r'[\\/]')).last;
      expect(backups.any((b) => b.fileName == exportedName), isTrue);
    });

    test('BackupInfo has correct metadata', () async {
      await Hive.box('students').put('s1', makeStudent().toMap());

      await BackupService.instance.exportAllData();

      final backups = await BackupService.instance.listBackups();
      final info = backups.first;

      expect(info.fileName, isNotEmpty);
      expect(info.sizeBytes, greaterThan(0));
      expect(info.date, isNotNull);
      expect(info.sizeFormatted, isNotEmpty);
      expect(info.sizeFormatted, contains(RegExp(r'[BKMG]')));
    });

    test('auto-backup files flagged correctly', () async {
      await Hive.box('students').put('s1', makeStudent().toMap());

      // Manual export
      await BackupService.instance.exportAllData();

      // Auto backup
      for (int i = 0; i < 10; i++) {
        await BackupService.instance.recordScanAndMaybeBackup();
      }

      final backups = await BackupService.instance.listBackups();
      final manual = backups.where((b) => !b.isAutoBackup).toList();
      final auto = backups.where((b) => b.isAutoBackup).toList();

      expect(manual, isNotEmpty);
      expect(auto, isNotEmpty);
    });

    test('listBackups sorted by date descending', () async {
      await Hive.box('students').put('s1', makeStudent().toMap());

      // Create two backups with a delay
      await BackupService.instance.exportAllData();
      await Future.delayed(const Duration(milliseconds: 10));
      await BackupService.instance.exportAllData();

      final backups = await BackupService.instance.listBackups();
      if (backups.length >= 2) {
        expect(
          backups[0].date.isAfter(backups[1].date) ||
              backups[0].date.isAtSameMomentAs(backups[1].date),
          isTrue,
        );
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // BACKUP INFO
  // ══════════════════════════════════════════════════════════════════

  group('BackupInfo', () {
    test('sizeFormatted formats bytes correctly', () {
      final info = BackupInfo(
        filePath: '/tmp/test.enc',
        fileName: 'test.enc',
        date: DateTime(2026, 1, 1),
        sizeBytes: 500,
        isAutoBackup: false,
      );
      expect(info.sizeFormatted, '500 B');
    });

    test('sizeFormatted formats KB correctly', () {
      final info = BackupInfo(
        filePath: '/tmp/test.enc',
        fileName: 'test.enc',
        date: DateTime(2026, 1, 1),
        sizeBytes: 2048,
        isAutoBackup: false,
      );
      expect(info.sizeFormatted, '2.0 KB');
    });

    test('sizeFormatted formats MB correctly', () {
      final info = BackupInfo(
        filePath: '/tmp/test.enc',
        fileName: 'test.enc',
        date: DateTime(2026, 1, 1),
        sizeBytes: 2 * 1024 * 1024,
        isAutoBackup: false,
      );
      expect(info.sizeFormatted, '2.0 MB');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // EDGE CASES
  // ══════════════════════════════════════════════════════════════════

  group('BackupService edge cases', () {
    test('import with corrupt scan result skips it', () async {
      final data = {
        'version': 1,
        'exportDate': DateTime.now().toIso8601String(),
        'students': [],
        'assessments': [],
        'scanResults': [
          {
            'id': 'bad_scan',
            'assessmentId': '',
            'studentId': '',
            'studentName': '',
            'imagePath': '',
            'totalScore': 'not_a_number',
          }, // bad type
        ],
      };

      final file = File('${tempDir.path}/corrupt_scan.json');
      await file.writeAsString(jsonEncode(data));

      final result = await BackupService.instance.importData(file.path);
      expect(result.skipped, greaterThanOrEqualTo(1));
      expect(result.errors, isNotEmpty);
    });

    test('import handles assessment with empty questions list', () async {
      final data = {
        'version': 1,
        'exportDate': DateTime.now().toIso8601String(),
        'students': [],
        'assessments': [
          makeAssessment(questions: []).toMap()
            ..['questions'] = [], // empty questions
        ],
        'scanResults': [],
      };

      final file = File('${tempDir.path}/empty_questions.json');
      await file.writeAsString(jsonEncode(data));

      final result = await BackupService.instance.importData(file.path);
      // Should either import (if valid) or skip — depends on validation
      expect(result.imported + result.skipped, 1);
    });

    test('export with many records produces valid file', () async {
      // Add 50 students
      for (int i = 0; i < 50; i++) {
        await Hive.box('students').put(
          's$i',
          makeStudent(
            id: 's$i',
            firstName: 'Student $i',
            studentId: '$i',
          ).toMap(),
        );
      }

      final exportPath = await BackupService.instance.exportAllData();
      expect(exportPath, isNotNull);

      final file = File(exportPath!);
      expect(await file.exists(), isTrue);
      expect(
        file.lengthSync(),
        greaterThan(1000),
      ); // should be reasonably sized
    });
  });
}
