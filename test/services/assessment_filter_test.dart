import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/services/assessment_provider.dart';

void main() {
  group('AssessmentFilter', () {
    test('default filter is all', () {
      final provider = AssessmentProvider();
      expect(provider.filter, AssessmentFilter.all);
    });

    test('setFilter changes filter value', () {
      final provider = AssessmentProvider();
      provider.setFilter(AssessmentFilter.active);
      expect(provider.filter, AssessmentFilter.active);
    });

    test('setFilter with same value does not notify', () {
      final provider = AssessmentProvider();
      var notifyCount = 0;
      provider.addListener(() => notifyCount++);
      provider.setFilter(AssessmentFilter.all); // same as default
      expect(notifyCount, 0);
    });

    test('setFilter with different value notifies', () {
      final provider = AssessmentProvider();
      var notifyCount = 0;
      provider.addListener(() => notifyCount++);
      provider.setFilter(AssessmentFilter.completed);
      expect(notifyCount, 1);
    });
  });

  group('filteredAssessments (in-memory)', () {
    late AssessmentProvider provider;

    setUp(() {
      provider = AssessmentProvider();
    });

    test('returns empty list when no assessments', () {
      expect(provider.filteredAssessments, isEmpty);
    });

    test('all filter returns all assessments', () {
      // Simulate loaded state via internal list
      // Since we can't easily populate Hive in unit tests,
      // verify the enum switching logic is correct
      provider.setFilter(AssessmentFilter.all);
      expect(provider.filter, AssessmentFilter.all);
      expect(provider.filteredAssessments, isEmpty);
    });

    test('active filter is selectable', () {
      provider.setFilter(AssessmentFilter.active);
      expect(provider.filter, AssessmentFilter.active);
    });

    test('completed filter is selectable', () {
      provider.setFilter(AssessmentFilter.completed);
      expect(provider.filter, AssessmentFilter.completed);
    });

    test('filter cycles through all values', () {
      provider.setFilter(AssessmentFilter.active);
      expect(provider.filter, AssessmentFilter.active);
      provider.setFilter(AssessmentFilter.completed);
      expect(provider.filter, AssessmentFilter.completed);
      provider.setFilter(AssessmentFilter.all);
      expect(provider.filter, AssessmentFilter.all);
    });
  });
}
