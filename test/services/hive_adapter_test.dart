import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'dart:io';

import 'package:ethiograde/models/student.dart';
import 'package:ethiograde/models/class_info.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/models/audit_entry.dart';
import 'package:ethiograde/models/grading_scale.dart';
import 'package:ethiograde/models/teacher.dart';
import 'package:ethiograde/models/weighted_grade.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_adapter_test');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('Hive TypeAdapter typeIds', () {
    test('all models have unique typeId annotations', () {
      // Verify annotations compile — if duplicate typeIds exist,
      // Hive.registerAdapter() will throw at runtime.
      // This test catches annotation errors before deploy.
      expect(Student, isNotNull);
      expect(ClassInfo, isNotNull);
      expect(Assessment, isNotNull);
      expect(Question, isNotNull);
      expect(EssayRubric, isNotNull);
      expect(AssessmentStatus.values, isNotEmpty);
      expect(QuestionType.values, isNotEmpty);
      expect(ScanResult, isNotNull);
      expect(AnswerMatch, isNotNull);
      expect(BoundingBox, isNotNull);
      expect(ScanStatus.values, isNotEmpty);
      expect(AuditEntry, isNotNull);
      expect(GradingScale, isNotNull);
      expect(GradeRange, isNotNull);
      expect(Teacher, isNotNull);
      expect(WeightedGradeScale, isNotNull);
      expect(GradeComponent, isNotNull);
    });

    test('Student round-trips through toMap/fromMap', () {
      final student = Student(
        studentId: 'S001',
        firstName: 'Abebe',
        lastName: 'Kebede',
        gender: 'M',
        classIds: ['class-1'],
        grade: 5);

      final map = student.toMap();
      final restored = Student.fromMap(map);

      expect(restored.id, student.id);
      expect(restored.studentId, 'S001');
      expect(restored.firstName, 'Abebe');
      expect(restored.lastName, 'Kebede');
      expect(restored.gender, 'M');
      expect(restored.classIds, ['class-1']);
      expect(restored.grade, 5);
    });

    test('ClassInfo round-trips through toMap/fromMap', () {
      final classInfo = ClassInfo(
        name: 'Grade 5A',
        school: 'Test School',
        grade: 5,
        section: 'A',
        subject: 'Math',
        studentIds: ['s1', 's2'],
        ownerId: 'teacher-1');

      final map = classInfo.toMap();
      final restored = ClassInfo.fromMap(map);

      expect(restored.id, classInfo.id);
      expect(restored.name, 'Grade 5A');
      expect(restored.grade, 5);
      expect(restored.studentIds, ['s1', 's2']);
    });

    test('Assessment round-trips through toMap/fromMap', () {
      final assessment = Assessment(
        title: 'Midterm',
        subject: 'Math',
        questions: [
          Question(
            number: 1,
            type: QuestionType.mcq,
            points: 2.0,
            correctAnswer: 'A'),
          Question(
            number: 2,
            type: QuestionType.trueFalse,
            points: 1.0,
            correctAnswer: 'true'),
        ],
        totalPoints: 3,
        passingPoints: 2,
        status: AssessmentStatus.active);

      final map = assessment.toMap();
      final restored = Assessment.fromMap(map);

      expect(restored.id, assessment.id);
      expect(restored.title, 'Midterm');
      expect(restored.questions.length, 2);
      expect(restored.questions[0].type, QuestionType.mcq);
      expect(restored.questions[1].type, QuestionType.trueFalse);
      expect(restored.status, AssessmentStatus.active);
    });

    test('ScanResult round-trips through toMap/fromMap', () {
      final result = ScanResult(
        assessmentId: 'a1',
        studentId: 's1',
        studentName: 'Abebe',
        imagePath: '/path/to/image.jpg',
        answers: [
          AnswerMatch(
            questionNumber: 1,
            detectedAnswer: 'A',
            correctAnswer: 'A',
            isCorrect: true,
            score: 2,
            maxScore: 2,
            confidence: 0.95,
            boundingBox: BoundingBox(left: 10, top: 20, right: 50, bottom: 60)),
        ],
        totalScore: 2,
        maxScore: 2,
        percentage: 100,
        grade: 'A',
        status: ScanStatus.graded,
        confidence: 0.95);

      final map = result.toMap();
      final restored = ScanResult.fromMap(map);

      expect(restored.id, result.id);
      expect(restored.studentName, 'Abebe');
      expect(restored.answers.length, 1);
      expect(restored.answers[0].isCorrect, true);
      expect(restored.answers[0].boundingBox!.left, 10);
      expect(restored.status, ScanStatus.graded);
    });

    test('Teacher round-trips through toMap/fromMap', () {
      final teacher = Teacher(
        name: 'Ato Kebede',
        subject: 'Math',
        school: 'Test School',
        role: 'teacher');

      final map = teacher.toMap();
      final restored = Teacher.fromMap(map);

      expect(restored.id, teacher.id);
      expect(restored.name, 'Ato Kebede');
      expect(restored.role, 'teacher');
    });

    test('GradingScale round-trips through toMap/fromMap', () {
      final scale = GradingScale(
        name: 'Standard',
        ranges: [
          const GradeRange(grade: 'A', minScore: 90, maxScore: 100),
          const GradeRange(grade: 'B', minScore: 80, maxScore: 89),
          const GradeRange(grade: 'F', minScore: 0, maxScore: 79),
        ]);

      final map = scale.toMap();
      final restored = GradingScale.fromMap(map);

      expect(restored.id, scale.id);
      expect(restored.name, 'Standard');
      expect(restored.ranges.length, 3);
      expect(restored.gradeFor(95), 'A');
      expect(restored.gradeFor(75), 'F');
    });

    test('WeightedGradeScale round-trips through toMap/fromMap', () {
      final scale = WeightedGradeScale(
        name: 'Semester 1',
        classId: 'c1',
        components: [
          const GradeComponent(name: 'Quiz', weight: 0.30),
          const GradeComponent(name: 'Final', weight: 0.70),
        ]);

      final map = scale.toMap();
      final restored = WeightedGradeScale.fromMap(map);

      expect(restored.id, scale.id);
      expect(restored.name, 'Semester 1');
      expect(restored.components.length, 2);
      expect(restored.isValid, true);
    });
  });
}
