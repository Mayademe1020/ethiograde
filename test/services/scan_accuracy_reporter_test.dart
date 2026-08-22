import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/services/answer_parser.dart';
import 'package:ethiograde/services/scan_accuracy_reporter.dart';
import 'package:ethiograde/services/scoring_service.dart';

void main() {
  const parser = AnswerParser();
  const scoring = ScoringService();
  const reporter = ScanAccuracyReporter();

  Assessment makeAssessment({
    List<Question>? questions,
    bool isTf = false,
    bool isShortAnswer = false,
  }) {
    final qs =
        questions ??
        [
          for (var i = 1; i <= 10; i++)
            Question(
              number: i,
              type: isTf
                  ? QuestionType.trueFalse
                  : isShortAnswer
                  ? QuestionType.shortAnswer
                  : QuestionType.mcq,
              points: 1,
              correctAnswer: isTf
                  ? (i.isEven ? 'True' : 'False')
                  : isShortAnswer
                  ? 'Answer $i'
                  : String.fromCharCode(65 + ((i - 1) % 4)), // A,B,C,D,A,...
            ),
        ];
    return Assessment(title: 'Accuracy', subject: 'Science', questions: qs);
  }

  /// Format a correct-answer OCR line for question [i] using the assessment key.
  String correctLine(Assessment a, int i) {
    final q = a.questions.firstWhere((q) => q.number == i);
    return '$i. ${q.correctAnswer}';
  }

  ScanResult score({
    required Assessment assessment,
    required String name,
    required List<String> ocrLines,
  }) {
    final regions = [
      for (final line in ocrLines)
        TextRegionInput(text: line, confidence: 0.95, x: 10, y: 10),
    ];
    final parsed = parser.parseAnswers(regions);
    final detected = [
      for (final p in parsed)
        DetectedAnswer(
          questionNumber: p.questionNumber,
          answer: p.answer,
          confidence: p.confidence,
          rawText: p.rawText,
        ),
    ];
    final scored = scoring.scoreAnswers(
      detected: detected,
      assessment: assessment,
    );
    return ScanResult(
      id: name,
      assessmentId: assessment.id,
      studentId: name,
      studentName: name,
      imagePath: '',
      answers: scored,
      totalScore: scoring.calculateTotalScore(scored),
      maxScore: assessment.maxScore,
      percentage: scoring.calculatePercentage(
        totalScore: scoring.calculateTotalScore(scored),
        maxScore: assessment.maxScore,
      ),
      grade: '',
      status: ScanStatus.graded,
      confidence: 0.9,
    );
  }

  group('ScanAccuracyReporter', () {
    test('counts correct answers on a clean sheet', () {
      final assessment = makeAssessment();
      final result = score(
        assessment: assessment,
        name: 's1',
        ocrLines: [for (var i = 1; i <= 10; i++) correctLine(assessment, i)],
      );

      final report = reporter.report(assessment: assessment, results: [result]);

      expect(report.overallAccuracy, 1.0);
      expect(report.correctCount, 10);
      expect(report.wrongCount, 0);
      expect(report.missedCount, 0);
      expect(report.students.first.accuracy, 1.0);
    });

    test('classifies wrong and missed answers', () {
      final assessment = makeAssessment();
      // Q1 wrong (B instead of A), Q2 missed (not in OCR), rest correct
      final lines = <String>['1. B'];
      for (var i = 3; i <= 10; i++) {
        lines.add(correctLine(assessment, i));
      }
      final result = score(assessment: assessment, name: 's1', ocrLines: lines);

      final report = reporter.report(assessment: assessment, results: [result]);

      expect(report.correctCount, 8);
      expect(report.wrongCount, 1);
      expect(report.missedCount, 1);
      expect(report.overallAccuracy, closeTo(0.8, 0.001));
      expect(
        report.questions.firstWhere((q) => q.questionNumber == 1).wrongCount,
        1,
      );
      expect(
        report.questions.firstWhere((q) => q.questionNumber == 2).missedCount,
        1,
      );
    });

    test('blank and multiple-mark detected answers count as missed', () {
      final assessment = makeAssessment();
      final lines = <String>[
        correctLine(assessment, 1),
        '2. BLANK',
        correctLine(assessment, 3),
        '4. [MULTIPLE]',
      ];
      for (var i = 5; i <= 10; i++) {
        lines.add(correctLine(assessment, i));
      }
      final result = score(assessment: assessment, name: 's1', ocrLines: lines);

      final report = reporter.report(assessment: assessment, results: [result]);

      expect(report.correctCount, 8);
      expect(report.wrongCount, 0);
      expect(report.missedCount, 2);
    });

    test('report across multiple students aggregates per-question', () {
      final assessment = makeAssessment();
      // Both students answer B everywhere. Questions whose key is B get 2
      // correct; others get 2 wrong. Expected: 5 correct (Q2,3,6,7,10).
      final s1 = score(
        assessment: assessment,
        name: 's1',
        ocrLines: [for (var i = 1; i <= 10; i++) '$i. B'],
      );
      final s2 = score(
        assessment: assessment,
        name: 's2',
        ocrLines: [for (var i = 1; i <= 10; i++) '$i. B'],
      );

      final report = reporter.report(assessment: assessment, results: [s1, s2]);

      expect(report.totalStudents, 2);
      expect(report.totalQuestions, 10);
      // Keys are A,B,C,D,A,B,C,D,A,B. Both answer B → correct only on B-key
      // questions (Q2, Q6, Q10): 3 correct × 2 students = 6.
      expect(report.correctCount, 6);
      expect(report.wrongCount, 14);
      expect(report.missedCount, 0);
      expect(
        report.questions.firstWhere((q) => q.questionNumber == 2).correctCount,
        2,
      );
      expect(
        report.questions.firstWhere((q) => q.questionNumber == 1).wrongCount,
        2,
      );
      expect(report.overallAccuracy, closeTo(0.3, 0.001));
    });

    test(
      'problemQuestions returns low-accuracy questions sorted worst-first',
      () {
        final assessment = makeAssessment();
        // All B — only B-key questions are correct
        final result = score(
          assessment: assessment,
          name: 's1',
          ocrLines: [for (var i = 1; i <= 10; i++) '$i. B'],
        );

        final report = reporter.report(
          assessment: assessment,
          results: [result],
        );

        final problems = report.problemQuestions(threshold: 0.6);
        expect(problems, isNotEmpty);
        // Worst accuracy first
        for (var i = 1; i < problems.length; i++) {
          expect(problems[i - 1].accuracy <= problems[i].accuracy, isTrue);
        }
      },
    );

    test('handles true/false questions', () {
      final assessment = makeAssessment(isTf: true);
      final result = score(
        assessment: assessment,
        name: 's1',
        ocrLines: [for (var i = 1; i <= 10; i++) correctLine(assessment, i)],
      );

      final report = reporter.report(assessment: assessment, results: [result]);

      expect(report.overallAccuracy, 1.0);
      expect(report.correctCount, 10);
    });

    test('short-answer fuzzy matching counts correct answers', () {
      final assessment = makeAssessment(isShortAnswer: true);
      final result = score(
        assessment: assessment,
        name: 's1',
        ocrLines: [for (var i = 1; i <= 10; i++) correctLine(assessment, i)],
      );

      final report = reporter.report(assessment: assessment, results: [result]);

      expect(report.overallAccuracy, 1.0);
    });

    test('empty results produce a zeroed report', () {
      final assessment = makeAssessment();
      final report = reporter.report(assessment: assessment, results: const []);

      expect(report.totalStudents, 0);
      expect(report.correctCount, 0);
      expect(report.overallAccuracy, 0.0);
      expect(report.questions, hasLength(10));
      for (final q in report.questions) {
        expect(q.missedCount, 0);
        expect(q.accuracy, 0.0);
      }
    });
  });
}
