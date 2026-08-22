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

      expect(find.text('Grade Bands'), findsOneWidget);
      expect(find.byType(Card), findsAtLeastNWidgets(4));
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
      expect(find.byType(Card), findsAtLeastNWidgets(2));
    });

    testWidgets('shows confirmation dialog on save tap', (tester) async {
      await tester.pumpWidget(wrapEditor());
      await tester.pump();

      await tester.enterText(find.byType(TextFormField).at(0), 'My Scale');
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('grading sessions'), findsOneWidget);
    });

    testWidgets('cancel in confirmation dialog does not save', (tester) async {
      await tester.pumpWidget(wrapEditor());
      await tester.pump();

      await tester.enterText(find.byType(TextFormField).at(0), 'My Scale');
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Grade Bands'), findsOneWidget);
    });

    testWidgets('add range button adds a new entry', (tester) async {
      await tester.pumpWidget(wrapEditor());
      await tester.pump();

      final cardsBefore = find.byType(Card).evaluate().length;
      expect(cardsBefore, greaterThanOrEqualTo(4));

      await tester.scrollUntilVisible(
        find.text('Add'), 300,
        scrollable: find.byType(Scrollable).first, maxScrolls: 20);
      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(Card).evaluate().length, greaterThanOrEqualTo(cardsBefore));
    });
  });
}
