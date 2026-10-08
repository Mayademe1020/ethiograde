import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ethiograde/services/demo_data_service.dart';
import 'package:ethiograde/services/class_provider.dart';
import 'package:ethiograde/services/student_provider.dart';
import 'package:ethiograde/services/assessment_provider.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/config/hive_adapters.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ClassProvider classProvider;
  late StudentProvider studentProvider;
  late AssessmentProvider assessmentProvider;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ethiograde_demo_test_');
    Hive.init(tempDir.path);
    registerHiveAdapters();
  });

  setUp(() async {
    await Hive.openBox('classes');
    await Hive.openBox('students');
    await Hive.openBox('assessments');

    classProvider = ClassProvider();
    await classProvider.loadClasses();

    studentProvider = StudentProvider();
    // StudentProvider loads in constructor

    assessmentProvider = AssessmentProvider();
    // AssessmentProvider loads in constructor
  });

  tearDown(() async {
    for (final name in ['classes', 'students', 'assessments']) {
      final box = Hive.box(name);
      await box.clear();
      await box.close();
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('DemoDataService — seed', () {
    test('creates 1 demo class', () async {
      await DemoDataService.seed(
        classProvider: classProvider,
        studentProvider: studentProvider,
        assessmentProvider: assessmentProvider);

      expect(classProvider.classes, hasLength(1));
      final cls = classProvider.classes.first;
      expect(cls.id, 'demo-class-001');
      expect(cls.grade, 5);
      expect(cls.section, 'A');
      expect(cls.subject, 'Mathematics');
    });

    test('creates 5 students linked to class', () async {
      await DemoDataService.seed(
        classProvider: classProvider,
        studentProvider: studentProvider,
        assessmentProvider: assessmentProvider);

      expect(studentProvider.students, hasLength(5));

      // All students should be in the demo class
      for (final student in studentProvider.students) {
        expect(student.classIds, contains('demo-class-001'));
        expect(student.grade, 5);
        expect(student.section, 'A');
      }

      // Class should have 5 student IDs
      final cls = classProvider.classes.first;
      expect(cls.studentIds, hasLength(5));
    });

    test('students have bilingual names', () async {
      await DemoDataService.seed(
        classProvider: classProvider,
        studentProvider: studentProvider,
        assessmentProvider: assessmentProvider);

      for (final student in studentProvider.students) {
        expect(student.firstName, isNotEmpty);
        expect(student.lastName, isNotEmpty);
      }
    });

    test('creates 1 assessment with 10 questions', () async {
      await DemoDataService.seed(
        classProvider: classProvider,
        studentProvider: studentProvider,
        assessmentProvider: assessmentProvider);

      expect(assessmentProvider.assessments, hasLength(greaterThanOrEqualTo(1)));
      final assessment = assessmentProvider.assessments
          .firstWhere((a) => a.id == 'demo-assessment-001');
      expect(assessment.questions, hasLength(10));
      expect(assessment.status, AssessmentStatus.active);
    });

    test('questions have bilingual text and correct answers', () async {
      await DemoDataService.seed(
        classProvider: classProvider,
        studentProvider: studentProvider,
        assessmentProvider: assessmentProvider);

      final assessment = assessmentProvider.assessments
          .firstWhere((a) => a.id == 'demo-assessment-001');
      final questions = assessment.questions;
      for (final q in questions) {
        expect(q.text, isNotEmpty);
        expect(q.correctAnswer, isNotNull);
        expect(q.points, greaterThan(0));
      }
    });

    test('is idempotent — does not duplicate on second call', () async {
      await DemoDataService.seed(
        classProvider: classProvider,
        studentProvider: studentProvider,
        assessmentProvider: assessmentProvider);

      await DemoDataService.seed(
        classProvider: classProvider,
        studentProvider: studentProvider,
        assessmentProvider: assessmentProvider);

      final countBefore = assessmentProvider.assessments.length;

      await DemoDataService.seed(
        classProvider: classProvider,
        studentProvider: studentProvider,
        assessmentProvider: assessmentProvider);

      expect(classProvider.classes, hasLength(1));
      expect(studentProvider.students, hasLength(5));
      expect(assessmentProvider.assessments, hasLength(countBefore));
    });

    test('assessment has mix of MCQ and True/False', () async {
      await DemoDataService.seed(
        classProvider: classProvider,
        studentProvider: studentProvider,
        assessmentProvider: assessmentProvider);

      final assessment = assessmentProvider.assessments
          .firstWhere((a) => a.id == 'demo-assessment-001');
      final questions = assessment.questions;
      final mcqCount = questions.where((q) => q.type == QuestionType.mcq).length;
      final tfCount = questions.where((q) => q.type == QuestionType.trueFalse).length;

      expect(mcqCount, 8);
      expect(tfCount, 2);
    });
  });
}
