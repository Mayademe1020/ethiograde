import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/config/integrity_metadata_keys.dart';
import 'package:ethiograde/services/answer_key_fingerprint_service.dart';
import 'package:ethiograde/services/legacy_baseline_service.dart';
import 'package:ethiograde/services/integrity_state_resolver.dart';

void main() {
  final fingerprintService = const AnswerKeyFingerprintService();

  Assessment _makeLegacyAssessment({List<Question>? questions}) {
    final qs = questions ?? [
      Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
    ];
    // Legacy assessment: no fingerprint, no revision
    return Assessment(
      title: 'Legacy Test',
      subject: 'Math',
      questions: qs,
      answerKeyRevision: 0,
      answerKeyFingerprint: '',
    );
  }

  ScanResult _makeLegacyResult({String? assessmentId}) {
    // Legacy result: no scoring fingerprint
    return ScanResult(
      assessmentId: assessmentId ?? 'test-assessment',
      studentId: 'student-1',
      studentName: 'Test Student',
      imagePath: '/path/to/image.jpg',
      answers: [
        AnswerMatch(questionNumber: 1, detectedAnswer: 'A', correctAnswer: 'A', isCorrect: true, score: 1, maxScore: 1, confidence: 0.95),
      ],
      totalScore: 1,
      maxScore: 1,
      percentage: 100,
      grade: 'A+',
      status: ScanStatus.graded,
      metadata: {}, // No integrity metadata
    );
  }

  group('LegacyBaselineService', () {
    test('legacy assessment gets baseline through explicit service', () {
      final legacy = _makeLegacyAssessment();
      final service = LegacyBaselineService();

      expect(legacy.answerKeyFingerprint, isEmpty);
      expect(legacy.answerKeyRevision, 0);

      final baseline = service.ensureBaseline(legacy);

      expect(baseline.answerKeyFingerprint, isNotEmpty);
      expect(baseline.answerKeyRevision, 1);
      expect(baseline.answerKeyFingerprint, fingerprintService.compute(legacy));
    });

    test('ordinary model reads do not mutate persistence', () {
      final legacy = _makeLegacyAssessment();

      // Reading the fingerprint should not change it
      expect(legacy.answerKeyFingerprint, isEmpty);
      expect(legacy.answerKeyRevision, 0);

      // Multiple reads should not change anything
      final _ = legacy.answerKeyFingerprint;
      final __ = legacy.answerKeyRevision;

      expect(legacy.answerKeyFingerprint, isEmpty);
      expect(legacy.answerKeyRevision, 0);
    });

    test('assessment with existing fingerprint is not modified', () {
      final assessment = _makeLegacyAssessment();
      final withFingerprint = assessment.copyWith(
        answerKeyRevision: 5,
        answerKeyFingerprint: 'existing-fingerprint',
      );

      final service = LegacyBaselineService();
      final result = service.ensureBaseline(withFingerprint);

      // Should not be modified
      expect(result.answerKeyFingerprint, 'existing-fingerprint');
      expect(result.answerKeyRevision, 5);
    });

    test('baseline persists through copyWith', () {
      final legacy = _makeLegacyAssessment();
      final service = LegacyBaselineService();
      final baseline = service.ensureBaseline(legacy);

      // Simulate persistence by creating new instance with same values
      final persisted = Assessment(
        title: baseline.title,
        subject: baseline.subject,
        questions: baseline.questions,
        answerKeyRevision: baseline.answerKeyRevision,
        answerKeyFingerprint: baseline.answerKeyFingerprint,
      );

      expect(persisted.answerKeyFingerprint, baseline.answerKeyFingerprint);
      expect(persisted.answerKeyRevision, baseline.answerKeyRevision);
    });

    test('first future answer-key change is correctly detected', () {
      final legacy = _makeLegacyAssessment();
      final service = LegacyBaselineService();
      final baseline = service.ensureBaseline(legacy);

      // Simulate answer key change
      final newQuestions = [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'B', points: 1),
      ];
      final newAssessment = Assessment(
        title: baseline.title,
        subject: baseline.subject,
        questions: newQuestions,
        answerKeyRevision: baseline.answerKeyRevision + 1,
        answerKeyFingerprint: fingerprintService.compute(
          Assessment(title: baseline.title, subject: baseline.subject, questions: newQuestions),
        ),
      );

      // Fingerprint should be different
      expect(newAssessment.answerKeyFingerprint, isNot(equals(baseline.answerKeyFingerprint)));

      // Legacy result without fingerprint → legacyUnknown (not outdated)
      // This is correct: we cannot verify if the legacy result used the old or new key
      final resolver = const IntegrityStateResolver();
      final result = _makeLegacyResult(assessmentId: baseline.id);
      final state = resolver.resolve(result: result, assessment: newAssessment);
      expect(state, IntegrityState.legacyUnknown);
    });
  });

  group('Hive backward compatibility', () {
    test('assessment with no fingerprint reads with safe defaults', () {
      // Simulate a legacy Assessment with only old fields
      final map = {
        'id': 'test-id',
        'title': 'Test',
        'subject': 'Math',
        'className': '',
        'grade': 1,
        'rubricType': 'moe_national',
        'questions': [
          {'id': 'q1', 'number': 1, 'type': 0, 'text': '', 'points': 1.0, 'options': ['A', 'B', 'C', 'D', 'E'], 'correctAnswer': 'A'}
        ],
        'createdAt': DateTime.now().toIso8601String(),
        'totalPoints': 1,
        'passingPoints': 0,
        'status': 0,
        'isQuickGrade': false,
        'settings': {},
        // No answerKeyRevision or answerKeyFingerprint
      };

      final assessment = Assessment.fromMap(map);

      expect(assessment.answerKeyRevision, 0);
      expect(assessment.answerKeyFingerprint, '');
    });

    test('assessment round-trip preserves fingerprint', () {
      final original = Assessment(
        title: 'Test',
        subject: 'Math',
        questions: [
          Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
        ],
        answerKeyRevision: 5,
        answerKeyFingerprint: 'test-fingerprint-123',
      );

      // Serialize and deserialize
      final map = original.toMap();
      final restored = Assessment.fromMap(map);

      expect(restored.answerKeyRevision, 5);
      expect(restored.answerKeyFingerprint, 'test-fingerprint-123');
    });

    test('scan result round-trip preserves scoring metadata', () {
      final original = ScanResult(
        assessmentId: 'assess-1',
        studentId: 'student-1',
        studentName: 'Test',
        imagePath: '/path/to/image.jpg',
        answers: [
          AnswerMatch(questionNumber: 1, detectedAnswer: 'A', correctAnswer: 'A', isCorrect: true, score: 1, maxScore: 1, confidence: 0.95),
        ],
        totalScore: 1,
        maxScore: 1,
        percentage: 100,
        grade: 'A+',
        status: ScanStatus.graded,
        metadata: {
          IntegrityMetadataKeys.scoredWithKeyFingerprint: 'fp-123',
          IntegrityMetadataKeys.scoredWithKeyRevision: 3,
        },
      );

      final map = original.toMap();
      final restored = ScanResult.fromMap(map);

      expect(restored.metadata[IntegrityMetadataKeys.scoredWithKeyFingerprint], 'fp-123');
      expect(restored.metadata[IntegrityMetadataKeys.scoredWithKeyRevision], 3);
    });
  });
}
