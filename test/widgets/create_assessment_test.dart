import 'dart:io';

import 'package:ethiograde/screens/assessment/exam_day_create_screen.dart';
import 'package:ethiograde/services/assessment_provider.dart';
import 'package:ethiograde/services/class_provider.dart';
import 'package:ethiograde/services/settings_provider.dart';
import 'package:ethiograde/services/student_provider.dart';
import 'package:ethiograde/services/teacher_provider.dart';
import 'package:ethiograde/services/weighted_grade_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ethiograde_create_test_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Hive.openBox('students');
    await Hive.openBox('assessments');
    await Hive.openBox('classes');
    await Hive.openBox('teachers');
    await Hive.openBox('settings_pii');
    await Hive.openBox('metadata');
    await Hive.openBox('weighted_grades');
  });

  tearDown(() async {
    for (final name in [
      'students',
      'assessments',
      'classes',
      'teachers',
      'settings_pii',
      'metadata',
      'weighted_grades',
    ]) {
      if (Hive.isBoxOpen(name)) {
        try {
          await Hive.box(name).clear();
          await Hive.box(name).close();
        } catch (_) {}
      }
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Widget buildScreen({ExamDayStartMode? initialMode}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => StudentProvider()),
        ChangeNotifierProvider(create: (_) => AssessmentProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => ClassProvider()),
        ChangeNotifierProvider(create: (_) => TeacherProvider()),
        ChangeNotifierProvider(create: (_) => WeightedGradeProvider()),
      ],
      child: MaterialApp(home: ExamDayCreateScreen(initialMode: initialMode)),
    );
  }

  Future<void> scrollToText(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(
      find.text(text),
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 20,
    );
  }

  group('ExamDayCreateScreen', () {
    testWidgets('starts from the teacher grading job', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Grade papers'), findsOneWidget);
      expect(find.text('I have papers. I need grades.'), findsOneWidget);
      expect(find.text('Answer key'), findsOneWidget);
      expect(
        find.text('Choose how the correct answers will be created.'),
        findsOneWidget,
      );
      expect(find.text('Scan master answer sheet'), findsOneWidget);
      expect(find.text('Enter answer key manually'), findsOneWidget);
      await scrollToText(tester, 'Student list');
      expect(find.text('Student list'), findsOneWidget);
    });

    testWidgets('keeps student mode and answer-key mode separate', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Scan master answer sheet'), findsOneWidget);
      expect(find.text('Enter answer key manually'), findsOneWidget);
      await scrollToText(tester, 'Grade without student list');
      expect(find.text('Grade without student list'), findsOneWidget);
      await scrollToText(tester, 'Grade with class list');
      expect(find.text('Grade with class list'), findsOneWidget);
    });

    testWidgets('supports custom question count', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await scrollToText(tester, 'Custom');
      final customField = find.widgetWithText(TextField, 'Custom');
      expect(customField, findsOneWidget);

      await tester.enterText(customField, '37');
      await tester.pumpAndSettle();

      expect(find.text('37'), findsOneWidget);
    });

    testWidgets('initial no-roster mode still allows master scan choice', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildScreen(initialMode: ExamDayStartMode.noRoster),
      );
      await tester.pumpAndSettle();

      await scrollToText(tester, 'Grade without student list');
      expect(find.text('Grade without student list'), findsOneWidget);
      await scrollToText(tester, 'Answer key');
      expect(find.text('Scan master answer sheet'), findsOneWidget);
      expect(find.text('Continue to master scan'), findsOneWidget);
    });

    testWidgets('initial manual-key mode changes the primary action', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildScreen(initialMode: ExamDayStartMode.manualKey),
      );
      await tester.pumpAndSettle();

      await scrollToText(tester, 'Enter answer key manually');
      expect(find.text('Enter answer key manually'), findsOneWidget);
      expect(find.text('Continue to answer key'), findsOneWidget);
    });
  });
}
