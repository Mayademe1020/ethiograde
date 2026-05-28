import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethiograde/screens/assessment/answer_key_screen.dart';
import 'package:ethiograde/services/assessment_provider.dart';
import 'package:ethiograde/services/student_provider.dart';
import 'package:ethiograde/services/class_provider.dart';
import 'package:ethiograde/models/assessment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('ethiograde_answerkey_test_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Hive.openBox('assessments');
    await Hive.openBox('students');
    await Hive.openBox('classes');
    await Hive.openBox('settings_pii');
  });

  tearDown(() async {
    for (final name in ['assessments', 'students', 'classes', 'settings_pii']) {
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
    String title = 'Math Midterm',
    String subject = 'Mathematics',
    List<Question> questions = const [],
  }) =>
      Assessment(
        title: title,
        subject: subject,
        questions: questions);

  Widget wrapAnswerKey({Assessment? assessment}) {
    final assessmentProv = AssessmentProvider();

    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<AssessmentProvider>.value(
              value: assessmentProv),
          ChangeNotifierProvider(create: (_) => StudentProvider()),
          ChangeNotifierProvider(create: (_) => ClassProvider()),
        ],
        child: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.pushNamed(
                context,
                '/answer-key',
                arguments: assessment),
              child: const Text('Go'))))),
      routes: {
        '/answer-key': (_) => MultiProvider(
              providers: [
                ChangeNotifierProvider<AssessmentProvider>.value(
                    value: assessmentProv),
                ChangeNotifierProvider(create: (_) => StudentProvider()),
                ChangeNotifierProvider(create: (_) => ClassProvider()),
              ],
              child: const AnswerKeyScreen()),
      });
  }

  group('AnswerKeyScreen', () {
    testWidgets('shows no assessment message when null', (tester) async {
      await tester.pumpWidget(wrapAnswerKey(assessment: null));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.text('No assessment selected'), findsOneWidget);
    });

    testWidgets('shows assessment title', (tester) async {
      final assessment = makeAssessment(
        title: 'Science Quiz',
        subject: 'Science');
      await tester.pumpWidget(wrapAnswerKey(assessment: assessment));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.text('Science Quiz'), findsOneWidget);
    });

    testWidgets('shows subject and question count', (tester) async {
      final assessment = makeAssessment(
        subject: 'English',
        questions: [
          Question(number: 1, type: QuestionType.mcq, points: 2),
          Question(number: 2, type: QuestionType.trueFalse, points: 1),
        ]);
      await tester.pumpWidget(wrapAnswerKey(assessment: assessment));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.textContaining('English'), findsOneWidget);
      expect(find.textContaining('2'), findsWidgets); // question count
    });

    testWidgets('shows Done button', (tester) async {
      final assessment = makeAssessment();
      await tester.pumpWidget(wrapAnswerKey(assessment: assessment));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('shows Answer Key section title', (tester) async {
      final assessment = makeAssessment();
      await tester.pumpWidget(wrapAnswerKey(assessment: assessment));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.text('Answer Key'), findsOneWidget);
    });

    testWidgets('shows English-only fallback when no assessment selected',
        (tester) async {
      final assessmentProv = AssessmentProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<AssessmentProvider>.value(
                  value: assessmentProv),
              ChangeNotifierProvider(create: (_) => StudentProvider()),
              ChangeNotifierProvider(create: (_) => ClassProvider()),
            ],
            child: AnswerKeyScreen())));
      await tester.pumpAndSettle();

      expect(find.text('No assessment selected'), findsOneWidget);
    });
  });
}
