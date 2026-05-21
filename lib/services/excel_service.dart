import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/student.dart';

/// CSV import and export for students and assessment results.
///
/// Pure Dart — no native dependencies beyond file_picker and path_provider.
class ImportService {
  static final ImportService _instance = ImportService._();
  factory ImportService() => _instance;
  ImportService._();


  static final _columnPatterns = <String, List<RegExp>>{
    'firstName': [
      RegExp(r'^ስም$', unicode: true),
      RegExp(r'^name$', caseSensitive: false),
      RegExp(r'first\s*name', caseSensitive: false),
      RegExp(r'^fullname$', caseSensitive: false),
      RegExp(r'^full\s*name$', caseSensitive: false),
    ],
    'lastName': [
      RegExp(r'የአባት\s*ስም', unicode: true),
      RegExp(r"father'?s?\s*name", caseSensitive: false),
      RegExp(r'last\s*name', caseSensitive: false),
      RegExp(r'surname', caseSensitive: false),
      RegExp(r'family\s*name', caseSensitive: false),
    ],
    'studentId': [
      RegExp(r'ተ\.?ቁ', unicode: true),
      RegExp(r'id', caseSensitive: false),
      RegExp(r'roll\s*no', caseSensitive: false),
      RegExp(r'student\s*id', caseSensitive: false),
      RegExp(r'student\s*number', caseSensitive: false),
    ],
    'gender': [
      RegExp(r'ጾታ', unicode: true),
      RegExp(r'gender', caseSensitive: false),
      RegExp(r'sex', caseSensitive: false),
      RegExp(r'ወንድ/ሴት', unicode: true),
      RegExp(r'M/F', caseSensitive: false),
    ],
    'className': [
      RegExp(r'ክፍል', unicode: true),
      RegExp(r'class', caseSensitive: false),
      RegExp(r'grade', caseSensitive: false),
      RegExp(r'ደረጃ', unicode: true),
    ],
    'section': [
      RegExp(r'ቡድን', unicode: true),
      RegExp(r'section', caseSensitive: false),
      RegExp(r'stream', caseSensitive: false),
      RegExp(r'group', caseSensitive: false),
    ],
    'grade': [
      RegExp(r'ክፍል\s*ቁጥር', unicode: true),
      RegExp(r'grade\s*level', caseSensitive: false),
      RegExp(r'year', caseSensitive: false),
    ],
  };

  // ── Import ──────────────────────────────────────────────────────

  /// Import students from a CSV file.
  /// File picker shows .csv files only.
  Future<ImportResult> importStudents({String? classId}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv']);

    if (result == null || result.files.isEmpty) {
      return ImportResult(success: false, message: 'No file selected');
    }

    final file = File(result.files.single.path!);
    final content = await file.readAsString();

    return _parseCsvContent(content, classId: classId);
  }

  /// Parse CSV content string into students. Public for testing.
  ImportResult _parseCsvContent(String content, {String? classId}) {
    final rows = const CsvToListConverter(eol: '\n').convert(content);
    if (rows.isEmpty) {
      return ImportResult(success: false, message: 'Empty CSV file');
    }

    // Find header row
    int headerRow = -1;
    Map<String, int> columnMap = {};

    for (int i = 0; i < rows.length; i++) {
      final headerCandidates =
          rows[i].map((cell) => cell.toString().trim()).toList();
      final detected = _detectColumns(headerCandidates);
      if (detected.containsKey('firstName') ||
          detected.containsKey('studentId')) {
        headerRow = i;
        columnMap = detected;
        break;
      }
    }

    if (headerRow == -1) {
      return ImportResult(
        success: false,
        message: 'No header row found — expected columns like ስም / Name / ID');
    }

    final students = <Student>[];
    final errors = <String>[];

    for (int i = headerRow + 1; i < rows.length; i++) {
      final row = rows[i];

      try {
        final firstName = _getCell(row, columnMap['firstName']);
        final lastName = _getCell(row, columnMap['lastName']);
        final studentId = _getCell(row, columnMap['studentId']);
        final genderRaw = _getCell(row, columnMap['gender']);
        final className = _getCell(row, columnMap['className']);
        final section = _getCell(row, columnMap['section']);
        final gradeStr = _getCell(row, columnMap['grade']);

        if (firstName.isEmpty && lastName.isEmpty && studentId.isEmpty) {
          continue;
        }

        final classIds = <String>[];
        if (classId != null && classId.isNotEmpty) classIds.add(classId);

        students.add(Student(
          id: const Uuid().v4(),
          studentId: studentId,
          firstName: firstName,
          lastName: lastName,
          gender: _normalizeGender(genderRaw),
          classIds: classIds,
          className: className,
          section: section,
          grade: int.tryParse(gradeStr) ?? 1));
      } catch (e) {
        errors.add('Row ${i + 1}: $e');
      }
    }

    if (students.isEmpty) {
      final dataRows = rows.length - headerRow - 1;
      return ImportResult(
        success: false,
        message: dataRows > 0
            ? 'Found $dataRows rows but none had valid names'
            : 'No data rows found after header',
        errors: errors);
    }

    return ImportResult(
      success: true,
      students: students,
      message: 'Found ${students.length} students',
      errors: errors);
  }

