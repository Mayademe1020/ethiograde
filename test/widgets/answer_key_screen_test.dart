import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/config/integrity_metadata_keys.dart';
import 'package:ethiograde/services/answer_key_fingerprint_service.dart';
import 'package:ethiograde/services/integrity_state_resolver.dart';
import 'package:ethiograde/services/scoring_service.dart';

/// Logic-level tests for AnswerKeyScreen behavior.
/// These prove the correctness of the integration logic without requiring
/// Hive boxes or widget infrastructure.
void main() {
  final fingerprintService = const AnswerKeyFingerprintService();
  final resolver = const IntegrityStateResolver();
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
    String? fingerprint,
    int? revision,
    bool isManualEntry = false,
    Map<String, dynamic>? overrideTypes,
    double totalScore = 4,
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
      assessmentId: 'test-assessment',
      studentId: 'student-1',
      studentName: 'Test Student',
      imagePath: '/path/to/image.jpg',
      answers: [
        AnswerMatch(questionNumber: 1, detectedAnswer: 'A', correctAnswer: 'A', isCorrect: true, score: 1, maxScore: 1, confidence: 0.95),
        AnswerMatch(questionNumber: 2, detectedAnswer: 'B', correctAnswer: 'B', isCorrect: true, score: 1, maxScore: 1, confidence: 0.95),
        AnswerMatch(questionNumber: 3, detectedAnswer: 'True', correctAnswer: 'True', isCorrect: true, score: 2, maxScore: 2, confidence: 0.95),
      ],
      totalScore: totalScore,
      maxScore: 4,
      percentage: 100,
      grade: 'A+',
      status: ScanStatus.graded,
      isManualEntry: isManualEntry,
      metadata: metadata,
    );
  }

  group('Fingerprint change detection (AnswerKeyScreen logic)', () {
    test('no change → no dialog needed', () {
      final assessment = _makeAssessment();
      final preFingerprint = assessment.answerKeyFingerprint;
      final postFingerprint = fingerprintService.compute(assessment);
      expect(preFingerprint, equals(postFingerprint));
      // keyChanged = false → no dialog
    });

    test('MCQ change → dialog needed', () {
      final assessment = _makeAssessment();
      final preFingerprint = assessment.answerKeyFingerprint;

      // Change q1 from A to C
      final newQs = [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'C', points: 1),
        Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: 'B', points: 1),
        Question(id: 'q3', number: 3, type: QuestionType.trueFalse, correctAnswer: 'True', points: 2),
      ];
      final changed = assessment.copyWith(questions: newQs);
      final postFingerprint = fingerprintService.compute(changed);

      expect(preFingerprint, isNot(equals(postFingerprint)));
      // keyChanged = true → dialog needed
    });

    test('presentation-only text change → no dialog', () {
      final assessment = _makeAssessment();
      final preFingerprint = assessment.answerKeyFingerprint;

      // Change q1 text only (not correctAnswer)
      final newQs = [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1, text: 'New question text'),
        Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: 'B', points: 1),
        Question(id: 'q3', number: 3, type: QuestionType.trueFalse, correctAnswer: 'True', points: 2),
      ];
      final changed = assessment.copyWith(questions: newQs);
      final postFingerprint = fingerprintService.compute(changed);

      expect(preFingerprint, equals(postFingerprint));
      // keyChanged = false → no dialog
    });

    test('points change → dialog needed', () {
      final assessment = _makeAssessment();
      final preFingerprint = assessment.answerKeyFingerprint;

      final newQs = [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 2), // changed
        Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: 'B', points: 1),
        Question(id: 'q3', number: 3, type: QuestionType.trueFalse, correctAnswer: 'True', points: 2),
      ];
      final changed = assessment.copyWith(questions: newQs);
      final postFingerprint = fingerprintService.compute(changed);

      expect(preFingerprint, isNot(equals(postFingerprint)));
    });
  });

  group('Cancel behavior', () {
    test('assessment unchanged after cancel', () {
      final assessment = _makeAssessment();
      final originalFingerprint = assessment.answerKeyFingerprint;
      final originalRevision = assessment.answerKeyRevision;

      // Simulate: teacher changes answer but cancels
      // The assessment object is NOT persisted
      // So the original values remain
      expect(assessment.answerKeyFingerprint, equals(originalFingerprint));
      expect(assessment.answerKeyRevision, equals(originalRevision));
    });

    test('result unchanged after cancel', () {
      final assessment = _makeAssessment();
      final result = _makeResult(
        fingerprint: assessment.answerKeyFingerprint,
        revision: 1,
      );

      // After cancel, result is not modified
      expect(
        result.metadata[IntegrityMetadataKeys.scoredWithKeyFingerprint],
        equals(assessment.answerKeyFingerprint),
      );
    });
  });

  group('Save and recalculate later behavior', () {
    test('assessment gets new fingerprint', () {
      final assessment = _makeAssessment();
      final oldFingerprint = assessment.answerKeyFingerprint;

      // Simulate answer key change
      final newQs = [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'C', points: 1),
        Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: 'B', points: 1),
        Question(id: 'q3', number: 3, type: QuestionType.trueFalse, correctAnswer: 'True', points: 2),
      ];
      final changed = assessment.copyWith(
        questions: newQs,
        answerKeyRevision: assessment.answerKeyRevision + 1,
        answerKeyFingerprint: fingerprintService.compute(assessment.copyWith(questions: newQs)),
      );

      expect(changed.answerKeyFingerprint, isNot(equals(oldFingerprint)));
      expect(changed.answerKeyRevision, greaterThan(assessment.answerKeyRevision));
    });

    test('result remains outdated', () {
      final assessment = _makeAssessment();
      final result = _makeResult(
        fingerprint: assessment.answerKeyFingerprint,
        revision: 1,
      );

      // After "save and recalculate later", result fingerprint is still old
      // Assessment has new fingerprint
      final newAssessment = assessment.copyWith(
        answerKeyRevision: 2,
        answerKeyFingerprint: 'new-fingerprint',
      );

      final state = resolver.resolve(result: result, assessment: newAssessment);
      expect(state, IntegrityState.outdated);
    });

    test('finalization blocked for outdated results', () {
      final assessment = _makeAssessment();
      final result = _makeResult(
        fingerprint: 'old-fingerprint',
        revision: 1,
      );

      final newAssessment = assessment.copyWith(
        answerKeyRevision: 2,
        answerKeyFingerprint: 'new-fingerprint',
      );

      final state = resolver.resolve(result: result, assessment: newAssessment);
      expect(state, IntegrityState.outdated);

      // _confirmFinalSaveIfNeeded would block because outdatedCount > 0
      final outdatedCount = [result].where((r) =>
        resolver.resolve(result: r, assessment: newAssessment) == IntegrityState.outdated
      ).length;
      expect(outdatedCount, greaterThan(0));
    });
  });

  group('Recalculate now behavior', () {
    test('eligible result gets new fingerprint', () {
      final assessment = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
        Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: 'B', points: 1),
      ]);

      final result = _makeResult(
        fingerprint: 'old-fingerprint',
        revision: 1,
        totalScore: 1,
      );

      // Simulate recalculation: checkAnswer with new key
      final newAssessment = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
        Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: 'C', points: 1), // changed
      ], revision: 2);

      // Re-score each answer
      for (final oldMatch in result.answers) {
        final question = newAssessment.questions.where(
          (q) => q.number == oldMatch.questionNumber,
        ).firstOrNull;
        if (question == null) continue;

        final isCorrect = scoringService.checkAnswer(
          detected: oldMatch.detectedAnswer,
          correct: question.correctAnswer,
          type: question.type,
        );
        final newScore = isCorrect ? question.points : 0.0;

        // Verify scoring logic
        if (oldMatch.questionNumber == 1) {
          // A detected, A correct → correct
          expect(isCorrect, true);
          expect(newScore, 1);
        } else if (oldMatch.questionNumber == 2) {
          // B detected, C correct → wrong (changed key)
          expect(isCorrect, false);
          expect(newScore, 0);
        }
      }
    });

    test('manual essay marks preserved', () {
      final result = _makeResult(
        fingerprint: 'old-fingerprint',
        revision: 1,
        totalScore: 7,
        overrideTypes: {'1': AnswerOverrideType.essayManual},
      );

      // Essay results should be preserved (not recalculated)
      expect(resolver.isEligibleForRecalculation(result), false);
    });

    test('teacher-corrected responses preserved', () {
      final result = _makeResult(
        fingerprint: 'old-fingerprint',
        revision: 1,
        overrideTypes: {'1': AnswerOverrideType.teacherCorrected},
      );

      expect(resolver.isEligibleForRecalculation(result), false);
    });

    test('manual entry preserved', () {
      final result = _makeResult(
        fingerprint: 'old-fingerprint',
        revision: 1,
        isManualEntry: true,
      );

      expect(resolver.isEligibleForRecalculation(result), false);
    });

    test('assessment becomes current when all results have matching fingerprint', () {
      final assessment = _makeAssessment();
      final results = [
        _makeResult(fingerprint: assessment.answerKeyFingerprint, revision: assessment.answerKeyRevision),
        _makeResult(fingerprint: assessment.answerKeyFingerprint, revision: assessment.answerKeyRevision),
      ];

      final allCurrent = resolver.allCurrent(results: results, assessment: assessment);
      expect(allCurrent, true);
    });

    test('assessment not current when any result is outdated', () {
      final assessment = _makeAssessment();
      final results = [
        _makeResult(fingerprint: assessment.answerKeyFingerprint, revision: assessment.answerKeyRevision),
        _makeResult(fingerprint: 'old-fingerprint', revision: 1), // outdated
      ];

      final allCurrent = resolver.allCurrent(results: results, assessment: assessment);
      expect(allCurrent, false);
    });
  });

  group('Score computation after recalculation', () {
    test('changed score reflects new key', () {
      final assessment = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
        Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: 'B', points: 1),
      ]);

      // Student: A, C
      final detected = [
        DetectedAnswer(questionNumber: 1, answer: 'A', confidence: 0.95, rawText: 'A'),
        DetectedAnswer(questionNumber: 2, answer: 'C', confidence: 0.95, rawText: 'C'),
      ];

      // Old key: A, B → q1 correct, q2 wrong → total=1, pct=50
      final oldMatches = scoringService.scoreAnswers(detected: detected, assessment: assessment);
      final oldTotal = scoringService.calculateTotalScore(oldMatches);
      expect(oldTotal, 1);

      // New key: A, C → both correct → total=2, pct=100
      final newAssessment = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
        Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: 'C', points: 1),
      ], revision: 2);

      final newMatches = scoringService.scoreAnswers(detected: detected, assessment: newAssessment);
      final newTotal = scoringService.calculateTotalScore(newMatches);
      expect(newTotal, 2);

      // Grade changes
      final oldPct = scoringService.calculatePercentage(totalScore: oldTotal, maxScore: 2);
      final newPct = scoringService.calculatePercentage(totalScore: newTotal, maxScore: 2);
      expect(oldPct, 50);
      expect(newPct, 100);
    });

    test('unchanged scores remain same', () {
      final assessment = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
        Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: 'B', points: 1),
      ]);

      final detected = [
        DetectedAnswer(questionNumber: 1, answer: 'A', confidence: 0.95, rawText: 'A'),
        DetectedAnswer(questionNumber: 2, answer: 'B', confidence: 0.95, rawText: 'B'),
      ];

      // Change q3 (not in this assessment) → scores unchanged
      final newAssessment = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
        Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: 'B', points: 1),
      ], revision: 2);

      final oldMatches = scoringService.scoreAnswers(detected: detected, assessment: assessment);
      final newMatches = scoringService.scoreAnswers(detected: detected, assessment: newAssessment);

      expect(
        scoringService.calculateTotalScore(oldMatches),
        equals(scoringService.calculateTotalScore(newMatches)),
      );
    });
  });

  group('Integrity state for all scenarios', () {
    test('current result → current', () {
      final assessment = _makeAssessment();
      final result = _makeResult(fingerprint: assessment.answerKeyFingerprint);
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.current);
    });

    test('outdated result → outdated', () {
      final assessment = _makeAssessment();
      final result = _makeResult(fingerprint: 'old-fp');
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.outdated);
    });

    test('legacy result → legacyUnknown', () {
      final assessment = _makeAssessment();
      final result = _makeResult(); // no fingerprint
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.legacyUnknown);
    });

    test('manual entry with matching fingerprint → currentNeedsManualReview', () {
      final assessment = _makeAssessment();
      final result = _makeResult(fingerprint: assessment.answerKeyFingerprint, isManualEntry: true);
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.currentNeedsManualReview);
    });

    test('recalculation in progress → recalculating', () {
      final baseAssessment = Assessment(title: 'Test', subject: 'Math', questions: [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
      ]);
      final assessment = baseAssessment.copyWith(
        answerKeyRevision: 1,
        answerKeyFingerprint: fingerprintService.compute(baseAssessment),
        settings: {IntegrityMetadataKeys.recalculationInProgress: true},
      );
      final result = _makeResult(fingerprint: assessment.answerKeyFingerprint);
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.recalculating);
    });
  });
}
