import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/services/validation_service.dart';
import 'package:ethiograde/models/student.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';

void main() {
  const validator = ValidationService();

  // ── Helper factories ──────────────────────────────────────────────

  Student _student({
    String firstName = 'Abebe',
    String lastName = 'Kebede',
    int grade = 5,
  }) =>
      Student(
        id: 's1',
        firstName: firstName,
        lastName: lastName,
        grade: grade,
      );

  Question _mcq(int number, dynamic correctAnswer) => Question(
        number: number,
        type: QuestionType.mcq,
        correctAnswer: correctAnswer,
      );

  Question _tf(int number, dynamic correctAnswer) => Question(
        number: number,
        type: QuestionType.trueFalse,
        correctAnswer: correctAnswer,
      );

  Assessment _assessment({
    String title = 'Math Midterm',
    List<Question>? questions,
  }) =>
          Assessment(
            id: 'a1',
            title: title,
            subject: 'Math',
            questions: questions ?? [_mcq(1, 'A'), _mcq(2, 'B')],
          );

  ScanResult _scanResult({
    double totalScore = 8,
    double maxScore = 10,
    double confidence = 0.9,
    double percentage = 80,
    String assessmentId = 'a1',
    String studentId = 's1',
  }) =>
          ScanResult(
            assessmentId: assessmentId,
            studentId: studentId,
            studentName: 'Abebe Kebede',
            imagePath: '/tmp/test.jpg',
            totalScore: totalScore,
            maxScore: maxScore,
            confidence: confidence,
            percentage: percentage,
          );

  // ── Student validation ────────────────────────────────────────────

  group('Student validation', () {
    test('valid student passes', () {
      final result = validator.validateStudent(_student());
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('empty first name fails', () {
      final result = validator.validateStudent(_student(firstName: ''));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('empty'));
    });

    test('whitespace-only name fails', () {
      final result = validator.validateStudent(
        _student(firstName: '   ', lastName: '   '),
      );
      expect(result.isValid, isFalse);
    });

    test('200-char name fails', () {
      final long = 'A' * 200;
      final result = validator.validateStudent(_student(firstName: long));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('100'));
    });

    test('exactly 100-char name passes', () {
      final name = 'A' * 100;
      final result = validator.validateStudent(
        _student(firstName: name.substring(0, 50), lastName: name.substring(50)),
      );
      expect(result.isValid, isTrue);
    });

    test('grade 0 (University) passes', () {
      final result = validator.validateStudent(_student(grade: 0));
      expect(result.isValid, isTrue);
    });

    test('grade 12 passes', () {
      final result = validator.validateStudent(_student(grade: 12));
      expect(result.isValid, isTrue);
    });

    test('grade -1 fails', () {
      final result = validator.validateStudent(_student(grade: -1));
      expect(result.isValid, isFalse);
    });

    test('grade 13 fails', () {
      final result = validator.validateStudent(_student(grade: 13));
      expect(result.isValid, isFalse);
    });
  });

  // ── Assessment validation ─────────────────────────────────────────

  group('Assessment validation', () {
    test('valid assessment passes', () {
      final result = validator.validateAssessment(_assessment());
      expect(result.isValid, isTrue);
    });

    test('empty title fails', () {
      final result = validator.validateAssessment(_assessment(title: ''));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('title'));
    });

    test('whitespace-only title fails', () {
      final result = validator.validateAssessment(_assessment(title: '   '));
      expect(result.isValid, isFalse);
    });

    test('empty questions list fails', () {
      final result =
          validator.validateAssessment(_assessment(questions: []));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('at least one'));
    });

    test('valid MCQ answers pass', () {
      final a = _assessment(questions: [
        _mcq(1, 'A'),
        _mcq(2, 'B'),
        _mcq(3, 'E'),
      ]);
      expect(validator.validateAssessment(a).isValid, isTrue);
    });

    test('invalid MCQ answer "Z" fails', () {
      final a = _assessment(questions: [_mcq(1, 'Z')]);
      final result = validator.validateAssessment(a);
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('MCQ'));
    });

    test('valid True/False answers pass', () {
      final a = _assessment(questions: [
        _tf(1, 'True'),
        _tf(2, 'False'),
      ]);
      expect(validator.validateAssessment(a).isValid, isTrue);
    });

    test('lowercase true/false normalises and passes', () {
      final a = _assessment(questions: [
        _tf(1, 'true'),
        _tf(2, 'false'),
      ]);
      expect(validator.validateAssessment(a).isValid, isTrue);
    });

    test('invalid TF answer "Maybe" fails', () {
      final a = _assessment(questions: [_tf(1, 'Maybe')]);
      final result = validator.validateAssessment(a);
      expect(result.isValid, isFalse);
    });

    test('missing correct answer fails', () {
      final q = Question(number: 1, type: QuestionType.mcq);
      final a = _assessment(questions: [q]);
      final result = validator.validateAssessment(a);
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('missing'));
    });

    test('short answer with empty string fails', () {
      final q = Question(
        number: 1,
        type: QuestionType.shortAnswer,
        correctAnswer: '  ',
      );
      final a = _assessment(questions: [q]);
      final result = validator.validateAssessment(a);
      expect(result.isValid, isFalse);
    });

    test('mixed valid + invalid reports all errors', () {
      final a = _assessment(questions: [
        _mcq(1, 'A'),
        _mcq(2, 'INVALID'),
        _tf(3, 'True'),
        _tf(4, 'nope'),
      ]);
      final result = validator.validateAssessment(a);
      expect(result.isValid, isFalse);
      expect(result.errors.length, 2);
    });
  });

  // ── ScanResult validation ─────────────────────────────────────────

  group('ScanResult validation', () {
    test('valid scan result passes', () {
      final result = validator.validateScanResult(_scanResult());
      expect(result.isValid, isTrue);
    });

    test('negative score fails', () {
      final result = validator.validateScanResult(_scanResult(totalScore: -5));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('negative'));
    });

    test('score exceeding max fails', () {
      final result =
          validator.validateScanResult(_scanResult(totalScore: 15, maxScore: 10));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('exceeds'));
    });

    test('zero score is valid', () {
      final result = validator.validateScanResult(_scanResult(totalScore: 0));
      expect(result.isValid, isTrue);
    });

    test('score equals max is valid', () {
      final result =
          validator.validateScanResult(_scanResult(totalScore: 10, maxScore: 10));
      expect(result.isValid, isTrue);
    });

    test('confidence out of range fails', () {
      final result = validator.validateScanResult(_scanResult(confidence: 1.5));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('Confidence'));
    });

    test('negative confidence fails', () {
      final result = validator.validateScanResult(_scanResult(confidence: -0.1));
      expect(result.isValid, isFalse);
    });

    test('percentage over 100 fails', () {
      final result = validator.validateScanResult(_scanResult(percentage: 150));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('Percentage'));
    });

    test('empty assessment ID fails', () {
      final result =
          validator.validateScanResult(_scanResult(assessmentId: ''));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('Assessment ID'));
    });

    test('empty student ID fails', () {
      final result =
          validator.validateScanResult(_scanResult(studentId: ''));
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('Student ID'));
    });
  });
}
