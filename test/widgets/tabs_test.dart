import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethiograde/screens/home/assessments_tab.dart';
import 'package:ethiograde/screens/home/students_tab.dart';
import 'package:ethiograde/screens/home/settings_tab.dart';
import 'package:ethiograde/services/student_provider.dart';
import 'package:ethiograde/services/assessment_provider.dart';
import 'package:ethiograde/services/settings_provider.dart';
import 'package:ethiograde/services/class_provider.dart';
import 'package:ethiograde/services/teacher_provider.dart';
import 'package:ethiograde/services/weighted_grade_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ethiograde_tabs_test_');
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
    await Hive.openBox('grading_drafts');
  });

  tearDown(() async {
    for (final name in [
      'students',
      'assessments',
      'classes',
      'teachers',
      'settings_pii',
      'metadata',
      'grading_drafts',
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

  Widget wrapTab(Widget child) {
    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => StudentProvider()),
          ChangeNotifierProvider(create: (_) => AssessmentProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => TeacherProvider()),
          ChangeNotifierProvider(create: (_) => ClassProvider()),
          ChangeNotifierProvider(create: (_) => WeightedGradeProvider()),
        ],
        child: Scaffold(body: child),
      ),
    );
  }

  // ─── AssessmentsTab ──────────────────────────────────────────────

  group('AssessmentsTab', () {
    testWidgets('renders without crash', (tester) async {
      await tester.pumpWidget(wrapTab(const AssessmentsTab()));
      await tester.pumpAndSettle();
      expect(find.byType(AssessmentsTab), findsOneWidget);
    });

    testWidgets('renders at compact width 320px without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(wrapTab(const AssessmentsTab()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(AssessmentsTab), findsOneWidget);
    });
  });

  // ─── StudentsTab ─────────────────────────────────────────────────

  group('StudentsTab', () {
    testWidgets('renders without crash', (tester) async {
      await tester.pumpWidget(wrapTab(const StudentsTab()));
      await tester.pumpAndSettle();
      expect(find.byType(StudentsTab), findsOneWidget);
    });

    testWidgets('shows search bar', (tester) async {
      await tester.pumpWidget(wrapTab(const StudentsTab()));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('renders at compact width 320px without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(wrapTab(const StudentsTab()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(StudentsTab), findsOneWidget);
    });
  });

  // ─── SettingsTab ─────────────────────────────────────────────────

  group('SettingsTab', () {
    testWidgets('renders without crash', (tester) async {
      await tester.pumpWidget(wrapTab(const SettingsTab()));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsTab), findsOneWidget);
    });

    testWidgets('renders at compact width 320px without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(wrapTab(const SettingsTab()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SettingsTab), findsOneWidget);
    });
  });
}
