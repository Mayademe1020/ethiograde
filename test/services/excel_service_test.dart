import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:ethiograde/models/student.dart';
import 'package:ethiograde/services/excel_service.dart';

void main() {
  /// Create a minimal valid .xlsx file for testing.
  Future<String> createTestExcel({
    List<String> headers = const ['First Name', 'Last Name', 'Class'],
    List<List<String>> rows = const [],
    String? sheetName,
  }) async {
    final excel = Excel.createExcel();
    final sheet = sheetName != null ? excel[sheetName] : excel['Sheet1'];

    for (int i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, row: 0))
          .value = TextCellValue(headers[i]);
    }

    for (int r = 0; r < rows.length; r++) {
      for (int c = 0; c < rows[r].length; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, row: r + 1))
            .value = TextCellValue(rows[r][c]);
      }
    }

    final file = File('${Directory.systemTemp.path}/test_${DateTime.now().microsecondsSinceEpoch}.xlsx');
    final bytes = excel.save();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    }
    return file.path;
  }

  // ──── Excel Decoding ────

  group('Excel decoding', () {
    test('can decode a valid .xlsx file', () async {
      final path = await createTestExcel(
        headers: ['First Name', 'Last Name', 'Class'],
        rows: [
          ['Abebe', 'Kebede', '10A'],
          ['Bekele', 'Tesfaye', '10A'],
        ],
      );

      final file = File(path);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);

      expect(excel.tables, isNotEmpty);
      final sheet = excel.tables.values.first;
      expect(sheet, isNotNull);
      expect(sheet!.maxRows, 3); // header + 2 rows

      await file.delete();
    });

    test('handles empty .xlsx file', () async {
      final excel = Excel.createExcel();
      final file = File('${Directory.systemTemp.path}/empty_${DateTime.now().microsecondsSinceEpoch}.xlsx');
      final bytes = excel.save();
      if (bytes != null) {
        await file.writeAsBytes(bytes);
      }

      final decoded = Excel.decodeBytes(bytes!);
      expect(decoded.tables, isNotEmpty);

      await file.delete();
    });

    test('reads cell values correctly', () async {
      final path = await createTestExcel(
        headers: ['Name', 'Score'],
        rows: [
          ['Abebe', '85'],
          ['Bekele', '92'],
        ],
      );

      final file = File(path);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables.values.first!;

      expect(sheet.rows[1][0]?.value.toString(), 'Abebe');
      expect(sheet.rows[1][1]?.value.toString(), '85');
      expect(sheet.rows[2][0]?.value.toString(), 'Bekele');
      expect(sheet.rows[2][1]?.value.toString(), '92');

      await file.delete();
    });

    test('handles Amharic headers and content', () async {
      final path = await createTestExcel(
        headers: ['ስም', 'ክፍል'],
        rows: [
          ['አበበ', '10ሀ'],
          ['ከበደ', '9ለ'],
        ],
      );

      final file = File(path);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables.values.first!;

      expect(sheet.rows[0][0]?.value.toString(), 'ስም');
      expect(sheet.rows[0][1]?.value.toString(), 'ክፍል');
      expect(sheet.rows[1][0]?.value.toString(), 'አበበ');
      expect(sheet.rows[1][1]?.value.toString(), '10ሀ');
      expect(sheet.rows[2][0]?.value.toString(), 'ከበደ');

      await file.delete();
    });

    test('handles single row (header only)', () async {
      final path = await createTestExcel(
        headers: ['Name', 'Class'],
        rows: [],
      );

      final file = File(path);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables.values.first!;

      expect(sheet.maxRows, 1); // header only

      await file.delete();
    });

    test('handles mixed valid and empty rows', () async {
      final path = await createTestExcel(
        headers: ['First Name', 'Last Name', 'Class'],
        rows: [
          ['Abebe', 'Kebede', '10A'],
          ['', '', ''],
          ['Bekele', 'Tesfaye', '10B'],
        ],
      );

      final file = File(path);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables.values.first!;

      expect(sheet.maxRows, 4); // header + 3 rows
      // Empty row should still decode
      expect(sheet.rows[2][0]?.value.toString(), '');

      await file.delete();
    });

    test('handles extra columns gracefully', () async {
      final path = await createTestExcel(
        headers: ['First Name', 'Last Name', 'Class', 'Section', 'ID', 'Grade'],
        rows: [
          ['Abebe', 'Kebede', '10A', 'A', '1001', '10'],
          ['Bekele', 'Tesfaye', '10B', 'B', '1002', '10'],
        ],
      );

      final file = File(path);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables.values.first!;

      expect(sheet.rows[1][3]?.value.toString(), 'A');
      expect(sheet.rows[1][4]?.value.toString(), '1001');
      expect(sheet.rows[1][5]?.value.toString(), '10');

      await file.delete();
    });
  });

  // ──── Column Detection ────

  group('Excel column detection', () {
    test('detects standard English headers', () async {
      final path = await createTestExcel(
        headers: ['First Name', 'Last Name', 'Student ID', 'Class', 'Section', 'Grade'],
        rows: [
          ['Abebe', 'Kebede', '1001', '10A', 'A', '10'],
        ],
      );

      final file = File(path);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables.values.first!;

      // Verify all columns are readable
      final headerRow = sheet.rows[0];
      expect(headerRow[0]?.value.toString(), 'First Name');
      expect(headerRow[1]?.value.toString(), 'Last Name');
      expect(headerRow[2]?.value.toString(), 'Student ID');
      expect(headerRow[3]?.value.toString(), 'Class');
      expect(headerRow[4]?.value.toString(), 'Section');
      expect(headerRow[5]?.value.toString(), 'Grade');

      await file.delete();
    });

    test('detects Amharic headers', () async {
      final path = await createTestExcel(
        headers: ['ስም', 'የአባት ስም', 'ክፍል'],
        rows: [
          ['አበበ', 'ከበደ', '10ሀ'],
        ],
      );

      final file = File(path);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables.values.first!;

      expect(sheet.rows[0][0]?.value.toString(), 'ስም');
      expect(sheet.rows[1][0]?.value.toString(), 'አበበ');

      await file.delete();
    });

    test('detects "Name" as first name', () async {
      final path = await createTestExcel(
        headers: ['Name', 'Class'],
        rows: [
          ['Abebe Kebede', '10A'],
        ],
      );

      final file = File(path);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);

      expect(excel.tables.values.first!.rows[1][0]?.value.toString(), 'Abebe Kebede');

      await file.delete();
    });
  });

  // ──── Student Model ────

  group('Student model — serialization', () {
    test('creates Student from Excel row data', () {
      final student = Student(
        id: 'test-id',
        firstName: 'Abebe',
        lastName: 'Kebede',
        firstNameAmharic: 'አበበ',
        lastNameAmharic: 'ከበደ',
        className: '10A',
        section: 'A',
        studentId: '1001',
      );

      expect(student.firstName, 'Abebe');
      expect(student.lastName, 'Kebede');
      expect(student.className, '10A');
      expect(student.fullName, 'Abebe Kebede');
      expect(student.fullNameAmharic, 'አበበ ከበደ');
    });

    test('Student toMap/fromMap round-trip', () {
      final original = Student(
        id: 'test-id',
        firstName: 'Abebe',
        lastName: 'Kebede',
        firstNameAmharic: 'አበበ',
        lastNameAmharic: 'ከበደ',
        className: '10A',
        section: 'A',
        studentId: '1001',
      );

      final map = original.toMap();
      final restored = Student.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.firstName, original.firstName);
      expect(restored.lastName, original.lastName);
      expect(restored.firstNameAmharic, original.firstNameAmharic);
      expect(restored.lastNameAmharic, original.lastNameAmharic);
      expect(restored.className, original.className);
      expect(restored.section, original.section);
      expect(restored.studentId, original.studentId);
    });

    test('Student fullName concatenates correctly', () {
      final student = Student(
        id: 'id',
        firstName: 'Chaltu',
        lastName: 'Dida',
      );

      expect(student.fullName, 'Chaltu Dida');
    });

    test('Student fullNameAmharic handles empty Amharic names', () {
      final student = Student(
        id: 'id',
        firstName: 'John',
        lastName: 'Smith',
      );

      expect(student.fullNameAmharic, ' ');
    });

    test('Student getDisplayName returns Amharic in am locale', () {
      final student = Student(
        id: 'id',
        firstName: 'Abebe',
        lastName: 'Kebede',
        firstNameAmharic: 'አበበ',
        lastNameAmharic: 'ከበደ',
      );

      expect(student.getDisplayName('am'), 'አበበ ከበደ');
      expect(student.getDisplayName('en'), 'Abebe Kebede');
    });

    test('Student getDisplayName falls back to English when Amharic empty', () {
      final student = Student(
        id: 'id',
        firstName: 'John',
        lastName: 'Smith',
      );

      // No Amharic names — should always return English
      expect(student.getDisplayName('am'), 'John Smith');
      expect(student.getDisplayName('en'), 'John Smith');
    });

    test('Student handles missing optional fields', () {
      final student = Student(
        id: 'id',
        firstName: 'Test',
        lastName: 'User',
      );

      expect(student.className, '');
      expect(student.section, '');
      expect(student.studentId, '');
      expect(student.grade, 1);
    });

    test('Student fromMap handles missing keys gracefully', () {
      final student = Student.fromMap({
        'id': 'id',
        'firstName': 'Test',
        'lastName': 'User',
      });

      expect(student.firstName, 'Test');
      expect(student.lastName, 'User');
      expect(student.className, '');
      expect(student.studentId, '');
    });
  });

  // ──── Export ────

  group('Excel export helpers', () {
    test('ExcelImportResult captures success state', () {
      final result = ExcelImportResult(
        success: true,
        students: [
          Student(id: 's1', firstName: 'Abebe', lastName: 'Kebede'),
        ],
        message: 'Imported 1 student',
      );

      expect(result.success, isTrue);
      expect(result.students.length, 1);
      expect(result.errors, isEmpty);
    });

    test('ExcelImportResult captures failure state', () {
      final result = ExcelImportResult(
        success: false,
        message: 'No valid students found',
        errors: ['Row 2: missing name', 'Row 5: invalid format'],
      );

      expect(result.success, isFalse);
      expect(result.students, isEmpty);
      expect(result.errors.length, 2);
    });
  });

  // ──── Edge Cases ────

  group('Excel edge cases', () {
    test('handles very long cell values', () async {
      final longValue = 'A' * 500;
      final path = await createTestExcel(
        headers: ['Name'],
        rows: [
          [longValue],
        ],
      );

      final file = File(path);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables.values.first!;

      expect(sheet.rows[1][0]?.value.toString(), longValue);

      await file.delete();
    });

    test('handles special characters in cells', () async {
      final path = await createTestExcel(
        headers: ['Name', 'Notes'],
        rows: [
          ['O\'Brien', 'Score: 85% (A)'],
          ['Müller', 'Passed & qualified'],
        ],
      );

      final file = File(path);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables.values.first!;

      expect(sheet.rows[1][0]?.value.toString(), 'O\'Brien');
      expect(sheet.rows[1][1]?.value.toString(), 'Score: 85% (A)');
      expect(sheet.rows[2][0]?.value.toString(), 'Müller');

      await file.delete();
    });

    test('handles many rows without error', () async {
      final rows = List.generate(100, (i) => ['Student$i', 'Class$i', '$i']);
      final path = await createTestExcel(
        headers: ['Name', 'Class', 'ID'],
        rows: rows,
      );

      final file = File(path);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables.values.first!;

      expect(sheet.maxRows, 101); // header + 100 rows
      expect(sheet.rows[50][0]?.value.toString(), 'Student49');

      await file.delete();
    });

    test('handles numeric-like strings', () async {
      final path = await createTestExcel(
        headers: ['ID', 'Phone'],
        rows: [
          ['1001', '0911223344'],
          ['1002', '0922334455'],
        ],
      );

      final file = File(path);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables.values.first!;

      // Strings that look like numbers should still be strings
      expect(sheet.rows[1][0]?.value.toString(), '1001');
      expect(sheet.rows[1][1]?.value.toString(), '0911223344');

      await file.delete();
    });
  });
}
