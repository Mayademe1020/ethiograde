import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/services/roster_parser.dart';

void main() {
  const parser = RosterParser();

  group('RosterParser — numbered lines', () {
    test('parses "1. አበበ ከበደ"', () {
      final results = parser.parse('1. አበበ ከበደ');
      expect(results, hasLength(1));
      expect(results.first.studentId, '1');
      expect(results.first.firstName, 'አበበ');
      expect(results.first.lastName, 'ከበደ');
    });

    test('parses "1) Abebe Kebede"', () {
      final results = parser.parse('1) Abebe Kebede');
      expect(results, hasLength(1));
      expect(results.first.studentId, '1');
      expect(results.first.firstName, 'Abebe');
      expect(results.first.lastName, 'Kebede');
    });

    test('parses multiple numbered lines', () {
      const text = '1. አበበ ከበደ\n2. ተስፋዬ ወልዴ\n3. ሃብተ አለሙ';
      final results = parser.parse(text);
      expect(results, hasLength(3));
      expect(results[0].studentId, '1');
      expect(results[0].firstName, 'አበበ');
      expect(results[1].studentId, '2');
      expect(results[1].firstName, 'ተስፋዬ');
      expect(results[2].studentId, '3');
      expect(results[2].firstName, 'ሃብተ');
    });

    test('handles "001 " prefix (column format)', () {
      final results = parser.parse('001  አበበ ከበደ');
      expect(results, hasLength(1));
      expect(results.first.studentId, '001');
      expect(results.first.firstName, 'አበበ');
    });
  });

  group('RosterParser — table format with gender', () {
    test('extracts male gender from end', () {
      final results = parser.parse('001 አበበ ከበደ ወንድ');
      expect(results, hasLength(1));
      expect(results.first.gender, 'M');
      expect(results.first.firstName, 'አበበ');
      expect(results.first.lastName, 'ከበደ');
    });

    test('extracts female gender from end', () {
      final results = parser.parse('002 ሃብተ አለሙ ሴት');
      expect(results, hasLength(1));
      expect(results.first.gender, 'F');
      expect(results.first.firstName, 'ሃብተ');
    });

    test('handles English gender markers', () {
      final results = parser.parse('003 Abebe Kebede M');
      expect(results, hasLength(1));
      expect(results.first.gender, 'M');
      expect(results.first.firstName, 'Abebe');
    });

    test('parses full table', () {
      const text = '001 አበበ ከበደ ወንድ\n002 ሃብተ ወልዴ ሴት\n003 ተስፋዬ ገብረ ወንድ';
      final results = parser.parse(text);
      expect(results, hasLength(3));
      expect(results[0].gender, 'M');
      expect(results[1].gender, 'F');
      expect(results[2].gender, 'M');
    });
  });

  group('RosterParser — Ethiopian naming (2-3 words)', () {
    test('handles 3-word name: FirstName FatherName GrandfatherName', () {
      final results = parser.parse('1. አበበ ከበደ ተስፋዬ');
      expect(results, hasLength(1));
      expect(results.first.firstName, 'አበበ');
      expect(results.first.lastName, 'ከበደ ተስፋዬ');
    });

    test('handles 2-word name', () {
      final results = parser.parse('1. አበበ ከበደ');
      expect(results, hasLength(1));
      expect(results.first.firstName, 'አበበ');
      expect(results.first.lastName, 'ከበደ');
    });

    test('handles 3-word English name', () {
      final results = parser.parse('1. Abebe Kebede Tesfaye');
      expect(results, hasLength(1));
      expect(results.first.firstName, 'Abebe');
      expect(results.first.lastName, 'Kebede Tesfaye');
    });

    test('handles single name (low confidence)', () {
      final results = parser.parse('1. አበበ');
      expect(results, hasLength(1));
      expect(results.first.firstName, 'አበበ');
      expect(results.first.lastName, isEmpty);
      expect(results.first.confidence, lessThan(0.8));
    });
  });

  group('RosterParser — attendance marks', () {
    test('strips checkmark attendance', () {
      final results = parser.parse('አበበ ከበደ ✓');
      expect(results, hasLength(1));
      expect(results.first.firstName, 'አበበ');
      expect(results.first.lastName, 'ከበደ');
    });

    test('strips P/A attendance', () {
      final results = parser.parse('Abebe Kebede P');
      expect(results, hasLength(1));
      expect(results.first.firstName, 'Abebe');
    });

    test('strips Amharic attendance marks', () {
      final results = parser.parse('አበበ ከበደ ተገኝ');
      expect(results, hasLength(1));
      expect(results.first.firstName, 'አበበ');
    });
  });

  group('RosterParser — noise filtering', () {
    test('skips separator lines', () {
      final results = parser.parse('---\nአበበ ከበደ\n===\n');
      expect(results, hasLength(1));
      expect(results.first.firstName, 'አበበ');
    });

    test('skips header-like lines', () {
      final results = parser.parse('ስም\nአበበ ከበደ');
      expect(results, hasLength(1));
      expect(results.first.firstName, 'አበበ');
    });

    test('skips empty lines', () {
      final results = parser.parse('\n\nአበበ ከበደ\n\n');
      expect(results, hasLength(1));
    });
  });

  group('RosterParser — mixed format roster', () {
    test('parses real-world roster', () {
      const text = '''ተ.ቁ  ስም  ጾታ
1. አበበ ከበደ ተስፋዬ ወንድ
2. ሃብተ ወልዴ አለሙ ሴት
3. ገብረ ሃይለ ወርቅ ወንድ
4. ተክለ ሃይለ ወልደ ጊዮርጊስ ወንድ''';
      final results = parser.parse(text);
      // Header line "ተ.ቁ ስም ጾታ" might parse as noise or as a name
      // The important thing is the 4 students are parsed
      expect(results.length, greaterThanOrEqualTo(4));

      // Find the known students
      final abebe = results.where((r) => r.firstName == 'አበበ').firstOrNull;
      expect(abebe, isNotNull);
      expect(abebe!.gender, 'M');
      expect(abebe.lastName, contains('ከበደ'));

      final habte = results.where((r) => r.firstName == 'ሃብተ').firstOrNull;
      expect(habte, isNotNull);
      expect(habte!.gender, 'F');
    });
  });

  group('RosterParser — deduplication', () {
    test('deduplicates by student ID', () {
      const text = '001 አበበ ከበደ\n001 አበበ ከበደ';
      final results = parser.parse(text);
      expect(results, hasLength(1));
    });

    test('deduplicates by name when no ID', () {
      const text = 'አበበ ከበደ\nአበበ ከበደ';
      final results = parser.parse(text);
      expect(results, hasLength(1));
    });
  });

  group('RosterParser — confidence scoring', () {
    test('full parse has high confidence', () {
      final results = parser.parse('001 አበበ ከበደ ወንድ');
      expect(results.first.confidence, greaterThanOrEqualTo(0.8));
    });

    test('missing gender reduces confidence', () {
      final results = parser.parse('001 አበበ ከበደ');
      expect(results.first.confidence, lessThan(1.0));
    });

    test('missing roll number reduces confidence', () {
      final results = parser.parse('አበበ ከበደ ወንድ');
      expect(results.first.confidence, lessThan(1.0));
    });
  });

  group('RosterParser — auto-index fallback', () {
    test('assigns sequential IDs when no roll number found', () {
      const text = 'አበበ ከበደ\nሃብተ ወልዴ\nገብረ ሃይለ';
      final results = parser.parse(text);
      expect(results, hasLength(3));
      expect(results[0].studentId, '001');
      expect(results[1].studentId, '002');
      expect(results[2].studentId, '003');
    });
  });

  group('ParsedStudent — toStudent', () {
    test('converts to Student model', () {
      const parsed = ParsedStudent(
        studentId: '001',
        firstName: 'Abebe',
        lastName: 'Kebede',
        gender: 'M');
      final student = parsed.toStudent(classId: 'class-1');
      expect(student.studentId, '001');
      expect(student.firstName, 'Abebe');
      expect(student.lastName, 'Kebede');
      expect(student.gender, 'M');
      expect(student.classIds, ['class-1']);
    });
  });
}
