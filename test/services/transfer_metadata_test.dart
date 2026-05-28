import 'package:flutter_test/flutter_test.dart';

import 'package:ethiograde/models/student.dart';

void main() {
  group('Student transfer metadata persistence (FIX.4)', () {
    test('copyWith preserves metadata by default', () {
      final student = Student(
        id: 's1',
        studentId: '001',
        firstName: 'Abebe',
        lastName: 'Kebede',
        classIds: ['classA'],
        metadata: {'key': 'value'});

      final updated = student.copyWith(firstName: 'Bekele');
      expect(updated.metadata['key'], 'value');
      expect(updated.firstName, 'Bekele');
    });

    test('copyWith can update metadata with transfer history', () {
      final student = Student(
        id: 's1',
        studentId: '001',
        firstName: 'Abebe',
        lastName: 'Kebede',
        classIds: ['classA', 'classB'],
        metadata: {});

      final newMetadata = Map<String, dynamic>.from(student.metadata);
      newMetadata['transfers'] = [
        {
          'fromClassId': 'classA',
          'toClassId': 'classB',
          'timestamp': '2026-04-13T00:00:00Z',
          'reason': 'Family moved',
          'teacherId': 't1',
          'teacherName': 'Teacher One',
        },
      ];

      final updated = student.copyWith(
        classIds: ['classB'],
        metadata: newMetadata);

      expect(updated.classIds, ['classB']);
      expect(updated.metadata['transfers'], isNotNull);

      final transfers = updated.metadata['transfers'] as List;
      expect(transfers.length, 1);
      expect(transfers[0]['fromClassId'], 'classA');
      expect(transfers[0]['toClassId'], 'classB');
      expect(transfers[0]['reason'], 'Family moved');
    });

    test('transfer metadata survives toMap/fromMap round-trip', () {
      final student = Student(
        id: 's1',
        studentId: '001',
        firstName: 'Abebe',
        lastName: 'Kebede',
        classIds: ['classB'],
        metadata: {
          'transfers': [
            {
              'fromClassId': 'classA',
              'toClassId': 'classB',
              'timestamp': '2026-04-13T00:00:00Z',
              'reason': 'Family moved',
            },
          ],
        });

      final map = student.toMap();
      final restored = Student.fromMap(map);

      expect(restored.metadata['transfers'], isNotNull);
      final transfers = restored.metadata['transfers'] as List;
      expect(transfers[0]['fromClassId'], 'classA');
    });

    test('multiple transfers accumulate in metadata', () {
      var student = Student(
        id: 's1',
        studentId: '001',
        firstName: 'Abebe',
        lastName: 'Kebede',
        classIds: ['classA'],
        metadata: {});

      // First transfer: A → B
      final meta1 = Map<String, dynamic>.from(student.metadata);
      meta1['transfers'] = [
        {'fromClassId': 'classA', 'toClassId': 'classB', 'timestamp': '2026-01-01'},
      ];
      student = student.copyWith(classIds: ['classB'], metadata: meta1);

      // Second transfer: B → C
      final transfers2 = List<Map<String, dynamic>>.from(
        student.metadata['transfers'] ?? []);
      transfers2.add({
        'fromClassId': 'classB',
        'toClassId': 'classC',
        'timestamp': '2026-03-01',
      });
      final meta2 = Map<String, dynamic>.from(student.metadata);
      meta2['transfers'] = transfers2;
      student = student.copyWith(classIds: ['classC'], metadata: meta2);

      final transfers = student.metadata['transfers'] as List;
      expect(transfers.length, 2);
      expect(transfers[0]['fromClassId'], 'classA');
      expect(transfers[1]['fromClassId'], 'classB');
    });
  });
}
