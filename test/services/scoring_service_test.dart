import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/services/scoring_service.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';

void main() {
  const scoring = ScoringService();

  // ── Helper builders ──

  Assessment makeAssessment({
    String rubricType = 'moe_national',
    List<Question>? questions,
  }) {
    return Assessment(
      title: 'Test',
      subject: 'Math',
      rubricType: rubricType,
      questions: questions ?? [],
    );
  }

  Question mcq(int number, String correct, {double points = 1.0}) => Question(
        number: number,
        type: QuestionType.mcq,
        correctAnswer: correct,
        points: points,
      );

  Question tf(int number, String correct, {double points = 1.0}) => Question(
        number: number,
        type: QuestionType.trueFalse,
        correctAnswer: correct,
        points: points,
      );

  Question shortAnswer(
    int number,
    dynamic correct, {
    double points = 2.0,
  }) =>
      Question(
        number: number,
        type: QuestionType.shortAnswer,
        correctAnswer: correct,
        points: points,
      );

  DetectedAnswer det(int q, String answer, {double confidence = 0.9}) =>
      DetectedAnswer(
        questionNumber: q,
        answer: answer,
        confidence: confidence,
        rawText: '$q. $answer',
      );

  // ════════════════════════════════════════════════════════════════
  // checkAnswer
  // ════════════════════════════════════════════════════════════════

  group('checkAnswer — MCQ', () {
    test('exact match (uppercase)', () {
      expect(
        scoring.checkAnswer(
            detected: 'A', correct: 'A', type: QuestionType.mcq),
        isTrue,
      );
    });

    test('case-insensitive match', () {
      expect(
        scoring.checkAnswer(
            detected: 'b', correct: 'B', type: QuestionType.mcq),
        isTrue,
      );
    });

    test('wrong answer', () {
      expect(
        scoring.checkAnswer(
            detected: 'C', correct: 'A', type: QuestionType.mcq),
        isFalse,
      );
    });

    test('null detected → false', () {
      expect(
        scoring.checkAnswer(
            detected: null, correct: 'A', type: QuestionType.mcq),
        isFalse,
      );
    });

    test('null correct → false', () {
      expect(
        scoring.checkAnswer(
            detected: 'A', correct: null, type: QuestionType.mcq),
        isFalse,
      );
    });
  });

  group('checkAnswer — True/False', () {
    test('True matches True', () {
      expect(
        scoring.checkAnswer(
            detected: 'True', correct: 'True', type: QuestionType.trueFalse),
        isTrue,
      );
    });

    test('false matches False (case-insensitive)', () {
      expect(
        scoring.checkAnswer(
            detected: 'false', correct: 'False', type: QuestionType.trueFalse),
        isTrue,
      );
    });

    test('True ≠ False', () {
      expect(
        scoring.checkAnswer(
            detected: 'True', correct: 'False', type: QuestionType.trueFalse),
        isFalse,
      );
    });
  });

  group('checkAnswer — Short Answer', () {
    test('exact string match (case-insensitive)', () {
      expect(
        scoring.checkAnswer(
          detected: 'Addis Ababa',
          correct: 'addis ababa',
          type: QuestionType.shortAnswer,
        ),
        isTrue,
      );
    });

    test('matches any in accepted list', () {
      expect(
        scoring.checkAnswer(
          detected: 'Ethiopia',
          correct: ['ethiopia', 'Habesha'],
          type: QuestionType.shortAnswer,
        ),
        isTrue,
      );
    });

    test('no match in list', () {
      expect(
        scoring.checkAnswer(
          detected: 'Kenya',
          correct: ['ethiopia', 'habesha'],
          type: QuestionType.shortAnswer,
        ),
        isFalse,
      );
    });

    test('case-insensitive list match', () {
      expect(
        scoring.checkAnswer(
          detected: 'HABESHA',
          correct: ['ethiopia', 'habesha'],
          type: QuestionType.shortAnswer,
        ),
        isTrue,
      );
    });
  });

  // ════════════════════════════════════════════════════════════════
  // scoreAnswers
  // ════════════════════════════════════════════════════════════════

  group('scoreAnswers', () {
    test('all correct MCQ → full score', () {
      final assessment = makeAssessment(questions: [
        mcq(1, 'A'),
        mcq(2, 'B'),
        mcq(3, 'C'),
      ]);
      final detected = [det(1, 'A'), det(2, 'B'), det(3, 'C')];

      final results = scoring.scoreAnswers(
          detected: detected, assessment: assessment);

      expect(results.length, 3);
      expect(results.every((r) => r.isCorrect), isTrue);
      expect(results.every((r) => r.score == 1.0), isTrue);
    });

    test('all wrong → zero score', () {
      final assessment = makeAssessment(questions: [
        mcq(1, 'A'),
        mcq(2, 'B'),
      ]);
      final detected = [det(1, 'D'), det(2, 'E')];

      final results = scoring.scoreAnswers(
          detected: detected, assessment: assessment);

      expect(results.every((r) => !r.isCorrect), isTrue);
      expect(results.every((r) => r.score == 0), isTrue);
    });

    test('missing detection → [MISSING], score 0', () {
      final assessment = makeAssessment(questions: [
        mcq(1, 'A'),
        mcq(2, 'B'),
      ]);
      final detected = [det(1, 'A')]; // Q2 missing

      final results = scoring.scoreAnswers(
          detected: detected, assessment: assessment);

      expect(results[1].detectedAnswer, '[MISSING]');
      expect(results[1].isCorrect, isFalse);
      expect(results[1].score, 0);
      expect(results[1].confidence, 0);
    });

    test('mixed correct/wrong → partial score', () {
      final assessment = makeAssessment(questions: [
        mcq(1, 'A', points: 2.0),
        mcq(2, 'B', points: 3.0),
        mcq(3, 'C', points: 1.0),
      ]);
      final detected = [det(1, 'A'), det(2, 'X'), det(3, 'C')];

      final results = scoring.scoreAnswers(
          detected: detected, assessment: assessment);

      expect(results[0].isCorrect, isTrue);
      expect(results[0].score, 2.0);
      expect(results[1].isCorrect, isFalse);
      expect(results[1].score, 0);
      expect(results[2].isCorrect, isTrue);
      expect(results[2].score, 1.0);
    });

    test('question types mixed (MCQ + T/F + short)', () {
      final assessment = makeAssessment(questions: [
        mcq(1, 'A'),
        tf(2, 'True'),
        shortAnswer(3, 'gravity'),
      ]);
      final detected = [
        det(1, 'A'),
        det(2, 'True'),
        det(3, 'gravity'),
      ];

      final results = scoring.scoreAnswers(
          detected: detected, assessment: assessment);

      expect(results.every((r) => r.isCorrect), isTrue);
    });

    test('preserves OCR raw text in results', () {
      final assessment = makeAssessment(questions: [mcq(1, 'A')]);
      final detected = [
        const DetectedAnswer(
          questionNumber: 1,
          answer: 'A',
          confidence: 0.85,
          rawText: '1. A ',
        ),
      ];

      final results = scoring.scoreAnswers(
          detected: detected, assessment: assessment);

      expect(results[0].ocrRawText, '1. A ');
      expect(results[0].confidence, 0.85);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // deduplicateAnswers
  // ════════════════════════════════════════════════════════════════

  group('deduplicateAnswers', () {
    test('same question number → keeps highest confidence', () {
      final answers = [
        det(1, 'A', confidence: 0.6),
        det(1, 'A', confidence: 0.9),
        det(1, 'B', confidence: 0.7), // wrong answer but higher than 0.6
      ];

      final result = scoring.deduplicateAnswers(answers);

      expect(result.length, 1);
      expect(result[0].confidence, 0.9);
      expect(result[0].answer, 'A');
    });

    test('different questions → all kept', () {
      final answers = [det(1, 'A'), det(2, 'B'), det(3, 'C')];

      final result = scoring.deduplicateAnswers(answers);

      expect(result.length, 3);
    });

    test('result sorted by question number', () {
      final answers = [det(3, 'C'), det(1, 'A'), det(2, 'B')];

      final result = scoring.deduplicateAnswers(answers);

      expect(result.map((a) => a.questionNumber), [1, 2, 3]);
    });

    test('empty input → empty output', () {
      expect(scoring.deduplicateAnswers([]), isEmpty);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // calculateConfidence
  // ════════════════════════════════════════════════════════════════

  group('calculateConfidence', () {
    test('average of all answers', () {
      final answers = [
        AnswerMatch(
            questionNumber: 1,
            detectedAnswer: 'A',
            correctAnswer: 'A',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.8),
        AnswerMatch(
            questionNumber: 2,
            detectedAnswer: 'B',
            correctAnswer: 'B',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.6),
      ];

      expect(scoring.calculateConfidence(answers), closeTo(0.7, 0.001));
    });

    test('empty → 0', () {
      expect(scoring.calculateConfidence([]), 0);
    });

    test('single answer → its confidence', () {
      final answers = [
        AnswerMatch(
            questionNumber: 1,
            detectedAnswer: 'A',
            correctAnswer: 'A',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.95),
      ];

      expect(scoring.calculateConfidence(answers), closeTo(0.95, 0.001));
    });
  });

  // ════════════════════════════════════════════════════════════════
  // calculateTotalScore
  // ════════════════════════════════════════════════════════════════

  group('calculateTotalScore', () {
    test('sums all scores', () {
      final answers = [
        AnswerMatch(
            questionNumber: 1,
            detectedAnswer: 'A',
            correctAnswer: 'A',
            isCorrect: true,
            score: 2,
            maxScore: 2,
            confidence: 0.9),
        AnswerMatch(
            questionNumber: 2,
            detectedAnswer: 'B',
            correctAnswer: 'X',
            isCorrect: false,
            score: 0,
            maxScore: 3,
            confidence: 0.8),
        AnswerMatch(
            questionNumber: 3,
            detectedAnswer: 'C',
            correctAnswer: 'C',
            isCorrect: true,
            score: 5,
            maxScore: 5,
            confidence: 0.95),
      ];

      expect(scoring.calculateTotalScore(answers), 7.0);
    });

    test('empty → 0', () {
      expect(scoring.calculateTotalScore([]), 0);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // calculatePercentage
  // ════════════════════════════════════════════════════════════════

  group('calculatePercentage', () {
    test('7/10 → 70%', () {
      expect(
        scoring.calculatePercentage(totalScore: 7, maxScore: 10),
        closeTo(70.0, 0.001),
      );
    });

    test('0/10 → 0%', () {
      expect(
        scoring.calculatePercentage(totalScore: 0, maxScore: 10),
        0,
      );
    });

    test('10/10 → 100%', () {
      expect(
        scoring.calculatePercentage(totalScore: 10, maxScore: 10),
        closeTo(100.0, 0.001),
      );
    });

    test('maxScore = 0 → 0 (no division by zero)', () {
      expect(
        scoring.calculatePercentage(totalScore: 5, maxScore: 0),
        0,
      );
    });

    test('negative maxScore → 0', () {
      expect(
        scoring.calculatePercentage(totalScore: 5, maxScore: -1),
        0,
      );
    });
  });

  // ════════════════════════════════════════════════════════════════
  // calculateGrade — MoE National
  // ════════════════════════════════════════════════════════════════

  group('calculateGrade — moe_national', () {
    final cases = <double, String>{
      100: 'A+',
      97: 'A+',
      95: 'A+',
      94: 'A',
      90: 'A',
      89: 'A-',
      85: 'A-',
      84: 'B+',
      80: 'B+',
      79: 'B',
      75: 'B',
      74: 'B-',
      70: 'B-',
      69: 'C+',
      65: 'C+',
      64: 'C',
      60: 'C',
      59: 'C-',
      55: 'C-',
      54: 'D',
      50: 'D',
      49: 'F',
      25: 'F',
      0: 'F',
    };

    for (final entry in cases.entries) {
      test('${entry.key}% → ${entry.value}', () {
        expect(
          scoring.calculateGrade(entry.key, 'moe_national'),
          entry.value,
        );
      });
    }
  });

  // ════════════════════════════════════════════════════════════════
  // calculateGrade — Private International
  // ════════════════════════════════════════════════════════════════

  group('calculateGrade — private_international', () {
    final cases = <double, String>{
      100: 'A*',
      90: 'A*',
      89: 'A',
      80: 'A',
      79: 'B',
      70: 'B',
      69: 'C',
      60: 'C',
      59: 'D',
      50: 'D',
      49: 'F',
      0: 'F',
    };

    for (final entry in cases.entries) {
      test('${entry.key}% → ${entry.value}', () {
        expect(
          scoring.calculateGrade(entry.key, 'private_international'),
          entry.value,
        );
      });
    }
  });

  // ════════════════════════════════════════════════════════════════
  // calculateGrade — University
  // ════════════════════════════════════════════════════════════════

  group('calculateGrade — university', () {
    final cases = <double, String>{
      100: 'A',
      90: 'A',
      89: 'A-',
      85: 'A-',
      84: 'B+',
      80: 'B+',
      79: 'B',
      75: 'B',
      74: 'B-',
      70: 'B-',
      69: 'C+',
      65: 'C+',
      64: 'C',
      60: 'C',
      59: 'C-',
      55: 'C-',
      54: 'D',
      50: 'D',
      49: 'F',
      0: 'F',
    };

    for (final entry in cases.entries) {
      test('${entry.key}% → ${entry.value}', () {
        expect(
          scoring.calculateGrade(entry.key, 'university'),
          entry.value,
        );
      });
    }
  });

  // ════════════════════════════════════════════════════════════════
  // calculateGrade — Edge cases
  // ════════════════════════════════════════════════════════════════

  group('calculateGrade — edge cases', () {
    test('unknown rubric type → falls back to moe_national', () {
      expect(
        scoring.calculateGrade(92, 'some_unknown_rubric'),
        'A',
      );
    });

    test('100.0 → top grade', () {
      expect(scoring.calculateGrade(100.0, 'moe_national'), 'A+');
    });

    test('0.0 → F', () {
      expect(scoring.calculateGrade(0.0, 'moe_national'), 'F');
    });
  });

  // ════════════════════════════════════════════════════════════════
  // End-to-end: full scoring pipeline
  // ════════════════════════════════════════════════════════════════

  group('full scoring pipeline', () {
    test('20-question MCQ assessment, 17 correct → 85% A- (MoE)', () {
      final questions = List.generate(
          20, (i) => mcq(i + 1, 'A', points: 1.0));

      // Student got 17 right, 3 wrong
      final detected = <DetectedAnswer>[];
      for (int i = 1; i <= 20; i++) {
        detected.add(det(i, i <= 17 ? 'A' : 'X'));
      }

      final assessment = makeAssessment(questions: questions);
      final deduped = scoring.deduplicateAnswers(detected);
      final scored = scoring.scoreAnswers(
          detected: deduped, assessment: assessment);
      final total = scoring.calculateTotalScore(scored);
      final pct = scoring.calculatePercentage(
          totalScore: total, maxScore: assessment.maxScore);
      final grade = scoring.calculateGrade(pct, 'moe_national');
      final confidence = scoring.calculateConfidence(scored);

      expect(total, 17.0);
      expect(pct, closeTo(85.0, 0.01));
      expect(grade, 'A-');
      expect(confidence, closeTo(0.9, 0.01));
    });

    test('perfect score → 100% A+ (MoE)', () {
      final questions = List.generate(
          10, (i) => mcq(i + 1, 'B', points: 2.0));
      final detected = List.generate(
          10, (i) => det(i + 1, 'B'));

      final assessment = makeAssessment(questions: questions);
      final scored = scoring.scoreAnswers(
          detected: detected, assessment: assessment);
      final total = scoring.calculateTotalScore(scored);
      final pct = scoring.calculatePercentage(
          totalScore: total, maxScore: assessment.maxScore);

      expect(total, 20.0);
      expect(pct, closeTo(100.0, 0.01));
      expect(scoring.calculateGrade(pct, 'moe_national'), 'A+');
    });

    test('zero score → 0% F', () {
      final questions = [mcq(1, 'A'), mcq(2, 'B')];
      final detected = [det(1, 'Z'), det(2, 'Z')];

      final assessment = makeAssessment(questions: questions);
      final scored = scoring.scoreAnswers(
          detected: detected, assessment: assessment);
      final total = scoring.calculateTotalScore(scored);
      final pct = scoring.calculatePercentage(
          totalScore: total, maxScore: assessment.maxScore);

      expect(total, 0);
      expect(pct, 0);
      expect(scoring.calculateGrade(pct, 'moe_national'), 'F');
    });

    test('mixed types + missing + dedup', () {
      final questions = [
        mcq(1, 'A', points: 1.0),
        tf(2, 'True', points: 1.0),
        shortAnswer(3, 'photosynthesis', points: 3.0),
      ];
      final detected = [
        det(1, 'A'),
        det(2, 'True'),
        // Q3 detected twice — dedup should keep highest confidence
        const DetectedAnswer(
          questionNumber: 3,
          answer: 'photosynthesis',
          confidence: 0.6,
          rawText: '3 photosynthesis',
        ),
        const DetectedAnswer(
          questionNumber: 3,
          answer: 'photosynthesis',
          confidence: 0.95,
          rawText: '3. photosynthesis',
        ),
      ];

      final assessment = makeAssessment(questions: questions);
      final deduped = scoring.deduplicateAnswers(detected);
      expect(deduped.length, 3);

      final scored = scoring.scoreAnswers(
          detected: deduped, assessment: assessment);
      final total = scoring.calculateTotalScore(scored);

      // All correct: 1 + 1 + 3 = 5
      expect(total, 5.0);
      expect(scored.every((s) => s.isCorrect), isTrue);
    });

    test('short answer with multiple accepted answers', () {
      final questions = [
        shortAnswer(1, ['ethiopia', 'ኢትዮጵያ', 'habesha']),
      ];
      final detected = [det(1, 'Ethiopia')]; // case differs

      final assessment = makeAssessment(questions: questions);
      final scored = scoring.scoreAnswers(
          detected: detected, assessment: assessment);

      expect(scored[0].isCorrect, isTrue);
      expect(scored[0].score, 2.0);
    });

    test('different rubrics produce different grades for same score', () {
      // 85% on each scale
      expect(scoring.calculateGrade(85, 'moe_national'), 'A-');
      expect(scoring.calculateGrade(85, 'private_international'), 'A');
      expect(scoring.calculateGrade(85, 'university'), 'A-');
    });
  });
}
