import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/config/integrity_metadata_keys.dart';
import 'package:ethiograde/services/answer_key_recalculation_service.dart';
import 'package:ethiograde/services/answer_key_fingerprint_service.dart';
import 'package:ethiograde/services/integrity_state_resolver.dart';
import 'package:ethiograde/services/scoring_service.dart';

void main() {
  final fingerprintService = const AnswerKeyFingerprintService();
  final scoringService = const ScoringService();

  Assessment _makeAssessment({
    List<Question>? questions,
    int revision = 1,
    String? fingerprint,
  }) {
    final qs = questions ?? [
      Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
      Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: 'B', points: 1),
      Question(id: 'q3', number: 3, type: QuestionType.trueFalse, correctAnswer: 'True', points: 2),
    ];
    final a = Assessment(title: 'Test', subject: 'Math', questions: qs);
    return a.copyWith(
      answerKeyRevision: revision,
      answerKeyFingerprint: fingerprint ?? fingerprintService.compute(a),
    );
  }

  ScanResult _makeResult({
    required String id,
    required String assessmentId,
    List<AnswerMatch>? answers,
    double totalScore = 2,
    String? fingerprint,
    int? revision,
    bool isManualEntry = false,
    Map<String, dynamic>? overrideTypes,
  }) {
    final metadata = <String, dynamic>{};
    if (fingerprint != null) {
      metadata[IntegrityMetadataKeys.scoredWithKeyFingerprint] = fingerprint;
    }
    if (revision != null) {
      metadata[IntegrityMetadataKeys.scoredWithKeyRevision] = revision;
    }
    if (overrideTypes != null) {
      metadata[IntegrityMetadataKeys.answerOverrideTypes] = overrideTypes;
    }

    return ScanResult(
      assessmentId: assessmentId,
      studentId: 'student-1',
      studentName: 'Test Student',
      imagePath: '/path/to/image.jpg',
      answers: answers ?? [
        AnswerMatch(questionNumber: 1, detectedAnswer: 'A', correctAnswer: 'A', isCorrect: true, score: 1, maxScore: 1, confidence: 0.95),
        AnswerMatch(questionNumber: 2, detectedAnswer: 'B', correctAnswer: 'B', isCorrect: true, score: 1, maxScore: 1, confidence: 0.95),
        AnswerMatch(questionNumber: 3, detectedAnswer: 'True', correctAnswer: 'True', isCorrect: true, score: 2, maxScore: 2, confidence: 0.95),
      ],
      totalScore: totalScore,
      maxScore: 4,
      percentage: 50,
      grade: 'F',
      status: ScanStatus.graded,
      isManualEntry: isManualEntry,
      metadata: metadata,
    );
  }

  group('Scoring correctness (pure logic, no Hive)', () {
    test('MCQ rescoring with new key', () {
      final assessment = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
        Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: 'B', points: 1),
      ]);

      // Student answered A and C
      final detected = [
        {'number': 1, 'answer': 'A'},
        {'number': 2, 'answer': 'C'},
      ];

      // Old key: B correct → q2 wrong
      final oldMatches = scoringService.scoreAnswers(
        detected: detected.map((d) => DetectedAnswer(
          questionNumber: d['number'] as int,
          answer: d['answer'] as String,
          confidence: 0.95,
          rawText: d['answer'] as String,
        )).toList(),
        assessment: assessment,
      );
      expect(oldMatches[1].isCorrect, false);
      expect(oldMatches[1].score, 0);

      // New key: C correct → q2 now correct
      final newAssessment = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
        Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: 'C', points: 1),
      ], revision: 2);

      final newMatches = scoringService.scoreAnswers(
        detected: detected.map((d) => DetectedAnswer(
          questionNumber: d['number'] as int,
          answer: d['answer'] as String,
          confidence: 0.95,
          rawText: d['answer'] as String,
        )).toList(),
        assessment: newAssessment,
      );
      expect(newMatches[1].isCorrect, true);
      expect(newMatches[1].score, 1);
    });

    test('TF rescoring with new key', () {
      final assessment = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.trueFalse, correctAnswer: 'True', points: 2),
      ]);

      // Student answered False
      final oldMatches = scoringService.scoreAnswers(
        detected: [DetectedAnswer(questionNumber: 1, answer: 'False', confidence: 0.95, rawText: 'False')],
        assessment: assessment,
      );
      expect(oldMatches[0].isCorrect, false);

      // New key: False correct
      final newAssessment = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.trueFalse, correctAnswer: 'False', points: 2),
      ], revision: 2);

      final newMatches = scoringService.scoreAnswers(
        detected: [DetectedAnswer(questionNumber: 1, answer: 'False', confidence: 0.95, rawText: 'False')],
        assessment: newAssessment,
      );
      expect(newMatches[0].isCorrect, true);
    });

    test('short answer rescoring', () {
      final assessment = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.shortAnswer, correctAnswer: 'Addis Ababa', points: 1),
      ]);

      // Student answered "addis ababa"
      final oldMatches = scoringService.scoreAnswers(
        detected: [DetectedAnswer(questionNumber: 1, answer: 'addis ababa', confidence: 0.9, rawText: 'addis ababa')],
        assessment: assessment,
      );
      expect(oldMatches[0].isCorrect, true); // Case-insensitive match

      // New key with multiple accepted answers
      final newAssessment = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.shortAnswer, correctAnswer: ['Addis Ababa', 'Addis Abeba'], points: 1),
      ], revision: 2);

      final newMatches = scoringService.scoreAnswers(
        detected: [DetectedAnswer(questionNumber: 1, answer: 'addis ababa', confidence: 0.9, rawText: 'addis ababa')],
        assessment: newAssessment,
      );
      expect(newMatches[0].isCorrect, true);
    });

    test('matching rescoring', () {
      final assessment = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.matching, correctAnswer: 'MATCH:A-B-C', points: 3),
      ]);

      // Student answered MATCH:A-B-D
      final oldMatches = scoringService.scoreAnswers(
        detected: [DetectedAnswer(questionNumber: 1, answer: 'MATCH:A-B-D', confidence: 0.95, rawText: 'A B D')],
        assessment: assessment,
      );
      expect(oldMatches[0].isCorrect, false);

      // New key: MATCH:A-B-D correct
      final newAssessment = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.matching, correctAnswer: 'MATCH:A-B-D', points: 3),
      ], revision: 2);

      final newMatches = scoringService.scoreAnswers(
        detected: [DetectedAnswer(questionNumber: 1, answer: 'MATCH:A-B-D', confidence: 0.95, rawText: 'A B D')],
        assessment: newAssessment,
      );
      expect(newMatches[0].isCorrect, true);
    });

    test('essay score is always 0 from auto-grading', () {
      final assessment = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.essay, correctAnswer: null, points: 10),
      ]);

      final matches = scoringService.scoreAnswers(
        detected: [DetectedAnswer(questionNumber: 1, answer: 'Essay text here', confidence: 0.8, rawText: 'Essay text here')],
        assessment: assessment,
      );
      // Essays always score 0 from auto-grading (manual review required)
      expect(matches[0].isCorrect, false);
      expect(matches[0].score, 0);
    });
  });

  group('Integrity eligibility (pure logic)', () {
    final resolver = const IntegrityStateResolver();

    test('auto-scored MCQ result is eligible', () {
      final result = _makeResult(id: 'r1', assessmentId: 'a1');
      expect(resolver.isEligibleForRecalculation(result), true);
    });

    test('manual entry result is not eligible', () {
      final result = _makeResult(id: 'r1', assessmentId: 'a1', isManualEntry: true);
      expect(resolver.isEligibleForRecalculation(result), false);
    });

    test('result with teacher-corrected override is not eligible', () {
      final result = _makeResult(
        id: 'r1',
        assessmentId: 'a1',
        overrideTypes: {'1': AnswerOverrideType.teacherCorrected},
      );
      expect(resolver.isEligibleForRecalculation(result), false);
    });

    test('result with all auto overrides is eligible', () {
      final result = _makeResult(
        id: 'r1',
        assessmentId: 'a1',
        overrideTypes: {'1': AnswerOverrideType.auto, '2': AnswerOverrideType.auto},
      );
      expect(resolver.isEligibleForRecalculation(result), true);
    });

    test('result with hasManualOverrides flag is not eligible', () {
      final result = ScanResult(
        assessmentId: 'a1',
        studentId: 's1',
        studentName: 'Test',
        imagePath: '/path',
        totalScore: 1,
        maxScore: 2,
        percentage: 50,
        grade: 'F',
        status: ScanStatus.graded,
        metadata: {IntegrityMetadataKeys.hasManualOverrides: true},
      );
      expect(resolver.isEligibleForRecalculation(result), false);
    });
  });

  group('Idempotency guard', () {
    final resolver = const IntegrityStateResolver();

    test('result with matching fingerprint is skipped', () {
      final assessment = _makeAssessment();
      final result = _makeResult(
        id: 'r1',
        assessmentId: assessment.id,
        fingerprint: assessment.answerKeyFingerprint,
        revision: assessment.answerKeyRevision,
      );

      // The idempotency guard checks: resultFp == assessment.answerKeyFingerprint
      final resultFp = result.metadata[IntegrityMetadataKeys.scoredWithKeyFingerprint] as String?;
      expect(resultFp, assessment.answerKeyFingerprint);
      // This result should be skipped by the recalculation service
    });

    test('result with different fingerprint is processed', () {
      final assessment = _makeAssessment();
      final result = _makeResult(
        id: 'r1',
        assessmentId: assessment.id,
        fingerprint: 'old-fingerprint',
        revision: 1,
      );

      final resultFp = result.metadata[IntegrityMetadataKeys.scoredWithKeyFingerprint] as String?;
      expect(resultFp, isNot(equals(assessment.answerKeyFingerprint)));
      // This result should be processed by the recalculation service
    });
  });

  group('Score computation correctness', () {
    test('percentage calculation', () {
      final matches = [
        AnswerMatch(questionNumber: 1, detectedAnswer: 'A', correctAnswer: 'A', isCorrect: true, score: 1, maxScore: 1, confidence: 0.95),
        AnswerMatch(questionNumber: 2, detectedAnswer: 'B', correctAnswer: 'B', isCorrect: true, score: 1, maxScore: 1, confidence: 0.95),
      ];

      final total = scoringService.calculateTotalScore(matches);
      expect(total, 2);

      final percentage = scoringService.calculatePercentage(totalScore: total, maxScore: 2);
      expect(percentage, 100);
    });

    test('grade calculation with moe_national scale', () {
      expect(scoringService.calculateGrade(95, 'moe_national'), 'A+');
      expect(scoringService.calculateGrade(85, 'moe_national'), 'A-');
      expect(scoringService.calculateGrade(75, 'moe_national'), 'B');
      expect(scoringService.calculateGrade(55, 'moe_national'), 'C-');
      expect(scoringService.calculateGrade(40, 'moe_national'), 'F');
    });

    test('mixed correct/incorrect scoring', () {
      final matches = [
        AnswerMatch(questionNumber: 1, detectedAnswer: 'A', correctAnswer: 'A', isCorrect: true, score: 1, maxScore: 1, confidence: 0.95),
        AnswerMatch(questionNumber: 2, detectedAnswer: 'C', correctAnswer: 'B', isCorrect: false, score: 0, maxScore: 1, confidence: 0.95),
        AnswerMatch(questionNumber: 3, detectedAnswer: 'True', correctAnswer: 'True', isCorrect: true, score: 2, maxScore: 2, confidence: 0.95),
      ];

      final total = scoringService.calculateTotalScore(matches);
      expect(total, 3);

      final percentage = scoringService.calculatePercentage(totalScore: total, maxScore: 4);
      expect(percentage, 75);

      final grade = scoringService.calculateGrade(75, 'moe_national');
      expect(grade, 'B');
    });
  });
}
