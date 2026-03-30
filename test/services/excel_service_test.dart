import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:ethiograde/models/student.dart';

void main() {
  /// Create a minimal valid .xlsx file for testing.
  Future<String> createTestExcel({
    List<String> headers = const ['First Name', 'Last Name', 'Class'],
    List<List<String>> rows = const [],
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];

    // Add header row
    for (int i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, row: 0))
          .value = TextCellValue(headers[i]);
    }

    // Add data rows
    for (int r = 0; r < rows.length; r++) {
      for (int c = 0; c < rows[r].length; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, row: r + 1))
            .value = TextCellValue(rows[r][c]);
      }
    }

    final file = File('${Directory.systemTemp.path}/test_students.xlsx');
    final bytes = excel.save();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    }
    return file.path;
  }

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
      final file = File('${Directory.systemTemp.path}/empty.xlsx');
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

      // Row 0 = header, Row 1 = first data row
      expect(sheet.rows[1][0]?.value.toString(), 'Abebe');
      expect(sheet.rows[1][1]?.value.toString(), '85');

      await file.delete();
    });

    test('handles Amharic headers and content', () async {
      final path = await createTestExcel(
        headers: ['ስም', 'ክፍል'],
        rows: [
          ['አበበ', '10ሀ'],
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
  });

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
    });

    test('Student toMap/fromMap round-trip', () {
      final original = Student(
        id: 'test-id',
        firstName: 'Abebe',
        lastName: 'Kebede',
        className: '10A',
      );

      final map = original.toMap();
      final restored = Student.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.firstName, original.firstName);
      expect(restored.lastName, original.lastName);
      expect(restored.className, original.className);
    });
  });
}
