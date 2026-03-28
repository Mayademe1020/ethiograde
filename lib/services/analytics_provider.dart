import 'dart:math';
import 'package:flutter/material.dart';
import '../models/scan_result.dart';
import '../models/assessment.dart';
import '../models/class_info.dart';

class AnalyticsProvider extends ChangeNotifier {
  ClassAnalytics? _currentAnalytics;
  Map<String, List<double>> _studentScoreHistory = {};

  ClassAnalytics? get currentAnalytics => _currentAnalytics;

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
    final passMark = _getPassMark(assessment.rubricType);

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

      final correct =
          questionAnswers.where((a) => a.isCorrect).length;
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
        if (question?.topicTag != null) {
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

    final analytics = ClassAnalytics(
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

    _currentAnalytics = analytics;
    notifyListeners();
    return analytics;
  }

  List<QuestionAnalytics> getDifficultQuestions(
    List<QuestionAnalytics> analytics, {
    double threshold = 0.4,
  }) {
    return analytics
        .where((q) => q.correctRate < threshold)
        .toList()
      ..sort((a, b) => a.correctRate.compareTo(b.correctRate));
  }

  List<QuestionAnalytics> getEasyQuestions(
    List<QuestionAnalytics> analytics, {
    double threshold = 0.85,
  }) {
    return analytics
        .where((q) => q.correctRate > threshold)
        .toList()
      ..sort((a, b) => b.correctRate.compareTo(a.correctRate));
  }

  /// Get heatmap data for topic weaknesses
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

  int _getPassMark(String rubricType) {
    const scales = {
      'moe_national': 50,
      'private_international': 60,
      'university': 50,
    };
    return scales[rubricType] ?? 50;
  }

  void clear() {
    _currentAnalytics = null;
    _studentScoreHistory.clear();
    notifyListeners();
  }
}
