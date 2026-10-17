import 'dart:io';

import 'package:ethiograde/models/class_info.dart';
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
      expect(find.text('Type Answers'), findsOneWidget);
      expect(find.text('Continue to Answer Key'), findsOneWidget);

      await scrollToText(tester, 'Scan Answer Sheet');
      expect(find.text('Scan Answer Sheet'), findsOneWidget);
    });

    testWidgets('shows questions count field', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await scrollToText(tester, 'Questions');
      expect(find.text('Questions'), findsOneWidget);
      expect(find.widgetWithText(TextField, '20'), findsOneWidget);
    });

    testWidgets('supports custom question count', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await scrollToText(tester, 'Questions');
      final countField = find.widgetWithText(TextField, '20');
      await tester.enterText(countField, '37');
      await tester.pumpAndSettle();

      expect(find.text('37'), findsOneWidget);
    });

    testWidgets('shows Type Answers option', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await scrollToText(tester, 'Type Answers');
      expect(find.text('Type Answers'), findsOneWidget);
      expect(find.text('Quick Grading'), findsNothing);
    });

    testWidgets('selecting Type Answers changes the primary action', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await scrollToText(tester, 'Type Answers');
      await tester.tap(find.text('Type Answers'));
      await tester.pumpAndSettle();

      expect(find.text('Continue to Answer Key'), findsOneWidget);
      expect(find.text('Continue to Scan'), findsNothing);
    });

    testWidgets('shows continue button for scan mode', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await scrollToText(tester, 'Scan Answer Sheet');
      await tester.tap(find.text('Scan Answer Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Continue to Scan'), findsOneWidget);
    });

    testWidgets('requires a class before continuing', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'e.g. Grade 8 Biology midterm'),
        'Biology Midterm',
      );
      await tester.pumpAndSettle();

      // No class selected yet — the CTA shows a hint and prompts on tap.
      expect(find.text('Select a class first'), findsOneWidget);
      await tester.tap(find.text('Continue to Answer Key'));
      await tester.pumpAndSettle();

      // The prompt asks for a title/class rather than proceeding.
      expect(find.text('Exam title required'), findsOneWidget);
      expect(find.text('Continue to Answer Key'), findsOneWidget);
    });

    testWidgets('initial manual-key mode changes the primary action', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildScreen(initialMode: ExamDayStartMode.manualKey),
      );
      await tester.pumpAndSettle();

      expect(find.text('Continue to Answer Key'), findsOneWidget);
      expect(find.text('Continue to Scan'), findsNothing);
    });

    testWidgets('shows summary line with question count and no class', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('20 Qs · No class selected'), findsOneWidget);
    });

    testWidgets('selecting a class shows its subject and updates summary', (
      tester,
    ) async {
      final classProvider = ClassProvider();
      await tester.runAsync(() async {
        await classProvider.addClass(
          ClassInfo(
            id: 'c1',
            name: 'Grade 5A',
            school: 'Test School',
            grade: 5,
            section: 'A',
            subject: 'Math',
            studentIds: const ['s1', 's2'],
            ownerId: 't1',
            createdAt: DateTime(2026, 1, 1),
          ),
        );
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => StudentProvider()),
            ChangeNotifierProvider(create: (_) => AssessmentProvider()),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(create: (_) => classProvider),
            ChangeNotifierProvider(create: (_) => TeacherProvider()),
            ChangeNotifierProvider(create: (_) => WeightedGradeProvider()),
          ],
          child: const MaterialApp(
            home: ExamDayCreateScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 50));

      // No class selected yet.
      expect(find.text('20 Qs · No class selected'), findsOneWidget);

      // Select the class — summary updates and subject defaults to the class.
      await scrollToText(tester, 'Grade 5 A Math');
      await tester.tap(find.text('Grade 5 A Math'));
      await tester.pumpAndSettle();

      expect(find.text('20 Qs · Grade 5 A Math'), findsOneWidget);
      expect(find.text('Math'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Grade 5 A Math — Midterm'),
        findsNothing,
      );
      expect(
        find.widgetWithText(TextField, 'Exam title *'),
        findsOneWidget,
      );
    });
  });
}
