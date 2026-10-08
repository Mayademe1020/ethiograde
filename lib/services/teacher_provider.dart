import 'package:flutter/foundation.dart';
import '../models/teacher.dart';
import 'app_log.dart';
import 'error_handler.dart';
import 'hive_box_mixin.dart';
import 'result.dart';
import 'validation_service.dart';

/// Manages teacher profiles with Hive persistence.
///
/// Single-teacher (individual) and multi-teacher (school) modes supported.
/// In individual mode, the first teacher is the "active" one.
class TeacherProvider extends ChangeNotifier with HiveBoxMixin {
  static const String _boxName = 'teachers';
  static const ValidationService _validator = ValidationService();
  List<Teacher> _teachers = [];
  bool _loaded = false;
  List<String> _lastAddErrors = [];

  List<Teacher> get teachers => List.unmodifiable(_teachers);
  bool get isLoaded => _loaded;

  /// Validation errors from the last [addTeacher] or [updateTeacher] call.
  List<String> get lastAddErrors => List.unmodifiable(_lastAddErrors);

  /// The currently active teacher (first active one, or the single teacher).
  Teacher? get activeTeacher {
    for (final t in _teachers) {
      if (t.isActive) return t;
    }
    return _teachers.isNotEmpty ? _teachers.first : null;
  }

  /// Convenience: active teacher name, or empty string.
  String get activeTeacherName => activeTeacher?.name ?? '';

  /// Load teachers from Hive. Safe to call multiple times.
  Future<void> loadTeachers() async {
    if (_loaded) return;
    try {
      final box = await openBox(_boxName);
      _teachers = box.values
          .map(
            (data) => Teacher.fromMap(Map<String, dynamic>.from(data as Map)),
          )
          .toList();
      _teachers.sort((a, b) => a.name.compareTo(b.name));
      _loaded = true;
      AppLog.info(this, 'loadTeachers', 'loaded ${_teachers.length} teacher(s)');
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'loadTeachers', e, st);
      _teachers = [];
      _loaded = true;
    }
    notifyListeners();
  }

  /// Add a new teacher. Returns the created Teacher on success, null on failure.
  Future<Result<Teacher>> addTeacher(Teacher teacher) async {
    final validation = _validator.validateTeacher(
      teacher,
      existingTeachers: _teachers,
    );
    if (!validation.isValid) {
      AppLog.warn(this, 'addTeacher', 'validation failed: ${validation.errors}');
      _lastAddErrors = validation.errors;
      notifyListeners();
      return Result.failure(validation.errors.join('; '));
    }

    try {
      final box = await openBox(_boxName);
      await box.put(teacher.id, teacher.toMap());
      _teachers.add(teacher);
      _teachers.sort((a, b) => a.name.compareTo(b.name));
      _lastAddErrors = [];
      notifyListeners();
      AppLog.info(this, 'addTeacher', 'added ${teacher.name}');
      return Result.success(teacher);
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'addTeacher', e, st);
      return const Result.failure('Failed to save teacher');
    }
  }

  /// Update an existing teacher. Returns true on success.
  Future<Result<Teacher>> updateTeacher(Teacher updated) async {
    final others = _teachers.where((t) => t.id != updated.id).toList();
    final validation = _validator.validateTeacher(
      updated,
      existingTeachers: others,
    );
    if (!validation.isValid) {
      AppLog.warn(this, 'updateTeacher', 'validation failed: ${validation.errors}');
      _lastAddErrors = validation.errors;
      notifyListeners();
      return Result.failure(validation.errors.join('; '));
    }

    try {
      final box = await openBox(_boxName);
      await box.put(updated.id, updated.toMap());
      final index = _teachers.indexWhere((t) => t.id == updated.id);
      if (index >= 0) {
        _teachers[index] = updated;
        _teachers.sort((a, b) => a.name.compareTo(b.name));
        _lastAddErrors = [];
        notifyListeners();
        AppLog.info(this, 'updateTeacher', 'updated ${updated.name}');
        return Result.success(updated);
      }
      return Result.failure('Teacher ${updated.id} not found');
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'updateTeacher', e, st);
      return const Result.failure('Failed to update teacher');
    }
  }

  /// Delete a teacher by ID. Returns true on success.
  Future<Result<void>> deleteTeacher(String id) async {
    try {
      final box = await openBox(_boxName);
      await box.delete(id);
      _teachers.removeWhere((t) => t.id == id);
      notifyListeners();
      AppLog.info(this, 'deleteTeacher', 'deleted $id');
      return const Result.success(null);
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'deleteTeacher', e, st);
      return const Result.failure('Failed to delete teacher');
    }
  }

  /// Set a teacher as the active one (deactivates others).
  Future<Result<void>> setActive(String id) async {
    for (final t in _teachers) {
      if (t.id == id && !t.isActive) {
        await updateTeacher(t.copyWith(isActive: true));
      } else if (t.id != id && t.isActive) {
        await updateTeacher(t.copyWith(isActive: false));
      }
    }
    return const Result.success(null);
  }

  /// Get a teacher by ID.
  Teacher? getById(String id) {
    for (final t in _teachers) {
      if (t.id == id) return t;
    }
    return null;
  }
}
