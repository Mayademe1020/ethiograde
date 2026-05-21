import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/teacher.dart';
import 'validation_service.dart';

/// Manages teacher profiles with Hive persistence.
///
/// Single-teacher (individual) and multi-teacher (school) modes supported.
/// In individual mode, the first teacher is the "active" one.
class TeacherProvider extends ChangeNotifier {
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
    try {
      return _teachers.firstWhere((t) => t.isActive);
    } catch (_) {
      return _teachers.isNotEmpty ? _teachers.first : null;
    }
  }

  /// Convenience: active teacher name, or empty string.
  String get activeTeacherName => activeTeacher?.name ?? '';

  /// Ensures the Hive box is open (lazy init).
  Future<Box> _getBox() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return await Hive.openBox(_boxName);
  }

  /// Load teachers from Hive. Safe to call multiple times.
  Future<void> loadTeachers() async {
    if (_loaded) return;
    try {
      final box = await _getBox();
      _teachers = box.values
          .map(
            (data) => Teacher.fromMap(Map<String, dynamic>.from(data as Map)))
          .toList();
      _teachers.sort((a, b) => a.name.compareTo(b.name));
      _loaded = true;
      debugPrint('TeacherProvider: loaded ${_teachers.length} teacher(s)');
    } catch (e, st) {
      debugPrint('TeacherProvider: load failed ($e)\n$st');
      _teachers = [];
      _loaded = true;
    }
    notifyListeners();
  }

  /// Add a new teacher. Returns the created Teacher on success, null on failure.
  ///
  /// Validates name (non-empty, ≤100 chars), role, and duplicate name
  /// before persisting. Check [lastAddError] for validation errors.
  Future<Teacher?> addTeacher(Teacher teacher) async {
    // Validate against existing teachers
    final validation = _validator.validateTeacher(
      teacher,
      existingTeachers: _teachers);
    if (!validation.isValid) {
      debugPrint(
        'TeacherProvider: addTeacher validation failed: '
        '${validation.errors}');
      _lastAddErrors = validation.errors;
      notifyListeners();
      return null;
    }

    try {
      final box = await _getBox();
      await box.put(teacher.id, teacher.toMap());
      _teachers.add(teacher);
      _teachers.sort((a, b) => a.name.compareTo(b.name));
      _lastAddErrors = [];
      notifyListeners();
      debugPrint('TeacherProvider: added ${teacher.name}');
      return teacher;
    } catch (e, st) {
      debugPrint('TeacherProvider: addTeacher failed ($e)\n$st');
      return null;
    }
  }

  /// Update an existing teacher. Returns true on success.
  ///
  /// Validates name, role, and duplicate name (excluding self) before persisting.
  Future<bool> updateTeacher(Teacher updated) async {
    // Validate — exclude self from duplicate check
    final others = _teachers.where((t) => t.id != updated.id).toList();
    final validation = _validator.validateTeacher(
      updated,
      existingTeachers: others);
    if (!validation.isValid) {
      debugPrint(
        'TeacherProvider: updateTeacher validation failed: '
        '${validation.errors}');
      _lastAddErrors = validation.errors;
      notifyListeners();
      return false;
    }

    try {
      final box = await _getBox();
      await box.put(updated.id, updated.toMap());
      final index = _teachers.indexWhere((t) => t.id == updated.id);
      if (index >= 0) {
        _teachers[index] = updated;
        _teachers.sort((a, b) => a.name.compareTo(b.name));
        _lastAddErrors = [];
        notifyListeners();
        debugPrint('TeacherProvider: updated ${updated.name}');
        return true;
      }
      return false;
    } catch (e, st) {
      debugPrint('TeacherProvider: updateTeacher failed ($e)\n$st');
      return false;
    }
  }

  /// Delete a teacher by ID. Returns true on success.
  Future<bool> deleteTeacher(String id) async {
    try {
      final box = await _getBox();
      await box.delete(id);
      _teachers.removeWhere((t) => t.id == id);
      notifyListeners();
      debugPrint('TeacherProvider: deleted $id');
      return true;
    } catch (e, st) {
      debugPrint('TeacherProvider: deleteTeacher failed ($e)\n$st');
      return false;
    }
  }

  /// Set a teacher as the active one (deactivates others).
  Future<void> setActive(String id) async {
    for (final t in _teachers) {
      if (t.id == id && !t.isActive) {
        await updateTeacher(t.copyWith(isActive: true));
      } else if (t.id != id && t.isActive) {
        await updateTeacher(t.copyWith(isActive: false));
      }
    }
  }

  /// Get a teacher by ID.
  Teacher? getById(String id) {
    try {
      return _teachers.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }
}
