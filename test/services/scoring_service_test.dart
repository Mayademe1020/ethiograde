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

  // ════════════════════════════════════════════════════════════════
  // generateAnswerFingerprint
  // ════════════════════════════════════════════════════════════════

  group('generateAnswerFingerprint', () {
    test('basic MCQ answers', () {
      final answers = [
        AnswerMatch(
            questionNumber: 1,
            detectedAnswer: 'A',
            correctAnswer: 'A',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.9),
        AnswerMatch(
            questionNumber: 2,
            detectedAnswer: 'B',
            correctAnswer: 'B',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.8),
        AnswerMatch(
            questionNumber: 3,
            detectedAnswer: 'C',
            correctAnswer: 'C',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.85),
      ];

      expect(scoring.generateAnswerFingerprint(answers), '1:A|2:B|3:C');
    });

    test('answers sorted by question number regardless of input order', () {
      final answers = [
        AnswerMatch(
            questionNumber: 3,
            detectedAnswer: 'C',
            correctAnswer: 'C',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.9),
        AnswerMatch(
            questionNumber: 1,
            detectedAnswer: 'A',
            correctAnswer: 'A',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.9),
        AnswerMatch(
            questionNumber: 2,
            detectedAnswer: 'B',
            correctAnswer: 'B',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.9),
      ];

      expect(scoring.generateAnswerFingerprint(answers), '1:A|2:B|3:C');
    });

    test('answers uppercased for comparison', () {
      final answers = [
        AnswerMatch(
            questionNumber: 1,
            detectedAnswer: 'a',
            correctAnswer: 'A',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.9),
      ];

      expect(scoring.generateAnswerFingerprint(answers), '1:A');
    });

    test('True/False answers normalized', () {
      final answers = [
        AnswerMatch(
            questionNumber: 1,
            detectedAnswer: 'True',
            correctAnswer: 'True',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.9),
        AnswerMatch(
            questionNumber: 2,
            detectedAnswer: 'false',
            correctAnswer: 'False',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.9),
      ];

      expect(scoring.generateAnswerFingerprint(answers), '1:TRUE|2:FALSE');
    });

    test('MISSING answers excluded from fingerprint', () {
      final answers = [
        AnswerMatch(
            questionNumber: 1,
            detectedAnswer: 'A',
            correctAnswer: 'A',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.9),
        AnswerMatch(
            questionNumber: 2,
            detectedAnswer: '[MISSING]',
            correctAnswer: 'B',
            isCorrect: false,
            score: 0,
            maxScore: 1,
            confidence: 0),
      ];

      expect(scoring.generateAnswerFingerprint(answers), '1:A');
    });

    test('empty answers → empty string', () {
      expect(scoring.generateAnswerFingerprint([]), '');
    });

    test('deterministic — same input always produces same output', () {
      final answers = [det(1, 'A'), det(2, 'B')];
      final fp1 = scoring.generateAnswerFingerprint(answers);
      final fp2 = scoring.generateAnswerFingerprint(answers);
      expect(fp1, fp2);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // compareFingerprints
  // ════════════════════════════════════════════════════════════════

  group('compareFingerprints', () {
    test('identical fingerprints → 1.0', () {
      final ratio = scoring.compareFingerprints('1:A|2:B|3:C', '1:A|2:B|3:C');
      expect(ratio, closeTo(1.0, 0.001));
    });

    test('all different → 0.0', () {
      final ratio = scoring.compareFingerprints('1:A|2:B', '1:D|2:E');
      expect(ratio, closeTo(0.0, 0.001));
    });

    test('partial match — 2 of 3 same', () {
      final ratio = scoring.compareFingerprints('1:A|2:B|3:C', '1:A|2:B|3:D');
      expect(ratio, closeTo(2.0 / 3.0, 0.001));
    });

    test('empty fingerprint → 0.0', () {
      expect(scoring.compareFingerprints('', '1:A'), 0.0);
      expect(scoring.compareFingerprints('1:A', ''), 0.0);
      expect(scoring.compareFingerprints('', ''), 0.0);
    });

    test('different question sets — only common compared', () {
      // fp1 has Q1,Q2; fp2 has Q1,Q3 — only Q1 is common
      final ratio = scoring.compareFingerprints('1:A|2:B', '1:A|3:C');
      expect(ratio, closeTo(1.0, 0.001)); // 1/1 common questions match
    });

    test('case-insensitive comparison (fingerprints are uppercased)', () {
      final ratio = scoring.compareFingerprints('1:A|2:B', '1:a|2:b');
      // Both should be uppercased by the fingerprint generator,
      // but if passed raw they'd be compared as-is
      expect(ratio, closeTo(1.0, 0.001));
    });

    test('no common questions → 0.0', () {
      final ratio = scoring.compareFingerprints('1:A|2:B', '3:C|4:D');
      expect(ratio, 0.0);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // detectAnswerDuplicates
  // ════════════════════════════════════════════════════════════════

  group('detectAnswerDuplicates', () {
    test('identical answer sets → detected', () {
      final answers1 = [det(1, 'A'), det(2, 'B'), det(3, 'C')];
      final answers2 = [det(1, 'A'), det(2, 'B'), det(3, 'C')];

      final result = scoring.detectAnswerDuplicates([answers1, answers2]);

      expect(result.length, 1);
      expect(result[0].scanIndexA, 0);
      expect(result[0].scanIndexB, 1);
      expect(result[0].matchRatio, closeTo(1.0, 0.001));
    });

    test('different answer sets → no duplicate', () {
      final answers1 = [det(1, 'A'), det(2, 'B'), det(3, 'C')];
      final answers2 = [det(1, 'D'), det(2, 'E'), det(3, 'A')];

      final result = scoring.detectAnswerDuplicates([answers1, answers2]);

      expect(result, isEmpty);
    });

    test('90% match (threshold default) → detected', () {
      // 10 questions, 9 match, 1 different
      final answers1 = List.generate(10, (i) => det(i + 1, 'A'));
      final answers2 = List.generate(9, (i) => det(i + 1, 'A'))
        ..add(det(10, 'B'));

      final result = scoring.detectAnswerDuplicates([answers1, answers2]);

      expect(result.length, 1);
      expect(result[0].matchRatio, closeTo(0.9, 0.001));
    });

    test('89% match (below threshold) → not detected', () {
      // 9 questions: 8 match, 1 different → 8/9 ≈ 88.9%
      final answers1 = List.generate(9, (i) => det(i + 1, 'A'));
      final answers2 = List.generate(8, (i) => det(i + 1, 'A'))
        ..add(det(9, 'B'));

      final result = scoring.detectAnswerDuplicates([answers1, answers2]);

      expect(result, isEmpty);
    });

    test('custom threshold works', () {
      // 50% match
      final answers1 = [det(1, 'A'), det(2, 'B')];
      final answers2 = [det(1, 'A'), det(2, 'Z')];

      // At 50% threshold → detected
      final result50 = scoring.detectAnswerDuplicates(
        [answers1, answers2],
        threshold: 0.5,
      );
      expect(result50.length, 1);

      // At 51% threshold → not detected
      final result51 = scoring.detectAnswerDuplicates(
        [answers1, answers2],
        threshold: 0.51,
      );
      expect(result51, isEmpty);
    });

    test('3 scans, 2 duplicates → 1 pair detected', () {
      final answers1 = [det(1, 'A'), det(2, 'B')];
      final answers2 = [det(1, 'A'), det(2, 'B')]; // dup of 1
      final answers3 = [det(1, 'D'), det(2, 'E')]; // different

      final result = scoring.detectAnswerDuplicates([answers1, answers2, answers3]);

      expect(result.length, 1);
      expect(result[0].scanIndexA, 0);
      expect(result[0].scanIndexB, 1);
    });

    test('3 scans, all identical → 3 pairs detected', () {
      final answers = [det(1, 'A'), det(2, 'B')];

      final result = scoring.detectAnswerDuplicates([answers, answers, answers]);

      // Pairs: (0,1), (0,2), (1,2)
      expect(result.length, 3);
    });

    test('empty list → no duplicates', () {
      expect(scoring.detectAnswerDuplicates([]), isEmpty);
    });

    test('single scan → no duplicates', () {
      final answers = [det(1, 'A')];
      expect(scoring.detectAnswerDuplicates([answers]), isEmpty);
    });

    test('empty answers in one scan → skipped', () {
      final answers1 = [det(1, 'A')];
      final answers2 = <DetectedAnswer>[];

      final result = scoring.detectAnswerDuplicates([answers1, answers2]);

      expect(result, isEmpty);
    });

    test('matchPercent helper', () {
      const dup = AnswerDuplicate(
        scanIndexA: 0,
        scanIndexB: 1,
        matchRatio: 0.975,
      );
      expect(dup.matchPercent, closeTo(97.5, 0.001));
    });

    test('re-scans with slight OCR variance still detected', () {
      // Same paper re-scanned: most answers match, one OCR reads "B" instead of "A"
      final original = [det(1, 'A'), det(2, 'B'), det(3, 'C'), det(4, 'A'),
                        det(5, 'B'), det(6, 'C'), det(7, 'A'), det(8, 'B'),
                        det(9, 'C'), det(10, 'A')];
      final rescan = [det(1, 'A'), det(2, 'B'), det(3, 'C'), det(4, 'A'),
                      det(5, 'B'), det(6, 'C'), det(7, 'B'), // 1 error
                      det(8, 'B'), det(9, 'C'), det(10, 'A')];

      final result = scoring.detectAnswerDuplicates([original, rescan]);

      expect(result.length, 1);
      expect(result[0].matchRatio, closeTo(0.9, 0.001)); // 9/10
    });
  });
}

  group('ScanResult.checkAlignment', () {
    ScanResult _makeResult(List<AnswerMatch> answers) {
      return ScanResult(
        assessmentId: 'test',
        studentId: 's1',
        studentName: 'Test',
        imagePath: '',
        answers: answers,
      );
    }

    AnswerMatch _match(int num, String detected) => AnswerMatch(
          questionNumber: num,
          detectedAnswer: detected,
          correctAnswer: 'A',
          isCorrect: detected == 'A',
          score: detected == 'A' ? 1 : 0,
          maxScore: 1,
        );

    test('no missing answers — no warning', () {
      final result = _makeResult([
        _match(1, 'A'), _match(2, 'B'), _match(3, 'A'),
      ]);
      final check = result.checkAlignment(3);
      expect(check.needsWarning, false);
      expect(check.missingCount, 0);
      expect(check.detectedObjective, 3);
    });

    test('few missing (< 20%) — no warning', () {
      final result = _makeResult([
        _match(1, 'A'), _match(2, 'B'), _match(3, 'A'),
        _match(4, '[MISSING]'), _match(5, 'C'),
      ]);
      final check = result.checkAlignment(5);
      expect(check.needsWarning, false);
      expect(check.missingCount, 1);
    });

    test('many missing (> 20%) — warning', () {
      final result = _makeResult([
        _match(1, 'A'), _match(2, 'B'),
        _match(3, '[MISSING]'), _match(4, '[MISSING]'),
        _match(5, '[MISSING]'),
      ]);
      final check = result.checkAlignment(5);
      expect(check.needsWarning, true);
      expect(check.missingCount, 3);
      expect(check.detectedObjective, 2);
      expect(check.missingRatio, 0.6);
    });

    test('all missing — warning', () {
      final result = _makeResult([
        _match(1, '[MISSING]'), _match(2, '[MISSING]'),
      ]);
      final check = result.checkAlignment(2);
      expect(check.needsWarning, true);
      expect(check.missingCount, 2);
      expect(check.missingRatio, 1.0);
    });

    test('zero expected — no warning', () {
      final result = _makeResult([_match(1, 'A')]);
      final check = result.checkAlignment(0);
      expect(check.needsWarning, false);
    });

    test('empty answers — no warning', () {
      final result = _makeResult([]);
      final check = result.checkAlignment(10);
      expect(check.needsWarning, false);
    });
  });
}
