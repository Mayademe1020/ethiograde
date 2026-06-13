import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethiograde/screens/quick_enter/quick_enter_screen.dart';
import 'package:ethiograde/services/assessment_provider.dart';
import 'package:ethiograde/services/student_provider.dart';
import 'package:ethiograde/services/class_provider.dart';
import 'package:ethiograde/services/settings_provider.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/student.dart';
import 'package:ethiograde/models/class_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ethiograde_qe_test_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Hive.openBox('students');
    await Hive.openBox('assessments');
    await Hive.openBox('settings_pii');
    await Hive.openBox('metadata');
  });

  tearDown(() async {
    for (final name in ['students', 'assessments', 'settings_pii', 'metadata']) {
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

  /// Screen with no assessment argument — shows picker.
  Widget buildPicker() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AssessmentProvider()),
        ChangeNotifierProvider(create: (_) => StudentProvider()),
        ChangeNotifierProvider(create: (_) => ClassProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(
        home: const QuickEnterScreen()),
    );
  }

  /// Screen with assessment argument — shows score table.
  Widget buildWithAssessment(Assessment assessment) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AssessmentProvider()),
        ChangeNotifierProvider(create: (_) => StudentProvider()),
        ChangeNotifierProvider(create: (_) => ClassProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  settings: RouteSettings(arguments: assessment),
                  builder: (_) => const QuickEnterScreen())),
              child: const Text('GO'))))));
  }

  Assessment _makeAssessment({String className = ''}) {
    return Assessment(
      id: 'a1',
      title: 'Math Midterm',
      subject: 'Math',
      className: className,
      questions: [
        Question(number: 1, text: 'Q1', type: QuestionType.mcq, points: 10, correctAnswer: 'A'),
        Question(number: 2, text: 'Q2', type: QuestionType.mcq, points: 10, correctAnswer: 'B'),
        Question(number: 3, text: 'Q3', type: QuestionType.mcq, points: 10, correctAnswer: 'C'),
      ],
      status: AssessmentStatus.draft,
    );
  }

  group('QuickEnterScreen — Assessment Picker', () {
    testWidgets('shows empty state when no assessments', (tester) async {
      await tester.pumpWidget(buildPicker());
      await tester.pumpAndSettle();

      expect(find.text('Select Assessment'), findsOneWidget);
      expect(find.text('No assessments yet'), findsOneWidget);
      expect(find.byIcon(Icons.assignment_outlined), findsOneWidget);
    });
  });

  group('QuickEnterScreen — Score Table', () {
    testWidgets('renders title and assessment info', (tester) async {
      final assessment = _makeAssessment();
      await tester.pumpWidget(buildWithAssessment(assessment));
      await tester.pump();
      await tester.pump();

      // Tap GO to navigate to QuickEnterScreen
      await tester.tap(find.text('GO'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // The screen should show Quick Enter and "No students found" (empty roster)
      expect(find.text('Quick Enter'), findsOneWidget);
    });

    testWidgets('shows no students message when roster empty', (tester) async {
      final assessment = _makeAssessment();
      await tester.pumpWidget(buildWithAssessment(assessment));
      await tester.pumpAndSettle();

      await tester.tap(find.text('GO'));
      await tester.pumpAndSettle();

      expect(find.text('No students found'), findsOneWidget);
      expect(find.text('Add students or link a class first'), findsOneWidget);
      expect(find.byIcon(Icons.people_outline), findsOneWidget);
    });

    testWidgets('renders score table headers with questions', (tester) async {
      final assessment = _makeAssessment();
      final studentProv = StudentProvider();
      final student = Student(
        id: 's1', firstName: 'Abebe', lastName: 'Kebede',
        className: '', section: '', studentId: '001', gender: 'M');
      await tester.runAsync(() => studentProv.addStudent(student));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<StudentProvider>.value(value: studentProv),
            ChangeNotifierProvider(create: (_) => AssessmentProvider()),
            ChangeNotifierProvider(create: (_) => ClassProvider()),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      settings: RouteSettings(arguments: assessment),
                      builder: (_) => const QuickEnterScreen())),
                  child: const Text('GO')))))));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('GO'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Student'), findsOneWidget);
      expect(find.text('Q1'), findsOneWidget);
      expect(find.text('Q2'), findsOneWidget);
      expect(find.text('Q3'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('Abebe Kebede'), findsOneWidget);
    });

    testWidgets('save all button exists and is enabled', (tester) async {
      final assessment = _makeAssessment();
      final studentProv = StudentProvider();
      await tester.runAsync(() => studentProv.addStudent(Student(
        id: 's1', firstName: 'Abebe', lastName: 'Kebede',
        className: '', section: '', studentId: '001', gender: 'M')));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<StudentProvider>.value(value: studentProv),
            ChangeNotifierProvider(create: (_) => AssessmentProvider()),
            ChangeNotifierProvider(create: (_) => ClassProvider()),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      settings: RouteSettings(arguments: assessment),
                      builder: (_) => const QuickEnterScreen())),
                  child: const Text('GO')))))));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('GO'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Save All'), findsOneWidget);
      expect(find.byIcon(Icons.save), findsOneWidget);
    });

    testWidgets('score cells show dash when no score entered', (tester) async {
      final assessment = _makeAssessment();
      final studentProv = StudentProvider();
      await tester.runAsync(() => studentProv.addStudent(Student(
        id: 's1', firstName: 'Abebe', lastName: 'Kebede',
        className: '', section: '', studentId: '001', gender: 'M')));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<StudentProvider>.value(value: studentProv),
            ChangeNotifierProvider(create: (_) => AssessmentProvider()),
            ChangeNotifierProvider(create: (_) => ClassProvider()),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      settings: RouteSettings(arguments: assessment),
                      builder: (_) => const QuickEnterScreen())),
                  child: const Text('GO')))))));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('GO'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('—'), findsNWidgets(3));
    });

    testWidgets('tapping score cell opens bottom sheet', (tester) async {
      final assessment = _makeAssessment();
      final studentProv = StudentProvider();
      await tester.runAsync(() => studentProv.addStudent(Student(
        id: 's1', firstName: 'Abebe', lastName: 'Kebede',
        className: '', section: '', studentId: '001', gender: 'M')));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<StudentProvider>.value(value: studentProv),
            ChangeNotifierProvider(create: (_) => AssessmentProvider()),
            ChangeNotifierProvider(create: (_) => ClassProvider()),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      settings: RouteSettings(arguments: assessment),
                      builder: (_) => const QuickEnterScreen())),
                  child: const Text('GO')))))));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('GO'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('—').first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Question 1'), findsOneWidget);
      expect(find.text('of 10 points'), findsOneWidget);
    });
  });
}
