import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/services/answer_parser.dart';
import 'package:ethiograde/services/scoring_service.dart';
import 'package:ethiograde/models/assessment.dart';

void main() {
  const parser = AnswerParser();
  const scoring = ScoringService();

  // ══════════════════════════════════════════════════════════════════
  // AnswerParser — Matching pair detection
  // ══════════════════════════════════════════════════════════════════

  group('AnswerParser — matching pairs', () {
    test('"G D" → MATCH:G-D (two letters beyond E)', () {
      final result = parser.parseQuestionAnswer('1. G D');
      expect(result, isNotNull);
      expect(result!.$1, 1);
      expect(result.$2, 'MATCH:G-D');
    });

    test('"G,D,E" → MATCH:G-D-E (comma separated)', () {
      final result = parser.parseQuestionAnswer('2. G,D,E');
      expect(result, isNotNull);
      expect(result!.$1, 2);
      expect(result.$2, 'MATCH:G-D-E');
    });

    test('"F G H" → MATCH:F-G-H (three letters beyond E)', () {
      final result = parser.parseQuestionAnswer('3. F G H');
      expect(result, isNotNull);
      expect(result!.$1, 3);
      expect(result.$2, 'MATCH:F-G-H');
    });

    test('"G D" standalone (no question number) parses via normalizeAnswer',
        () {
      // normalizeAnswer should detect matching pair
      expect(parser.normalizeAnswer('G D'), 'MATCH:G-D');
      expect(parser.normalizeAnswer('F,G'), 'MATCH:F-G');
    });

    test('single MCQ letter stays as MCQ, not matching', () {
      // A-E single letter should NOT become matching
      expect(parser.normalizeAnswer('A'), 'A');
      expect(parser.normalizeAnswer('B'), 'B');
      expect(parser.normalizeAnswer('E'), 'E');
    });

    test('"A B" (two MCQ letters) is ambiguous — stays as-is', () {
      // Could be multi-select MCQ or matching. Since both letters are A-E
      // and no non-MCQ letter, _tryParseMatchingPair returns null.
      // normalizeAnswer falls through to short-answer acceptance.
      final result = parser.normalizeAnswer('A B');
      expect(result, 'A B');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // AnswerParser — Worksheet format (question text + answer same line)
  // ══════════════════════════════════════════════════════════════════

  group('AnswerParser — worksheet format extraction', () {
    test('"1. What is the greeting? A" extracts answer A', () {
      final result = parser.parseQuestionAnswer(
        '1. What is the greeting? A');
      expect(result, isNotNull);
      expect(result!.$1, 1);
      expect(result.$2, 'A');
    });

    test('"2. The capital of Ethiopia is B" extracts answer B', () {
      final result = parser.parseQuestionAnswer(
        '2. The capital of Ethiopia is B');
      expect(result, isNotNull);
      expect(result!.$1, 2);
      expect(result.$2, 'B');
    });

    test('"3. Is this true? True" extracts True', () {
      final result = parser.parseQuestionAnswer(
        '3. Is this true? True');
      expect(result, isNotNull);
      expect(result!.$1, 3);
      expect(result.$2, 'True');
    });

    test('"4. Opposite of short is False" extracts False', () {
      final result = parser.parseQuestionAnswer(
        '4. Opposite of short is False');
      expect(result, isNotNull);
      expect(result!.$1, 4);
      expect(result.$2, 'False');
    });

    test('"5. Match the words G D" extracts matching pair', () {
      final result = parser.parseQuestionAnswer(
        '5. Match the words G D');
      expect(result, isNotNull);
      expect(result!.$1, 5);
      expect(result.$2, 'MATCH:G-D');
    });

    test('"10. The opposite of teacher is C" extracts C', () {
      final result = parser.parseQuestionAnswer(
        '10. The opposite of teacher is C');
      expect(result, isNotNull);
      expect(result!.$1, 10);
      expect(result.$2, 'C');
    });

    test('"1) መልስ የትኛው ነው? ሐ" extracts Amharic letter → C', () {
      final result = parser.parseQuestionAnswer(
        '1) መልስ የትኛው ነው? ሐ');
      expect(result, isNotNull);
      expect(result!.$1, 1);
      expect(result.$2, 'C');
    });

    test('plain MCQ still works: "1. A"', () {
      final result = parser.parseQuestionAnswer('1. A');
      expect(result, isNotNull);
      expect(result!.$1, 1);
      expect(result.$2, 'A');
    });

    test('plain T/F still works: "2. True"', () {
      final result = parser.parseQuestionAnswer('2. True');
      expect(result, isNotNull);
      expect(result!.$1, 2);
      expect(result.$2, 'True');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // AnswerParser — Spatial awareness (position-based grouping)
  // ══════════════════════════════════════════════════════════════════

  group('AnswerParser — spatial parsing', () {
    test('question number and answer on same horizontal line', () {
      // Simulates: "1." on left, "A" on right, same Y
      final regions = [
        const TextRegionInput(text: '1.', confidence: 0.9, x: 50, y: 100),
        const TextRegionInput(text: 'A', confidence: 0.85, x: 300, y: 102),
        const TextRegionInput(text: '2.', confidence: 0.9, x: 50, y: 150),
        const TextRegionInput(text: 'B', confidence: 0.88, x: 300, y: 152),
      ];

      final answers = parser.parseAnswersWithPosition(regions);
      expect(answers.length, 2);
      expect(answers[0].questionNumber, 1);
      expect(answers[0].answer, 'A');
      expect(answers[1].questionNumber, 2);
      expect(answers[1].answer, 'B');
    });

    test('standard parsing takes priority over spatial', () {
      // "1. A" is already parseable — spatial should not duplicate it
      final regions = [
        const TextRegionInput(text: '1. A', confidence: 0.9, x: 50, y: 100),
        const TextRegionInput(text: '2.', confidence: 0.9, x: 50, y: 150),
        const TextRegionInput(text: 'C', confidence: 0.85, x: 300, y: 152),
      ];

      final answers = parser.parseAnswersWithPosition(regions);
      expect(answers.length, 2);
      expect(answers[0].questionNumber, 1);
      expect(answers[0].answer, 'A');
      expect(answers[1].questionNumber, 2);
      expect(answers[1].answer, 'C');
    });

    test('T/F spatial: "1." + "True" on same line', () {
      final regions = [
        const TextRegionInput(text: '1.', confidence: 0.9, x: 50, y: 100),
        const TextRegionInput(text: 'True', confidence: 0.82, x: 300, y: 101),
      ];

      final answers = parser.parseAnswersWithPosition(regions);
      expect(answers.length, 1);
      expect(answers[0].questionNumber, 1);
      expect(answers[0].answer, 'True');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // AnswerParser — Real exam patterns from the 8 uploaded papers
  // ══════════════════════════════════════════════════════════════════

  group('AnswerParser — real Ethiopian exam patterns', () {
    // Exam 1: Oromo MCQ (A/B/C), student writes letter in blank
    test('Oromo MCQ: "1. A" single letter answer', () {
      final result = parser.parseQuestionAnswer('1. A');
      expect(result, isNotNull);
      expect(result!.$2, 'A');
    });

    // Exam 2: English MCQ (A-D), student circles/writes answer
    test('English MCQ: "3. C" standard', () {
      final result = parser.parseQuestionAnswer('3. C');
      expect(result, isNotNull);
      expect(result!.$2, 'C');
    });

    // Exam 3: True/False section
    test('English T/F: "1. True"', () {
      final result = parser.parseQuestionAnswer('1. True');
      expect(result, isNotNull);
      expect(result!.$2, 'True');
    });

    // Exam 3: Matching section — student writes "G D" for matches
    test('Matching: "6. G D" two column matches', () {
      final result = parser.parseQuestionAnswer('6. G D');
      expect(result, isNotNull);
      expect(result!.$1, 6);
      expect(result.$2, 'MATCH:G-D');
    });

    // Exam 5: Matching with 5 pairs
    test('Matching: "1. F G D E A" five matches', () {
      final result = parser.parseQuestionAnswer('1. F G D E A');
      expect(result, isNotNull);
      expect(result!.$1, 1);
      expect(result.$2, 'MATCH:F-G-D-E-A');
    });

    // Exam 8: Amharic T/F
    test('Amharic T/F: "1. እውነት"', () {
      final result = parser.parseQuestionAnswer('1. እውነት');
      expect(result, isNotNull);
      expect(result!.$2, 'True');
    });

    test('Amharic T/F: "2. ሐሰት"', () {
      final result = parser.parseQuestionAnswer('2. ሐሰት');
      expect(result, isNotNull);
      expect(result!.$2, 'False');
    });

    // Amharic MCQ
    test('Amharic MCQ: "1. ሀ" → A', () {
      final result = parser.parseQuestionAnswer('1. ሀ');
      expect(result, isNotNull);
      expect(result!.$2, 'A');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // ScoringService — Matching answer checking
  // ══════════════════════════════════════════════════════════════════

  group('ScoringService — matching answer checking', () {
    test('exact match: "MATCH:G-D" == "MATCH:G-D"', () {
      expect(
        scoring.checkAnswer(
          detected: 'MATCH:G-D',
          correct: 'MATCH:G-D',
          type: QuestionType.matching),
        isTrue);
    });

    test('exact match with different formats: "G D" == "MATCH:G-D"', () {
      expect(
        scoring.checkAnswer(
          detected: 'G D',
          correct: 'MATCH:G-D',
          type: QuestionType.matching),
        isTrue);
    });

    test('case insensitive: "g-d" == "MATCH:G-D"', () {
      expect(
        scoring.checkAnswer(
          detected: 'g-d',
          correct: 'MATCH:G-D',
          type: QuestionType.matching),
        isTrue);
    });

    test('mismatch: "MATCH:G-D" != "MATCH:D-G"', () {
      expect(
        scoring.checkAnswer(
          detected: 'MATCH:G-D',
          correct: 'MATCH:D-G',
          type: QuestionType.matching),
        isFalse);
    });

    test('different lengths: "MATCH:G" != "MATCH:G-D"', () {
      expect(
        scoring.checkAnswer(
          detected: 'MATCH:G',
          correct: 'MATCH:G-D',
          type: QuestionType.matching),
        isFalse);
    });

    test('null detected returns false', () {
      expect(
        scoring.checkAnswer(
          detected: null,
          correct: 'MATCH:G-D',
          type: QuestionType.matching),
        isFalse);
    });

    test('empty detected returns false', () {
      expect(
        scoring.checkAnswer(
          detected: '',
          correct: 'MATCH:G-D',
          type: QuestionType.matching),
        isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // ScoringService — Matching partial credit
  // ══════════════════════════════════════════════════════════════════

  group('ScoringService — matching partial credit', () {
    test('all correct: 5/5 → full points', () {
      final score = scoring.scoreMatchingPartial(
        detected: 'G-D-E-F-A',
        correct: 'G-D-E-F-A',
        totalPoints: 10);
      expect(score, 10.0);
    });

    test('3/5 correct → 6 points (proportional)', () {
      final score = scoring.scoreMatchingPartial(
        detected: 'G-D-X-F-A',
        correct: 'G-D-E-F-A',
        totalPoints: 10);
      expect(score, 6.0);
    });

    test('0/5 correct → 0 points', () {
      final score = scoring.scoreMatchingPartial(
        detected: 'A-B-C-D-E',
        correct: 'G-D-E-F-A',
        totalPoints: 10);
      expect(score, 0.0);
    });

    test('shorter detected: 2/3 correct out of 3', () {
      final score = scoring.scoreMatchingPartial(
        detected: 'G D',
        correct: 'G-D-E',
        totalPoints: 9);
      // 2 correct out of 3 → 6.0
      expect(score, 6.0);
    });

    test('empty detected → 0 points', () {
      final score = scoring.scoreMatchingPartial(
        detected: '',
        correct: 'G-D',
        totalPoints: 10);
      expect(score, 0.0);
    });

    test('comma-separated detected works', () {
      final score = scoring.scoreMatchingPartial(
        detected: 'G,D,E',
        correct: 'G-D-E',
        totalPoints: 6);
      expect(score, 6.0);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // ScoringService — Matching in full scoring pipeline
  // ══════════════════════════════════════════════════════════════════

  group('ScoringService — matching in full pipeline', () {
    test('scoreAnswers handles matching question type', () {
      final assessment = Assessment(
        title: 'Test',
        subject: 'English',
        questions: [
          Question(number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
          Question(number: 2, type: QuestionType.trueFalse, correctAnswer: 'True', points: 1),
          Question(number: 3, type: QuestionType.matching, correctAnswer: 'G-D-E', points: 3),
        ]);

      final detected = [
        const DetectedAnswer(questionNumber: 1, answer: 'A', confidence: 0.9, rawText: '1. A'),
        const DetectedAnswer(questionNumber: 2, answer: 'True', confidence: 0.85, rawText: '2. True'),
        const DetectedAnswer(questionNumber: 3, answer: 'MATCH:G-D-E', confidence: 0.8, rawText: '3. G D E'),
      ];

      final matches = scoring.scoreAnswers(detected: detected, assessment: assessment);

      expect(matches.length, 3);
      expect(matches[0].isCorrect, isTrue);
      expect(matches[0].score, 1.0);
      expect(matches[1].isCorrect, isTrue);
      expect(matches[1].score, 1.0);
      expect(matches[2].isCorrect, isTrue);
      expect(matches[2].score, 3.0);

      final total = scoring.calculateTotalScore(matches);
      expect(total, 5.0);
    });

    test('scoreAnswers handles partially correct matching', () {
      final assessment = Assessment(
        title: 'Test',
        subject: 'English',
        questions: [
          Question(number: 1, type: QuestionType.matching, correctAnswer: 'G-D-E', points: 3),
        ]);

      final detected = [
        const DetectedAnswer(questionNumber: 1, answer: 'MATCH:G-X-E', confidence: 0.8, rawText: '1. G X E'),
      ];

      final matches = scoring.scoreAnswers(detected: detected, assessment: assessment);

      expect(matches.length, 1);
      // Exact match check fails (G-X-E != G-D-E), so isCorrect = false, score = 0
      // Partial credit would need to be applied separately via scoreMatchingPartial
      expect(matches[0].isCorrect, isFalse);
      expect(matches[0].score, 0.0);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // Regression — existing MCQ/TF still works
  // ══════════════════════════════════════════════════════════════════

  group('Regression — MCQ and T/F still work after matching changes', () {
    test('MCQ checkAnswer still works', () {
      expect(
        scoring.checkAnswer(
          detected: 'A',
          correct: 'A',
          type: QuestionType.mcq),
        isTrue);
      expect(
        scoring.checkAnswer(
          detected: 'B',
          correct: 'A',
          type: QuestionType.mcq),
        isFalse);
    });

    test('T/F checkAnswer still works', () {
      expect(
        scoring.checkAnswer(
          detected: 'True',
          correct: 'True',
          type: QuestionType.trueFalse),
        isTrue);
      expect(
        scoring.checkAnswer(
          detected: 'False',
          correct: 'True',
          type: QuestionType.trueFalse),
        isFalse);
    });

    test('short answer checkAnswer still works', () {
      expect(
        scoring.checkAnswer(
          detected: 'Addis Ababa',
          correct: 'Addis Ababa',
          type: QuestionType.shortAnswer),
        isTrue);
    });

    test('answer parser still handles standard MCQ', () {
      final result = parser.parseQuestionAnswer('1. A');
      expect(result, isNotNull);
      expect(result!.$2, 'A');
    });

    test('answer parser still handles Amharic MCQ', () {
      final result = parser.parseQuestionAnswer('3. መ');
      expect(result, isNotNull);
      expect(result!.$2, 'D');
    });

    test('answer parser still handles concatenated bubbled', () {
      final result = parser.parseQuestionAnswer('10B');
      expect(result, isNotNull);
      expect(result!.$1, 10);
      expect(result.$2, 'B');
    });
  });
}