  // ── Export ──────────────────────────────────────────────────────

  /// Export students to CSV file.
  /// [outputDir] overrides the default directory (for testing).
  Future<String> exportStudents(
    List<Student> students, {
    String? outputDir,
  }) async {
    final rows = <List<dynamic>>[
      [
        'ID',
        'FirstName',
        'LastName',
        'Gender',
        'Class',
        'Section',
        'Grade',
      ],
      ...students.map((s) => [
            s.studentId,
            s.firstName,
            s.lastName,
            s.gender,
            s.className,
            s.section,
            s.grade,
          ]),
    ];

    final csv = const ListToCsvConverter().convert(rows);
    final dirPath =
        outputDir ?? (await getApplicationDocumentsDirectory()).path;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '$dirPath/ethiograde_students_$timestamp.csv';
    await File(path).writeAsString(csv, encoding: utf8);
    return path;
  }

  /// Export assessment results to CSV file.
  /// [outputDir] overrides the default directory (for testing).
  Future<String> exportResults({
    required String assessmentTitle,
    required List<Map<String, dynamic>> results,
    String? outputDir,
  }) async {
    final rows = <List<dynamic>>[
      ['StudentName', 'StudentID', 'Score', 'MaxScore', 'Percentage', 'Grade', 'Status'],
      ...results.map((r) {
        final pct = (r['percentage'] ?? 0).toDouble();
        return [
          r['studentName'] ?? '',
          r['studentId'] ?? '',
          (r['totalScore'] ?? 0).toDouble(),
          (r['maxScore'] ?? 0).toDouble(),
          '${pct.toStringAsFixed(1)}%',
          r['grade'] ?? '',
          pct >= 50 ? 'PASS' : 'FAIL',
        ];
      }),
    ];

    final csv = const ListToCsvConverter().convert(rows);
    final dirPath =
        outputDir ?? (await getApplicationDocumentsDirectory()).path;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = assessmentTitle.replaceAll(RegExp(r'[^\w]'), '_');
    final path = '$dirPath/ethiograde_${safeName}_$timestamp.csv';
    await File(path).writeAsString(csv, encoding: utf8);
    return path;
  }

  // ── Helpers ─────────────────────────────────────────────────────

  Map<String, int> _detectColumns(List<String> headers) {
    final map = <String, int>{};
    for (int i = 0; i < headers.length; i++) {
      final h = headers[i].trim();
      if (h.isEmpty) continue;
      for (final entry in _columnPatterns.entries) {
        if (map.containsKey(entry.key)) continue;
        for (final pattern in entry.value) {
          if (pattern.hasMatch(h)) {
            map[entry.key] = i;
            break;
          }
        }
      }
    }
    return map;
  }

  String _normalizeGender(String raw) {
    if (raw.isEmpty) return '';
    final lower = raw.trim().toLowerCase();
    if (lower == 'ወንድ' || lower == 'ወ' || lower == 'm' || lower == 'male' || lower == 'w') {
      return 'M';
    }
    if (lower == 'ሴት' || lower == 'ሴ' || lower == 'f' || lower == 'female') {
      return 'F';
    }
    if (raw.trim().toUpperCase() == 'M') return 'M';
    if (raw.trim().toUpperCase() == 'F') return 'F';
    return '';
  }

  String _getCell(List<dynamic> row, int? index) {
    if (index == null || index >= row.length) return '';
    return row[index].toString().trim();
  }
}

class ImportResult {
  final bool success;
  final String message;
  final List<Student> students;
  final List<String> errors;

  ImportResult({
    required this.success,
    required this.message,
    this.students = const [],
    this.errors = const [],
  });
}
