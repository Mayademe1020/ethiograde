import 'package:flutter/material.dart';
import '../models/scan_result.dart';
import '../models/assessment.dart';
import '../models/class_info.dart';
import 'analytics_service.dart';

class AnalyticsProvider extends ChangeNotifier {
  final AnalyticsService _analytics = const AnalyticsService();

  ClassAnalytics? _currentAnalytics;
  Map<String, List<double>> _studentScoreHistory = {};

  ClassAnalytics? get currentAnalytics => _currentAnalytics;

  ClassAnalytics computeAnalytics({
    required Assessment assessment,
    required List<ScanResult> results,
  }) {
    final result = _analytics.computeAnalytics(
      assessment: assessment,
      results: results,
    );
    _currentAnalytics = result;
    notifyListeners();
    return result;
  }

  List<QuestionAnalytics> getDifficultQuestions(
    List<QuestionAnalytics> analytics, {
    double threshold = 0.4,
  }) {
    return _analytics.getDifficultQuestions(analytics, threshold: threshold);
  }

  List<QuestionAnalytics> getEasyQuestions(
    List<QuestionAnalytics> analytics, {
    double threshold = 0.85,
  }) {
    return _analytics.getEasyQuestions(analytics, threshold: threshold);
  }

  Map<String, Map<String, double>> getTopicHeatmap({
    required List<Assessment> assessments,
    required List<List<ScanResult>> allResults,
  }) {
    return _analytics.getTopicHeatmap(
      assessments: assessments,
      allResults: allResults,
    );
  }

  void clear() {
    _currentAnalytics = null;
    _studentScoreHistory.clear();
    notifyListeners();
  }
}
