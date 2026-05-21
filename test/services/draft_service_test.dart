import 'package:flutter_test/flutter_test.dart';

import 'package:ethiograde/services/draft_service.dart';

void main() {
  group('GradingDraft', () {
    test('completedCount returns correct count', () {
      final draft = GradingDraft(
        assessmentId: 'a1',
        completedResults: [
          {'studentId': 's1'},
          {'studentId': 's2'},
          {'studentId': 's3'},
        ],
        currentStudentIndex: 3,
        savedAt: DateTime.now());

      expect(draft.completedCount, 3);
    });

    test('ageLabel returns human-readable time', () {
      final recent = GradingDraft(
        assessmentId: 'a1',
        completedResults: [],
        currentStudentIndex: 0,
        savedAt: DateTime.now().subtract(const Duration(seconds: 30)));
      expect(recent.ageLabel, 'just now');

      final minutes = GradingDraft(
        assessmentId: 'a1',
        completedResults: [],
        currentStudentIndex: 0,
        savedAt: DateTime.now().subtract(const Duration(minutes: 5)));
      expect(minutes.ageLabel, contains('5m'));

      final hours = GradingDraft(
        assessmentId: 'a1',
        completedResults: [],
        currentStudentIndex: 0,
        savedAt: DateTime.now().subtract(const Duration(hours: 3)));
      expect(hours.ageLabel, contains('3h'));

      final days = GradingDraft(
        assessmentId: 'a1',
        completedResults: [],
        currentStudentIndex: 0,
        savedAt: DateTime.now().subtract(const Duration(days: 2)));
      expect(days.ageLabel, contains('2d'));
    });

    test('ageLabel returns human-readable age', () {
      final draft = GradingDraft(
        assessmentId: 'a1',
        completedResults: [],
        currentStudentIndex: 0,
        savedAt: DateTime.now().subtract(const Duration(minutes: 10)));

      expect(draft.ageLabel, contains('10m'));
    });
  });
}
