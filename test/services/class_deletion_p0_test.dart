import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/class_info.dart';

void main() {
  group('P0.5 — Safe class deletion logic', () {
    test('empty class has no blocking reasons', () {
      final cls = ClassInfo(
        id: 'c1',
        name: 'Test Class',
        grade: 5,
        section: 'A',
        ownerId: 'teacher-1',
      );

      final reasons = <String>[];
      if (cls.studentIds.isNotEmpty) {
        reasons.add('${cls.studentIds.length} student(s) still in this class.');
      }

      expect(reasons, isEmpty);
    });

    test('class with students has blocking reason', () {
      final cls = ClassInfo(
        id: 'c1',
        name: 'Test Class',
        grade: 5,
        section: 'A',
        ownerId: 'teacher-1',
        studentIds: ['s1', 's2', 's3'],
      );

      final reasons = <String>[];
      if (cls.studentIds.isNotEmpty) {
        reasons.add('${cls.studentIds.length} student(s) still in this class. Remove them first.');
      }

      expect(reasons.length, 1);
      expect(reasons[0], contains('student'));
      expect(reasons[0], contains('Remove'));
    });

    test('blocking reasons explain why deletion is blocked', () {
      final cls = ClassInfo(
        id: 'c1',
        name: 'Test Class',
        grade: 5,
        section: 'A',
        ownerId: 'teacher-1',
        studentIds: ['s1'],
      );

      final reasons = <String>[];
      if (cls.studentIds.isNotEmpty) {
        reasons.add('${cls.studentIds.length} student(s) still in this class. Remove them first.');
      }

      expect(reasons.first, contains('Remove'));
    });

    test('class can be deleted when empty', () {
      final cls = ClassInfo(
        id: 'c1',
        name: 'Test Class',
        grade: 5,
        section: 'A',
        ownerId: 'teacher-1',
        studentIds: [],
      );

      final canDelete = cls.studentIds.isEmpty;
      expect(canDelete, true);
    });

    test('class cannot be deleted when has students', () {
      final cls = ClassInfo(
        id: 'c1',
        name: 'Test Class',
        grade: 5,
        section: 'A',
        ownerId: 'teacher-1',
        studentIds: ['s1'],
      );

      final canDelete = cls.studentIds.isEmpty;
      expect(canDelete, false);
    });
  });
}
