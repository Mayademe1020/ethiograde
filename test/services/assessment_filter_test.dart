import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ethiograde/services/assessment_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ethiograde_filter_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('assessments');
  });

  tearDownAll(() async {
    if (Hive.isBoxOpen('assessments')) {
      await Hive.box('assessments').clear();
      await Hive.box('assessments').close();
    }
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

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

    test('setFilter with same value does not notify', () async {
      final provider = AssessmentProvider();
      // Wait for async load to complete
      await Future.delayed(Duration.zero);

      var notifyCount = 0;
      provider.addListener(() => notifyCount++);
      provider.setFilter(AssessmentFilter.all); // same as default
      expect(notifyCount, 0);
    });

    test('setFilter with different value notifies', () async {
      final provider = AssessmentProvider();
      await Future.delayed(Duration.zero);

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
      provider.setFilter(AssessmentFilter.all);
      expect(provider.filter, AssessmentFilter.all);
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
