import 'package:ethiograde/models/scan_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScanResult copyWith', () {
    test('clears temporary image paths while preserving grade fields', () {
      final original = ScanResult(
        assessmentId: 'assessment-1',
        studentId: 'student-1',
        studentName: 'Paper 1',
        imagePath: '/tmp/paper.jpg',
        enhancedImagePath: '/tmp/paper_enhanced.jpg',
        totalScore: 8,
        maxScore: 10,
        percentage: 80,
        grade: 'A',
      );

      final gradesOnly = original.copyWith(
        imagePath: '',
        enhancedImagePath: null,
      );

      expect(gradesOnly.id, original.id);
      expect(gradesOnly.imagePath, isEmpty);
      expect(gradesOnly.enhancedImagePath, isNull);
      expect(gradesOnly.totalScore, 8);
      expect(gradesOnly.grade, 'A');
      expect(gradesOnly.studentName, 'Paper 1');
    });
  });
}
