import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/services/answer_key_fingerprint_service.dart';

void main() {
  final service = const AnswerKeyFingerprintService();

  Assessment _makeAssessment({
    List<Question>? questions,
    String rubricType = 'moe_national',
    String? weightedScaleId,
  }) {
    return Assessment(
      title: 'Test',
      subject: 'Math',
      questions: questions ??
          [
            Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
            Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: 'B', points: 1),
            Question(id: 'q3', number: 3, type: QuestionType.trueFalse, correctAnswer: 'True', points: 2),
          ],
      rubricType: rubricType,
      weightedScaleId: weightedScaleId,
    );
  }

  group('AnswerKeyFingerprintService', () {
    test('same scoring key gives same fingerprint', () {
      final a1 = _makeAssessment();
      final a2 = _makeAssessment();
      expect(service.compute(a1), equals(service.compute(a2)));
    });

    test('different correctAnswer gives different fingerprint', () {
      final a1 = _makeAssessment();
      final a2 = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
        Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: 'C', points: 1), // changed
        Question(id: 'q3', number: 3, type: QuestionType.trueFalse, correctAnswer: 'True', points: 2),
      ]);
      expect(service.compute(a1), isNot(equals(service.compute(a2))));
    });

    test('different question order gives different fingerprint', () {
      final a1 = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
        Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: 'B', points: 1),
      ]);
      final a2 = _makeAssessment(questions: [
        Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: 'B', points: 1),
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
      ]);
      expect(service.compute(a1), isNot(equals(service.compute(a2))));
    });

    test('different rubricType gives different fingerprint', () {
      final a1 = _makeAssessment(rubricType: 'moe_national');
      final a2 = _makeAssessment(rubricType: 'university');
      expect(service.compute(a1), isNot(equals(service.compute(a2))));
    });

    test('different points gives different fingerprint', () {
      final a1 = _makeAssessment();
      final a2 = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
        Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: 'B', points: 2), // changed
        Question(id: 'q3', number: 3, type: QuestionType.trueFalse, correctAnswer: 'True', points: 2),
      ]);
      expect(service.compute(a1), isNot(equals(service.compute(a2))));
    });

    test('presentation-only text changes do not change fingerprint', () {
      final a1 = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1, text: 'What is 2+2?'),
      ]);
      final a2 = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1, text: 'Calculate 2+2'),
      ]);
      expect(service.compute(a1), equals(service.compute(a2)));
    });

    test('empty questions gives empty string', () {
      final a = _makeAssessment(questions: []);
      expect(service.compute(a), equals(''));
    });

    test('MCQ case normalization in canonical form', () {
      // correctAnswer 'a' and 'A' should produce same fingerprint
      final a1 = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'a', points: 1),
      ]);
      final a2 = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
      ]);
      // These should be the same because canonical form normalizes via toString()
      expect(service.compute(a1), equals(service.compute(a2)));
    });

    test('matching answer canonical form', () {
      final a1 = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.matching, correctAnswer: 'MATCH:A-B-C', points: 3),
      ]);
      final a2 = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.matching, correctAnswer: 'MATCH:A-B-C', points: 3),
      ]);
      expect(service.compute(a1), equals(service.compute(a2)));
    });

    test('short answer list ordering does not affect fingerprint', () {
      // Lists are sorted alphabetically in canonical form
      final a1 = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.shortAnswer, correctAnswer: ['B', 'A'], points: 1),
      ]);
      final a2 = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.shortAnswer, correctAnswer: ['A', 'B'], points: 1),
      ]);
      expect(service.compute(a1), equals(service.compute(a2)));
    });

    test('different weighted scale gives different fingerprint', () {
      final a1 = _makeAssessment(weightedScaleId: 'scale1');
      final a2 = _makeAssessment(weightedScaleId: 'scale2');
      expect(service.compute(a1), isNot(equals(service.compute(a2))));
    });

    test('fingerprint is deterministic across calls', () {
      final a = _makeAssessment();
      final fp1 = service.compute(a);
      final fp2 = service.compute(a);
      final fp3 = service.compute(a);
      expect(fp1, equals(fp2));
      expect(fp2, equals(fp3));
    });

    test('fingerprint is a 64-char hex string', () {
      final fp = service.compute(_makeAssessment());
      expect(fp.length, equals(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(fp), isTrue);
    });
  });
}
