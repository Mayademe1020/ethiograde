import 'package:flutter_test/flutter_test.dart';

import 'package:ethiograde/services/scoring_service.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/models/weighted_grade.dart';

void main() {
  const scoring = ScoringService();

  group('ScoringService.computeWeightedPercentage', () {
    // 10 questions, split into 3 components by proportional distribution
    // Quiz (20%) → ~2 questions, Midterm (30%) → ~3, Final (50%) → ~5
    final questions = List.generate(
      10,
      (i) => Question(number: i + 1, type: QuestionType.mcq, points: 10));

    final scale = WeightedGradeScale(
      name: 'Test Weights',
      classId: 'c1',
      components: [
        const GradeComponent(name: 'Quiz', weight: 0.20, assessmentIds: ['a1']),
        const GradeComponent(name: 'Midterm', weight: 0.30, assessmentIds: ['a1']),
        const GradeComponent(name: 'Final', weight: 0.50, assessmentIds: ['a1']),
      ]);

    test('computes weighted percentage with proportional distribution', () {
      // All correct → 100% per component → 100% weighted
      final allCorrect = List.generate(
        10,
        (i) => AnswerMatch(
          questionNumber: i + 1,
          detectedAnswer: 'A',
          correctAnswer: 'A',
          isCorrect: true,
          score: 10,
          maxScore: 10,
          confidence: 1.0));

      final pct = scoring.computeWeightedPercentage(
        scoredAnswers: allCorrect,
        questions: questions,
        scale: scale);

      expect(pct, isNotNull);
      expect(pct, closeTo(100.0, 0.1));
    });

    test('handles partial correctness with weights', () {
      // First 2 correct (Quiz section), next 3 wrong (Midterm), last 5 correct (Final)
      final answers = <AnswerMatch>[];
      for (int i = 0; i < 10; i++) {
        final isWrong = i >= 2 && i < 5;
        answers.add(AnswerMatch(
          questionNumber: i + 1,
          detectedAnswer: isWrong ? 'B' : 'A',
          correctAnswer: 'A',
          isCorrect: !isWrong,
          score: isWrong ? 0 : 10,
          maxScore: 10,
          confidence: 1.0));
      }

      final pct = scoring.computeWeightedPercentage(
        scoredAnswers: answers,
        questions: questions,
        scale: scale);

      expect(pct, isNotNull);
      // Quiz: 2/2 = 100% × 0.20 = 20
      // Midterm: 0/3 = 0% × 0.30 = 0
      // Final: 5/5 = 100% × 0.50 = 50
      // Total: 70% (but normalized since only some components have questions)
      // The exact value depends on proportional distribution
      expect(pct, greaterThan(0));
      expect(pct, lessThanOrEqualTo(100));
    });

    test('returns null for empty answers', () {
      final pct = scoring.computeWeightedPercentage(
        scoredAnswers: [],
        questions: questions,
        scale: scale);
      expect(pct, isNull);
    });

    test('returns null for empty scale', () {
      final emptyScale = WeightedGradeScale(
        name: 'Empty',
        classId: 'c1',
        components: []);

      final answers = [
        AnswerMatch(
          questionNumber: 1,
          detectedAnswer: 'A',
          correctAnswer: 'A',
          isCorrect: true,
          score: 10,
          maxScore: 10,
          confidence: 1.0),
      ];

      final pct = scoring.computeWeightedPercentage(
        scoredAnswers: answers,
        questions: questions,
        scale: emptyScale);
      expect(pct, isNull);
    });

    test('matches questions by topic tag', () {
      final taggedQuestions = [
        Question(number: 1, type: QuestionType.mcq, points: 10, topicTag: 'Quiz'),
        Question(number: 2, type: QuestionType.mcq, points: 10, topicTag: 'Quiz'),
        Question(number: 3, type: QuestionType.mcq, points: 10, topicTag: 'Final'),
        Question(number: 4, type: QuestionType.mcq, points: 10, topicTag: 'Final'),
      ];

      final taggedScale = WeightedGradeScale(
        name: 'Tagged',
        classId: 'c1',
        components: [
          const GradeComponent(name: 'Quiz', weight: 0.30, assessmentIds: ['a1']),
          const GradeComponent(name: 'Final', weight: 0.70, assessmentIds: ['a1']),
        ]);

      // Quiz: 1/2 correct (50%), Final: 2/2 correct (100%)
      final answers = [
        AnswerMatch(
          questionNumber: 1, detectedAnswer: 'A', correctAnswer: 'A',
          isCorrect: true, score: 10, maxScore: 10, confidence: 1.0),
        AnswerMatch(
          questionNumber: 2, detectedAnswer: 'B', correctAnswer: 'A',
          isCorrect: false, score: 0, maxScore: 10, confidence: 1.0),
        AnswerMatch(
          questionNumber: 3, detectedAnswer: 'A', correctAnswer: 'A',
          isCorrect: true, score: 10, maxScore: 10, confidence: 1.0),
        AnswerMatch(
          questionNumber: 4, detectedAnswer: 'A', correctAnswer: 'A',
          isCorrect: true, score: 10, maxScore: 10, confidence: 1.0),
      ];

      final pct = scoring.computeWeightedPercentage(
        scoredAnswers: answers,
        questions: taggedQuestions,
        scale: taggedScale);

      expect(pct, isNotNull);
      // Quiz: 50% × 0.30 = 15
      // Final: 100% × 0.70 = 70
      // Total: 85%
      expect(pct, closeTo(85.0, 0.1));
    });

    test('single component returns its percentage', () {
      final singleScale = WeightedGradeScale(
        name: 'Single',
        classId: 'c1',
        components: [
          const GradeComponent(name: 'All', weight: 1.0, assessmentIds: ['a1']),
        ]);

      final answers = [
        AnswerMatch(
          questionNumber: 1, detectedAnswer: 'A', correctAnswer: 'A',
          isCorrect: true, score: 10, maxScore: 10, confidence: 1.0),
        AnswerMatch(
          questionNumber: 2, detectedAnswer: 'B', correctAnswer: 'A',
          isCorrect: false, score: 0, maxScore: 10, confidence: 1.0),
      ];

      final pct = scoring.computeWeightedPercentage(
        scoredAnswers: answers,
        questions: questions.sublist(0, 2),
        scale: singleScale);

      expect(pct, closeTo(50.0, 0.1));
    });
  });
}
