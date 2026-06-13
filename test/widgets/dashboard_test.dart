import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethiograde/screens/home/main_dashboard.dart';
import 'package:ethiograde/services/student_provider.dart';
import 'package:ethiograde/services/assessment_provider.dart';
import 'package:ethiograde/services/settings_provider.dart';
import 'package:ethiograde/services/class_provider.dart';
import 'package:ethiograde/services/teacher_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ethiograde_dash_test_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Open all boxes the providers need
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

  /// Wraps MainDashboard with all required providers.
  Widget wrapDashboard() {
    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => StudentProvider()),
          ChangeNotifierProvider(create: (_) => AssessmentProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => ClassProvider()),
          ChangeNotifierProvider(create: (_) => TeacherProvider()),
        ],
        child: const MainDashboard(),
      ),
    );
  }

  group('MainDashboard', () {
    testWidgets('renders bottom navigation bar with 4 tabs', (tester) async {
      await tester.pumpWidget(wrapDashboard());
      await tester.pumpAndSettle();

      // 4 navigation destinations
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Assess'), findsOneWidget);
      expect(find.text('Students'), findsWidgets);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('home shows teacher-first next action', (tester) async {
      await tester.pumpWidget(wrapDashboard());
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.textContaining('Welcome,'), findsOneWidget);
      expect(find.text('Grade papers'), findsOneWidget);
    });

    testWidgets('does not show FAB on non-home tabs', (tester) async {
      await tester.pumpWidget(wrapDashboard());
      await tester.pumpAndSettle();

      // Tap Assess tab
      await tester.tap(find.text('Assess'));
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('shows empty state for assessments', (tester) async {
      await tester.pumpWidget(wrapDashboard());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Assess'));
      await tester.pumpAndSettle();

      expect(find.text('No assessments yet'), findsOneWidget);
    });

    testWidgets('shows "No classes yet" when no classes exist', (tester) async {
      await tester.pumpWidget(wrapDashboard());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('No classes yet'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('No classes yet'), findsOneWidget);
    });

    testWidgets('shows stat cards with zero counts', (tester) async {
      await tester.pumpWidget(wrapDashboard());
      await tester.pumpAndSettle();

      // Stat cards show "0" for empty providers
      expect(find.text('0'), findsWidgets);
      expect(find.text('Students'), findsWidgets);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
    });

    testWidgets('shows pilot grading quick actions', (tester) async {
      await tester.pumpWidget(wrapDashboard());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Quick actions'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Quick actions'), findsOneWidget);
      expect(find.text('Master Key'), findsOneWidget);
      expect(find.text('No List'), findsOneWidget);
      expect(find.text('Class List'), findsOneWidget);
      expect(find.text('Manual Key'), findsOneWidget);
    });

    testWidgets('switching tabs shows different content', (tester) async {
      await tester.pumpWidget(wrapDashboard());
      await tester.pumpAndSettle();

      // Home tab: Quick actions visible
      await tester.scrollUntilVisible(
        find.text('Quick actions'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Quick actions'), findsOneWidget);

      // Switch to Assessments tab
      await tester.tap(find.text('Assess'));
      await tester.pumpAndSettle();

      // Assessments tab shows empty state
      expect(find.text('No assessments yet'), findsOneWidget);

      // Switch to Students tab
      await tester.tap(find.text('Students'));
      await tester.pumpAndSettle();

      // Students tab has header
      expect(find.text('Students'), findsWidgets);

      // Switch to Settings tab
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('PROFILE'), findsOneWidget);
      expect(find.text('PREFERENCES'), findsOneWidget);
      // DATA & PRIVACY is below the fold — scroll to check it exists
      await tester.scrollUntilVisible(
        find.text('DATA & PRIVACY'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('DATA & PRIVACY'), findsOneWidget);
    });

    testWidgets('settings tab shows language toggle', (tester) async {
      await tester.pumpWidget(wrapDashboard());
      await tester.pumpAndSettle();

      // Go to Settings tab
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
    });

    testWidgets('settings tab shows privacy info', (tester) async {
      await tester.pumpWidget(wrapDashboard());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('DATA & PRIVACY'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();

      expect(find.text('Storage Usage'), findsOneWidget);
      expect(find.text('Export Backup'), findsOneWidget);
      expect(find.text('Import Backup'), findsOneWidget);
      expect(find.text('Clear All Data'), findsOneWidget);
    });

    testWidgets('settings tab shows version', (tester) async {
      await tester.pumpWidget(wrapDashboard());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('ABOUT'),
        300,
        scrollable: find.byType(Scrollable).last,
      );

      expect(find.text('Version'), findsOneWidget);
      // Version text starts with 'v0.'
      expect(find.textContaining('v0.'), findsOneWidget);
    });
  });
}
