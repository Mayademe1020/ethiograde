import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethiograde/screens/review/review_screen.dart';
import 'package:ethiograde/services/student_provider.dart';
import 'package:ethiograde/services/assessment_provider.dart';
import 'package:ethiograde/models/scan_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ethiograde_review_test_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Hive.openBox('students');
    await Hive.openBox('assessments');
    await Hive.openBox('settings_pii');
  });

  tearDown(() async {
    for (final name in ['students', 'assessments', 'settings_pii']) {
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

  ScanResult makeResult({
    String studentName = 'Abebe Kebede',
    double totalScore = 7,
    double maxScore = 10,
    double percentage = 70,
    double confidence = 0.9,
    String grade = 'B',
  }) => ScanResult(
    assessmentId: 'a1',
    studentId: 's1',
    studentName: studentName,
    imagePath: '/fake/path.png',
    totalScore: totalScore,
    maxScore: maxScore,
    percentage: percentage,
    grade: grade,
    confidence: confidence,
    status: ScanStatus.graded,
  );

  Widget wrapReview(List<ScanResult> results) {
    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => StudentProvider()),
          ChangeNotifierProvider(create: (_) => AssessmentProvider()),
        ],
        child: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () =>
                  Navigator.pushNamed(context, '/review', arguments: results),
              child: const Text('Go'),
            ),
          ),
        ),
      ),
      routes: {
        '/review': (_) => MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => StudentProvider()),
            ChangeNotifierProvider(create: (_) => AssessmentProvider()),
          ],
          child: const ReviewScreen(),
        ),
      },
    );
  }

  group('ReviewScreen', () {
    testWidgets('shows empty state when no results', (tester) async {
      await tester.pumpWidget(wrapReview([]));
      await tester.pumpAndSettle();

      // Navigate to review screen
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.text('No results to review'), findsOneWidget);
      expect(find.byIcon(Icons.inbox), findsOneWidget);
    });

    testWidgets('shows sort button in app bar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => StudentProvider()),
              ChangeNotifierProvider(create: (_) => AssessmentProvider()),
            ],
            child: const ReviewScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.sort), findsOneWidget);
    });

    testWidgets('app bar shows Review Results title', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => StudentProvider()),
              ChangeNotifierProvider(create: (_) => AssessmentProvider()),
            ],
            child: const ReviewScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Review Results'), findsOneWidget);
    });

    testWidgets('renders result cards for each result', (tester) async {
      final results = [
        makeResult(studentName: 'Abebe Kebede', percentage: 80),
        makeResult(studentName: 'Tigist Haile', percentage: 45),
      ];

      await tester.pumpWidget(wrapReview(results));
      await tester.pumpAndSettle();

      // Navigate to review
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      // Both student names should appear
      await tester.scrollUntilVisible(
        find.text('Abebe Kebede'),
        120,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Abebe Kebede'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Tigist Haile'),
        120,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Tigist Haile'), findsOneWidget);
    });

    testWidgets('shows teacher-first review queue actions', (tester) async {
      final results = [
        makeResult(studentName: 'Paper 1', confidence: 0.5, percentage: 45),
        makeResult(studentName: 'Tigist Haile', percentage: 80),
      ];

      await tester.pumpWidget(wrapReview(results));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.text('Review queue'), findsOneWidget);
      expect(find.text('Check unclear answers'), findsWidgets);
      expect(find.text('Match paper names'), findsOneWidget);
      expect(find.text('Final save'), findsOneWidget);
      expect(find.text('Save draft'), findsOneWidget);
    });

    testWidgets('shows sort options when sort button tapped', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => StudentProvider()),
              ChangeNotifierProvider(create: (_) => AssessmentProvider()),
            ],
            child: const ReviewScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();

      // Sort options should be visible
      expect(find.text('Lowest to Highest'), findsOneWidget);
      expect(find.text('Highest to Lowest'), findsOneWidget);
      expect(find.text('Needs Review First'), findsOneWidget);
      expect(find.text('Missing Students First'), findsOneWidget);
      expect(find.text('Answer Key Changes First'), findsOneWidget);
    });
  });
}
