import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/student.dart';
import '../config/constants.dart';

class StudentProvider extends ChangeNotifier {
  List<Student> _students = [];
  bool _isLoading = false;
  String _selectedClassName = '';

  List<Student> get students => _students;
  bool get isLoading => _isLoading;
  String get selectedClassName => _selectedClassName;

  List<Student> get studentsByClass => _selectedClassName.isEmpty
      ? _students
      : _students.where((s) => s.className == _selectedClassName).toList();

  List<String> get classNames =>
      _students.map((s) => s.className).toSet().toList()..sort();

  int get totalStudents => _students.length;

  StudentProvider() {
    loadStudents();
  }

  Future<void> loadStudents() async {
    _isLoading = true;
    notifyListeners();

    final box = Hive.box(AppConstants.studentsBox);
    _students = box.values
        .map((data) => Student.fromMap(Map<String, dynamic>.from(data)))
        .toList()
      ..sort((a, b) => a.lastName.compareTo(b.lastName));

    _isLoading = false;
    notifyListeners();
  }

  Future<void> addStudent(Student student) async {
    final box = Hive.box(AppConstants.studentsBox);
    await box.put(student.id, student.toMap());
    _students.add(student);
    _students.sort((a, b) => a.lastName.compareTo(b.lastName));
    notifyListeners();
  }

  Future<void> addStudents(List<Student> students) async {
    final box = Hive.box(AppConstants.studentsBox);
    for (final student in students) {
      await box.put(student.id, student.toMap());
    }
    _students.addAll(students);
    _students.sort((a, b) => a.lastName.compareTo(b.lastName));
    notifyListeners();
  }

  Future<void> updateStudent(Student student) async {
    final box = Hive.box(AppConstants.studentsBox);
    await box.put(student.id, student.toMap());

    final index = _students.indexWhere((s) => s.id == student.id);
    if (index >= 0) {
      _students[index] = student;
    }
    notifyListeners();
  }

  Future<void> deleteStudent(String id) async {
    final box = Hive.box(AppConstants.studentsBox);
    await box.delete(id);
    _students.removeWhere((s) => s.id == id);
    notifyListeners();
  }

  void setSelectedClass(String className) {
    _selectedClassName = className;
    notifyListeners();
  }

  Student? getStudentById(String id) {
    try {
      return _students.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  List<Student> getStudentsByClass(String className) {
    return _students.where((s) => s.className == className).toList();
  }

  List<Student> searchStudents(String query) {
    final q = query.toLowerCase();
    return _students.where((s) =>
        s.firstName.toLowerCase().contains(q) ||
        s.lastName.toLowerCase().contains(q) ||
        s.firstNameAmharic.contains(query) ||
        s.lastNameAmharic.contains(query) ||
        s.studentId.toLowerCase().contains(q)
    ).toList();
  }

  Future<void> clearAll() async {
    final box = Hive.box(AppConstants.studentsBox);
    await box.clear();
    _students.clear();
    notifyListeners();
  }
}
