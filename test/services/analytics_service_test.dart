import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/models/student.dart';
import 'package:ethiograde/services/analytics_service.dart';

void main() {
  const analytics = AnalyticsService();

  late Assessment a1;
  late Assessment a2;
  late Student s1;
  late Student s2;

  setUp(() {
    a1 = Assessment(
      id: 'a1',
      title: 'Math Midterm',
      subject: 'Math',
      createdAt: DateTime(2026, 1, 15),
    );
    a2 = Assessment(
      id: 'a2',
      title: 'Math Final',
      subject: 'Math',
      createdAt: DateTime(2026, 3, 15),
    );
    s1 = Student(id: 's1', studentId: '001', firstName: 'Abebe', lastName: 'Kebede');
    s2 = Student(id: 's2', studentId: '002', firstName: 'Sara', lastName: 'Tesfaye');
  });

  ScanResult result({
    required String id,
    required String assessmentId,
    required String studentId,
    required double percentage,
  }) =>
      ScanResult(
        id: id,
        assessmentId: assessmentId,
        studentId: studentId,
        studentName: 'Test',
        imagePath: '/tmp/test.jpg',
        totalScore: percentage,
        maxScore: 100,
        percentage: percentage,
        confidence: 0.9,
      );

  group('computeStats', () {
    test('empty results returns zeros', () {
      final stats = analytics.computeStats(assessment: a1, results: []);
      expect(stats.average, 0);
      expect(stats.gradedCount, 0);
    });

    test('computes average correctly', () {
      final results = [
        result(id: 'r1', assessmentId: 'a1', studentId: 's1', percentage: 80),
        result(id: 'r2', assessmentId: 'a1', studentId: 's2', percentage: 60),
        result(id: 'r3', assessmentId: 'a1', studentId: 's3', percentage: 40),
      ];

      final stats = analytics.computeStats(assessment: a1, results: results);
      expect(stats.average, closeTo(60.0, 0.1));
      expect(stats.median, 60.0);
      expect(stats.min, 40.0);
      expect(stats.max, 80.0);
    });

    test('grade distribution counts pass/fail', () {
      final results = [
        result(id: 'r1', assessmentId: 'a1', studentId: 's1', percentage: 80),
        result(id: 'r2', assessmentId: 'a1', studentId: 's2', percentage: 60),
        result(id: 'r3', assessmentId: 'a1', studentId: 's3', percentage: 40),
        result(id: 'r4', assessmentId: 'a1', studentId: 's4', percentage: 30),
      ];

      final stats = analytics.computeStats(assessment: a1, results: results);
      expect(stats.gradeDistribution['PASS'], 2);
      expect(stats.gradeDistribution['FAIL'], 2);
    });
  });

  group('computeTrends', () {
    test('improving student detected', () {
      final results = [
        result(id: 'r1', assessmentId: 'a1', studentId: 's1', percentage: 50),
        result(id: 'r2', assessmentId: 'a2', studentId: 's1', percentage: 90),
      ];

      final trends = analytics.computeTrends(
        assessments: [a1, a2],
        allResults: results,
        students: [s1],
      );

      expect(trends.length, 1);
      expect(trends.first.direction, TrendDirection.improving);
    });

    test('declining student detected', () {
      final results = [
        result(id: 'r1', assessmentId: 'a1', studentId: 's1', percentage: 90),
        result(id: 'r2', assessmentId: 'a2', studentId: 's1', percentage: 50),
      ];

      final trends = analytics.computeTrends(
        assessments: [a1, a2],
        allResults: results,
        students: [s1],
      );

      expect(trends.first.direction, TrendDirection.declining);
    });

    test('stable student detected', () {
      final results = [
        result(id: 'r1', assessmentId: 'a1', studentId: 's1', percentage: 75),
        result(id: 'r2', assessmentId: 'a2', studentId: 's1', percentage: 78),
      ];

      final trends = analytics.computeTrends(
        assessments: [a1, a2],
        allResults: results,
        students: [s1],
      );

      expect(trends.first.direction, TrendDirection.stable);
    });
  });

  group('findAtRiskStudents', () {
    test('identifies student below threshold', () {
      final results = [
        result(id: 'r1', assessmentId: 'a1', studentId: 's1', percentage: 80),
        result(id: 'r2', assessmentId: 'a1', studentId: 's2', percentage: 30),
        result(id: 'r3', assessmentId: 'a2', studentId: 's2', percentage: 35),
      ];

      final atRisk = analytics.findAtRiskStudents(
        assessments: [a1, a2],
        allResults: results,
        students: [s1, s2],
      );

      expect(atRisk.length, 1);
      expect(atRisk.first.student.id, 's2');
      expect(atRisk.first.averagePercentage, closeTo(32.5, 0.1));
    });

    test('empty when all above threshold', () {
      final results = [
        result(id: 'r1', assessmentId: 'a1', studentId: 's1', percentage: 80),
        result(id: 'r2', assessmentId: 'a1', studentId: 's2', percentage: 70),
      ];

      final atRisk = analytics.findAtRiskStudents(
        assessments: [a1],
        allResults: results,
        students: [s1, s2],
      );

      expect(atRisk, isEmpty);
    });
  });

  group('computeBySubject', () {
    test('groups by subject', () {
      final a3 = Assessment(
        id: 'a3',
        title: 'English Quiz',
        subject: 'English',
        createdAt: DateTime(2026, 2, 1),
      );

      final results = [
        result(id: 'r1', assessmentId: 'a1', studentId: 's1', percentage: 80),
        result(id: 'r2', assessmentId: 'a2', studentId: 's1', percentage: 70),
        result(id: 'r3', assessmentId: 'a3', studentId: 's1', percentage: 90),
      ];

      final subjects = analytics.computeBySubject(
        assessments: [a1, a2, a3],
        allResults: results,
      );

      expect(subjects.length, 2);
      expect(subjects.first.subject, 'English');
      expect(subjects.first.classAverage, 90.0);
    });
  });
}
