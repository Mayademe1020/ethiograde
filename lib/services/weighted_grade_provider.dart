import 'package:flutter/foundation.dart';

import '../models/weighted_grade.dart';
import '../models/scan_result.dart';
import '../models/student.dart';
import 'app_log.dart';
import 'error_handler.dart';
import 'hive_box_mixin.dart';
import 'weighted_grade_service.dart';

/// Manages weighted grade scale persistence against the encrypted Hive
/// `weighted_scales` box.
///
/// Supports:
/// - Per-exam scales (keyed by assessment ID)
/// - Reusable templates (keyed by template name)
/// - CRUD operations for both
class WeightedGradeProvider extends ChangeNotifier with HiveBoxMixin {
  static const String _boxName = 'weighted_scales';
  static const String _templatePrefix = 'template:';
  static const String _examPrefix = 'exam:';

  List<WeightedGradeScale> _scales = [];
  bool _loaded = false;

  List<WeightedGradeScale> get scales => List.unmodifiable(_scales);
  bool get isLoaded => _loaded;

  /// All saved templates (reusable scales).
  List<WeightedGradeScale> get templates =>
      _scales.where((s) => s.id.startsWith(_templatePrefix)).toList();

  /// All per-exam scales.
  List<WeightedGradeScale> get examScales =>
      _scales.where((s) => s.id.startsWith(_examPrefix)).toList();

  WeightedGradeProvider() {
    _loadScales();
  }

  Future<void> _loadScales() async {
    if (_loaded) return;
    try {
      final box = await openBox(_boxName);
      _scales = box.values
          .map(
            (v) =>
                WeightedGradeScale.fromMap(Map<String, dynamic>.from(v as Map)),
          )
          .toList();
      _loaded = true;
      AppLog.info(this, '_loadScales', 'loaded ${_scales.length} scale(s)');
    } catch (e, st) {
      AppErrorHandler.catchError(this, '_loadScales', e, st);
      _scales = [];
      _loaded = true;
    }
    notifyListeners();
  }

  /// Save a scale for a specific exam.
  Future<void> saveForExam(String examId, WeightedGradeScale scale) async {
    try {
      final box = await openBox(_boxName);
      final keyed = WeightedGradeScale(
        id: '$_examPrefix$examId',
        name: scale.name,
        classId: scale.classId,
        components: scale.components,
        rubricType: scale.rubricType,
        createdAt: scale.createdAt,
      );
      await box.put(keyed.id, keyed.toMap());
      _scales.removeWhere((s) => s.id == keyed.id);
      _scales.add(keyed);
      notifyListeners();
      AppLog.info(this, 'saveForExam', 'saved exam scale: $examId');
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'saveForExam', e, st);
    }
  }

  /// Get the scale for a specific exam, if any.
  WeightedGradeScale? getForExam(String examId) {
    try {
      return _scales.firstWhere((s) => s.id == '$_examPrefix$examId');
    } catch (_) {
      return null;
    }
  }

  /// Remove the scale for a specific exam.
  Future<void> removeForExam(String examId) async {
    try {
      final box = await openBox(_boxName);
      final key = '$_examPrefix$examId';
      await box.delete(key);
      _scales.removeWhere((s) => s.id == key);
      notifyListeners();
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'removeForExam', e, st);
    }
  }

  /// Save a scale as a reusable template.
  Future<void> saveTemplate(
    String templateName,
    WeightedGradeScale scale,
  ) async {
    try {
      final box = await openBox(_boxName);
      final keyed = WeightedGradeScale(
        id: '$_templatePrefix$templateName',
        name: templateName,
        classId: '',
        components: scale.components,
        rubricType: scale.rubricType,
        createdAt: DateTime.now(),
      );
      await box.put(keyed.id, keyed.toMap());
      _scales.removeWhere((s) => s.id == keyed.id);
      _scales.add(keyed);
      notifyListeners();
      AppLog.info(this, 'saveTemplate', 'saved template: $templateName');
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'saveTemplate', e, st);
    }
  }

  /// Get a template by name.
  WeightedGradeScale? getTemplate(String name) {
    try {
      return _scales.firstWhere((s) => s.id == '$_templatePrefix$name');
    } catch (_) {
      return null;
    }
  }

  /// Delete a template.
  Future<void> deleteTemplate(String name) async {
    try {
      final box = await openBox(_boxName);
      final key = '$_templatePrefix$name';
      await box.delete(key);
      _scales.removeWhere((s) => s.id == key);
      notifyListeners();
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'deleteTemplate', e, st);
    }
  }

  /// Rename a template.
  Future<void> renameTemplate(String oldName, String newName) async {
    try {
      final old = getTemplate(oldName);
      if (old == null) return;

      final box = await openBox(_boxName);
      await box.delete(old.id);
      _scales.removeWhere((s) => s.id == old.id);

      final renamed = WeightedGradeScale(
        id: '$_templatePrefix$newName',
        name: newName,
        classId: old.classId,
        components: old.components,
        rubricType: old.rubricType,
        createdAt: old.createdAt,
      );
      await box.put(renamed.id, renamed.toMap());
      _scales.add(renamed);
      notifyListeners();
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'renameTemplate', e, st);
    }
  }

  /// Compute composite grades for an exam that has a weighted scale.
  Future<List<CompositeGrade>?> computeForExam({
    required String examId,
    required List<Student> students,
  }) async {
    final scale = getForExam(examId);
    if (scale == null) return null;

    final allResults = <String, List<ScanResult>>{};
    try {
      final box = await openBox('scan_results');
      for (final key in box.keys) {
        final data = await box.get(key);
        if (data == null) continue;
        final map = Map<String, dynamic>.from(data as Map);
        final assessmentId = map['assessmentId'] as String? ?? '';
        if (assessmentId.isEmpty) continue;

        final isRelevant = scale.components.any(
          (c) => c.assessmentIds.contains(assessmentId),
        );
        if (!isRelevant) continue;

        allResults.putIfAbsent(assessmentId, () => []);
        allResults[assessmentId]!.add(ScanResult.fromMap(map));
      }
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'computeForExam', e, st);
      return [];
    }

    const service = WeightedGradeService();
    return service.computeClassGrades(
      students: students,
      scale: scale,
      allResults: allResults,
    );
  }

  /// Clear all scales.
  Future<void> clearAll() async {
    try {
      final box = await openBox(_boxName);
      await box.clear();
      _scales.clear();
      notifyListeners();
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'clearAll', e, st);
    }
  }
}
