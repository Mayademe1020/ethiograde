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
    testWidgets('renders Create Exam title and answer key section', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Create Exam'), findsOneWidget);
      expect(find.text('Answer key'), findsOneWidget);
      expect(find.text('Scan Answer Sheet'), findsOneWidget);
      expect(find.text('Type Answers'), findsOneWidget);
    });

    testWidgets('shows questions count field', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Questions'), findsOneWidget);
      expect(find.widgetWithText(TextField, '20'), findsOneWidget);
    });

    testWidgets('supports custom question count', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      final countField = find.widgetWithText(TextField, '20');
      await tester.enterText(countField, '37');
      await tester.pumpAndSettle();

      expect(find.text('37'), findsOneWidget);
    });

    testWidgets('shows Quick Grading option', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await scrollToText(tester, 'Quick Grading');
      expect(find.text('Quick Grading'), findsOneWidget);
    });

    testWidgets('shows continue button for scan mode', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Continue to Scan'), findsOneWidget);
    });

    testWidgets('initial manual-key mode changes the primary action', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildScreen(initialMode: ExamDayStartMode.manualKey),
      );
      await tester.pumpAndSettle();

      expect(find.text('Type Answers'), findsOneWidget);
      expect(find.text('Continue to Answer Key'), findsOneWidget);
    });
  });
}
