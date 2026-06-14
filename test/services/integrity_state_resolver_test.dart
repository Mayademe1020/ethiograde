import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/config/integrity_metadata_keys.dart';
import 'package:ethiograde/services/integrity_state_resolver.dart';
import 'package:ethiograde/services/answer_key_fingerprint_service.dart';

void main() {
  final resolver = const IntegrityStateResolver();
  final fingerprintService = const AnswerKeyFingerprintService();

  Assessment _makeAssessment({
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

  ScanResult _makeResult({
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
      final assessment = _makeAssessment();
      final result = _makeResult(fingerprint: assessment.answerKeyFingerprint);
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.current);
    });

    test('missing fingerprint on result → legacyUnknown', () {
      final assessment = _makeAssessment();
      final result = _makeResult(); // no fingerprint
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.legacyUnknown);
    });

    test('mismatched fingerprint → outdated', () {
      final assessment = _makeAssessment();
      final result = _makeResult(fingerprint: 'wrong-fingerprint-value');
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.outdated);
    });

    test('manual entry → current', () {
      final assessment = _makeAssessment();
      final result = _makeResult(fingerprint: assessment.answerKeyFingerprint, isManualEntry: true);
      // Manual entry with matching fingerprint is still current (just needs manual review)
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.currentNeedsManualReview);
    });

    test('has manual overrides → currentNeedsManualReview', () {
      final assessment = _makeAssessment();
      final result = _makeResult(
        fingerprint: assessment.answerKeyFingerprint,
        hasManualOverrides: true,
      );
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.currentNeedsManualReview);
    });

    test('final score manually set → currentNeedsManualReview', () {
      final assessment = _makeAssessment();
      final result = _makeResult(
        fingerprint: assessment.answerKeyFingerprint,
        finalScoreManuallySet: true,
      );
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.currentNeedsManualReview);
    });

    test('assessment with recalculation in progress → recalculating', () {
      final assessment = _makeAssessment(settings: {
        IntegrityMetadataKeys.recalculationInProgress: true,
      });
      final result = _makeResult(fingerprint: assessment.answerKeyFingerprint);
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.recalculating);
    });

    test('assessment with recalculation failed → recalculationFailed', () {
      final assessment = _makeAssessment(settings: {
        IntegrityMetadataKeys.recalculationFailed: true,
      });
      final result = _makeResult(fingerprint: assessment.answerKeyFingerprint);
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.recalculationFailed);
    });

    test('both missing fingerprints → current (legacy baseline)', () {
      final assessment = _makeAssessment(fingerprint: '');
      final result = _makeResult(); // no fingerprint
      expect(resolver.resolve(result: result, assessment: assessment), IntegrityState.current);
    });
  });

  group('isEligibleForRecalculation', () {
    test('auto-scored result is eligible', () {
      final result = _makeResult();
      expect(resolver.isEligibleForRecalculation(result), isTrue);
    });

    test('manual entry is not eligible', () {
      final result = _makeResult(isManualEntry: true);
      expect(resolver.isEligibleForRecalculation(result), isFalse);
    });

    test('result with manual overrides is not eligible', () {
      final result = _makeResult(hasManualOverrides: true);
      expect(resolver.isEligibleForRecalculation(result), isFalse);
    });

    test('result with final score manually set is not eligible', () {
      final result = _makeResult(finalScoreManuallySet: true);
      expect(resolver.isEligibleForRecalculation(result), isFalse);
    });

    test('result with teacher-corrected answers is not eligible', () {
      final result = _makeResult(overrideTypes: {
        '1': AnswerOverrideType.teacherCorrected,
        '2': AnswerOverrideType.auto,
      });
      expect(resolver.isEligibleForRecalculation(result), isFalse);
    });

    test('result with all auto overrides is eligible', () {
      final result = _makeResult(overrideTypes: {
        '1': AnswerOverrideType.auto,
        '2': AnswerOverrideType.auto,
      });
      expect(resolver.isEligibleForRecalculation(result), isTrue);
    });
  });

  group('allCurrent', () {
    test('all matching fingerprints → true', () {
      final assessment = _makeAssessment();
      final results = [
        _makeResult(fingerprint: assessment.answerKeyFingerprint),
        _makeResult(fingerprint: assessment.answerKeyFingerprint),
      ];
      expect(resolver.allCurrent(results: results, assessment: assessment), isTrue);
    });

    test('one outdated → false', () {
      final assessment = _makeAssessment();
      final results = [
        _makeResult(fingerprint: assessment.answerKeyFingerprint),
        _makeResult(fingerprint: 'wrong-fingerprint'),
      ];
      expect(resolver.allCurrent(results: results, assessment: assessment), isFalse);
    });
  });

  group('countByState', () {
    test('counts correctly', () {
      final assessment = _makeAssessment();
      final results = [
        _makeResult(fingerprint: assessment.answerKeyFingerprint),
        _makeResult(fingerprint: assessment.answerKeyFingerprint, hasManualOverrides: true),
        _makeResult(fingerprint: 'wrong-fingerprint'),
      ];
      final counts = resolver.countByState(results: results, assessment: assessment);
      expect(counts[IntegrityState.current], 1);
      expect(counts[IntegrityState.currentNeedsManualReview], 1);
      expect(counts[IntegrityState.outdated], 1);
    });
  });
}
