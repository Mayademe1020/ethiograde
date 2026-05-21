import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/answer_sheet_config.dart';
import 'package:ethiograde/models/assessment.dart';

void main() {
  group('AnswerSheetConfig', () {
    test('detectRanges for pure MCQ assessment', () {
      final assessment = Assessment(
        id: 'mcq-only',
        title: 'MCQ Test',
        subject: 'Math',
        questions: List.generate(
          20,
          (i) => Question(
            number: i + 1,
            type: QuestionType.mcq,
            correctAnswer: 'A')));

      final ranges = AnswerSheetConfig.detectRanges(assessment);
      expect(ranges, hasLength(1));
      expect(ranges[0].start, 1);
      expect(ranges[0].end, 20);
      expect(ranges[0].isMcq, isTrue);
      expect(ranges[0].count, 20);
    });

    test('detectRanges for pure T/F assessment', () {
      final assessment = Assessment(
        id: 'tf-only',
        title: 'TF Test',
        subject: 'Science',
        questions: List.generate(
          10,
          (i) => Question(
            number: i + 1,
            type: QuestionType.trueFalse,
            correctAnswer: 'True')));

      final ranges = AnswerSheetConfig.detectRanges(assessment);
      expect(ranges, hasLength(1));
      expect(ranges[0].start, 1);
      expect(ranges[0].end, 10);
      expect(ranges[0].isMcq, isFalse);
    });

    test('detectRanges for mixed assessment', () {
      final assessment = Assessment(
        id: 'mixed',
        title: 'Mixed Test',
        subject: 'General',
        questions: [
          ...List.generate(
            35,
            (i) => Question(
              number: i + 1,
              type: QuestionType.mcq,
              correctAnswer: 'A')),
          ...List.generate(
            5,
            (i) => Question(
              number: 36 + i,
              type: QuestionType.trueFalse,
              correctAnswer: 'True')),
        ]);

      final ranges = AnswerSheetConfig.detectRanges(assessment);
      expect(ranges, hasLength(2));
      expect(ranges[0].start, 1);
      expect(ranges[0].end, 35);
      expect(ranges[0].isMcq, isTrue);
      expect(ranges[1].start, 36);
      expect(ranges[1].end, 40);
      expect(ranges[1].isMcq, isFalse);
    });

    test('detectRanges for alternating types', () {
      final assessment = Assessment(
        id: 'alt',
        title: 'Alternating',
        subject: 'Mixed',
        questions: [
          const Question(number: 1, type: QuestionType.mcq, correctAnswer: 'A'),
          const Question(number: 2, type: QuestionType.trueFalse, correctAnswer: 'True'),
          const Question(number: 3, type: QuestionType.mcq, correctAnswer: 'B'),
          const Question(number: 4, type: QuestionType.trueFalse, correctAnswer: 'False'),
        ]);

      final ranges = AnswerSheetConfig.detectRanges(assessment);
      expect(ranges, hasLength(4));
      expect(ranges[0].isMcq, isTrue);
      expect(ranges[1].isMcq, isFalse);
      expect(ranges[2].isMcq, isTrue);
      expect(ranges[3].isMcq, isFalse);
    });

    test('detectRanges for empty assessment', () {
      final assessment = Assessment(
        id: 'empty',
        title: 'Empty',
        subject: 'Math');

      final ranges = AnswerSheetConfig.detectRanges(assessment);
      expect(ranges, isEmpty);
    });

    test('detectRanges treats matching as MCQ', () {
      final assessment = Assessment(
        id: 'matching',
        title: 'Matching Test',
        subject: 'English',
        questions: [
          const Question(number: 1, type: QuestionType.mcq, correctAnswer: 'A'),
          const Question(number: 2, type: QuestionType.matching, correctAnswer: 'MATCH:A-B'),
          const Question(number: 3, type: QuestionType.mcq, correctAnswer: 'C'),
        ]);

      final ranges = AnswerSheetConfig.detectRanges(assessment);
      // All three should be in one MCQ range since matching is treated as MCQ
      expect(ranges, hasLength(1));
      expect(ranges[0].isMcq, isTrue);
      expect(ranges[0].count, 3);
    });
  });

  group('QuestionTypeRange', () {
    test('count calculates correctly', () {
      const range = QuestionTypeRange(start: 5, end: 10, isMcq: true);
      expect(range.count, 6);
    });

    test('label for single question', () {
      const range = QuestionTypeRange(start: 7, end: 7, isMcq: false);
      expect(range.label, 'Q7');
    });

    test('label for range', () {
      const range = QuestionTypeRange(start: 1, end: 35, isMcq: true);
      expect(range.label, 'Q1–35');
    });
  });

  group('AnswerSheetConfig — computed properties', () {
    test('totalQuestions sums ranges', () {
      const config = AnswerSheetConfig(
        assessmentId: 'test',
        typeRanges: [
          QuestionTypeRange(start: 1, end: 35, isMcq: true),
          QuestionTypeRange(start: 36, end: 40, isMcq: false),
        ]);
      expect(config.totalQuestions, 40);
    });

    test('mcqCount and tfCount', () {
      const config = AnswerSheetConfig(
        assessmentId: 'test',
        typeRanges: [
          QuestionTypeRange(start: 1, end: 35, isMcq: true),
          QuestionTypeRange(start: 36, end: 40, isMcq: false),
        ]);
      expect(config.mcqCount, 35);
      expect(config.tfCount, 5);
    });

    test('copyWith preserves assessmentId', () {
      const config = AnswerSheetConfig(
        assessmentId: 'test-123',
        schoolName: 'Old School');
      final updated = config.copyWith(schoolName: 'New School');
      expect(updated.assessmentId, 'test-123');
      expect(updated.schoolName, 'New School');
    });
  });
}
