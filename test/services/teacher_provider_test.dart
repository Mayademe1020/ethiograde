import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ethiograde/services/teacher_provider.dart';
import 'package:ethiograde/models/teacher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  const boxName = 'teachers';

  Teacher makeTeacher({
    String? id,
    String name = 'Abebe',
    String subject = 'Math',
    String school = 'Bole School',
    String role = 'teacher',
  }) =>
      Teacher(id: id, name: name, subject: subject, school: school, role: role);

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ethiograde_teacher_test_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    await Hive.openBox(boxName);
  });

  tearDown(() async {
    final box = Hive.box(boxName);
    await box.clear();
    await box.close();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('TeacherProvider — load', () {
    test('loads empty list when box is empty', () async {
      final provider = TeacherProvider();
      await provider.loadTeachers();
      expect(provider.isLoaded, isTrue);
      expect(provider.teachers, isEmpty);
    });

    test('loads teachers sorted by name', () async {
      // Pre-populate the box
      final box = Hive.box(boxName);
      final t1 = makeTeacher(id: '1', name: 'Zeleke');
      final t2 = makeTeacher(id: '2', name: 'Abebe');
      await box.put(t1.id, t1.toMap());
      await box.put(t2.id, t2.toMap());

      final provider = TeacherProvider();
      await provider.loadTeachers();

      expect(provider.teachers.length, 2);
      expect(provider.teachers.first.name, 'Abebe');
      expect(provider.teachers.last.name, 'Zeleke');
    });
  });

  group('TeacherProvider — addTeacher', () {
    test('adds valid teacher and persists to Hive', () async {
      final provider = TeacherProvider();
      await provider.loadTeachers();

      final teacher = makeTeacher(name: 'Almaz');
      final result = await provider.addTeacher(teacher);

      expect(result, isNotNull);
      expect(result!.name, 'Almaz');
      expect(provider.teachers.length, 1);

      // Verify persisted
      final box = Hive.box(boxName);
      expect(box.containsKey(teacher.id), isTrue);
    });

    test('rejects teacher with empty name', () async {
      final provider = TeacherProvider();
      await provider.loadTeachers();

      final result = await provider.addTeacher(makeTeacher(name: ''));

      expect(result, isNull);
      expect(provider.teachers, isEmpty);
      expect(provider.lastAddErrors, isNotEmpty);
      expect(provider.lastAddErrors.first, contains('empty'));
    });

    test('rejects teacher with whitespace-only name', () async {
      final provider = TeacherProvider();
      await provider.loadTeachers();

      final result = await provider.addTeacher(makeTeacher(name: '   '));

      expect(result, isNull);
      expect(provider.lastAddErrors.first, contains('empty'));
    });

    test('rejects teacher with name exceeding 100 chars', () async {
      final provider = TeacherProvider();
      await provider.loadTeachers();

      final longName = 'A' * 101;
      final result = await provider.addTeacher(makeTeacher(name: longName));

      expect(result, isNull);
      expect(provider.lastAddErrors.first, contains('100'));
    });

    test('rejects duplicate teacher name (case-insensitive)', () async {
      final provider = TeacherProvider();
      await provider.loadTeachers();

      await provider.addTeacher(makeTeacher(id: '1', name: 'Abebe'));
      final result = await provider.addTeacher(
        makeTeacher(id: '2', name: 'ABEBE'));

      expect(result, isNull);
      expect(provider.teachers.length, 1);
      expect(provider.lastAddErrors.first, contains('already exists'));
    });

    test('rejects invalid role', () async {
      final provider = TeacherProvider();
      await provider.loadTeachers();

      final teacher = Teacher(name: 'Test', role: 'superadmin');
      final result = await provider.addTeacher(teacher);

      expect(result, isNull);
      expect(provider.lastAddErrors.first, contains('Invalid role'));
    });

    test('maintains sorted order after adding', () async {
      final provider = TeacherProvider();
      await provider.loadTeachers();

      await provider.addTeacher(makeTeacher(id: '1', name: 'Zeleke'));
      await provider.addTeacher(makeTeacher(id: '2', name: 'Abebe'));

      expect(provider.teachers.first.name, 'Abebe');
      expect(provider.teachers.last.name, 'Zeleke');
    });
  });

  group('TeacherProvider — updateTeacher', () {
    test('updates existing teacher', () async {
      final provider = TeacherProvider();
      await provider.loadTeachers();

      final teacher = makeTeacher(id: '1', name: 'Abebe');
      await provider.addTeacher(teacher);

      final updated = teacher.copyWith(
        name: 'Abebe Updated',
        subject: 'Physics');
      final result = await provider.updateTeacher(updated);

      expect(result, isTrue);
      expect(provider.getById('1')!.name, 'Abebe Updated');
      expect(provider.getById('1')!.subject, 'Physics');
    });

    test('rejects update with empty name', () async {
      final provider = TeacherProvider();
      await provider.loadTeachers();

      final teacher = makeTeacher(id: '1', name: 'Abebe');
      await provider.addTeacher(teacher);

      final updated = teacher.copyWith(name: '');
      final result = await provider.updateTeacher(updated);

      expect(result, isFalse);
      // Original unchanged
      expect(provider.getById('1')!.name, 'Abebe');
    });

    test('rejects update with duplicate name (other teacher)', () async {
      final provider = TeacherProvider();
      await provider.loadTeachers();

      await provider.addTeacher(makeTeacher(id: '1', name: 'Abebe'));
      await provider.addTeacher(makeTeacher(id: '2', name: 'Zeleke'));

      // Try to rename Zeleke to Abebe
      final updated = provider.getById('2')!.copyWith(name: 'Abebe');
      final result = await provider.updateTeacher(updated);

      expect(result, isFalse);
      expect(provider.getById('2')!.name, 'Zeleke');
    });

    test('allows updating teacher to same name (no change)', () async {
      final provider = TeacherProvider();
      await provider.loadTeachers();

      final teacher = makeTeacher(id: '1', name: 'Abebe');
      await provider.addTeacher(teacher);

      // Update with same name but different subject
      final updated = teacher.copyWith(subject: 'Science');
      final result = await provider.updateTeacher(updated);

      expect(result, isTrue);
      expect(provider.getById('1')!.subject, 'Science');
    });
  });

  group('TeacherProvider — deleteTeacher', () {
    test('deletes existing teacher', () async {
      final provider = TeacherProvider();
      await provider.loadTeachers();

      await provider.addTeacher(makeTeacher(id: '1', name: 'Abebe'));
      expect(provider.teachers.length, 1);

      final result = await provider.deleteTeacher('1');

      expect(result, isTrue);
      expect(provider.teachers, isEmpty);

      // Verify removed from Hive
      final box = Hive.box(boxName);
      expect(box.containsKey('1'), isFalse);
    });

    test('returns true even for non-existent ID', () async {
      final provider = TeacherProvider();
      await provider.loadTeachers();

      final result = await provider.deleteTeacher('nonexistent');
      expect(result, isTrue);
    });
  });

  group('TeacherProvider — activeTeacher', () {
    test('returns first active teacher', () async {
      final provider = TeacherProvider();
      await provider.loadTeachers();

      await provider.addTeacher(makeTeacher(id: '1', name: 'Abebe'));
      expect(provider.activeTeacher, isNotNull);
      expect(provider.activeTeacher!.name, 'Abebe');
    });

    test('returns null for empty list', () async {
      final provider = TeacherProvider();
      await provider.loadTeachers();

      expect(provider.activeTeacher, isNull);
      expect(provider.activeTeacherName, '');
    });

    test('setActive switches active teacher', () async {
      final provider = TeacherProvider();
      await provider.loadTeachers();

      await provider.addTeacher(makeTeacher(id: '1', name: 'Abebe'));
      await provider.addTeacher(makeTeacher(id: '2', name: 'Zeleke'));

      await provider.setActive('2');

      expect(provider.activeTeacher!.id, '2');
      // '1' should be deactivated
      expect(provider.getById('1')!.isActive, isFalse);
    });
  });

  group('TeacherProvider — getById', () {
    test('returns teacher by ID', () async {
      final provider = TeacherProvider();
      await provider.loadTeachers();

      await provider.addTeacher(makeTeacher(id: '1', name: 'Abebe'));

      final found = provider.getById('1');
      expect(found, isNotNull);
      expect(found!.name, 'Abebe');
    });

    test('returns null for unknown ID', () async {
      final provider = TeacherProvider();
      await provider.loadTeachers();

      expect(provider.getById('unknown'), isNull);
    });
  });
}
