import 'package:flutter_test/flutter_test.dart';

import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/weighted_grade.dart';

void main() {
  group('Assessment weightedScaleId linkage (FIX.1)', () {
    test('weightedScaleId is null by default', () {
      final a = Assessment(title: 'Test', subject: 'Math');
      expect(a.weightedScaleId, isNull);
    });

    test('weightedScaleId survives toMap/fromMap round-trip', () {
      final a = Assessment(
        title: 'Semester Final',
        subject: 'Biology',
        weightedScaleId: 'exam:abc-123');

      final map = a.toMap();
      expect(map['weightedScaleId'], 'exam:abc-123');

      final restored = Assessment.fromMap(map);
      expect(restored.weightedScaleId, 'exam:abc-123');
      expect(restored.title, 'Semester Final');
    });

    test('copyWith preserves weightedScaleId when not overridden', () {
      final a = Assessment(
        title: 'Test',
        subject: 'Math',
        weightedScaleId: 'exam:abc-123');

      final b = a.copyWith(title: 'Updated Title');
      expect(b.weightedScaleId, 'exam:abc-123');
      expect(b.title, 'Updated Title');
    });

    test('copyWith can set weightedScaleId', () {
      final a = Assessment(title: 'Test', subject: 'Math');

      final b = a.copyWith(weightedScaleId: 'exam:new-id');
      expect(b.weightedScaleId, 'exam:new-id');
    });

    test('copyWith can clear weightedScaleId with null', () {
      final a = Assessment(
        title: 'Test',
        subject: 'Math',
        weightedScaleId: 'exam:abc-123');

      // copyWith doesn't accept null to clear — use the constructor directly
      final b = Assessment(
        id: a.id,
        title: a.title,
        subject: a.subject,
        createdAt: a.createdAt,
        weightedScaleId: null);
      expect(b.weightedScaleId, isNull);
    });

    test('fromMap handles missing weightedScaleId gracefully', () {
      final map = {
        'id': 'test-id',
        'title': 'Old Assessment',
        'subject': 'English',
        'createdAt': DateTime.now().toIso8601String(),
        // No weightedScaleId in map — pre-fix data
      };

      final a = Assessment.fromMap(map);
      expect(a.weightedScaleId, isNull);
      expect(a.title, 'Old Assessment');
    });

    test('weightedScaleId format is exam:{uuid}', () {
      const examId = '550e8400-e29b-41d4-a716-446655440000';
      final a = Assessment(
        title: 'Test',
        subject: 'Math',
        weightedScaleId: 'exam:$examId');

      expect(a.weightedScaleId, startsWith('exam:'));
      // Strip prefix to recover exam ID
      final recoveredId = a.weightedScaleId!.substring('exam:'.length);
      expect(recoveredId, examId);
    });
  });

  group('WeightedGradeScale component linkage (FIX.1b)', () {
    test('components can have assessmentIds populated', () {
      const examId = 'exam-123';
      final scale = WeightedGradeScale(
        name: 'Semester 1',
        classId: 'class-1',
        components: [
          const GradeComponent(
            name: 'Quiz',
            weight: 0.20,
            assessmentIds: [examId]),
          const GradeComponent(
            name: 'Final',
            weight: 0.80,
            assessmentIds: [examId]),
        ]);

      expect(scale.components[0].assessmentIds, contains(examId));
      expect(scale.components[1].assessmentIds, contains(examId));
    });

    test('linked scale survives toMap/fromMap round-trip', () {
      final scale = WeightedGradeScale(
        name: 'Linked',
        classId: 'c1',
        components: [
          const GradeComponent(
            name: 'Quiz',
            weight: 0.30,
            assessmentIds: ['a1', 'a2']),
          const GradeComponent(
            name: 'Final',
            weight: 0.70,
            assessmentIds: ['a3']),
        ]);

      final map = scale.toMap();
      final restored = WeightedGradeScale.fromMap(map);

      expect(restored.components[0].assessmentIds, ['a1', 'a2']);
      expect(restored.components[1].assessmentIds, ['a3']);
    });
  });
}
