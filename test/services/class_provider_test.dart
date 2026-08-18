import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ethiograde/services/class_provider.dart';
import 'package:ethiograde/models/class_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  const boxName = 'classes';

  ClassInfo makeClass({
    String? id,
    String name = 'Grade 5A',
    int grade = 5,
    String section = 'A',
    String subject = 'Math',
    String ownerId = 'teacher-1',
    List<String>? studentIds,
  }) => ClassInfo(
    id: id,
    name: name,
    grade: grade,
    section: section,
    subject: subject,
    ownerId: ownerId,
    studentIds: studentIds,
  );

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ethiograde_class_test_');
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

  group('ClassProvider — load', () {
    test('loads empty list when box is empty', () async {
      final provider = ClassProvider();
      await provider.loadClasses();
      expect(provider.classes, isEmpty);
      expect(provider.isLoaded, isTrue);
    });

    test('loads classes from Hive', () async {
      final box = Hive.box(boxName);
      final cls = makeClass();
      await box.put(cls.id, cls.toMap());

      final provider = ClassProvider();
      await provider.loadClasses();

      expect(provider.classes, hasLength(1));
      expect(provider.classes.first.name, 'Grade 5A');
      expect(provider.isLoaded, isTrue);
    });

    test('does not reload if already loaded', () async {
      final provider = ClassProvider();
      await provider.loadClasses();
      await provider.loadClasses(); // second call should be no-op
      expect(provider.isLoaded, isTrue);
    });

    test('flags loadFailed on read failure, reload recovers', () async {
      final box = Hive.box(boxName);
      await box.put('broken', {'name': 123, 'grade': 'not-an-int'});

      final provider = ClassProvider();
      await provider.loadClasses();

      expect(provider.loadFailed, isTrue);
      expect(provider.classes, isEmpty);

      // Repair storage then reload — clears the failure flag.
      await box.delete('broken');
      await provider.reload();
      expect(provider.loadFailed, isFalse);
      expect(provider.classes, isEmpty);
    });
  });

  group('ClassProvider — add', () {
    test('adds a class and persists', () async {
      final provider = ClassProvider();
      await provider.loadClasses();

      final cls = makeClass();
      final result = await provider.addClass(cls);

      expect(result, isNotNull);
      expect(result!.id, cls.id);
      expect(provider.classes, hasLength(1));

      // Verify persisted
      final box = Hive.box(boxName);
      expect(box.containsKey(cls.id), isTrue);
    });

    test('rejects empty name', () async {
      final provider = ClassProvider();
      await provider.loadClasses();

      final result = await provider.addClass(makeClass(name: ''));
      expect(result, isNull);
      expect(provider.classes, isEmpty);
    });
  });

  group('ClassProvider — update', () {
    test('updates a class', () async {
      final provider = ClassProvider();
      await provider.loadClasses();

      final cls = makeClass();
      await provider.addClass(cls);

      final updated = cls.copyWith(name: 'Grade 5B');
      final ok = await provider.updateClass(updated);

      expect(ok, isTrue);
      expect(provider.classes.first.name, 'Grade 5B');
    });

    test('returns false for missing class', () async {
      final provider = ClassProvider();
      await provider.loadClasses();

      final ok = await provider.updateClass(makeClass(id: 'no-such-id'));
      expect(ok, isFalse);
    });
  });

  group('ClassProvider — delete', () {
    test('deletes a class', () async {
      final provider = ClassProvider();
      await provider.loadClasses();

      final cls = makeClass();
      await provider.addClass(cls);
      expect(provider.classes, hasLength(1));

      final ok = await provider.deleteClass(cls.id);
      expect(ok, isTrue);
      expect(provider.classes, isEmpty);
    });

    test('clears selection if deleted class was selected', () async {
      final provider = ClassProvider();
      await provider.loadClasses();

      final cls = makeClass();
      await provider.addClass(cls);
      provider.selectClass(cls.id);
      expect(provider.selectedClassId, cls.id);

      await provider.deleteClass(cls.id);
      expect(provider.selectedClassId, isEmpty);
    });
  });

  group('ClassProvider — student linking', () {
    test('addStudentToClass adds student ID', () async {
      final provider = ClassProvider();
      await provider.loadClasses();

      final cls = makeClass();
      await provider.addClass(cls);

      final ok = await provider.addStudentToClass(cls.id, 'student-1');
      expect(ok, isTrue);
      expect(provider.classes.first.studentIds, contains('student-1'));
    });

    test('addStudentToClass does not duplicate', () async {
      final provider = ClassProvider();
      await provider.loadClasses();

      final cls = makeClass(studentIds: ['student-1']);
      await provider.addClass(cls);

      final ok = await provider.addStudentToClass(cls.id, 'student-1');
      expect(ok, isTrue);
      expect(provider.classes.first.studentIds, hasLength(1));
    });

    test('removeStudentFromClass removes student ID', () async {
      final provider = ClassProvider();
      await provider.loadClasses();

      final cls = makeClass(studentIds: ['s1', 's2', 's3']);
      await provider.addClass(cls);

      final ok = await provider.removeStudentFromClass(cls.id, 's2');
      expect(ok, isTrue);
      expect(provider.classes.first.studentIds, ['s1', 's3']);
    });

    test('addStudentsToClass adds multiple', () async {
      final provider = ClassProvider();
      await provider.loadClasses();

      final cls = makeClass(studentIds: ['s1']);
      await provider.addClass(cls);

      final added = await provider.addStudentsToClass(cls.id, [
        's2',
        's3',
        's1',
      ]);
      expect(added, 2); // s1 already existed
      expect(provider.classes.first.studentIds, hasLength(3));
    });
  });

  group('ClassProvider — selection', () {
    test('selectClass and clearSelection', () async {
      final provider = ClassProvider();
      await provider.loadClasses();

      final cls = makeClass();
      await provider.addClass(cls);

      provider.selectClass(cls.id);
      expect(provider.selectedClass, isNotNull);
      expect(provider.selectedClass!.id, cls.id);

      provider.clearSelection();
      expect(provider.selectedClass, isNull);
    });
  });

  group('ClassProvider — queries', () {
    test('getClassById returns class', () async {
      final provider = ClassProvider();
      await provider.loadClasses();

      final cls = makeClass();
      await provider.addClass(cls);

      final found = provider.getClassById(cls.id);
      expect(found, isNotNull);
      expect(found!.name, 'Grade 5A');
    });

    test('getClassById returns null for missing', () async {
      final provider = ClassProvider();
      await provider.loadClasses();
      expect(provider.getClassById('nope'), isNull);
    });

    test('classesForTeacher filters by owner', () async {
      final provider = ClassProvider();
      await provider.loadClasses();

      await provider.addClass(makeClass(ownerId: 't1', name: 'Class A'));
      await provider.addClass(makeClass(ownerId: 't2', name: 'Class B'));
      await provider.addClass(makeClass(ownerId: 't1', name: 'Class C'));

      final t1Classes = provider.classesForTeacher('t1');
      expect(t1Classes, hasLength(2));
    });

    test('classesForStudent filters by student ID', () async {
      final provider = ClassProvider();
      await provider.loadClasses();

      await provider.addClass(makeClass(id: 'c1', studentIds: ['s1', 's2']));
      await provider.addClass(makeClass(id: 'c2', studentIds: ['s2', 's3']));
      await provider.addClass(makeClass(id: 'c3', studentIds: ['s1']));

      final s1Classes = provider.classesForStudent('s1');
      expect(s1Classes, hasLength(2));
      expect(s1Classes.map((c) => c.id), containsAll(['c1', 'c3']));
    });
  });
}
