import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/student.dart';

class ExcelService {
  static final ExcelService _instance = ExcelService._();
  factory ExcelService() => _instance;
  ExcelService._();

  /// Import students from an Excel (.xlsx) file
  Future<ExcelImportResult> importStudents() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );

    if (result == null || result.files.isEmpty) {
      return ExcelImportResult(
        success: false,
        message: 'No file selected',
      );
    }

    final file = File(result.files.single.path!);
    final bytes = await file.readAsBytes();
    final excel = Excel.decodeBytes(bytes);

    final students = <Student>[];
    final errors = <String>[];
    int rowNumber = 0;

    for (final sheetName in excel.tables.keys) {
      final sheet = excel.tables[sheetName];
      if (sheet == null) continue;

      // Find header row (look for "Name" or "First" or "ስም")
      int headerRow = -1;
      Map<String, int> columnMap = {};

      for (int i = 0; i < sheet.maxRows; i++) {
        final row = sheet.rows[i];
        final headerCandidates = row
            .map((cell) => cell?.value?.toString().toLowerCase().trim() ?? '')
            .toList();

        if (headerCandidates.any((h) =>
            h.contains('name') ||
            h.contains('ስም') ||
            h.contains('first'))) {
          headerRow = i;
          columnMap = _detectColumns(headerCandidates);
          break;
        }
      }

      if (headerRow == -1) {
        errors.add('Could not find header row with student names');
        continue;
      }

      // Parse data rows
      for (int i = headerRow + 1; i < sheet.maxRows; i++) {
        rowNumber = i + 1;
        final row = sheet.rows[i];

        try {
          final firstName = _getCellValue(row, columnMap['firstName']);
          final lastName = _getCellValue(row, columnMap['lastName']);
          final firstNameAm = _getCellValue(row, columnMap['firstNameAmharic']);
          final lastNameAm = _getCellValue(row, columnMap['lastNameAmharic']);
          final studentId = _getCellValue(row, columnMap['studentId']);
          final className = _getCellValue(row, columnMap['className']);
          final section = _getCellValue(row, columnMap['section']);
          final gradeStr = _getCellValue(row, columnMap['grade']);

          if (firstName.isEmpty && lastName.isEmpty) continue;

          final student = Student(
            id: const Uuid().v4(),
            firstName: firstName,
            lastName: lastName,
            firstNameAmharic: firstNameAm,
            lastNameAmharic: lastNameAm,
            studentId: studentId,
            className: className,
            section: section,
            grade: int.tryParse(gradeStr) ?? 1,
          );

          students.add(student);
        } catch (e) {
          errors.add('Row $rowNumber: $e');
        }
      }

      // Only process first sheet
      break;
    }

    if (students.isEmpty) {
      return ExcelImportResult(
        success: false,
        message: 'No valid students found in file',
        errors: errors,
      );
    }

    return ExcelImportResult(
      success: true,
      students: students,
      message: 'Imported ${students.length} students',
      errors: errors,
    );
  }

  /// Export students to Excel file
  Future<String> exportStudents(List<Student> students) async {
    final excel = Excel.createExcel();
    final sheet = excel['Students'];

    // Headers
    sheet.appendRow([
      TextCellValue('First Name'),
      TextCellValue('Last Name'),
      TextCellValue('ስም (Amharic)'),
      TextCellValue('የአባት ስም (Amharic)'),
      TextCellValue('Student ID'),
      TextCellValue('Class'),
      TextCellValue('Section'),
      TextCellValue('Grade'),
    ]);

    // Data
    for (final student in students) {
      sheet.appendRow([
        TextCellValue(student.firstName),
        TextCellValue(student.lastName),
        TextCellValue(student.firstNameAmharic),
        TextCellValue(student.lastNameAmharic),
        TextCellValue(student.studentId),
        TextCellValue(student.className),
        TextCellValue(student.section),
        IntCellValue(student.grade),
      ]);
    }

    // Save
    final dir = Directory('/storage/emulated/0/Download');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${dir.path}/ethiograde_students_$timestamp.xlsx';
    final fileBytes = excel.save();
    if (fileBytes != null) {
      await File(path).writeAsBytes(fileBytes);
    }

    return path;
  }

  /// Export assessment results to Excel
  Future<String> exportResults({
    required String assessmentTitle,
    required List<Map<String, dynamic>> results,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Results'];

    // Headers
    sheet.appendRow([
      TextCellValue('Student Name'),
      TextCellValue('Student ID'),
      TextCellValue('Score'),
      TextCellValue('Max Score'),
      TextCellValue('Percentage'),
      TextCellValue('Grade'),
      TextCellValue('Status'),
    ]);

    // Data
    for (final result in results) {
      sheet.appendRow([
        TextCellValue(result['studentName'] ?? ''),
        TextCellValue(result['studentId'] ?? ''),
        DoubleCellValue((result['totalScore'] ?? 0).toDouble()),
        DoubleCellValue((result['maxScore'] ?? 0).toDouble()),
        TextCellValue('${(result['percentage'] ?? 0).toStringAsFixed(1)}%'),
        TextCellValue(result['grade'] ?? ''),
        TextCellValue(
          (result['percentage'] ?? 0) >= 50 ? 'PASS' : 'FAIL',
        ),
      ]);
    }

    final dir = Directory('/storage/emulated/0/Download');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = assessmentTitle.replaceAll(RegExp(r'[^\w]'), '_');
    final path = '${dir.path}/ethiograde_${safeName}_$timestamp.xlsx';
    final fileBytes = excel.save();
    if (fileBytes != null) {
      await File(path).writeAsBytes(fileBytes);
    }

    return path;
  }

  // ──── Helpers ────

  Map<String, int> _detectColumns(List<String> headers) {
    final map = <String, int>{};

    for (int i = 0; i < headers.length; i++) {
      final h = headers[i];
      if (h.contains('first') && h.contains('name')) {
        map['firstName'] = i;
      } else if (h.contains('last') && h.contains('name')) {
        map['lastName'] = i;
      } else if (h == 'name' || h == 'ስም') {
        map['firstName'] = i;
      } else if (h.contains('ስም') && h.contains('የአባት')) {
        map['firstNameAmharic'] = i;
      } else if (h.contains('amharic') && h.contains('first')) {
        map['firstNameAmharic'] = i;
      } else if (h.contains('amharic') && h.contains('last')) {
        map['lastNameAmharic'] = i;
      } else if (h.contains('id') || h.contains('number')) {
        map['studentId'] = i;
      } else if (h.contains('class') || h.contains('ክፍል')) {
        map['className'] = i;
      } else if (h.contains('section') || h.contains('ቡድን')) {
        map['section'] = i;
      } else if (h.contains('grade') || h.contains('ደረጃ')) {
        map['grade'] = i;
      }
    }

    return map;
  }

  String _getCellValue(List<Data?> row, int? index) {
    if (index == null || index >= row.length) return '';
    return row[index]?.value?.toString().trim() ?? '';
  }
}

class ExcelImportResult {
  final bool success;
  final String message;
  final List<Student> students;
  final List<String> errors;

  ExcelImportResult({
    required this.success,
    required this.message,
    this.students = const [],
    this.errors = const [],
  });
}
