import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/assessment.dart';
import '../config/constants.dart';

class AssessmentProvider extends ChangeNotifier {
  List<Assessment> _assessments = [];
  Assessment? _currentAssessment;
  bool _isLoading = false;

  List<Assessment> get assessments => _assessments;
  Assessment? get currentAssessment => _currentAssessment;
  bool get isLoading => _isLoading;

  List<Assessment> get activeAssessments =>
      _assessments.where((a) => a.status == AssessmentStatus.active).toList();

  List<Assessment> get completedAssessments =>
      _assessments.where((a) => a.status == AssessmentStatus.completed).toList();

  AssessmentProvider() {
    loadAssessments();
  }

  Future<void> loadAssessments() async {
    _isLoading = true;
    notifyListeners();

    final box = Hive.box(AppConstants.assessmentsBox);
    _assessments = box.values
        .map((data) => Assessment.fromMap(Map<String, dynamic>.from(data)))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    _isLoading = false;
    notifyListeners();
  }

  Future<void> saveAssessment(Assessment assessment) async {
    final box = Hive.box(AppConstants.assessmentsBox);
    await box.put(assessment.id, assessment.toMap());

    final index = _assessments.indexWhere((a) => a.id == assessment.id);
    if (index >= 0) {
      _assessments[index] = assessment;
    } else {
      _assessments.insert(0, assessment);
    }
    _currentAssessment = assessment;
    notifyListeners();
  }

  Future<void> deleteAssessment(String id) async {
    final box = Hive.box(AppConstants.assessmentsBox);
    await box.delete(id);
    _assessments.removeWhere((a) => a.id == id);
    if (_currentAssessment?.id == id) {
      _currentAssessment = null;
    }
    notifyListeners();
  }

  void setCurrentAssessment(Assessment assessment) {
    _currentAssessment = assessment;
    notifyListeners();
  }

  void clearCurrentAssessment() {
    _currentAssessment = null;
    notifyListeners();
  }

  Future<void> updateAssessmentStatus(
    String id,
    AssessmentStatus status,
  ) async {
    final index = _assessments.indexWhere((a) => a.id == id);
    if (index >= 0) {
      final updated = _assessments[index].copyWith(status: status);
      await saveAssessment(updated);
    }
  }

  Assessment? getAssessmentById(String id) {
    try {
      return _assessments.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  List<Assessment> getAssessmentsByClass(String className) {
    return _assessments
        .where((a) => a.className == className)
        .toList();
  }

  List<Assessment> getAssessmentsBySubject(String subject) {
    return _assessments
        .where((a) => a.subject == subject)
        .toList();
  }
}
