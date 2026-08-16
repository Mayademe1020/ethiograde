import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/student.dart';
import 'package:ethiograde/services/excel_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Student model — serialization', () {
    test('creates Student from data', () {
      final student = Student(
        id: 'test-id',
        firstName: 'Abebe',
        lastName: 'Kebede',
        className: '10A',
        section: 'A',
        studentId: '1001',
      );

      expect(student.firstName, 'Abebe');
      expect(student.lastName, 'Kebede');
      expect(student.className, '10A');
      expect(student.fullName, 'Abebe Kebede');
    });

    test('Student toMap/fromMap round-trip', () {
      final original = Student(
        id: 'test-id',
        studentId: '001',
        firstName: 'Abebe',
        lastName: 'Kebede',
        className: '10A',
      );

      final map = original.toMap();
      final restored = Student.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.firstName, original.firstName);
      expect(restored.lastName, original.lastName);
      expect(restored.className, original.className);
    });
  });

  group('ImportService — CSV export', () {
    late ImportService service;

    setUp(() {
      service = ImportService();
    });

    test('exportStudents creates valid CSV file', () async {
      final students = [
        Student(
          id: 's1',
          studentId: '001',
          firstName: 'Abebe',
          lastName: 'Kebede',
          className: '10A',
        ),
        Student(
          id: 's2',
          studentId: '002',
          firstName: 'Bekele',
          lastName: 'Tesfaye',
          className: '10A',
        ),
      ];

      final path = await service.exportStudents(
        students,
        outputDir: Directory.systemTemp.path,
      );
      final file = File(path);
      expect(await file.exists(), isTrue);

      final content = await file.readAsString();
      final lines = content
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();

      // Header + 2 data rows
      expect(lines.length, 3);
      expect(lines[0], contains('FirstName'));
      expect(lines[1], contains('Abebe'));
      expect(lines[2], contains('Bekele'));

      await file.delete();
    });

    test('exportResults creates valid CSV file', () async {
      final results = [
        {
          'studentName': 'Abebe',
          'studentId': '001',
          'totalScore': 45,
          'maxScore': 50,
          'percentage': 90.0,
          'grade': 'A',
          'paperLabel': 'Paper 1',
          'confidence': 0.95,
          'reviewStatus': 'Reviewed',
          'answers': [
            {'questionNumber': 1, 'score': 1.0, 'maxScore': 1.0},
            {'questionNumber': 2, 'score': 0.0, 'maxScore': 1.0},
          ],
        },
        {
          'studentName': 'Bekele',
          'studentId': '002',
          'totalScore': 20,
          'maxScore': 50,
          'percentage': 40.0,
          'grade': 'F',
          'paperLabel': 'Paper 2',
          'confidence': 0.55,
          'reviewStatus': 'Needs review',
          'answers': [
            {'questionNumber': 1, 'score': 0.0, 'maxScore': 1.0},
            {'questionNumber': 2, 'score': 0.0, 'maxScore': 1.0},
          ],
        },
      ];

      final path = await service.exportResults(
        assessmentTitle: 'Math Final',
        results: results,
        outputDir: Directory.systemTemp.path,
      );
      final file = File(path);
      expect(await file.exists(), isTrue);

      final content = await file.readAsString();
      final lines = content
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();

      expect(lines.length, 3);
      expect(lines[0], contains('StudentName'));
      expect(lines[0], contains('PaperLabel'));
      expect(lines[0], contains('ReviewStatus'));
      expect(lines[0], contains('Confidence'));
      expect(lines[0], contains('Q1'));
      expect(lines[0], contains('Q2'));
      expect(lines[1], contains('PASS'));
      expect(lines[1], contains('Reviewed'));
      expect(lines[1], contains('Paper 1'));
      expect(lines[1], contains('1/1'));
      expect(lines[1], contains('0/1'));
      expect(lines[2], contains('FAIL'));
      expect(lines[2], contains('Needs review'));

      await file.delete();
    });

    test('CSV escapes commas in names', () async {
      final students = [
        Student(
          id: 's1',
          studentId: '001',
          firstName: 'Abebe, Jr.',
          lastName: 'Kebede',
          className: '10A',
        ),
      ];

      final path = await service.exportStudents(
        students,
        outputDir: Directory.systemTemp.path,
      );
      final file = File(path);
      final content = await file.readAsString();

      // "Abebe, Jr." should be quoted
      expect(content, contains('"Abebe, Jr."'));

      await file.delete();
    });

    test('CSV handles content', () async {
      final students = [
        Student(
          id: 's1',
          studentId: '001',
          firstName: 'አበበ',
          lastName: 'ከበደ',
          className: '10ሀ',
        ),
      ];

      final path = await service.exportStudents(
        students,
        outputDir: Directory.systemTemp.path,
      );
      final file = File(path);
      final content = await file.readAsString();

      expect(content, contains('አበበ'));
      expect(content, contains('ከበደ'));

      await file.delete();
    });

    test('CSV handles empty students list', () async {
      final path = await service.exportStudents(
        [],
        outputDir: Directory.systemTemp.path,
      );
      final file = File(path);
      final content = await file.readAsString();
      final lines = content
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();

      // Only header
      expect(lines.length, 1);

      await file.delete();
    });

    test('exportResults filename includes assessment title', () async {
      final path = await service.exportResults(
        assessmentTitle: 'Math Final Exam',
        results: [
          {'studentName': 'Abebe', 'percentage': 80.0},
        ],
        outputDir: Directory.systemTemp.path,
      );

      expect(path, contains('Math_Final_Exam'));

      await File(path).delete();
    });
  });
}
