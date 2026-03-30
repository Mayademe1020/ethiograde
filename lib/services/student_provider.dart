import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/student.dart';
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

  List<Student> get students => List.unmodifiable(_students);
  bool get isLoading => _isLoading;
  String get selectedClassName => _selectedClassName;

  List<Student> get studentsByClass => _selectedClassName.isEmpty
      ? List.unmodifiable(_students)
      : List.unmodifiable(
          _students.where((s) => s.className == _selectedClassName));

  List<String> get classNames =>
      _students.map((s) => s.className).toSet().toList()..sort();

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
      _students = box.values
          .map((data) => Student.fromMap(Map<String, dynamic>.from(data)))
          .toList()
        ..sort((a, b) => a.fullName.toLowerCase().compareTo(
              b.fullName.toLowerCase(),
            ));
    } catch (e, st) {
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
    final withId = student.id.isEmpty
        ? Student(
            id: _uuid.v4(),
            firstName: student.firstName,
            lastName: student.lastName,
            firstNameAmharic: student.firstNameAmharic,
            lastNameAmharic: student.lastNameAmharic,
            studentId: student.studentId,
            className: student.className,
            section: student.section,
            grade: student.grade,
            photoPath: student.photoPath,
            parentPhone: student.parentPhone,
            createdAt: student.createdAt,
            metadata: student.metadata,
          )
        : student;

    // Check duplicate
    final box = Hive.box(AppConstants.studentsBox);
    if (box.containsKey(withId.id)) {
      return Result.failure('Student with ID ${withId.id} already exists');
    }

    // Persist
    try {
      await box.put(withId.id, withId.toMap());
    } catch (e, st) {
      debugPrint('[StudentProvider] addStudent Hive write failed: $e');
      return Result.failure('Failed to save student');
    }

    _students.add(withId);
    _students.sort((a, b) => a.fullName.toLowerCase().compareTo(
          b.fullName.toLowerCase(),
        ));
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
    } catch (e, st) {
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
    } catch (e, st) {
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
    try {
      return _students.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Filter students by class name.
  List<Student> getStudentsByClass(String className) {
    return _students.where((s) => s.className == className).toList();
  }

  /// Case-insensitive search across English + Amharic names.
  List<Student> searchStudents(String query) {
    if (query.trim().isEmpty) return List.unmodifiable(_students);
    final q = query.toLowerCase();
    return _students
        .where((s) =>
            s.firstName.toLowerCase().contains(q) ||
            s.lastName.toLowerCase().contains(q) ||
            s.firstNameAmharic.contains(query) ||
            s.lastNameAmharic.contains(query) ||
            s.studentId.toLowerCase().contains(q))
        .toList();
  }

  // ── Bulk ──────────────────────────────────────────────────────────

  /// Add multiple students in one call. Returns count of successful adds.
  Future<Result<int>> addStudents(List<Student> students) async {
    int added = 0;
    for (final s in students) {
      final result = await addStudent(s);
      if (result.success) added++;
    }
    return added > 0
        ? Result.success(added)
        : Result.failure('No students were added');
  }

  // ── UI helpers ────────────────────────────────────────────────────

  void setSelectedClass(String className) {
    _selectedClassName = className;
    notifyListeners();
  }

  /// Wipe the box and in-memory cache.
  Future<void> clearAll() async {
    try {
      final box = Hive.box(AppConstants.studentsBox);
      await box.clear();
    } catch (e, st) {
      debugPrint('[StudentProvider] clearAll failed: $e');
    }
    _students.clear();
    notifyListeners();
  }
}
