import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethiograde/screens/settings/grading_scale_editor_screen.dart';
import 'package:ethiograde/services/settings_provider.dart';
import 'package:ethiograde/services/teacher_provider.dart';
import 'package:ethiograde/models/grading_scale.dart';
import 'package:ethiograde/models/teacher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ethiograde_scale_test_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Hive.openBox('settings_pii');
    await Hive.openBox('teachers');
    await Hive.openBox('audit_trail');
  });

  tearDown(() async {
    for (final name in ['settings_pii', 'teachers', 'audit_trail']) {
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

  Widget wrapEditor({GradingScale? existingScale}) {
    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => TeacherProvider()),
        ],
        child: GradingScaleEditorScreen(existingScale: existingScale),
      ),
    );
  }

  group('GradingScaleEditorScreen', () {
    testWidgets('renders with default template ranges', (tester) async {
      await tester.pumpWidget(wrapEditor());
      await tester.pump();

      expect(find.text('A+'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(find.text('D'), findsOneWidget);
      expect(find.text('F'), findsOneWidget);
      expect(find.text('Create Scale'), findsOneWidget);
    });

    testWidgets('renders edit mode with existing scale', (tester) async {
      final scale = GradingScale(
        name: 'Test Scale',
        ranges: [
          const GradeRange(grade: 'Pass', minScore: 50, maxScore: 100),
          const GradeRange(grade: 'Fail', minScore: 0, maxScore: 49),
        ],
      );

      await tester.pumpWidget(wrapEditor(existingScale: scale));
      await tester.pump();

      expect(find.text('Edit Grading Scale'), findsOneWidget);
      expect(find.text('Update Scale'), findsOneWidget);
      expect(find.text('Pass'), findsOneWidget);
      expect(find.text('Fail'), findsOneWidget);
    });

    testWidgets('shows confirmation dialog on save tap', (tester) async {
      await tester.pumpWidget(wrapEditor());
      await tester.pump();

      await tester.tap(find.text('Create Scale'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('future grading sessions'), findsOneWidget);
    });

    testWidgets('confirmation dialog shows impact warning', (tester) async {
      await tester.pumpWidget(wrapEditor());
      await tester.pump();

      await tester.tap(find.text('Create Scale'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('future grading sessions'), findsOneWidget);
      expect(find.textContaining('Existing saved records'), findsOneWidget);
    });

    testWidgets('cancel in confirmation dialog does not save', (tester) async {
      await tester.pumpWidget(wrapEditor());
      await tester.pump();

      await tester.tap(find.text('Create Scale'));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Grade Bands'), findsOneWidget);
    });

    testWidgets('edit mode dialog shows new grade bands', (tester) async {
      final scale = GradingScale(
        name: 'School Scale',
        ranges: [
          const GradeRange(grade: 'A', minScore: 80, maxScore: 100),
          const GradeRange(grade: 'F', minScore: 0, maxScore: 79),
        ],
      );

      await tester.pumpWidget(wrapEditor(existingScale: scale));
      await tester.pump();

      await tester.tap(find.text('Update Scale'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Update Grading Scale?'), findsOneWidget);
      expect(find.textContaining('School Scale'), findsAtLeastNWidgets(1));
      expect(find.textContaining('A: 80–100%'), findsOneWidget);
      expect(find.textContaining('F: 0–79%'), findsOneWidget);
    });

    testWidgets('add range button adds a new entry', (tester) async {
      await tester.pumpWidget(wrapEditor());
      await tester.pump();

      final initialCount = find.byType(Card).evaluate().length;

      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(Card).evaluate().length, initialCount + 1);
    });

    testWidgets('remove range deletes an entry', (tester) async {
      await tester.pumpWidget(wrapEditor());
      await tester.pump();

      final initialCount = find.byType(Card).evaluate().length;

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();
      await tester.pump();

      expect(find.byType(Card).evaluate().length, initialCount - 1);
    });
  });
}
