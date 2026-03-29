import '../models/scan_result.dart';
import '../models/assessment.dart';
import '../models/class_info.dart';
import 'scoring_service.dart';

/// Pure-Dart analytics engine. No Flutter, no platform plugins.
/// Extracted from AnalyticsProvider for independent testability.
///
/// Computes:
/// - Class statistics: average, median, highest/lowest, pass rate
/// - Grade distribution
/// - Per-question analytics: correct rate, answer distribution
/// - Topic scores: average score per topic tag
/// - Difficulty filters: hard questions (<40%), easy questions (>85%)
/// - Topic heatmap: topic × subject correctness counts
class AnalyticsService {
  const AnalyticsService();

  /// Pass mark percentage by rubric type.
  static const Map<String, int> passMarks = {
    'moe_national': 50,
    'private_international': 60,
    'university': 50,
  };

  /// Compute full class analytics from an assessment and its scan results.
  ClassAnalytics computeAnalytics({
    required Assessment assessment,
    required List<ScanResult> results,
  }) {
    if (results.isEmpty) {
      return ClassAnalytics(
        classId: assessment.className,
        assessmentId: assessment.id,
      );
    }

    final scores = results.map((r) => r.percentage).toList()..sort();
    final passMark = passMarks[assessment.rubricType] ?? 50;

    final passed = scores.where((s) => s >= passMark).length;
    final failed = scores.length - passed;

    // Grade distribution
    final gradeDistribution = <String, int>{};
    for (final result in results) {
      final grade = result.grade;
      gradeDistribution[grade] = (gradeDistribution[grade] ?? 0) + 1;
    }

    // Question analytics
    final questionAnalytics = <QuestionAnalytics>[];
    for (final question in assessment.questions) {
      final questionAnswers = results
          .expand((r) => r.answers)
          .where((a) => a.questionNumber == question.number)
          .toList();

      if (questionAnswers.isEmpty) continue;

      final correct = questionAnswers.where((a) => a.isCorrect).length;
      final distribution = <String, int>{};
      for (final answer in questionAnswers) {
        final key = answer.detectedAnswer;
        distribution[key] = (distribution[key] ?? 0) + 1;
      }

      questionAnalytics.add(QuestionAnalytics(
        questionNumber: question.number,
        correctRate: correct / questionAnswers.length,
        totalAttempts: questionAnswers.length,
        correctAttempts: correct,
        answerDistribution: distribution,
        topicTag: question.topicTag,
      ));
    }

    // Topic scores
    final topicScores = <String, List<double>>{};
    for (final result in results) {
      for (final answer in result.answers) {
        final question = assessment.questions
            .where((q) => q.number == answer.questionNumber)
            .firstOrNull;
        if (question?.topicTag != null && answer.maxScore > 0) {
          topicScores.putIfAbsent(question!.topicTag!, () => []);
          topicScores[question.topicTag!]!
              .add(answer.score / answer.maxScore * 100);
        }
      }
    }

    final topicAverages = topicScores.map(
      (topic, scores) => MapEntry(
        topic,
        scores.reduce((a, b) => a + b) / scores.length,
      ),
    );

    return ClassAnalytics(
      classId: assessment.className,
      assessmentId: assessment.id,
      classAverage: scores.reduce((a, b) => a + b) / scores.length,
      highestScore: scores.last,
      lowestScore: scores.first,
      medianScore: _median(scores),
      passRate: passed / scores.length * 100,
      totalStudents: scores.length,
      passedStudents: passed,
      failedStudents: failed,
      gradeDistribution: gradeDistribution,
      questionAnalytics: questionAnalytics,
      topicScores: topicAverages,
    );
  }

  /// Filter questions where correct rate is below threshold (default 40%).
  List<QuestionAnalytics> getDifficultQuestions(
    List<QuestionAnalytics> analytics, {
    double threshold = 0.4,
  }) {
    return analytics
        .where((q) => q.correctRate < threshold)
        .toList()
      ..sort((a, b) => a.correctRate.compareTo(b.correctRate));
  }

  /// Filter questions where correct rate is above threshold (default 85%).
  List<QuestionAnalytics> getEasyQuestions(
    List<QuestionAnalytics> analytics, {
    double threshold = 0.85,
  }) {
    return analytics
        .where((q) => q.correctRate > threshold)
        .toList()
      ..sort((a, b) => b.correctRate.compareTo(a.correctRate));
  }

  /// Compute topic heatmap: topic → subject → correct count.
  Map<String, Map<String, double>> getTopicHeatmap({
    required List<Assessment> assessments,
    required List<List<ScanResult>> allResults,
  }) {
    final heatmap = <String, Map<String, double>>{};

    for (int i = 0; i < assessments.length; i++) {
      final assessment = assessments[i];
      final results = i < allResults.length ? allResults[i] : <ScanResult>[];

      for (final result in results) {
        for (final answer in result.answers) {
          final question = assessment.questions
              .where((q) => q.number == answer.questionNumber)
              .firstOrNull;
          final topic = question?.topicTag ?? 'General';

          heatmap.putIfAbsent(topic, () => {});
          heatmap[topic]![assessment.subject] =
              (heatmap[topic]![assessment.subject] ?? 0) +
              (answer.isCorrect ? 1 : 0);
        }
      }
    }

    return heatmap;
  }

  double _median(List<double> sorted) {
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }
}
