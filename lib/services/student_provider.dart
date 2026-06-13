import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/student.dart';
import '../config/constants.dart';
import 'validation_service.dart';
import 'result.dart';

export 'result.dart';

/// Manages student persistence against the encrypted Hive `students` box.
///
/// All operations are wrapped in try/catch — persistence errors never
/// crash the app.  Callers check [Result.success].
class StudentProvider extends ChangeNotifier {
  static const _uuid = Uuid();
  static const _validator = ValidationService();

  List<Student> _students = [];
  bool _isLoading = false;
  String _selectedClassName = '';
  String _searchQuery = '';

  List<Student> get students => List.unmodifiable(_students);
  bool get isLoading => _isLoading;
  String get selectedClassName => _selectedClassName;
  String get searchQuery => _searchQuery;

  /// Filter by class ID (from ClassProvider). Empty = show all.
  List<Student> studentsByClassId(String? classId) {
    final byClass = (classId == null || classId.isEmpty)
        ? _students
        : _students.where((s) => s.classIds.contains(classId)).toList();
    return List.unmodifiable(byClass);
  }

  /// Combined filter: selected class + search query (used by StudentsTab).
  List<Student> get studentsByClass {
    final byClass = _selectedClassName.isEmpty
        ? _students
        : _students
              .where((s) => s.classIds.contains(_selectedClassName))
              .toList();
    if (_searchQuery.trim().isEmpty) return List.unmodifiable(byClass);
    final q = _searchQuery.toLowerCase();
    return List.unmodifiable(
      byClass.where(
        (s) =>
            s.firstName.toLowerCase().contains(q) ||
            s.lastName.toLowerCase().contains(q) ||
            s.studentId.toLowerCase().contains(q)));
  }

  /// Unique class IDs that students belong to (for filter chips).
  List<String> get classIdsInUse =>
      _students.expand((s) => s.classIds).toSet().toList()..sort();

  int get totalStudents => _students.length;

  StudentProvider() {
    loadStudents();
  }

  // ── Load ──────────────────────────────────────────────────────────

  /// Read every entry from the `students` box, sort by name, cache.
  Future<void> loadStudents() async {
    _isLoading = true;
    notifyListeners();

    try {
      final box = Hive.box(AppConstants.studentsBox);
      _students =
          box.values
              .map((data) => Student.fromMap(Map<String, dynamic>.from(data)))
              .toList()
            ..sort(
              (a, b) =>
                  a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    } catch (e) {
      debugPrint('[StudentProvider] loadStudents failed: $e');
      _students = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  // ── Add ───────────────────────────────────────────────────────────

  /// Validate, persist, and register a new student.
  Future<Result<Student>> addStudent(Student student) async {
    // Validate
    final validation = _validator.validateStudent(student);
    if (!validation.isValid) {
      return Result.failure(validation.errors.join('; '));
    }

    // Ensure ID
    final withId = student.id.isEmpty ? student.copyWith(id: _uuid.v4()) : student;

    // Check duplicate
    final box = Hive.box(AppConstants.studentsBox);
    if (box.containsKey(withId.id)) {
      return Result.failure('Student with ID ${withId.id} already exists');
    }

    // Persist
    try {
      await box.put(withId.id, withId.toMap());
    } catch (e) {
      debugPrint('[StudentProvider] addStudent Hive write failed: $e');
      return Result.failure('Failed to save student');
    }

    _students.add(withId);
    _students.sort(
      (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    notifyListeners();
    return Result.success(withId);
  }

  // ── Update ────────────────────────────────────────────────────────

  /// Validate and overwrite an existing student.
  Future<Result<Student>> updateStudent(Student student) async {
    final validation = _validator.validateStudent(student);
    if (!validation.isValid) {
      return Result.failure(validation.errors.join('; '));
    }

    final box = Hive.box(AppConstants.studentsBox);
    if (!box.containsKey(student.id)) {
      return Result.failure('Student ${student.id} not found');
    }

    try {
      await box.put(student.id, student.toMap());
    } catch (e) {
      debugPrint('[StudentProvider] updateStudent Hive write failed: $e');
      return Result.failure('Failed to update student');
    }

    final index = _students.indexWhere((s) => s.id == student.id);
    if (index >= 0) {
      _students[index] = student;
    }
    notifyListeners();
    return Result.success(student);
  }

  // ── Delete ────────────────────────────────────────────────────────

  /// Remove a student. Associated scan results are kept for history.
  Future<Result<void>> deleteStudent(String studentId) async {
    final box = Hive.box(AppConstants.studentsBox);
    if (!box.containsKey(studentId)) {
      return Result.failure('Student $studentId not found');
    }

    try {
      await box.delete(studentId);
    } catch (e) {
      debugPrint('[StudentProvider] deleteStudent Hive delete failed: $e');
      return Result.failure('Failed to delete student');
    }

    _students.removeWhere((s) => s.id == studentId);
    notifyListeners();
    return Result.success(null);
  }

  // ── Queries ───────────────────────────────────────────────────────

  /// Single lookup by ID. Returns `null` when not found (not an error).
  Student? getStudentById(String id) {
    for (final s in _students) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Filter students by class name.
  List<Student> getStudentsByClass(String className) {
    return _students.where((s) => s.className == className).toList();
  }

  /// Case-insensitive search across English names names.
  List<Student> searchStudents(String query) {
    if (query.trim().isEmpty) return List.unmodifiable(_students);
    final q = query.toLowerCase();
    return _students
        .where(
          (s) =>
              s.firstName.toLowerCase().contains(q) ||
              s.lastName.toLowerCase().contains(q) ||
              s.studentId.toLowerCase().contains(q))
        .toList();
  }

  // ── Bulk ──────────────────────────────────────────────────────────

  /// Add multiple students in one call. Batches Hive writes + single notify.
  Future<Result<int>> addStudents(List<Student> students) async {
    if (students.isEmpty) return Result.failure('No students provided');

    final box = Hive.box(AppConstants.studentsBox);
    int added = 0;
    final List<String> errors = [];

    for (final s in students) {
      // Validate
      final validation = _validator.validateStudent(s);
      if (!validation.isValid) {
        errors.add('${s.fullName}: ${validation.errors.join("; ")}');
        continue;
      }

      // Ensure ID
      final withId = s.id.isEmpty ? s.copyWith(id: _uuid.v4()) : s;

      // Skip duplicates
      if (box.containsKey(withId.id)) continue;

      try {
        await box.put(withId.id, withId.toMap());
        _students.add(withId);
        added++;
      } catch (e) {
        errors.add('${s.fullName}: save failed');
      }
    }

    if (added > 0) {
      _students.sort(
        (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
      notifyListeners(); // Single rebuild for the whole batch
      debugPrint(
        '[StudentProvider] Batch added $added/${students.length} students');
      return Result.success(added);
    }

    return Result.failure('No students added. Errors: ${errors.join("; ")}');
  }

  // ── UI helpers ────────────────────────────────────────────────────

  void setSelectedClass(String className) {
    _selectedClassName = className;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Wipe the box and in-memory cache.
  Future<void> clearAll() async {
    try {
      final box = Hive.box(AppConstants.studentsBox);
      await box.clear();
    } catch (e) {
      debugPrint('[StudentProvider] clearAll failed: $e');
    }
    _students.clear();
    notifyListeners();
  }
}
