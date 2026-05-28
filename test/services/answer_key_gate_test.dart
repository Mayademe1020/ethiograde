import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/assessment.dart';

void main() {
  group('Assessment — answer key completeness', () {
    test('answeredQuestionCount counts non-null answers', () {
      final a = Assessment(
        id: 'test',
        title: 'Test',
        subject: 'Math',
        questions: [
          const Question(number: 1, type: QuestionType.mcq, correctAnswer: 'A'),
          const Question(number: 2, type: QuestionType.mcq, correctAnswer: 'B'),
          const Question(number: 3, type: QuestionType.mcq, correctAnswer: null),
        ]);
      expect(a.answeredQuestionCount, 2);
    });

    test('answeredQuestionCount ignores empty strings', () {
      final a = Assessment(
        id: 'test',
        title: 'Test',
        subject: 'Math',
        questions: [
          const Question(number: 1, type: QuestionType.mcq, correctAnswer: 'A'),
          const Question(number: 2, type: QuestionType.mcq, correctAnswer: ''),
        ]);
      expect(a.answeredQuestionCount, 1);
    });

    test('answeredQuestionCount is 0 for empty questions', () {
      final a = Assessment(id: 'test', title: 'Test', subject: 'Math');
      expect(a.answeredQuestionCount, 0);
    });

    test('answerKeyCompleteness returns ratio', () {
      final a = Assessment(
        id: 'test',
        title: 'Test',
        subject: 'Math',
        questions: [
          const Question(number: 1, type: QuestionType.mcq, correctAnswer: 'A'),
          const Question(number: 2, type: QuestionType.mcq, correctAnswer: 'B'),
          const Question(number: 3, type: QuestionType.mcq, correctAnswer: null),
          const Question(number: 4, type: QuestionType.mcq, correctAnswer: ''),
        ]);
      expect(a.answerKeyCompleteness, 0.5);
    });

    test('answerKeyCompleteness is 0 for empty questions', () {
      final a = Assessment(id: 'test', title: 'Test', subject: 'Math');
      expect(a.answerKeyCompleteness, 0.0);
    });

    test('isAnswerKeyComplete is true when all set', () {
      final a = Assessment(
        id: 'test',
        title: 'Test',
        subject: 'Math',
        questions: [
          const Question(number: 1, type: QuestionType.mcq, correctAnswer: 'A'),
          const Question(number: 2, type: QuestionType.trueFalse, correctAnswer: 'True'),
        ]);
      expect(a.isAnswerKeyComplete, isTrue);
    });

    test('isAnswerKeyComplete is false when some missing', () {
      final a = Assessment(
        id: 'test',
        title: 'Test',
        subject: 'Math',
        questions: [
          const Question(number: 1, type: QuestionType.mcq, correctAnswer: 'A'),
          const Question(number: 2, type: QuestionType.mcq, correctAnswer: null),
        ]);
      expect(a.isAnswerKeyComplete, isFalse);
    });

    test('isAnswerKeyComplete is false for empty questions', () {
      final a = Assessment(id: 'test', title: 'Test', subject: 'Math');
      expect(a.isAnswerKeyComplete, isFalse);
    });

    test('answerKeyStatus returns progress string', () {
      final a = Assessment(
        id: 'test',
        title: 'Test',
        subject: 'Math',
        questions: [
          const Question(number: 1, type: QuestionType.mcq, correctAnswer: 'A'),
          const Question(number: 2, type: QuestionType.mcq, correctAnswer: null),
          const Question(number: 3, type: QuestionType.mcq, correctAnswer: 'C'),
        ]);
      expect(a.answerKeyStatus, '2/3 answers set');
    });

    test('True/False answers count correctly', () {
      final a = Assessment(
        id: 'test',
        title: 'Test',
        subject: 'Science',
        questions: [
          const Question(number: 1, type: QuestionType.trueFalse, correctAnswer: 'True'),
          const Question(number: 2, type: QuestionType.trueFalse, correctAnswer: 'False'),
          const Question(number: 3, type: QuestionType.trueFalse, correctAnswer: null),
        ]);
      expect(a.answeredQuestionCount, 2);
      expect(a.isAnswerKeyComplete, isFalse);
    });

    test('mixed type answers count correctly', () {
      final a = Assessment(
        id: 'test',
        title: 'Test',
        subject: 'Mixed',
        questions: [
          const Question(number: 1, type: QuestionType.mcq, correctAnswer: 'A'),
          const Question(number: 2, type: QuestionType.trueFalse, correctAnswer: 'True'),
          const Question(number: 3, type: QuestionType.mcq, correctAnswer: 'C'),
          const Question(number: 4, type: QuestionType.trueFalse, correctAnswer: 'False'),
        ]);
      expect(a.answeredQuestionCount, 4);
      expect(a.isAnswerKeyComplete, isTrue);
      expect(a.answerKeyCompleteness, 1.0);
    });
  });
}
