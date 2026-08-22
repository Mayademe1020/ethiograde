import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/services/coordinate_map_omr_service.dart';

void main() {
  group('CoordinateMapOmrResult', () {
    test('empty result has zero values', () {
      const result = CoordinateMapOmrResult.empty;
      expect(result.answers, isEmpty);
      expect(result.totalQuestions, 0);
      expect(result.correctAnswers, 0);
      expect(result.averageConfidence, 0);
      expect(result.anchorsDetected, 0);
    });

    test('percentage calculates correctly', () {
      const result = CoordinateMapOmrResult(
        answers: [],
        totalQuestions: 10,
        correctAnswers: 8,
        averageConfidence: 0.9,
        anchorsDetected: 4);
      expect(result.percentage, 80.0);
    });

    test('percentage is 0 for zero questions', () {
      const result = CoordinateMapOmrResult(
        answers: [],
        totalQuestions: 0,
        correctAnswers: 0,
        averageConfidence: 0,
        anchorsDetected: 0);
      expect(result.percentage, 0.0);
    });

    test('missingAnswers counts empty detected answers', () {
      const result = CoordinateMapOmrResult(
        answers: [
          CoordinateMapAnswer(
            questionNumber: 1,
            detectedAnswer: 'A',
            correctAnswer: 'A',
            confidence: 0.9,
            fillRatio: 0.7,
            fillRatios: {'A': 0.7, 'B': 0.1, 'C': 0.05, 'D': 0.05},
            isCorrect: true,
            questionType: 'MCQ'),
          CoordinateMapAnswer(
            questionNumber: 2,
            detectedAnswer: '',
            correctAnswer: 'B',
            confidence: 0.0,
            fillRatio: 0.0,
            fillRatios: {'A': 0.05, 'B': 0.05, 'C': 0.05, 'D': 0.05},
            isCorrect: false,
            questionType: 'MCQ'),
        ],
        totalQuestions: 2,
        correctAnswers: 1,
        averageConfidence: 0.45,
        anchorsDetected: 4);
      expect(result.missingAnswers, 1);
    });

    test('lowConfidenceAnswers counts answers below 0.6', () {
      const result = CoordinateMapOmrResult(
        answers: [
          CoordinateMapAnswer(
            questionNumber: 1,
            detectedAnswer: 'A',
            correctAnswer: 'A',
            confidence: 0.9,
            fillRatio: 0.7,
            fillRatios: {},
            isCorrect: true,
            questionType: 'MCQ'),
          CoordinateMapAnswer(
            questionNumber: 2,
            detectedAnswer: 'B',
            correctAnswer: 'B',
            confidence: 0.4,
            fillRatio: 0.3,
            fillRatios: {},
            isCorrect: true,
            questionType: 'MCQ'),
          CoordinateMapAnswer(
            questionNumber: 3,
            detectedAnswer: 'C',
            correctAnswer: 'D',
            confidence: 0.5,
            fillRatio: 0.35,
            fillRatios: {},
            isCorrect: false,
            questionType: 'MCQ'),
        ],
        totalQuestions: 3,
        correctAnswers: 2,
        averageConfidence: 0.6,
        anchorsDetected: 4);
      // Q2 (0.4) and Q3 (0.5) are below 0.6
      expect(result.lowConfidenceAnswers, 2);
    });
  });

  group('CoordinateMapAnswer', () {
    test('isEmpty returns true for empty answer', () {
      const answer = CoordinateMapAnswer(
        questionNumber: 1,
        detectedAnswer: '',
        correctAnswer: 'A',
        confidence: 0.0,
        fillRatio: 0.0,
        fillRatios: {},
        isCorrect: false,
        questionType: 'MCQ');
      expect(answer.isEmpty, isTrue);
    });

    test('isEmpty returns false for non-empty answer', () {
      const answer = CoordinateMapAnswer(
        questionNumber: 1,
        detectedAnswer: 'A',
        correctAnswer: 'A',
        confidence: 0.9,
        fillRatio: 0.7,
        fillRatios: {},
        isCorrect: true,
        questionType: 'MCQ');
      expect(answer.isEmpty, isFalse);
    });
  });

  group('Answer Key Detection', () {
    test('isAnswerKey defaults to false', () {
      const result = CoordinateMapOmrResult.empty;
      expect(result.isAnswerKey, isFalse);
    });

    test('isAnswerKey can be set to true', () {
      const result = CoordinateMapOmrResult(
        answers: [
          CoordinateMapAnswer(
            questionNumber: 1,
            detectedAnswer: 'A',
            correctAnswer: '',
            confidence: 0.9,
            fillRatio: 0.7,
            fillRatios: {'A': 0.7},
            isCorrect: false,
            questionType: 'MCQ'),
        ],
        totalQuestions: 1,
        correctAnswers: 0,
        averageConfidence: 0.9,
        anchorsDetected: 4,
        isAnswerKey: true);
      expect(result.isAnswerKey, isTrue);
    });

    test('answerKey extracts question→answer map', () {
      const result = CoordinateMapOmrResult(
        answers: [
          CoordinateMapAnswer(
            questionNumber: 1, detectedAnswer: 'A', correctAnswer: '',
            confidence: 0.9, fillRatio: 0.7, fillRatios: {},
            isCorrect: false, questionType: 'MCQ'),
          CoordinateMapAnswer(
            questionNumber: 2, detectedAnswer: 'B', correctAnswer: '',
            confidence: 0.8, fillRatio: 0.6, fillRatios: {},
            isCorrect: false, questionType: 'MCQ'),
          CoordinateMapAnswer(
            questionNumber: 3, detectedAnswer: '', correctAnswer: '',
            confidence: 0.0, fillRatio: 0.0, fillRatios: {},
            isCorrect: false, questionType: 'MCQ'),
        ],
        totalQuestions: 3,
        correctAnswers: 0,
        averageConfidence: 0.57,
        anchorsDetected: 4,
        isAnswerKey: true);

      final key = result.answerKey;
      expect(key, hasLength(2)); // Q3 is empty, not included
      expect(key[1], 'A');
      expect(key[2], 'B');
      expect(key.containsKey(3), isFalse);
    });

    test('answerKey is empty when no answers detected', () {
      const result = CoordinateMapOmrResult(
        answers: [],
        totalQuestions: 0,
        correctAnswers: 0,
        averageConfidence: 0,
        anchorsDetected: 4,
        isAnswerKey: true);
      expect(result.answerKey, isEmpty);
    });
  });
}
