import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/models/student.dart';
import 'package:ethiograde/services/assessment_completion_gate.dart';
import 'package:ethiograde/services/answer_key_fingerprint_service.dart';

void main() {
  final fingerprintService = const AnswerKeyFingerprintService();

  Assessment _makeAssessment({
    List<Question>? questions,
    String? fingerprint,
    String rubricType = 'moe_national',
    Map<String, dynamic>? settings,
  }) {
    final qs = questions ?? [
      Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
      Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: 'B', points: 1),
    ];
    final a = Assessment(title: 'Test', subject: 'Math', questions: qs, rubricType: rubricType);
    return a.copyWith(
      answerKeyRevision: 1,
      answerKeyFingerprint: fingerprint ?? fingerprintService.compute(a),
      settings: settings ?? {},
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

  List<Student> _makeRoster() {
    return [
      Student(id: 's1', studentId: '001', firstName: 'Abebe', lastName: 'Tesfaye', gender: 'M', classIds: ['c1']),
      Student(id: 's2', studentId: '002', firstName: 'Bethlehem', lastName: 'Assefa', gender: 'F', classIds: ['c1']),
      Student(id: 's3', studentId: '003', firstName: 'Dawit', lastName: 'Haile', gender: 'M', classIds: ['c1']),
    ];
  }

  group('Completion gate — all checks', () {
    test('complete assessment with all checks passing', () {
      final assessment = _makeAssessment();
      final results = [
        _makeResult(fingerprint: assessment.answerKeyFingerprint, studentId: 's1'),
        _makeResult(fingerprint: assessment.answerKeyFingerprint, studentId: 's2'),
      ];
      final roster = _makeRoster();

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results, roster: roster);

      expect(check.isReady, true);
      expect(check.blocking, isEmpty);
    });

    test('incomplete answer key is blocking', () {
      final assessment = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1),
        Question(id: 'q2', number: 2, type: QuestionType.mcq, correctAnswer: null, points: 1),
      ]);
      final results = [_makeResult()];

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results);

      expect(check.isReady, false);
      expect(check.blocking.any((i) => i.label.contains('incomplete')), true);
      expect(check.blocking.first.actionLabel, 'Complete answer key');
    });

    test('outdated results are blocking', () {
      final assessment = _makeAssessment();
      final results = [_makeResult(fingerprint: 'old-fingerprint')];

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results);

      expect(check.isReady, false);
      expect(check.blocking.any((i) => i.label.contains('outdated')), true);
    });

    test('recalculation failure is blocking', () {
      final assessment = _makeAssessment(settings: {'ik_recalculationFailed': true});
      final results = [_makeResult(fingerprint: assessment.answerKeyFingerprint)];

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results);

      expect(check.isReady, false);
      expect(check.blocking.any((i) => i.label.contains('recalculation failed')), true);
    });

    test('unresolved review issues are blocking', () {
      final assessment = _makeAssessment();
      final results = [_makeResult(confidence: 0.5)];

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results);

      expect(check.isReady, false);
      expect(check.blocking.any((i) => i.label.contains('review')), true);
    });

    test('unmatched papers are blocking', () {
      final assessment = _makeAssessment();
      final results = [_makeResult(studentId: '', studentName: '')];

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results);

      expect(check.isReady, false);
      expect(check.blocking.any((i) => i.label.contains('assigned')), true);
    });

    test('unresolved duplicates are blocking', () {
      final assessment = _makeAssessment();
      final results = [_makeResult(metadata: {'answerDuplicate': true})];

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results);

      expect(check.isReady, false);
      expect(check.blocking.any((i) => i.label.contains('duplicate')), true);
    });

    test('multiple marks are blocking', () {
      final assessment = _makeAssessment();
      final results = [_makeResult(answers: [
        AnswerMatch(questionNumber: 1, detectedAnswer: '[MULTIPLE]', correctAnswer: 'A', isCorrect: false, score: 0, maxScore: 1, confidence: 0),
      ])];

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results);

      expect(check.isReady, false);
      expect(check.blocking.any((i) => i.label.contains('multiple marks')), true);
    });

    test('missing students are needs attention', () {
      final assessment = _makeAssessment();
      final results = [_makeResult(studentId: 's1')];
      final roster = _makeRoster(); // 3 students, only 1 scanned

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results, roster: roster);

      expect(check.needsAttention.any((i) => i.label.contains('no scanned paper')), true);
    });

    test('unscored manual answers are needs attention', () {
      final assessment = _makeAssessment();
      final results = [_makeResult(answers: [
        AnswerMatch(questionNumber: 1, detectedAnswer: '[MISSING]', correctAnswer: 'A', isCorrect: false, score: 0, maxScore: 1, confidence: 0),
      ])];

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results);

      expect(check.needsAttention.any((i) => i.label.contains('need scoring')), true);
    });

    test('invalid grading scale is blocking', () {
      final assessment = _makeAssessment(rubricType: '');
      final results = [_makeResult()];

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results);

      expect(check.isReady, false);
      expect(check.blocking.any((i) => i.label.contains('Grading scale')), true);
    });

    test('invalid score totals are blocking', () {
      final assessment = _makeAssessment();
      // Create a result with mismatched maxScore
      final badResult = ScanResult(
        assessmentId: 'test-assessment',
        studentId: 's1',
        studentName: 'Test Student',
        imagePath: '/path/to/image.jpg',
        answers: [
          AnswerMatch(questionNumber: 1, detectedAnswer: 'A', correctAnswer: 'A', isCorrect: true, score: 1, maxScore: 1, confidence: 0.95),
        ],
        totalScore: 1,
        maxScore: 5, // Mismatch with assessment.maxScore (2)
        percentage: 20,
        grade: 'F',
        status: ScanStatus.graded,
        confidence: 0.95,
      );

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: [badResult]);

      expect(check.isReady, false);
    });

    test('no results is needs attention', () {
      final assessment = _makeAssessment();

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: []);

      expect(check.isReady, true);
      expect(check.needsAttention.any((i) => i.label.contains('No results')), true);
    });

    test('each blocking item has an action', () {
      final assessment = _makeAssessment(questions: [
        Question(id: 'q1', number: 1, type: QuestionType.mcq, correctAnswer: null, points: 1),
      ]);

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: []);

      for (final item in check.blocking) {
        expect(item.actionLabel, isNotNull);
      }
    });

    test('resolved items do not block', () {
      final assessment = _makeAssessment();
      final results = [_makeResult(
        confidence: 0.5,
        status: ScanStatus.reviewed,
      )];

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results);

      expect(check.isReady, true);
    });

    test('absent students are accounted for', () {
      final assessment = _makeAssessment();
      final results = [
        _makeResult(studentId: 's1', metadata: {'batchReviewResolution': 'absent'}),
      ];
      final roster = _makeRoster();

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results, roster: roster);

      expect(check.ready.any((i) => i.label.contains('marked absent')), true);
    });

    test('explanation text is provided for blocking items', () {
      final assessment = _makeAssessment();
      final results = [_makeResult(fingerprint: 'old-fingerprint')];

      final gate = const AssessmentCompletionGate();
      final check = gate.check(assessment: assessment, results: results);

      expect(check.blocking.first.explanation, isNotNull);
      expect(check.blocking.first.explanation!.isNotEmpty, true);
    });
  });
}
