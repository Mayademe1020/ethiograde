import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/assessment.dart';
import '../config/constants.dart';
import 'validation_service.dart';

/// Operation result — mirrors StudentProvider's pattern.
class Result<T> {
  final bool success;
  final T? data;
  final String? error;

  const Result.success(this.data)
      : success = true,
        error = null;
  const Result.failure(this.error)
      : success = false,
        data = null;
}

/// Manages assessment persistence against the encrypted Hive `assessments` box.
///
/// All operations wrapped in try/catch — persistence errors never crash the app.
class AssessmentProvider extends ChangeNotifier {
  static const _uuid = Uuid();
  static const _validator = ValidationService();

  List<Assessment> _assessments = [];
  Assessment? _currentAssessment;
  bool _isLoading = false;

  List<Assessment> get assessments => List.unmodifiable(_assessments);
  Assessment? get currentAssessment => _currentAssessment;
  bool get isLoading => _isLoading;

  List<Assessment> get activeAssessments =>
      _assessments.where((a) => a.status == AssessmentStatus.active).toList();

  List<Assessment> get completedAssessments =>
      _assessments.where((a) => a.status == AssessmentStatus.completed).toList();

  AssessmentProvider() {
    loadAssessments();
  }

  // ── Load ──────────────────────────────────────────────────────────

  /// Read all entries, sort newest-first, cache.
  Future<void> loadAssessments() async {
    _isLoading = true;
    notifyListeners();

    try {
      final box = Hive.box(AppConstants.assessmentsBox);
      _assessments = box.values
          .map((data) => Assessment.fromMap(Map<String, dynamic>.from(data)))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e, st) {
      debugPrint('[AssessmentProvider] loadAssessments failed: $e');
      _assessments = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  // ── Add ───────────────────────────────────────────────────────────

  /// Validate, persist, and register a new assessment.
  Future<Result<Assessment>> addAssessment(Assessment assessment) async {
    final validation = _validator.validateAssessment(assessment);
    if (!validation.isValid) {
      return Result.failure(validation.errors.join('; '));
    }

    // Assessment constructor already generates UUID if id is null
    final box = Hive.box(AppConstants.assessmentsBox);
    if (box.containsKey(assessment.id)) {
      return Result.failure(
          'Assessment with ID ${assessment.id} already exists');
    }

    try {
      await box.put(assessment.id, assessment.toMap());
    } catch (e, st) {
      debugPrint('[AssessmentProvider] addAssessment Hive write failed: $e');
      return Result.failure('Failed to save assessment');
    }

    _assessments.insert(0, assessment);
    _currentAssessment = assessment;
    notifyListeners();
    return Result.success(assessment);
  }

  // ── Update ────────────────────────────────────────────────────────

  /// Validate and overwrite an existing assessment.
  Future<Result<Assessment>> updateAssessment(Assessment assessment) async {
    final validation = _validator.validateAssessment(assessment);
    if (!validation.isValid) {
      return Result.failure(validation.errors.join('; '));
    }

    final box = Hive.box(AppConstants.assessmentsBox);
    if (!box.containsKey(assessment.id)) {
      return Result.failure('Assessment ${assessment.id} not found');
    }

    try {
      await box.put(assessment.id, assessment.toMap());
    } catch (e, st) {
      debugPrint('[AssessmentProvider] updateAssessment Hive write failed: $e');
      return Result.failure('Failed to update assessment');
    }

    final index = _assessments.indexWhere((a) => a.id == assessment.id);
    if (index >= 0) {
      _assessments[index] = assessment;
    }
    if (_currentAssessment?.id == assessment.id) {
      _currentAssessment = assessment;
    }
    notifyListeners();
    return Result.success(assessment);
  }

  // ── Delete ────────────────────────────────────────────────────────

  /// Remove an assessment from the box and memory.
  Future<Result<void>> deleteAssessment(String assessmentId) async {
    final box = Hive.box(AppConstants.assessmentsBox);
    if (!box.containsKey(assessmentId)) {
      return Result.failure('Assessment $assessmentId not found');
    }

    try {
      await box.delete(assessmentId);
    } catch (e, st) {
      debugPrint('[AssessmentProvider] deleteAssessment Hive delete failed: $e');
      return Result.failure('Failed to delete assessment');
    }

    _assessments.removeWhere((a) => a.id == assessmentId);
    if (_currentAssessment?.id == assessmentId) {
      _currentAssessment = null;
    }
    notifyListeners();
    return Result.success(null);
  }

  // ── Compat ─────────────────────────────────────────────────────────

  /// Backward-compatible: save = update if exists, add if new.
  Future<void> saveAssessment(Assessment assessment) async {
    final box = Hive.box(AppConstants.assessmentsBox);
    if (box.containsKey(assessment.id)) {
      await updateAssessment(assessment);
    } else {
      await addAssessment(assessment);
    }
  }

  // ── Queries ───────────────────────────────────────────────────────

  /// Single lookup by ID. Returns `null` when not found.
  Assessment? getAssessmentById(String id) {
    try {
      return _assessments.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Return the [limit] most recent assessments (newest first).
  List<Assessment> getRecentAssessments(int limit) {
    final sorted = List<Assessment>.from(_assessments);
    sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.take(limit).toList();
  }

  /// Filter by class.
  List<Assessment> getAssessmentsByClass(String className) {
    return _assessments.where((a) => a.className == className).toList();
  }

  /// Filter by subject.
  List<Assessment> getAssessmentsBySubject(String subject) {
    return _assessments.where((a) => a.subject == subject).toList();
  }

  // ── UI helpers ────────────────────────────────────────────────────

  void setCurrentAssessment(Assessment assessment) {
    _currentAssessment = assessment;
    notifyListeners();
  }

  void clearCurrentAssessment() {
    _currentAssessment = null;
    notifyListeners();
  }

  /// Convenience: update just the status field.
  Future<Result<Assessment>> updateAssessmentStatus(
    String id,
    AssessmentStatus status,
  ) async {
    final existing = getAssessmentById(id);
    if (existing == null) {
      return Result.failure('Assessment $id not found');
    }
    return updateAssessment(existing.copyWith(status: status));
  }

  /// Wipe the box and in-memory cache.
  Future<void> clearAll() async {
    try {
      final box = Hive.box(AppConstants.assessmentsBox);
      await box.clear();
    } catch (e, st) {
      debugPrint('[AssessmentProvider] clearAll failed: $e');
    }
    _assessments.clear();
    _currentAssessment = null;
    notifyListeners();
  }
}
