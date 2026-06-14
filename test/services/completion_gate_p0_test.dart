import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/services/assessment_completion_gate.dart';
import 'package:ethiograde/services/answer_key_fingerprint_service.dart';

void main() {
  final fingerprintService = const AnswerKeyFingerprintService();

  Assessment _makeAssessment({
    List<Question>? questions,
    String? fingerprint,
  }) {
    final qs = questions ?? [
      Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
      Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: 'B', points: 1),
    ];
    final a = Assessment(title: 'Test', subject: 'Math', questions: qs);
    return a.copyWith(
      answerKeyRevision: 1,
      answerKeyFingerprint: fingerprint ?? fingerprintService.compute(a),
    );
  }

  ScanResult _makeResult({
    String? fingerprint,
    double confidence = 0.95,
    ScanStatus status = ScanStatus.graded,
    String studentId = 's1',
    String studentName = 'Test Student',
    List<AnswerMatch>? answers,
    Map<String, dynamic>? metadata,
  }) {
    final effectiveMetadata = Map<String, dynamic>.from(metadata ?? {});
    if (fingerprint != null) {
      effectiveMetadata['ik_scoredWithKeyFingerprint'] = fingerprint;
    }
    return ScanResult(
      assessmentId: 'test-assessment',
      studentId: studentId,
      studentName: studentName,
      imagePath: '/path/to/image.jpg',
      answers: answers ?? [
        AnswerMatch(questionNumber: 1, detectedAnswer: 'A', correctAnswer: 'A', isCorrect: true, score: 1, maxScore: 1, confidence: 0.95),
        AnswerMatch(questionNumber: 2, detectedAnswer: 'B', correctAnswer: 'B', isCorrect: true, score: 1, maxScore: 1, confidence: 0.95),
      ],
      totalScore: 2,
      maxScore: 2,
      percentage: 100,
      grade: 'A+',
      status: status,
      confidence: confidence,
      metadata: effectiveMetadata,
    );
  }

  group('P0.6 — Assessment completion gate', () {
    test('complete assessment with current results is ready', () {
      final assessment = _makeAssessment();
      final results = [
        _makeResult(fingerprint: assessment.answerKeyFingerprint),
        _makeResult(fingerprint: assessment.answerKeyFingerprint, studentId: 's2', studentName: 'Student 2'),
      ];

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results);

      expect(check.isReady, true);
      expect(check.blocking, isEmpty);
    });

    test('incomplete answer key is blocking', () {
      final assessment = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
        Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: null, points: 1), // No answer
      ]);
      final results = [_makeResult()];

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results);

      expect(check.isReady, false);
      expect(check.blocking.any((i) => i.label.contains('incomplete')), true);
    });

    test('outdated results are blocking', () {
      final assessment = _makeAssessment();
      final results = [
        _makeResult(fingerprint: 'old-fingerprint'), // Outdated
      ];

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results);

      expect(check.isReady, false);
      expect(check.blocking.any((i) => i.label.contains('outdated')), true);
    });

    test('unresolved review issues are blocking', () {
      final assessment = _makeAssessment();
      final results = [
        _makeResult(confidence: 0.5), // Low confidence → needs review
      ];

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results);

      expect(check.isReady, false);
      expect(check.blocking.any((i) => i.label.contains('review')), true);
    });

    test('unmatched papers are blocking', () {
      final assessment = _makeAssessment();
      final results = [
        _makeResult(studentId: '', studentName: ''), // No student assigned
      ];

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results);

      expect(check.isReady, false);
      expect(check.blocking.any((i) => i.label.contains('assigned')), true);
    });

    test('multiple-mark responses are blocking', () {
      final assessment = _makeAssessment();
      final results = [
        _makeResult(
          answers: [
            AnswerMatch(questionNumber: 1, detectedAnswer: '[MULTIPLE]', correctAnswer: 'A', isCorrect: false, score: 0, maxScore: 1, confidence: 0),
          ],
        ),
      ];

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results);

      expect(check.isReady, false);
      expect(check.blocking.any((i) => i.label.contains('multiple marks')), true);
    });

    test('no results is needs attention, not blocking', () {
      final assessment = _makeAssessment();

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: []);

      expect(check.isReady, true); // No blocking items
      expect(check.needsAttention.any((i) => i.label.contains('No results')), true);
    });

    test('resolved issues do not block', () {
      final assessment = _makeAssessment();
      final results = [
        _makeResult(
          confidence: 0.5,
          status: ScanStatus.reviewed, // Teacher reviewed
        ),
      ];

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results);

      expect(check.isReady, true);
    });

    test('each blocking item has an action', () {
      final assessment = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: null, points: 1),
      ]);
      final results = [
        _makeResult(studentId: '', studentName: ''),
      ];

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results);

      for (final item in check.blocking) {
        expect(item.actionLabel, isNotNull);
      }
    });
  });
}
