import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/config/integrity_metadata_keys.dart';
import 'package:ethiograde/services/integrity_state_resolver.dart';
import 'package:ethiograde/services/answer_key_fingerprint_service.dart';

void main() {
  const resolver = IntegrityStateResolver();
  const fingerprintService = AnswerKeyFingerprintService();

  Assessment makeAssessment({
    String? fingerprint,
    int revision = 1,
    Map<String, dynamic>? settings,
  }) {
    final questions = [
      Question(number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
      Question(number: 2, type: QuestionType.mcq, correctAnswer: 'B', points: 1),
    ];
    final assessment = Assessment(
      title: 'Test',
      subject: 'Math',
      questions: questions,
    );
    return assessment.copyWith(
      answerKeyRevision: revision,
      answerKeyFingerprint: fingerprint ?? fingerprintService.compute(assessment),
      settings: settings ?? {},
    );
  }

  ScanResult makeResult({
    String? fingerprint,
    int? revision,
    bool isManualEntry = false,
    bool hasManualOverrides = false,
    bool finalScoreManuallySet = false,
    Map<String, dynamic>? overrideTypes,
  }) {
    final metadata = <String, dynamic>{};
    if (fingerprint != null) {
      metadata[IntegrityMetadataKeys.scoredWithKeyFingerprint] = fingerprint;
    }
    if (revision != null) {
      metadata[IntegrityMetadataKeys.scoredWithKeyRevision] = revision;
    }
    if (hasManualOverrides) {
      metadata[IntegrityMetadataKeys.hasManualOverrides] = true;
    }
    if (finalScoreManuallySet) {
      metadata[IntegrityMetadataKeys.finalScoreManuallySet] = true;
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
      ],
      totalScore: 1,
      maxScore: 2,
      percentage: 50,
      grade: 'F',
      status: ScanStatus.graded,
      isManualEntry: isManualEntry,
      metadata: metadata,
    );
  }

  group('IntegrityStateResolver', () {
    test('matching fingerprint → current', () {
      final assessment = makeAssessment();
      final result = makeResult(fingerprint: assessment.answerKeyFingerprint);
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.current);
    });

    test('missing fingerprint on result → legacyUnknown', () {
      final assessment = makeAssessment();
      final result = makeResult(); // no fingerprint
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.legacyUnknown);
    });

    test('mismatched fingerprint → outdated', () {
      final assessment = makeAssessment();
      final result = makeResult(fingerprint: 'wrong-fingerprint-value');
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.outdated);
    });

    test('manual entry → current', () {
      final assessment = makeAssessment();
      final result = makeResult(fingerprint: assessment.answerKeyFingerprint, isManualEntry: true);
      // Manual entry with matching fingerprint is still current (just needs manual review)
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.currentNeedsManualReview);
    });

    test('has manual overrides → currentNeedsManualReview', () {
      final assessment = makeAssessment();
      final result = makeResult(
        fingerprint: assessment.answerKeyFingerprint,
        hasManualOverrides: true,
      );
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.currentNeedsManualReview);
    });

    test('final score manually set → currentNeedsManualReview', () {
      final assessment = makeAssessment();
      final result = makeResult(
        fingerprint: assessment.answerKeyFingerprint,
        finalScoreManuallySet: true,
      );
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.currentNeedsManualReview);
    });

    test('assessment with recalculation in progress → recalculating', () {
      final assessment = makeAssessment(settings: {
        IntegrityMetadataKeys.recalculationInProgress: true,
      });
      final result = makeResult(fingerprint: assessment.answerKeyFingerprint);
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.recalculating);
    });

    test('assessment with recalculation failed → recalculationFailed', () {
      final assessment = makeAssessment(settings: {
        IntegrityMetadataKeys.recalculationFailed: true,
      });
      final result = makeResult(fingerprint: assessment.answerKeyFingerprint);
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.recalculationFailed);
    });

    test('both missing fingerprints → current (legacy baseline)', () {
      final assessment = makeAssessment(fingerprint: '');
      final result = makeResult(); // no fingerprint
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.current);
    });
  });

  group('isEligibleForRecalculation', () {
    test('auto-scored result is eligible', () {
      final result = makeResult();
      expect(resolver.isEligibleForRecalculation(result), isTrue);
    });

    test('manual entry is not eligible', () {
      final result = makeResult(isManualEntry: true);
      expect(resolver.isEligibleForRecalculation(result), isFalse);
    });

    test('result with manual overrides is not eligible', () {
      final result = makeResult(hasManualOverrides: true);
      expect(resolver.isEligibleForRecalculation(result), isFalse);
    });

    test('result with final score manually set is not eligible', () {
      final result = makeResult(finalScoreManuallySet: true);
      expect(resolver.isEligibleForRecalculation(result), isFalse);
    });

    test('result with teacher-corrected answers is not eligible', () {
      final result = makeResult(overrideTypes: {
        '1': AnswerOverrideType.teacherCorrected,
        '2': AnswerOverrideType.auto,
      });
      expect(resolver.isEligibleForRecalculation(result), isFalse);
    });

    test('result with all auto overrides is eligible', () {
      final result = makeResult(overrideTypes: {
        '1': AnswerOverrideType.auto,
        '2': AnswerOverrideType.auto,
      });
      expect(resolver.isEligibleForRecalculation(result), isTrue);
    });
  });

  group('allCurrent', () {
    test('all matching fingerprints → true', () {
      final assessment = makeAssessment();
      final results = [
        makeResult(fingerprint: assessment.answerKeyFingerprint),
        makeResult(fingerprint: assessment.answerKeyFingerprint),
      ];
      expect(resolver.allCurrent(results: results, assessment: assessment), isTrue);
    });

    test('one outdated → false', () {
      final assessment = makeAssessment();
      final results = [
        makeResult(fingerprint: assessment.answerKeyFingerprint),
        makeResult(fingerprint: 'wrong-fingerprint'),
      ];
      expect(resolver.allCurrent(results: results, assessment: assessment), isFalse);
    });
  });

  group('countByState', () {
    test('counts correctly', () {
      final assessment = makeAssessment();
      final results = [
        makeResult(fingerprint: assessment.answerKeyFingerprint),
        makeResult(fingerprint: assessment.answerKeyFingerprint, hasManualOverrides: true),
        makeResult(fingerprint: 'wrong-fingerprint'),
      ];
      final counts = resolver.countByState(results: results, assessment: assessment);
      expect(counts[IntegrityState.current], 1);
      expect(counts[IntegrityState.currentNeedsManualReview], 1);
      expect(counts[IntegrityState.outdated], 1);
    });
  });
}
