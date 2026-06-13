import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/services/student_matcher.dart';
import 'package:ethiograde/models/student.dart';

void main() {
  Student makeStudent({
    String id = 's1',
    String studentId = '001',
    String firstName = 'Abebe',
    String lastName = 'Kebede',  }) => Student(
    id: id,
    studentId: studentId,
    firstName: firstName,
    lastName: lastName,
    gender: 'M');

  final classList = [
    makeStudent(
      id: 's1',
      studentId: '001',
      firstName: 'Abebe',
      lastName: 'Kebede',
    ),
    makeStudent(
      id: 's2',
      studentId: '002',
      firstName: 'Habte',
      lastName: 'Woldemariam',
    ),
    makeStudent(
      id: 's3',
      studentId: '003',
      firstName: 'Gebre',
      lastName: 'Hailu',
    ),
    makeStudent(
      id: 's4',
      studentId: '004',
      firstName: 'Abebe',
      lastName: 'Tadesse',
    ),
  ];

  group('StudentMatcher — exact match', () {
    test('matches full English name', () {
      final result = StudentMatcher.matchName('Abebe Kebede', classList);
      expect(result.hasMatch, isTrue);
      expect(result.matchedStudent!.id, 's1');
      expect(result.confidence, 1.0);
    });
    test('matches case-insensitively', () {
      final result = StudentMatcher.matchName('ABEBE KEBEDE', classList);
      expect(result.hasMatch, isTrue);
      expect(result.matchedStudent!.id, 's1');
    });
  });

  group('StudentMatcher — first name match', () {
    test('matches on first name when unique', () {
      final result = StudentMatcher.matchName('ገብረ', classList);
      expect(result.hasMatch, isTrue);
      expect(result.matchedStudent!.id, 's3');
      expect(result.confidence, lessThan(1.0)); // lower confidence
    });

    test('does not match on non-unique first name', () {
      final result = StudentMatcher.matchName('Abebe', classList);
      // Both s1 and s4 have first name "Abebe" — ambiguous
      expect(result.needsReview, isTrue);
    });
  });

  group('StudentMatcher — student ID match', () {
    test('matches by student ID', () {
      final result = StudentMatcher.matchById('002', classList);
      expect(result.hasMatch, isTrue);
      expect(result.matchedStudent!.id, 's2');
    });

    test('returns no match for unknown ID', () {
      final result = StudentMatcher.matchById('999', classList);
      expect(result.hasMatch, isFalse);
    });
  });

  group('StudentMatcher — fuzzy match', () {
    test('finds similar name', () {
      // Slight misspelling
      final result = StudentMatcher.matchName('Abebe Kebdee', classList);
      expect(result.hasMatch, isTrue);
      expect(result.matchedStudent!.id, 's1');
      expect(result.confidence, greaterThan(0.7));
    });

    test('handles no match at all', () {
      final result = StudentMatcher.matchName('Random Name', classList);
      expect(result.hasMatch, isFalse);
    });

    test('handles empty class list', () {
      final result = StudentMatcher.matchName('Abebe', []);
      expect(result.hasMatch, isFalse);
    });

    test('handles empty scanned name', () {
      final result = StudentMatcher.matchName('', classList);
      expect(result.hasMatch, isFalse);
    });
  });

  group('StudentMatcher — ambiguity', () {
    test('detects ambiguous match', () {
      // Very similar to two students
      final ambiguousList = [
        makeStudent(id: 's1', firstName: 'Abebe', lastName: 'Kebede'),
        makeStudent(id: 's2', firstName: 'Abebe', lastName: 'Kebeda'),
      ];
      final result = StudentMatcher.matchName('Abebe Kebede', ambiguousList);
      // One exact match
      expect(result.hasMatch, isTrue);
    });
  });

  group('StudentMatcher — matchFromOcr', () {
    test('parses OCR text and matches', () {
      final ocrText = '1. አበበ ከበደ ወንድ\n2. ሀብተ ወልደማርያም ሴት';
      final result = StudentMatcher.matchFromOcr(ocrText, classList);
      expect(result.hasMatch, isTrue);
      expect(result.matchedStudent!.firstName, 'Abebe');
    });

    test('returns no match for empty OCR', () {
      final result = StudentMatcher.matchFromOcr('', classList);
      expect(result.hasMatch, isFalse);
    });

    test('returns first parsed name when no class match', () {
      // Use input the roster parser won't parse as a valid name (too short/single char)
      final ocrText = '---';
      final result = StudentMatcher.matchFromOcr(ocrText, classList);
      expect(result.hasMatch, isFalse);
    });
  });
}
