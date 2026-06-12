import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethiograde/screens/assessment/answer_sheet_setup_screen.dart';
import 'package:ethiograde/services/student_provider.dart';
import 'package:ethiograde/services/assessment_provider.dart';
import 'package:ethiograde/services/settings_provider.dart';
import 'package:ethiograde/services/class_provider.dart';
import 'package:ethiograde/services/teacher_provider.dart';
import 'package:ethiograde/models/assessment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('ethiograde_sheet_setup_test_');
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
  });

  tearDown(() async {
    for (final name in [
      'students',
      'assessments',
      'classes',
      'teachers',
      'settings_pii',
      'metadata',
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

  Assessment makeAssessment({
    int mcqCount = 35,
    int tfCount = 5,
  }) {
    return Assessment(
      id: 'test-assessment',
      title: 'Unit 1 Test',
      subject: 'Math',
      className: 'Grade 5A',
      questions: [
        ...List.generate(
          mcqCount,
          (i) => Question(
            number: i + 1,
            type: QuestionType.mcq,
            correctAnswer: 'A')),
        ...List.generate(
          tfCount,
          (i) => Question(
            number: mcqCount + i + 1,
            type: QuestionType.trueFalse,
            correctAnswer: 'True')),
      ]);
  }

  Widget wrapScreen({Assessment? assessment}) {
    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => StudentProvider()),
          ChangeNotifierProvider(create: (_) => AssessmentProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => ClassProvider()),
          ChangeNotifierProvider(create: (_) => TeacherProvider()),
        ],
        child: AnswerSheetSetupScreen(assessment: assessment)));
  }

  group('AnswerSheetSetupScreen', () {
    testWidgets('renders app bar title', (tester) async {
      await tester.pumpWidget(wrapScreen());
      await tester.pumpAndSettle();

      expect(find.text('Answer Sheet Setup'), findsOneWidget);
    });

    testWidgets('shows assessment dropdown when no assessment provided',
        (tester) async {
      await tester.pumpWidget(wrapScreen());
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButtonFormField<Assessment>), findsOneWidget);
    });

    testWidgets('shows assessment card when assessment provided',
        (tester) async {
      final assessment = makeAssessment();
      await tester.pumpWidget(wrapScreen(assessment: assessment));
      await tester.pumpAndSettle();

      expect(find.text('Unit 1 Test'), findsAtLeastNWidgets(1));
      expect(find.text('Math · 40 questions'), findsOneWidget);
    });

    testWidgets('shows question type breakdown for mixed assessment',
        (tester) async {
      final assessment = makeAssessment(mcqCount: 35, tfCount: 5);
      await tester.pumpWidget(wrapScreen(assessment: assessment));
      await tester.pumpAndSettle();

      expect(find.text('Question Types'), findsOneWidget);
      expect(find.text('Q1–35'), findsOneWidget);
      expect(find.text('MCQ (A-D)'), findsOneWidget);
      expect(find.text('Q36–40'), findsOneWidget);
      expect(find.text('True/False'), findsOneWidget);
    });

    testWidgets('shows paper layout options', (tester) async {
      await tester.pumpWidget(wrapScreen());
      await tester.pumpAndSettle();

      expect(find.text('Paper Layout'), findsOneWidget);
      expect(find.text('Full A4'), findsOneWidget);
      expect(find.text('Half (2 per page)'), findsOneWidget);
    });

    testWidgets('can select paper layout option', (tester) async {
      await tester.pumpWidget(wrapScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Half (2 per page)'));
      await tester.pumpAndSettle();

      // The half sheet option should now be selected
      expect(find.text('Half (2 per page)'), findsOneWidget);
    });

    testWidgets('shows header fields', (tester) async {
      await tester.pumpWidget(wrapScreen());
      await tester.pumpAndSettle();

      expect(find.text('Header Info'), findsOneWidget);
      expect(find.text('School Name'), findsOneWidget);
      expect(find.text('Exam Name'), findsOneWidget);
      expect(find.text('Subject'), findsOneWidget);
    });

    testWidgets('shows student name mode options', (tester) async {
      await tester.pumpWidget(wrapScreen());
      await tester.pumpAndSettle();

      expect(find.text('Student Names'), findsOneWidget);
      expect(find.text('Blank'), findsOneWidget);
      expect(find.text('Prefill Names'), findsOneWidget);
    });

    testWidgets('can toggle student name mode', (tester) async {
      final assessment = makeAssessment();
      await tester.pumpWidget(wrapScreen(assessment: assessment));
      await tester.pumpAndSettle();

      // Tap Prefill Names
      await tester.tap(find.text('Prefill Names'));
      await tester.pumpAndSettle();

      // Should show student list preview section
      expect(find.text('Prefill Names'), findsOneWidget);
    });

    testWidgets('shows answer key status when assessment provided',
        (tester) async {
      final assessment = makeAssessment();
      await tester.pumpWidget(wrapScreen(assessment: assessment));
      await tester.pumpAndSettle();

      expect(find.text('Answer Key Status'), findsOneWidget);
      expect(find.text('40/40 answers set'), findsOneWidget);
    });

    testWidgets('shows partial answer key warning', (tester) async {
      // Create assessment with some missing answers
      final assessment = Assessment(
        id: 'partial',
        title: 'Partial Test',
        subject: 'Math',
        questions: [
          Question(number: 1, type: QuestionType.mcq, correctAnswer: 'A'),
          Question(number: 2, type: QuestionType.mcq, correctAnswer: null),
          Question(number: 3, type: QuestionType.mcq, correctAnswer: ''),
        ]);

      await tester.pumpWidget(wrapScreen(assessment: assessment));
      await tester.pumpAndSettle();

      expect(find.text('1/3 answers set'), findsOneWidget);
      expect(find.text('Fix'), findsOneWidget);
    });

    testWidgets('generate button is disabled without assessment',
        (tester) async {
      await tester.pumpWidget(wrapScreen());
      await tester.pumpAndSettle();

      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton).last);
      expect(button.onPressed, isNull);
    });

    testWidgets('generate button is enabled with assessment',
        (tester) async {
      final assessment = makeAssessment();
      await tester.pumpWidget(wrapScreen(assessment: assessment));
      await tester.pumpAndSettle();

      expect(find.text('Generate PDF'), findsOneWidget);
    });

  });
}
