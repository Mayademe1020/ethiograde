import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/teacher.dart';
import '../config/constants.dart';
import 'validation_service.dart';

/// Operation result — never throws, always returns a status.
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

/// Manages teacher persistence against the encrypted Hive `teachers` box.
///
/// All operations are wrapped in try/catch — persistence errors never
/// crash the app.  Callers check [Result.success].
class TeacherProvider extends ChangeNotifier {
  static const _uuid = Uuid();
  static const _validator = ValidationService();

  List<Teacher> _teachers = [];
  bool _isLoading = false;

  List<Teacher> get teachers => List.unmodifiable(_teachers);
  bool get isLoading => _isLoading;
  int get teacherCount => _teachers.length;
  List<Teacher> get activeTeachers =>
      _teachers.where((t) => t.isActive).toList();

  TeacherProvider() {
    loadTeachers();
  }

  // ── Load ──────────────────────────────────────────────────────────

  Future<void> loadTeachers() async {
    _isLoading = true;
    notifyListeners();

    try {
      final box = Hive.box(AppConstants.teachersBox);
      _teachers = box.values
          .map((data) => Teacher.fromMap(Map<String, dynamic>.from(data)))
          .toList()
        ..sort((a, b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (e, st) {
      debugPrint('[TeacherProvider] loadTeachers failed: $e');
      _teachers = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  // ── Add ───────────────────────────────────────────────────────────

  Future<Result<Teacher>> addTeacher(Teacher teacher) async {
    final validation = _validator.validateTeacher(teacher);
    if (!validation.isValid) {
      return Result.failure(validation.errors.join('; '));
    }

    final withId = teacher.id.isEmpty
        ? Teacher(
            id: _uuid.v4(),
            name: teacher.name,
            nameAmharic: teacher.nameAmharic,
            phone: teacher.phone,
            email: teacher.email,
            subject: teacher.subject,
            isActive: teacher.isActive,
            createdAt: teacher.createdAt,
            metadata: teacher.metadata,
          )
        : teacher;

    final box = Hive.box(AppConstants.teachersBox);
    if (box.containsKey(withId.id)) {
      return Result.failure('Teacher with ID ${withId.id} already exists');
    }

    try {
      await box.put(withId.id, withId.toMap());
    } catch (e, st) {
      debugPrint('[TeacherProvider] addTeacher Hive write failed: $e');
      return Result.failure('Failed to save teacher');
    }

    _teachers.add(withId);
    _teachers.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    return Result.success(withId);
  }

  // ── Update ────────────────────────────────────────────────────────

  Future<Result<Teacher>> updateTeacher(Teacher teacher) async {
    final validation = _validator.validateTeacher(teacher);
    if (!validation.isValid) {
      return Result.failure(validation.errors.join('; '));
    }

    final box = Hive.box(AppConstants.teachersBox);
    if (!box.containsKey(teacher.id)) {
      return Result.failure('Teacher ${teacher.id} not found');
    }

    try {
      await box.put(teacher.id, teacher.toMap());
    } catch (e, st) {
      debugPrint('[TeacherProvider] updateTeacher Hive write failed: $e');
      return Result.failure('Failed to update teacher');
    }

    final index = _teachers.indexWhere((t) => t.id == teacher.id);
    if (index >= 0) {
      _teachers[index] = teacher;
    }
    notifyListeners();
    return Result.success(teacher);
  }

  // ── Delete ────────────────────────────────────────────────────────

  Future<Result<void>> deleteTeacher(String teacherId) async {
    final box = Hive.box(AppConstants.teachersBox);
    if (!box.containsKey(teacherId)) {
      return Result.failure('Teacher $teacherId not found');
    }

    try {
      await box.delete(teacherId);
    } catch (e, st) {
      debugPrint('[TeacherProvider] deleteTeacher Hive delete failed: $e');
      return Result.failure('Failed to delete teacher');
    }

    _teachers.removeWhere((t) => t.id == teacherId);
    notifyListeners();
    return Result.success(null);
  }

  // ── Toggle active ─────────────────────────────────────────────────

  Future<Result<Teacher>> toggleActive(String teacherId) async {
    final teacher = getTeacherById(teacherId);
    if (teacher == null) {
      return Result.failure('Teacher $teacherId not found');
    }
    return updateTeacher(teacher.copyWith(isActive: !teacher.isActive));
  }

  // ── Queries ───────────────────────────────────────────────────────

  Teacher? getTeacherById(String id) {
    try {
      return _teachers.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  List<Teacher> searchTeachers(String query) {
    if (query.trim().isEmpty) return List.unmodifiable(_teachers);
    final q = query.toLowerCase();
    return _teachers
        .where((t) =>
            t.name.toLowerCase().contains(q) ||
            t.nameAmharic.contains(query) ||
            t.phone.contains(q) ||
            t.subject.toLowerCase().contains(q))
        .toList();
  }

  List<Teacher> getTeachersBySubject(String subject) {
    return _teachers
        .where((t) => t.subject.toLowerCase() == subject.toLowerCase())
        .toList();
  }

  List<String> get subjects =>
      _teachers.map((t) => t.subject).where((s) => s.isNotEmpty).toSet().toList()
        ..sort();

  // ── Bulk ──────────────────────────────────────────────────────────

  Future<Result<int>> addTeachers(List<Teacher> teachers) async {
    int added = 0;
    for (final t in teachers) {
      final result = await addTeacher(t);
      if (result.success) added++;
    }
    return added > 0
        ? Result.success(added)
        : Result.failure('No teachers were added');
  }

  // ── Clear ─────────────────────────────────────────────────────────

  Future<void> clearAll() async {
    try {
      final box = Hive.box(AppConstants.teachersBox);
      await box.clear();
    } catch (e, st) {
      debugPrint('[TeacherProvider] clearAll failed: $e');
    }
    _teachers.clear();
    notifyListeners();
  }
}
