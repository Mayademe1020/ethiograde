import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/services/homeroom_consolidation_service.dart';
import 'package:ethiograde/models/assessment.dart';

void main() {
  group('HomeroomConsolidationService Tests', () {
    final service = HomeroomConsolidationService();

    final testStudents = [
      {'id': 's1', 'fullName': 'Abebe Kebede', 'rollNumber': '001', 'gender': 'M'},
      {'id': 's2', 'fullName': 'Almaz Tesfaye', 'rollNumber': '002', 'gender': 'F'},
      {'id': 's3', 'fullName': 'Chala Bekele', 'rollNumber': '003', 'gender': 'M'},
    ];

    test('Consolidates class and calculates ranks based on scores', () {
      final assessments = [
        Assessment(
          id: 'a1',
          title: 'Biology Midterm Exam',
          className: 'Grade 10A',
          subject: 'Biology',
          maxScore: 30,
          rubricType: 'moe_national',
        ),
      ];

      final report = service.consolidateClass(
        classId: 'c1',
        className: 'Grade 10A',
        academicYear: '2017 E.C.',
        semester: 1,
        homeroomTeacherName: 'Teacher Aster',
        studentsData: testStudents,
        assessments: assessments,
      );

      expect(report.className, equals('Grade 10A'));
      expect(report.students.length, equals(3));
      expect(report.students[0].classRank, equals(1));
    });

    test('Propagates Finance Hold (እዳ ያለበት) flag correctly', () {
      final report = service.consolidateClass(
        classId: 'c1',
        className: 'Grade 10A',
        academicYear: '2017 E.C.',
        semester: 1,
        homeroomTeacherName: 'Teacher Aster',
        studentsData: testStudents,
        assessments: [],
        financeHolds: {'s2': true},
      );

      final s2Record = report.students.firstWhere((s) => s.studentId == 's2');
      final s1Record = report.students.firstWhere((s) => s.studentId == 's1');

      expect(s2Record.hasFinanceHold, isTrue);
      expect(s1Record.hasFinanceHold, isFalse);
    });

    test('Assigns conduct grade properly', () {
      final report = service.consolidateClass(
        classId: 'c1',
        className: 'Grade 10A',
        academicYear: '2017 E.C.',
        semester: 1,
        homeroomTeacherName: 'Teacher Aster',
        studentsData: testStudents,
        assessments: [],
        conductGrades: {'s3': 'B'},
      );

      final s3Record = report.students.firstWhere((s) => s.studentId == 's3');
      expect(s3Record.conduct, equals('B'));
    });
  });
}
