import '../models/assessment.dart';
import '../models/scan_result.dart';
import 'scoring_service.dart';

/// Per-question accuracy across a set of scanned results.
///
/// Mirrors the field-test protocol in WEEKEND_TEST.md / REAL_WORLD_TESTING.md:
/// every question is classified as correct, wrong, or missed, and accuracy
/// is correct ÷ (correct + wrong + missed).
class QuestionAccuracyReport {
  final int questionNumber;
  final String correctAnswer;
  final int correctCount;
  final int wrongCount;
  final int missedCount;

  const QuestionAccuracyReport({
    required this.questionNumber,
    required this.correctAnswer,
    required this.correctCount,
    required this.wrongCount,
    required this.missedCount,
  });

  int get totalAttempts => correctCount + wrongCount + missedCount;

  /// Proportion correct over every student who sat the exam.
  double get accuracy => totalAttempts == 0 ? 0 : correctCount / totalAttempts;
}

/// Per-student accuracy across the assessment's questions.
class StudentAccuracyReport {
  final String studentId;
  final String studentName;
  final int correctCount;
  final int wrongCount;
  final int missedCount;

  const StudentAccuracyReport({
    required this.studentId,
    required this.studentName,
    required this.correctCount,
    required this.wrongCount,
    required this.missedCount,
  });

  int get totalAttempts => correctCount + wrongCount + missedCount;
  double get accuracy => totalAttempts == 0 ? 0 : correctCount / totalAttempts;
}

/// Aggregate accuracy report for a class.
class ScanAccuracyReport {
  final int totalStudents;
  final int totalQuestions;
  final int correctCount;
  final int wrongCount;
  final int missedCount;
  final List<QuestionAccuracyReport> questions;
  final List<StudentAccuracyReport> students;

  const ScanAccuracyReport({
    required this.totalStudents,
    required this.totalQuestions,
    required this.correctCount,
    required this.wrongCount,
    required this.missedCount,
    required this.questions,
    required this.students,
  });

  int get totalAttempts => correctCount + wrongCount + missedCount;

  /// Overall detection accuracy (correct ÷ all classified answers).
  double get overallAccuracy =>
      totalAttempts == 0 ? 0 : correctCount / totalAttempts;

  /// Questions with accuracy below the given threshold — the "problem" set.
  List<QuestionAccuracyReport> problemQuestions({double threshold = 0.8}) =>
      questions.where((q) => q.accuracy < threshold).toList()
        ..sort((a, b) => a.accuracy.compareTo(b.accuracy));
}

/// Compares scanned answers against an assessment's ground-truth answer key
/// and produces an accuracy report.
///
/// Pure Dart — no platform plugins — so it can run in unit tests and on any
/// set of real scanned results to field-validate scan accuracy.
class ScanAccuracyReporter {
  const ScanAccuracyReporter();

  static const ScoringService _scoring = ScoringService();

  /// Build a report by independently re-scoring each result's detected answers
  /// against the assessment answer key.
  ///
  /// - correct: a detected answer matches the key
  /// - wrong: an answer was detected but doesn't match
  /// - missed: no answer detected for the question (blank / unreadable / absent)
  ScanAccuracyReport report({
    required Assessment assessment,
    required List<ScanResult> results,
  }) {
    final questions = List<Question>.from(assessment.questions)
      ..sort((a, b) => a.number.compareTo(b.number));

    final studentReports = <StudentAccuracyReport>[];
    var correctTotal = 0;
    var wrongTotal = 0;
    var missedTotal = 0;

    for (final result in results) {
      var correct = 0;
      var wrong = 0;
      var missed = 0;

      for (final q in questions) {
        final match = result.answers
            .where((a) => a.questionNumber == q.number)
            .firstOrNull;
        if (match == null || _isBlank(match.detectedAnswer)) {
          missed++;
          continue;
        }
        final isCorrect = _scoring.checkAnswer(
          detected: match.detectedAnswer,
          correct: q.correctAnswer,
          type: q.type,
        );
        if (isCorrect) {
          correct++;
        } else {
          wrong++;
        }
      }

      correctTotal += correct;
      wrongTotal += wrong;
      missedTotal += missed;
      studentReports.add(
        StudentAccuracyReport(
          studentId: result.studentId,
          studentName: result.studentName,
          correctCount: correct,
          wrongCount: wrong,
          missedCount: missed,
        ),
      );
    }

    final questionReports = questions.map((q) {
      var correct = 0;
      var wrong = 0;
      var missed = 0;
      for (final result in results) {
        final match = result.answers
            .where((a) => a.questionNumber == q.number)
            .firstOrNull;
        if (match == null || _isBlank(match.detectedAnswer)) {
          missed++;
          continue;
        }
        final isCorrect = _scoring.checkAnswer(
          detected: match.detectedAnswer,
          correct: q.correctAnswer,
          type: q.type,
        );
        if (isCorrect) {
          correct++;
        } else {
          wrong++;
        }
      }
      return QuestionAccuracyReport(
        questionNumber: q.number,
        correctAnswer: q.correctAnswer?.toString() ?? '',
        correctCount: correct,
        wrongCount: wrong,
        missedCount: missed,
      );
    }).toList();

    return ScanAccuracyReport(
      totalStudents: results.length,
      totalQuestions: questions.length,
      correctCount: correctTotal,
      wrongCount: wrongTotal,
      missedCount: missedTotal,
      questions: questionReports,
      students: studentReports,
    );
  }

  /// BLANK / UNREADABLE / empty / [MISSING] / multiple-mark sentinels mean
  /// "no usable answer detected" — counted as missed rather than wrong.
  static bool _isBlank(String detected) {
    final normalized = detected.trim().toUpperCase();
    return normalized.isEmpty ||
        normalized == 'BLANK' ||
        normalized == 'UNREADABLE' ||
        normalized == '[MISSING]' ||
        normalized == '[MULTIPLE]';
  }
}
