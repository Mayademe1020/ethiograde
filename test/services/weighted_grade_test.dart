import 'package:flutter_test/flutter_test.dart';

import 'package:ethiograde/services/weighted_grade_service.dart';
import 'package:ethiograde/models/weighted_grade.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/models/student.dart';

void main() {
  const service = WeightedGradeService();

  final student = Student(
    id: 's1',
    studentId: '001',
    firstName: 'Abebe',
    lastName: 'Kebede');

  final scale = WeightedGradeScale(
    id: 'scale1',
    name: 'Semester 1',
    classId: 'class1',
    components: [
      const GradeComponent(
        name: 'Quiz',
        weight: 0.20,
        assessmentIds: ['quiz1', 'quiz2']),
      const GradeComponent(
        name: 'Midterm',
        weight: 0.30,
        assessmentIds: ['midterm1']),
      const GradeComponent(
        name: 'Final',
        weight: 0.50,
        assessmentIds: ['final1']),
    ]);

  group('WeightedGradeScale', () {
    test('isValid returns true when weights sum to 1.0', () {
      expect(scale.isValid, isTrue);
    });

    test('isValid returns false when weights do not sum to 1.0', () {
      final badScale = WeightedGradeScale(
        name: 'Bad',
        classId: 'c1',
        components: [
          const GradeComponent(name: 'A', weight: 0.30),
          const GradeComponent(name: 'B', weight: 0.30),
        ]);
      expect(badScale.isValid, isFalse);
    });

    test('round-trips through toMap/fromMap', () {
      final map = scale.toMap();
      final restored = WeightedGradeScale.fromMap(map);
      expect(restored.name, 'Semester 1');
      expect(restored.components.length, 3);
      expect(restored.components[0].weight, 0.20);
      expect(restored.isValid, isTrue);
    });
  });

  group('WeightedGradeService.computeStudentGrade', () {
    test('computes weighted average correctly', () {
      // Quiz avg: (80 + 90) / 2 = 85 → 85 * 0.20 = 17
      // Midterm: 70 → 70 * 0.30 = 21
      // Final: 60 → 60 * 0.50 = 30
      // Total: 17 + 21 + 30 = 68 → grade C+
      final scores = {
        'quiz1': 80.0,
        'quiz2': 90.0,
        'midterm1': 70.0,
        'final1': 60.0,
      };

      final grade = service.computeStudentGrade(
        student: student,
        scale: scale,
        studentScores: scores);

      expect(grade, isNotNull);
      expect(grade!.weightedPercentage, closeTo(68.0, 0.1));
      expect(grade.letterGrade, 'C+');
      expect(grade.isComplete, isTrue);
    });

    test('handles missing components with partial grade', () {
      // Only quizzes graded
      final scores = {'quiz1': 80.0, 'quiz2': 90.0};

      final grade = service.computeStudentGrade(
        student: student,
        scale: scale,
        studentScores: scores);

      expect(grade, isNotNull);
      expect(grade!.isComplete, isFalse);
      expect(grade.missingComponents, contains('Midterm'));
      expect(grade.missingComponents, contains('Final'));
      // Partial: only quiz avg = 85%, normalized to 100% of quiz weight
      expect(grade.weightedPercentage, closeTo(85.0, 0.1));
    });

    test('returns null when no scores at all', () {
      final grade = service.computeStudentGrade(
        student: student,
        scale: scale,
        studentScores: {});
      expect(grade, isNull);
    });

    test('dropLowest works correctly', () {
      final scaleWithDrop = WeightedGradeScale(
        name: 'With Drop',
        classId: 'c1',
        components: [
          const GradeComponent(
            name: 'Quizzes',
            weight: 1.0,
            assessmentIds: ['q1', 'q2', 'q3'],
            dropLowest: 1),
        ]);

      // Scores: 50, 80, 90 → drop 50 → avg = (80+90)/2 = 85
      final scores = {'q1': 50.0, 'q2': 80.0, 'q3': 90.0};

      final grade = service.computeStudentGrade(
        student: student,
        scale: scaleWithDrop,
        studentScores: scores);

      expect(grade, isNotNull);
      expect(grade!.weightedPercentage, closeTo(85.0, 0.1));
    });
  });

  group('WeightedGradeService.recalculateWithNewScale', () {
    test('recalculates letter grades with new rubric', () {
      final oldGrades = [
        const CompositeGrade(
          studentId: 's1',
          studentName: 'Abebe',
          componentAverages: {'Quiz': 85},
          componentAttempts: {'Quiz': 1},
          weightedPercentage: 72.0,
          letterGrade: 'B-', // moe_national: 70-74
          rubricType: 'moe_national'),
      ];

      final newGrades = service.recalculateWithNewScale(
        existingGrades: oldGrades,
        newRubricType: 'private_international');

      expect(newGrades.length, 1);
      expect(newGrades[0].letterGrade, 'C'); // private: 60-69
      expect(newGrades[0].weightedPercentage, 72.0); // unchanged
    });
  });

  group('WeightedGradeService.computeClassStats', () {
    test('computes class statistics correctly', () {
      final grades = [
        const CompositeGrade(
          studentId: 's1', studentName: 'A',
          componentAverages: {}, componentAttempts: {},
          weightedPercentage: 85, letterGrade: 'A',
          rubricType: 'moe_national'),
        const CompositeGrade(
          studentId: 's2', studentName: 'B',
          componentAverages: {}, componentAttempts: {},
          weightedPercentage: 65, letterGrade: 'C+',
          rubricType: 'moe_national'),
        const CompositeGrade(
          studentId: 's3', studentName: 'C',
          componentAverages: {}, componentAttempts: {},
          weightedPercentage: 40, letterGrade: 'F',
          rubricType: 'moe_national'),
      ];

      final stats = service.computeClassStats(grades);

      expect(stats.studentCount, 3);
      expect(stats.average, closeTo(63.33, 0.1));
      expect(stats.highest, 85);
      expect(stats.lowest, 40);
      expect(stats.passRate, closeTo(66.67, 0.1)); // 2/3 pass
      expect(stats.gradeDistribution['A'], 1);
      expect(stats.gradeDistribution['F'], 1);
    });

    test('handles empty list', () {
      final stats = service.computeClassStats([]);
      expect(stats.studentCount, 0);
      expect(stats.average, 0);
    });
  });
}
