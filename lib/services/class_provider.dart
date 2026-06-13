import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/class_info.dart';
import '../models/student.dart';

/// Manages class profiles — the primary organizational unit.
///
/// Classes group students so assessments and scanning are scoped.
/// Every class belongs to one teacher (ownerId).
/// Students can belong to multiple classes via [Student.classIds].
class ClassProvider extends ChangeNotifier {
  static const _boxName = 'classes';

  List<ClassInfo> _classes = [];
  bool _loaded = false;
  String _selectedClassId = '';

  List<ClassInfo> get classes => List.unmodifiable(_classes);
  bool get isLoaded => _loaded;
  String get selectedClassId => _selectedClassId;

  ClassInfo? get selectedClass {
    if (_selectedClassId.isEmpty) return null;
    for (final c in _classes) {
      if (c.id == _selectedClassId) return c;
    }
    return null;
  }

  /// Classes for a specific teacher.
  List<ClassInfo> classesForTeacher(String teacherId) =>
      _classes.where((c) => c.ownerId == teacherId).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  /// Get a class by ID.
  ClassInfo? getClassById(String id) {
    for (final c in _classes) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Classes a student belongs to.
  List<ClassInfo> classesForStudent(String studentId) =>
      _classes.where((c) => c.studentIds.contains(studentId)).toList();

  /// Ensures the Hive box is open (lazy init).
  Future<Box> _getBox() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return await Hive.openBox(_boxName);
  }

  // ── Load ──────────────────────────────────────────────────────────

  Future<void> loadClasses() async {
    if (_loaded) return;
    try {
      final box = await _getBox();
      _classes =
          box.values
              .map(
                (data) =>
                    ClassInfo.fromMap(Map<String, dynamic>.from(data as Map)))
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      _loaded = true;
      debugPrint('ClassProvider: loaded ${_classes.length} class(es)');
    } catch (e) {
      debugPrint('ClassProvider: load failed ($e)');
      _classes = [];
      _loaded = true;
    }
    notifyListeners();
  }

  // ── Add ───────────────────────────────────────────────────────────

  /// Create a new class. Returns the ClassInfo on success, null on failure.
  Future<ClassInfo?> addClass(ClassInfo classInfo) async {
    if (classInfo.name.trim().isEmpty) return null;

    try {
      final box = await _getBox();
      await box.put(classInfo.id, classInfo.toMap());
      _classes.add(classInfo);
      _classes.sort((a, b) => a.name.compareTo(b.name));
      notifyListeners();
      debugPrint('ClassProvider: added ${classInfo.name}');
      return classInfo;
    } catch (e) {
      debugPrint('ClassProvider: addClass failed ($e)');
      return null;
    }
  }

  // ── Update ────────────────────────────────────────────────────────

  Future<bool> updateClass(ClassInfo updated) async {
    try {
      final box = await _getBox();
      await box.put(updated.id, updated.toMap());
      final index = _classes.indexWhere((c) => c.id == updated.id);
      if (index >= 0) {
        _classes[index] = updated;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('ClassProvider: updateClass failed ($e)');
      return false;
    }
  }

  // ── Delete ────────────────────────────────────────────────────────

  Future<bool> deleteClass(String classId) async {
    try {
      final box = await _getBox();
      await box.delete(classId);
      _classes.removeWhere((c) => c.id == classId);
      if (_selectedClassId == classId) _selectedClassId = '';
      notifyListeners();
      debugPrint('ClassProvider: deleted $classId');
      return true;
    } catch (e) {
      debugPrint('ClassProvider: deleteClass failed ($e)');
      return false;
    }
  }

  // ── Student ↔ Class linking ──────────────────────────────────────

  /// Add a student to a class. Updates both sides.
  Future<bool> addStudentToClass(String classId, String studentId) async {
    final index = _classes.indexWhere((c) => c.id == classId);
    if (index < 0) return false;

    final cls = _classes[index];
    if (cls.studentIds.contains(studentId)) return true; // already there

    final updated = cls.copyWith(studentIds: [...cls.studentIds, studentId]);
    return updateClass(updated);
  }

  /// Remove a student from a class.
  Future<bool> removeStudentFromClass(String classId, String studentId) async {
    final index = _classes.indexWhere((c) => c.id == classId);
    if (index < 0) return false;

    final cls = _classes[index];
    final updated = cls.copyWith(
      studentIds: cls.studentIds.where((id) => id != studentId).toList());
    return updateClass(updated);
  }

  /// Add multiple students to a class at once.
  Future<int> addStudentsToClass(
    String classId,
    List<String> studentIds) async {
    final index = _classes.indexWhere((c) => c.id == classId);
    if (index < 0) return 0;

    final cls = _classes[index];
    final existing = cls.studentIds.toSet();
    final merged = {...existing, ...studentIds}.toList();

    final updated = cls.copyWith(studentIds: merged);
    final ok = await updateClass(updated);
    return ok ? merged.length - existing.length : 0;
  }

  // ── Selection ─────────────────────────────────────────────────────

  void selectClass(String classId) {
    _selectedClassId = classId;
    notifyListeners();
  }

  void clearSelection() {
    _selectedClassId = '';
    notifyListeners();
  }

  // ── Cleanup ───────────────────────────────────────────────────────

  Future<void> clearAll() async {
    try {
      final box = await _getBox();
      await box.clear();
    } catch (e) {
      debugPrint('ClassProvider: clearAll failed ($e)');
    }
    _classes.clear();
    _selectedClassId = '';
    notifyListeners();
  }
}
