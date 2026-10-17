import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/class_info.dart';
import '../models/student.dart';
import 'result.dart';

/// Result of checking whether a class can be deleted.
class ClassDeletionCheck {
  final bool canDelete;
  final List<String> blockingReasons;

  const ClassDeletionCheck({
    required this.canDelete,
    required this.blockingReasons,
  });
}

/// Manages class profiles — the primary organizational unit.
///
/// Classes group students so assessments and scanning are scoped.
/// Every class belongs to one teacher (ownerId).
/// Students can belong to multiple classes via [Student.classIds].
class ClassProvider extends ChangeNotifier {
  static const _boxName = 'classes';

  List<ClassInfo> _classes = [];
  bool _loaded = false;
  bool _loadFailed = false;
  String _selectedClassId = '';

  List<ClassInfo> get classes => List.unmodifiable(_classes);
  bool get isLoaded => _loaded;
  bool get loadFailed => _loadFailed;
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
      _loadFailed = false;
      debugPrint('ClassProvider: loaded ${_classes.length} class(es)');
    } catch (e) {
      debugPrint('ClassProvider: load failed ($e)');
      _classes = [];
      _loaded = true;
      _loadFailed = true;
    }
    notifyListeners();
  }

  /// Clear the loaded cache and reload from Hive (used for retry).
  Future<void> reload() async {
    _loaded = false;
    _loadFailed = false;
    await loadClasses();
  }

  // ── Add ───────────────────────────────────────────────────────────

  /// Check if a class with the same grade+section+subject+year already exists.
  /// [excludeId] is for edit mode — don't flag the class being edited.
  bool hasDuplicate({
    required int grade,
    required String section,
    required String subject,
    required String ownerId,
    required String academicYear,
    String? excludeId,
  }) {
    final normSubject = subject.trim().toLowerCase();
    final normSection = section.trim().toUpperCase();
    return _classes.any((c) =>
      c.id != excludeId &&
      c.ownerId == ownerId &&
      c.grade == grade &&
      c.section.toUpperCase() == normSection &&
      c.subject.trim().toLowerCase() == normSubject &&
      c.academicYear == academicYear);
  }

  /// Create a new class. Returns the ClassInfo on success, null on failure.
  Future<Result<ClassInfo>> addClass(ClassInfo classInfo) async {
    if (classInfo.name.trim().isEmpty) {
      return const Result.failure('Class name is required');
    }

    try {
      final box = await _getBox();
      await box.put(classInfo.id, classInfo.toMap());
      _classes.add(classInfo);
      _classes.sort((a, b) => a.name.compareTo(b.name));
      notifyListeners();
      debugPrint('ClassProvider: added ${classInfo.name}');
      return Result.success(classInfo);
    } catch (e) {
      debugPrint('ClassProvider: addClass failed ($e)');
      return const Result.failure('Failed to save class');
    }
  }

  // ── Update ────────────────────────────────────────────────────────

  Future<Result<ClassInfo>> updateClass(ClassInfo updated) async {
    try {
      final box = await _getBox();
      await box.put(updated.id, updated.toMap());
      final index = _classes.indexWhere((c) => c.id == updated.id);
      if (index >= 0) {
        _classes[index] = updated;
        notifyListeners();
        return Result.success(updated);
      }
      return Result.failure('Class ${updated.id} not found');
    } catch (e) {
      debugPrint('ClassProvider: updateClass failed ($e)');
      return const Result.failure('Failed to update class');
    }
  }

  // ── Dependency Check ────────────────────────────────────────────────

  /// Check if a class can be safely deleted.
  ///
  /// Returns blocking reasons if deletion is not safe.
  ClassDeletionCheck canDeleteClass(String classId) {
    final cls = _classes.firstWhere((c) => c.id == classId, orElse: () => ClassInfo(name: '', ownerId: ''));
    if (cls.id.isEmpty) {
      return const ClassDeletionCheck(canDelete: true, blockingReasons: []);
    }

    final reasons = <String>[];

    // Check for students in the class
    if (cls.studentIds.isNotEmpty) {
      reasons.add('${cls.studentIds.length} student(s) still in this class. Remove them first.');
    }

    // Check for assessments linked to this class
    try {
      final assessBox = Hive.box('assessments');
      for (final key in assessBox.keys) {
        final data = assessBox.get(key);
        if (data == null) continue;
        final map = Map<String, dynamic>.from(data as Map);
        if (map['className'] == cls.displayName) {
          reasons.add('Assessment "${map['title'] ?? 'Unknown'}" is linked to this class.');
          break; // One assessment is enough to block
        }
      }
    } catch (_) {}

    // Check for grading drafts
    try {
      final draftBox = Hive.box('grading_drafts');
      for (final key in draftBox.keys) {
        final data = draftBox.get(key);
        if (data == null) continue;
        final map = Map<String, dynamic>.from(data as Map);
        if (map['metadata'] is Map) {
          final meta = Map<String, dynamic>.from(map['metadata']);
          if (meta['classId'] == classId) {
            reasons.add('Grading draft exists for this class.');
            break;
          }
        }
      }
    } catch (_) {}

    return ClassDeletionCheck(
      canDelete: reasons.isEmpty,
      blockingReasons: reasons,
    );
  }

  // ── Delete ────────────────────────────────────────────────────────

  Future<Result<void>> deleteClass(String classId) async {
    try {
      final box = await _getBox();
      await box.delete(classId);
      _classes.removeWhere((c) => c.id == classId);
      if (_selectedClassId == classId) _selectedClassId = '';
      notifyListeners();
      debugPrint('ClassProvider: deleted $classId');
      return const Result.success(null);
    } catch (e) {
      debugPrint('ClassProvider: deleteClass failed ($e)');
      return const Result.failure('Failed to delete class');
    }
  }

  // ── Student ↔ Class linking ──────────────────────────────────────

  /// Add a student to a class. Updates both sides.
  Future<Result<void>> addStudentToClass(String classId, String studentId) async {
    final index = _classes.indexWhere((c) => c.id == classId);
    if (index < 0) return Result.failure('Class $classId not found');

    final cls = _classes[index];
    if (cls.studentIds.contains(studentId)) {
      return const Result.success(null);
    } // already there

    final updated = cls.copyWith(studentIds: [...cls.studentIds, studentId]);
    return updateClass(updated).then((r) => r.success
        ? const Result.success(null)
        : Result.failure(r.error ?? 'Failed to add student'));
  }

  /// Remove a student from a class.
  Future<Result<void>> removeStudentFromClass(
    String classId,
    String studentId,
  ) async {
    final index = _classes.indexWhere((c) => c.id == classId);
    if (index < 0) return Result.failure('Class $classId not found');

    final cls = _classes[index];
    final updated = cls.copyWith(
      studentIds: cls.studentIds.where((id) => id != studentId).toList());
    return updateClass(updated).then((r) => r.success
        ? const Result.success(null)
        : Result.failure(r.error ?? 'Failed to remove student'));
  }

  /// Add multiple students to a class at once.
  Future<Result<int>> addStudentsToClass(
    String classId,
    List<String> studentIds) async {
    final index = _classes.indexWhere((c) => c.id == classId);
    if (index < 0) return Result.failure('Class $classId not found');

    final cls = _classes[index];
    final existing = cls.studentIds.toSet();
    final merged = {...existing, ...studentIds}.toList();

    final updated = cls.copyWith(studentIds: merged);
    final ok = await updateClass(updated);
    return ok.success
        ? Result.success(merged.length - existing.length)
        : Result.failure(ok.error ?? 'Failed to add students');
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
