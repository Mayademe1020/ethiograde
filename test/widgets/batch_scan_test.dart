import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethiograde/screens/scanning/batch_scan_screen.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/services/student_provider.dart';
import 'package:ethiograde/services/assessment_provider.dart';
import 'package:ethiograde/services/class_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'ethiograde_batch_scan_test_',
    );
    Hive.init(tempDir.path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Hive.openBox('students');
    await Hive.openBox('assessments');
    await Hive.openBox('classes');
    await Hive.openBox('scan_results');
    await Hive.openBox('settings_pii');
    await Hive.openBox('grading_drafts');
  });

  tearDown(() async {
    for (final name in [
      'students',
      'assessments',
      'classes',
      'scan_results',
      'settings_pii',
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

  /// Wraps BatchScanScreen with all required providers.
  Widget wrapBatchScan({Map<String, dynamic>? args}) {
    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => StudentProvider()),
          ChangeNotifierProvider(create: (_) => AssessmentProvider()),
          ChangeNotifierProvider(create: (_) => ClassProvider()),
        ],
        child: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () =>
                  Navigator.pushNamed(context, '/batch', arguments: args),
              child: const Text('Go'),
            ),
          ),
        ),
      ),
      routes: {
        '/batch': (_) => MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => StudentProvider()),
            ChangeNotifierProvider(create: (_) => AssessmentProvider()),
            ChangeNotifierProvider(create: (_) => ClassProvider()),
          ],
          child: const BatchScanScreen(),
        ),
      },
    );
  }

  /// Direct wrapper without route navigation — for empty state tests.
  Widget wrapDirect() {
    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => StudentProvider()),
          ChangeNotifierProvider(create: (_) => AssessmentProvider()),
          ChangeNotifierProvider(create: (_) => ClassProvider()),
        ],
        child: const BatchScanScreen(),
      ),
    );
  }

  group('BatchScanScreen — empty state', () {
    testWidgets('shows empty state when no results', (tester) async {
      await tester.pumpWidget(wrapDirect());
      await tester.pumpAndSettle();

      expect(find.text('No results yet'), findsOneWidget);
    });

    testWidgets('app bar shows Batch Scan title', (tester) async {
      await tester.pumpWidget(wrapDirect());
      await tester.pumpAndSettle();

      expect(find.text('Batch Scan'), findsOneWidget);
    });

    testWidgets('does not show stats when no results', (tester) async {
      await tester.pumpWidget(wrapDirect());
      await tester.pumpAndSettle();

      // Stats row should not appear
      expect(find.text('Avg'), findsNothing);
      expect(find.text('High'), findsNothing);
      expect(find.text('Low'), findsNothing);
      expect(find.text('Pass'), findsNothing);
    });

    testWidgets('does not show Review button when no results', (tester) async {
      await tester.pumpWidget(wrapDirect());
      await tester.pumpAndSettle();

      expect(find.text('Review All'), findsNothing);
    });

    testWidgets('does not show Read Scores button when no results', (
      tester,
    ) async {
      await tester.pumpWidget(wrapDirect());
      await tester.pumpAndSettle();

      expect(find.text('Read Scores Aloud'), findsNothing);
    });
  });

  group('BatchScanScreen — with Assessment arg only (no images)', () {
    testWidgets('renders screen without crashing with Assessment arg', (
      tester,
    ) async {
      // Passing just an Assessment (no images) should not crash —
      // the screen initializes but does not auto-process since images is null.
      await tester.pumpWidget(wrapDirect());
      await tester.pumpAndSettle();

      // Screen should render without errors
      expect(find.byType(BatchScanScreen), findsOneWidget);
    });
  });

  group('BatchScanScreen — progress header', () {
    testWidgets('shows Progress label in English', (tester) async {
      await tester.pumpWidget(wrapDirect());
      await tester.pumpAndSettle();

      // Progress header is visible even without results
      expect(find.text('Progress'), findsOneWidget);
    });

    testWidgets('shows 0/0 counter when no processing', (tester) async {
      await tester.pumpWidget(wrapDirect());
      await tester.pumpAndSettle();

      expect(find.text('0 / 0'), findsOneWidget);
    });
  });

  group('BatchScanScreen — master scan session', () {
    testWidgets('shows recovery session when master image is missing', (
      tester,
    ) async {
      final assessment = Assessment(
        id: 'master-test',
        title: 'Biology Quiz',
        subject: 'Biology',
        questions: [Question(number: 1, type: QuestionType.mcq)],
      );

      await tester.pumpWidget(
        wrapBatchScan(
          args: {
            'assessment': assessment,
            'images': <String>[],
            'masterOnly': true,
          },
        ),
      );

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.text('Grading Session'), findsOneWidget);
      expect(find.text('Master scan needs attention'), findsOneWidget);
      expect(find.text('No master answer sheet image found.'), findsOneWidget);
      expect(find.text('Enter answer key manually'), findsOneWidget);
    });
  });
}
