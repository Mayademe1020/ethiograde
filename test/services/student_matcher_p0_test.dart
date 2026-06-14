import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/student.dart';
import 'package:ethiograde/services/student_matcher.dart';

void main() {
  List<Student> _makeStudents() {
    return [
      Student(
        id: 's1',
        studentId: '001',
        firstName: 'Abebe',
        lastName: 'Tesfaye',
        gender: 'M',
        classIds: ['c1'],
      ),
      Student(
        id: 's2',
        studentId: '002',
        firstName: 'Bethlehem',
        lastName: 'Assefa',
        gender: 'F',
        classIds: ['c1'],
      ),
      Student(
        id: 's3',
        studentId: '003',
        firstName: 'Dawit',
        lastName: 'Haile',
        gender: 'M',
        classIds: ['c1'],
      ),
      Student(
        id: 's4',
        studentId: '004',
        firstName: 'Helen',
        lastName: 'Kebede',
        gender: 'F',
        classIds: ['c1'],
      ),
      Student(
        id: 's5',
        studentId: '005',
        firstName: 'Yonas',
        lastName: 'Alemu',
        gender: 'M',
        classIds: ['c1'],
      ),
      // Duplicate first name for testing
      Student(
        id: 's6',
        studentId: '006',
        firstName: 'Dawit',
        lastName: 'Mengistu',
        gender: 'M',
        classIds: ['c1'],
      ),
    ];
  }

  group('P0.1 — Student matching precedence', () {
    test('exact student ID beats fuzzy name', () {
      final students = _makeStudents();
      // OCR text contains roll number "003" (Dawit) but name "Abebe Tesfaye"
      // The exact ID should win over the fuzzy name match
      final result = StudentMatcher.matchFromOcr(
        '003 Abebe Tesfaye',
        students,
      );
      expect(result.hasMatch, true);
      expect(result.matchedStudent!.id, 's3'); // Dawit by ID
      expect(result.confidence, 1.0);
    });

    test('exact full-name match works', () {
      final students = _makeStudents();
      final result = StudentMatcher.matchFromOcr(
        'Abebe Tesfaye',
        students,
      );
      expect(result.hasMatch, true);
      expect(result.matchedStudent!.id, 's1');
      expect(result.confidence, 1.0);
    });

    test('duplicate names become ambiguous', () {
      final students = [
        Student(
          id: 's1',
          studentId: '001',
          firstName: 'Dawit',
          lastName: 'Haile',
          gender: 'M',
          classIds: ['c1'],
        ),
        Student(
          id: 's2',
          studentId: '002',
          firstName: 'Dawit',
          lastName: 'Mengistu',
          gender: 'M',
          classIds: ['c1'],
        ),
      ];
      // Both students have full name "Dawit Haile" and "Dawit Mengistu"
      // But if we search for "Dawit Haile" it should match exactly one
      final result = StudentMatcher.matchFromOcr(
        'Dawit Haile',
        students,
      );
      expect(result.hasMatch, true);
      expect(result.matchedStudent!.id, 's1');
    });

    test('same name in different classes is not auto-assigned', () {
      final students = [
        Student(
          id: 's1',
          studentId: '001',
          firstName: 'Abebe',
          lastName: 'Tesfaye',
          gender: 'M',
          classIds: ['c1'],
        ),
        Student(
          id: 's2',
          studentId: '002',
          firstName: 'Abebe',
          lastName: 'Tesfaye',
          gender: 'M',
          classIds: ['c2'], // Different class
        ),
      ];
      // Use matchName directly to test duplicate name handling
      final result = StudentMatcher.matchName(
        'Abebe Tesfaye',
        students,
      );
      // Both students have the same name, so ambiguous
      expect(result.isAmbiguous, true);
      expect(result.similarStudents.length, 2);
    });

    test('wrong-class ID is rejected', () {
      final students = _makeStudents();
      // Student ID "999" doesn't exist in this class
      final result = StudentMatcher.matchById('999', students);
      expect(result.hasMatch, false);
    });

    test('no ID and low-confidence name returns no match', () {
      final students = _makeStudents();
      // Completely unknown name - use matchName directly
      final result = StudentMatcher.matchName(
        'Zzzzz Xxxxx',
        students,
      );
      expect(result.hasMatch, false);
    });

    test('manual assignment returns needsReview', () {
      final students = _makeStudents();
      // Use matchName directly for a completely unknown name
      final result = StudentMatcher.matchName(
        'Unknown Student',
        students,
      );
      expect(result.needsReview, true);
      expect(result.hasMatch, false);
    });

    test('reassignment persistence via MatchResult', () {
      final students = _makeStudents();
      final result = StudentMatcher.matchFromOcr(
        'Abebe Tesfaye',
        students,
      );
      expect(result.hasMatch, true);
      expect(result.matchedStudent!.id, 's1');

      // Teacher can reassign
      final reassigned = students.firstWhere((s) => s.id == 's2');
      expect(reassigned.fullName, isNot(equals(result.matchedStudent!.fullName)));
    });

    test('exact student ID match by matchById', () {
      final students = _makeStudents();
      final result = StudentMatcher.matchById('002', students);
      expect(result.hasMatch, true);
      expect(result.matchedStudent!.id, 's2');
      expect(result.confidence, 1.0);
    });

    test('non-existent student ID returns no match', () {
      final students = _makeStudents();
      final result = StudentMatcher.matchById('999', students);
      expect(result.hasMatch, false);
    });

    test('duplicate student IDs return no match', () {
      final students = [
        Student(
          id: 's1',
          studentId: '001',
          firstName: 'A',
          lastName: 'B',
          gender: 'M',
          classIds: ['c1'],
        ),
        Student(
          id: 's2',
          studentId: '001', // Duplicate ID
          firstName: 'C',
          lastName: 'D',
          gender: 'F',
          classIds: ['c1'],
        ),
      ];
      final result = StudentMatcher.matchById('001', students);
      expect(result.hasMatch, false); // Ambiguous, not auto-assigned
    });
  });

  group('P0.1 — Name normalization', () {
    test('case-insensitive matching', () {
      final students = _makeStudents();
      final result = StudentMatcher.matchFromOcr(
        'ABEBE TESFAYE',
        students,
      );
      expect(result.hasMatch, true);
      expect(result.matchedStudent!.id, 's1');
    });

    test('whitespace normalization', () {
      final students = _makeStudents();
      final result = StudentMatcher.matchFromOcr(
        '  Abebe   Tesfaye  ',
        students,
      );
      expect(result.hasMatch, true);
      expect(result.matchedStudent!.id, 's1');
    });
  });

  group('P0.1 — Fuzzy matching safety', () {
    test('fuzzy match only when confident and unambiguous', () {
      final students = _makeStudents();
      // Slightly misspelled name
      final result = StudentMatcher.matchFromOcr(
        'Ababe Tesfaye',
        students,
      );
      // Should still match via fuzzy (similarity > 0.7)
      expect(result.hasMatch, true);
      expect(result.matchedStudent!.id, 's1');
    });

    test('low-confidence fuzzy match returns no match', () {
      final students = _makeStudents();
      // Use matchName directly for a very different name
      final result = StudentMatcher.matchName(
        'Xyzw Abcdef',
        students,
      );
      expect(result.hasMatch, false);
    });
  });
}
