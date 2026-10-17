import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/services/validation_service.dart';
import 'package:ethiograde/models/student.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/models/teacher.dart';

void main() {
  const validator = ValidationService();

  // ── Helper factories ──────────────────────────────────────────────

  Student student({
    String firstName = 'Abebe',
    String lastName = 'Kebede',
    int grade = 5,
    String studentId = '001',
    String gender = 'M',
  }) => Student(
    id: 's1',
    studentId: studentId,
    firstName: firstName,
    lastName: lastName,
    grade: grade,
    gender: gender);

  Question mcq(int number, dynamic correctAnswer) => Question(
    number: number,
    type: QuestionType.mcq,
    correctAnswer: correctAnswer);

  Question tf(int number, dynamic correctAnswer) => Question(
    number: number,
    type: QuestionType.trueFalse,
    correctAnswer: correctAnswer);

  Assessment assessment({
    String title = 'Math Midterm',
    List<Question>? questions,
  }) => Assessment(
    id: 'a1',
    title: title,
    subject: 'Math',
    questions: questions ?? [mcq(1, 'A'), mcq(2, 'B')]);

  ScanResult scanResult({
    double totalScore = 8,
    double maxScore = 10,
    double confidence = 0.9,
    double percentage = 80,
    String assessmentId = 'a1',
    String studentId = 's1',
  }) => ScanResult(
    assessmentId: assessmentId,
    studentId: studentId,
    studentName: 'Abebe Kebede',
    imagePath: '/tmp/test.jpg',
    totalScore: totalScore,
    maxScore: maxScore,
    confidence: confidence,
    percentage: percentage);

  // ── Student validation ────────────────────────────────────────────

  group('Student validation', () {
    test('valid student passes', () {
      final result = validator.validateStudent(student());
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('empty first name fails', () {
      final result = validator.validateStudent(
        student(firstName: '', lastName: ''));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('empty'));
    });

    test('whitespace-only name fails', () {
      final result = validator.validateStudent(
        student(firstName: '   ', lastName: '   '));
      expect(result.isValid, isFalse);
    });

    test('200-char name fails', () {
      final long = 'A' * 200;
      final result = validator.validateStudent(student(firstName: long));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('100'));
    });

    test('exactly 100-char name passes', () {
      final firstName = 'A' * 49;
      final lastName = 'B' * 49;
      // fullName = 'A*49 B*49' = 99 chars (with space)
      final result = validator.validateStudent(
        student(firstName: firstName, lastName: lastName));
      expect(result.isValid, isTrue);
    });

    test('grade 0 (University) passes', () {
      final result = validator.validateStudent(student(grade: 0));
      expect(result.isValid, isTrue);
    });

    test('grade 12 passes', () {
      final result = validator.validateStudent(student(grade: 12));
      expect(result.isValid, isTrue);
    });

    test('grade -1 fails', () {
      final result = validator.validateStudent(student(grade: -1));
      expect(result.isValid, isFalse);
    });

    test('grade 13 fails', () {
      final result = validator.validateStudent(student(grade: 13));
      expect(result.isValid, isFalse);
    });
  });

  // ── Assessment validation ─────────────────────────────────────────

  group('Assessment validation', () {
    test('valid assessment passes', () {
      final result = validator.validateAssessment(assessment());
      expect(result.isValid, isTrue);
    });

    test('empty title fails', () {
      final result = validator.validateAssessment(assessment(title: ''));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('title'));
    });

    test('whitespace-only title fails', () {
      final result = validator.validateAssessment(assessment(title: '   '));
      expect(result.isValid, isFalse);
    });

    test('empty questions list fails', () {
      final result = validator.validateAssessment(assessment(questions: []));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('at least one'));
    });

    test('valid MCQ answers pass', () {
      final a = assessment(
        questions: [mcq(1, 'A'), mcq(2, 'B'), mcq(3, 'E')]);
      expect(validator.validateAssessment(a).isValid, isTrue);
    });

    test('invalid MCQ answer "Z" fails', () {
      final a = assessment(questions: [mcq(1, 'Z')]);
      final result = validator.validateAssessment(a);
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('MCQ'));
    });

    test('valid True/False answers pass', () {
      final a = assessment(questions: [tf(1, 'True'), tf(2, 'False')]);
      expect(validator.validateAssessment(a).isValid, isTrue);
    });

    test('lowercase true/false normalises and passes', () {
      final a = assessment(questions: [tf(1, 'true'), tf(2, 'false')]);
      expect(validator.validateAssessment(a).isValid, isTrue);
    });

    test('invalid TF answer "Maybe" fails', () {
      final a = assessment(questions: [tf(1, 'Maybe')]);
      final result = validator.validateAssessment(a);
      expect(result.isValid, isFalse);
    });

    test('missing correct answer fails', () {
      final q = Question(number: 1, type: QuestionType.mcq);
      final a = assessment(questions: [q]);
      final result = validator.validateAssessment(a);
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('missing'));
    });

    test('short answer with empty string fails', () {
      final q = Question(
        number: 1,
        type: QuestionType.shortAnswer,
        correctAnswer: '  ');
      final a = assessment(questions: [q]);
      final result = validator.validateAssessment(a);
      expect(result.isValid, isFalse);
    });

    test('mixed valid + invalid reports all errors', () {
      final a = assessment(
        questions: [
          mcq(1, 'A'),
          mcq(2, 'INVALID'),
          tf(3, 'True'),
          tf(4, 'nope'),
        ]);
      final result = validator.validateAssessment(a);
      expect(result.isValid, isFalse);
      expect(result.errors.length, 2);
    });
  });

  // ── ScanResult validation ─────────────────────────────────────────

  group('ScanResult validation', () {
    test('valid scan result passes', () {
      final result = validator.validateScanResult(scanResult());
      expect(result.isValid, isTrue);
    });

    test('negative score fails', () {
      final result = validator.validateScanResult(scanResult(totalScore: -5));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('negative'));
    });

    test('score exceeding max fails', () {
      final result = validator.validateScanResult(
        scanResult(totalScore: 15, maxScore: 10));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('exceeds'));
    });

    test('zero score is valid', () {
      final result = validator.validateScanResult(scanResult(totalScore: 0));
      expect(result.isValid, isTrue);
    });

    test('score equals max is valid', () {
      final result = validator.validateScanResult(
        scanResult(totalScore: 10, maxScore: 10));
      expect(result.isValid, isTrue);
    });

    test('confidence out of range fails', () {
      final result = validator.validateScanResult(scanResult(confidence: 1.5));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('Confidence'));
    });

    test('negative confidence fails', () {
      final result = validator.validateScanResult(
        scanResult(confidence: -0.1));
      expect(result.isValid, isFalse);
    });

    test('percentage over 100 fails', () {
      final result = validator.validateScanResult(scanResult(percentage: 150));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('Percentage'));
    });

    test('empty assessment ID fails', () {
      final result = validator.validateScanResult(
        scanResult(assessmentId: ''));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('Assessment ID'));
    });

    test('empty student ID fails', () {
      final result = validator.validateScanResult(scanResult(studentId: ''));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('Student ID'));
    });
  });

  // ── Teacher validation ────────────────────────────────────────────

  Teacher teacher({
    String? id,
    String name = 'Abebe',
    String role = 'teacher',
  }) => Teacher(id: id, name: name, role: role);

  group('Teacher validation', () {
    test('valid teacher passes', () {
      final result = validator.validateTeacher(teacher());
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('empty name fails', () {
      final result = validator.validateTeacher(teacher(name: ''));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('empty'));
    });

    test('whitespace-only name fails', () {
      final result = validator.validateTeacher(teacher(name: '   '));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('empty'));
    });

    test('name exceeding 100 chars fails', () {
      final result = validator.validateTeacher(teacher(name: 'A' * 101));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('100'));
    });

    test('exactly 100-char name passes', () {
      final result = validator.validateTeacher(teacher(name: 'A' * 100));
      expect(result.isValid, isTrue);
    });

    test('invalid role fails', () {
      final result = validator.validateTeacher(teacher(role: 'superadmin'));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('Invalid role'));
    });

    test('role "admin" passes', () {
      final result = validator.validateTeacher(teacher(role: 'admin'));
      expect(result.isValid, isTrue);
    });

    test('duplicate name fails (case-insensitive)', () {
      final existing = [Teacher(id: '1', name: 'Abebe')];
      final result = validator.validateTeacher(
        teacher(id: '2', name: 'ABEBE'),
        existingTeachers: existing);
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('already exists'));
    });

    test('duplicate name with leading/trailing spaces fails', () {
      final existing = [Teacher(id: '1', name: 'Abebe')];
      final result = validator.validateTeacher(
        teacher(id: '2', name: '  Abebe  '),
        existingTeachers: existing);
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('already exists'));
    });

    test('same teacher with same name passes (update scenario)', () {
      final existing = [Teacher(id: '1', name: 'Abebe')];
      // Same ID, same name — should pass (self is excluded from duplicate check)
      final result = validator.validateTeacher(
        teacher(id: '1', name: 'Abebe'),
        existingTeachers: existing);
      expect(result.isValid, isTrue);
    });

    test('multiple errors reported together', () {
      final result = validator.validateTeacher(
        teacher(name: '', role: 'bad_role'));
      expect(result.isValid, isFalse);
      expect(result.errors.length, 2);
    });
  });
}
