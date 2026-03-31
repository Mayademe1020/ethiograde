import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/teacher.dart';

void main() {
  // ── Teacher Model ─────────────────────────────────────────────────

  group('Teacher model', () {
    test('creates with auto-generated ID and timestamp', () {
      final teacher = Teacher(name: 'Abebe Kebede');
      expect(teacher.id, isNotEmpty);
      expect(teacher.name, 'Abebe Kebede');
      expect(teacher.isActive, isTrue);
      expect(teacher.createdAt, isNotNull);
    });

    test('uses provided ID', () {
      final teacher = Teacher(id: 't1', name: 'Abebe');
      expect(teacher.id, 't1');
    });

    test('toMap / fromMap round-trip', () {
      final original = Teacher(
        id: 't1',
        name: 'Abebe Kebede',
        nameAmharic: 'አበበ ከበደ',
        phone: '+251911223344',
        email: 'abebe@school.et',
        subject: 'Math',
        isActive: true,
        metadata: {'role': 'head'},
      );

      final map = original.toMap();
      final restored = Teacher.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.nameAmharic, original.nameAmharic);
      expect(restored.phone, original.phone);
      expect(restored.email, original.email);
      expect(restored.subject, original.subject);
      expect(restored.isActive, original.isActive);
      expect(restored.metadata, original.metadata);
    });

    test('fromMap handles missing fields gracefully', () {
      final teacher = Teacher.fromMap({});
      expect(teacher.id, '');
      expect(teacher.name, '');
      expect(teacher.isActive, isTrue);
    });

    test('copyWith replaces specified fields', () {
      final original = Teacher(name: 'Abebe', subject: 'Math');
      final updated = original.copyWith(subject: 'Physics');
      expect(updated.name, 'Abebe');
      expect(updated.subject, 'Physics');
      expect(updated.id, original.id); // ID preserved
    });

    test('getDisplayName returns Amharic when locale is am and available',
        () {
      final teacher = Teacher(name: 'Abebe', nameAmharic: 'አበበ');
      expect(teacher.getDisplayName('am'), 'አበበ');
      expect(teacher.getDisplayName('en'), 'Abebe');
    });

    test('getDisplayName falls back to English when Amharic is empty', () {
      final teacher = Teacher(name: 'Abebe');
      expect(teacher.getDisplayName('am'), 'Abebe');
    });
  });
}
