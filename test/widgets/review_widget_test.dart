import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ethiograde/screens/review/review_screen.dart';
import 'package:ethiograde/services/locale_provider.dart';
import 'package:ethiograde/services/assessment_provider.dart';
import 'package:ethiograde/services/settings_provider.dart';
import 'package:ethiograde/config/theme.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/models/assessment.dart';

void main() {
  late LocaleProvider localeProvider;
  late SettingsProvider settingsProvider;
  late AssessmentProvider assessmentProvider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    localeProvider = LocaleProvider();
    settingsProvider = SettingsProvider();
    assessmentProvider = AssessmentProvider();
  });

  /// Helper test data
  List<ScanResult> makeResults() => [
    ScanResult(
      id: 'r1',
      assessmentId: 'a1',
      studentId: 's1',
      studentName: 'Abebe Kebede',
      imagePath: '/tmp/a.jpg',
      totalScore: 4,
      maxScore: 5,
      percentage: 80.0,
      grade: 'A',
      confidence: 0.92,
      answers: [
        AnswerMatch(
          questionNumber: 1,
          detectedAnswer: 'A',
          correctAnswer: 'A',
          isCorrect: true,
          score: 1,
          maxScore: 1,
          confidence: 0.95,
        ),
        AnswerMatch(
          questionNumber: 2,
          detectedAnswer: 'B',
          correctAnswer: 'B',
          isCorrect: true,
          score: 1,
          maxScore: 1,
          confidence: 0.90,
        ),
        AnswerMatch(
          questionNumber: 3,
          detectedAnswer: 'False',
          correctAnswer: 'True',
          isCorrect: false,
          score: 0,
          maxScore: 1,
          confidence: 0.85,
        ),
        AnswerMatch(
          questionNumber: 4,
          detectedAnswer: 'C',
          correctAnswer: 'C',
          isCorrect: true,
          score: 1,
          maxScore: 1,
          confidence: 0.92,
        ),
        AnswerMatch(
          questionNumber: 5,
          detectedAnswer: 'True',
          correctAnswer: 'True',
          isCorrect: true,
          score: 1,
          maxScore: 1,
          confidence: 0.88,
        ),
      ],
    ),
    ScanResult(
      id: 'r2',
      assessmentId: 'a1',
      studentId: 's2',
      studentName: 'Bekele Tesfaye',
      imagePath: '/tmp/b.jpg',
      totalScore: 2,
      maxScore: 5,
      percentage: 40.0,
      grade: 'F',
      confidence: 0.45,
      answers: [
        AnswerMatch(
          questionNumber: 1,
          detectedAnswer: 'A',
          correctAnswer: 'A',
          isCorrect: true,
          score: 1,
          maxScore: 1,
          confidence: 0.60,
        ),
        AnswerMatch(
          questionNumber: 2,
          detectedAnswer: 'A',
          correctAnswer: 'B',
          isCorrect: false,
          score: 0,
          maxScore: 1,
          confidence: 0.30,
        ),
        AnswerMatch(
          questionNumber: 3,
          detectedAnswer: 'True',
          correctAnswer: 'True',
          isCorrect: true,
          score: 1,
          maxScore: 1,
          confidence: 0.55,
        ),
        AnswerMatch(
          questionNumber: 4,
          detectedAnswer: '[MISSING]',
          correctAnswer: 'C',
          isCorrect: false,
          score: 0,
          maxScore: 1,
          confidence: 0.0,
        ),
        AnswerMatch(
          questionNumber: 5,
          detectedAnswer: '[MISSING]',
          correctAnswer: 'False',
          isCorrect: false,
          score: 0,
          maxScore: 1,
          confidence: 0.0,
        ),
      ],
    ),
    ScanResult(
      id: 'r3',
      assessmentId: 'a1',
      studentId: 's3',
      studentName: 'Chaltu Dida',
      imagePath: '/tmp/c.jpg',
      totalScore: 3,
      maxScore: 5,
      percentage: 60.0,
      grade: 'C',
      confidence: 0.78,
      answers: [
        AnswerMatch(
          questionNumber: 1,
          detectedAnswer: 'A',
          correctAnswer: 'A',
          isCorrect: true,
          score: 1,
          maxScore: 1,
          confidence: 0.90,
        ),
        AnswerMatch(
          questionNumber: 2,
          detectedAnswer: 'B',
          correctAnswer: 'B',
          isCorrect: true,
          score: 1,
          maxScore: 1,
          confidence: 0.85,
        ),
        AnswerMatch(
          questionNumber: 3,
          detectedAnswer: 'False',
          correctAnswer: 'True',
          isCorrect: false,
          score: 0,
          maxScore: 1,
          confidence: 0.70,
        ),
        AnswerMatch(
          questionNumber: 4,
          detectedAnswer: 'D',
          correctAnswer: 'C',
          isCorrect: false,
          score: 0,
          maxScore: 1,
          confidence: 0.65,
        ),
        AnswerMatch(
          questionNumber: 5,
          detectedAnswer: 'False',
          correctAnswer: 'False',
          isCorrect: true,
          score: 1,
          maxScore: 1,
          confidence: 0.80,
        ),
      ],
    ),
  ];

  /// Build ReviewScreen with route arguments.
  Widget buildReviewScreen(List<ScanResult> results, {bool isAmharic = false}) {
    if (isAmharic) localeProvider.setLocale('am');

    return MaterialApp(
      theme: AppTheme.lightTheme,
      initialRoute: '/review',
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => MultiProvider(
            providers: [
              ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
              ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
              ChangeNotifierProvider<AssessmentProvider>.value(value: assessmentProvider),
            ],
            child: const ReviewScreen(),
          ),
          settings: RouteSettings(name: '/review', arguments: results),
        );
      },
    );
  }

  // ──── ReviewScreen ────

  group('ReviewScreen — rendering', () {
    testWidgets('renders with results', (tester) async {
      final results = makeResults();
      await tester.pumpWidget(buildReviewScreen(results));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(find.text('Review Results'), findsOneWidget);
    });

    testWidgets('shows all student names', (tester) async {
      final results = makeResults();
      await tester.pumpWidget(buildReviewScreen(results));
      await tester.pumpAndSettle();

      expect(find.text('Abebe Kebede'), findsOneWidget);
      expect(find.text('Bekele Tesfaye'), findsOneWidget);
      expect(find.text('Chaltu Dida'), findsOneWidget);
    });

    testWidgets('shows score percentages', (tester) async {
      final results = makeResults();
      await tester.pumpWidget(buildReviewScreen(results));
      await tester.pumpAndSettle();

      expect(find.text('80%'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      expect(find.text('60%'), findsOneWidget);
    });

    testWidgets('shows pass/fail colors via grade', (tester) async {
      final results = makeResults();
      await tester.pumpWidget(buildReviewScreen(results));
      await tester.pumpAndSettle();

      expect(find.text('A'), findsOneWidget);
      expect(find.text('F'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
    });
  });

  group('ReviewScreen — empty state', () {
    testWidgets('shows empty state with no results', (tester) async {
      await tester.pumpWidget(buildReviewScreen([]));
      await tester.pumpAndSettle();

      expect(find.text('No results to review'), findsOneWidget);
    });

    testWidgets('shows Amharic empty state', (tester) async {
      await tester.pumpWidget(buildReviewScreen([], isAmharic: true));
      await tester.pumpAndSettle();

      expect(find.text('ውጤት የለም'), findsOneWidget);
    });
  });

  group('ReviewScreen — Amharic', () {
    testWidgets('shows Amharic app bar title', (tester) async {
      await tester.pumpWidget(buildReviewScreen(makeResults(), isAmharic: true));
      await tester.pumpAndSettle();

      expect(find.text('ውጤቶችን ይገምግሙ'), findsOneWidget);
    });

    testWidgets('shows Amharic confidence label', (tester) async {
      await tester.pumpWidget(buildReviewScreen(makeResults(), isAmharic: true));
      await tester.pumpAndSettle();

      // "መተማመን" should appear in result cards
      expect(find.textContaining('መተማመን'), findsWidgets);
    });
  });

  group('ReviewScreen — needs review', () {
    testWidgets('shows "Needs Review" badge for low confidence', (tester) async {
      final results = makeResults();
      await tester.pumpWidget(buildReviewScreen(results));
      await tester.pumpAndSettle();

      // Bekele has confidence 0.45 < 0.7 threshold
      expect(find.text('Needs Review'), findsOneWidget);
    });

    testWidgets('shows Amharic "Needs Review" badge', (tester) async {
      final results = makeResults();
      await tester.pumpWidget(buildReviewScreen(results, isAmharic: true));
      await tester.pumpAndSettle();

      expect(find.text('ማረሚያ ያስፈልጋል'), findsOneWidget);
    });
  });

  group('ReviewScreen — score display', () {
    testWidgets('shows score format total/max', (tester) async {
      final results = makeResults();
      await tester.pumpWidget(buildReviewScreen(results));
      await tester.pumpAndSettle();

      expect(find.text('4/5'), findsOneWidget);
      expect(find.text('2/5'), findsOneWidget);
      expect(find.text('3/5'), findsOneWidget);
    });

    testWidgets('shows confidence percentages', (tester) async {
      final results = makeResults();
      await tester.pumpWidget(buildReviewScreen(results));
      await tester.pumpAndSettle();

      expect(find.textContaining('92%'), findsOneWidget);
      expect(find.textContaining('45%'), findsOneWidget);
    });
  });

  group('ReviewScreen — answer summary', () {
    testWidgets('shows answer number badges for each result', (tester) async {
      final results = makeResults();
      await tester.pumpWidget(buildReviewScreen(results));
      await tester.pumpAndSettle();

      // Each result card should show question numbers 1-5
      // The numbers appear in the answer summary chips
      expect(find.text('1'), findsWidgets);
      expect(find.text('5'), findsWidgets);
    });
  });

  group('ReviewScreen — sort', () {
    testWidgets('shows sort button', (tester) async {
      final results = makeResults();
      await tester.pumpWidget(buildReviewScreen(results));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.sort), findsOneWidget);
    });

    testWidgets('tapping sort shows sort options', (tester) async {
      final results = makeResults();
      await tester.pumpWidget(buildReviewScreen(results));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();

      expect(find.text('Lowest to Highest'), findsOneWidget);
      expect(find.text('Highest to Lowest'), findsOneWidget);
      expect(find.text('Needs Review First'), findsOneWidget);
    });

    testWidgets('shows Amharic sort options', (tester) async {
      final results = makeResults();
      await tester.pumpWidget(buildReviewScreen(results, isAmharic: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();

      expect(find.text('ከዝቅተኛ ወደ ከፍተኛ'), findsOneWidget);
      expect(find.text('ከከፍተኛ ወደ ዝቅተኛ'), findsOneWidget);
      expect(find.text('ማረሚያ የሚያስፈልጉ'), findsOneWidget);
    });
  });

  group('ReviewScreen — scan date', () {
    testWidgets('shows scanned date on result cards', (tester) async {
      final results = makeResults();
      await tester.pumpWidget(buildReviewScreen(results));
      await tester.pumpAndSettle();

      expect(find.textContaining('Scanned:'), findsWidgets);
    });
  });

  group('SideBySideReview — model tests', () {
    test('ScanResult needsReview triggers on low confidence', () {
      final result = ScanResult(
        assessmentId: 'a1',
        studentId: 's1',
        studentName: 'Test',
        imagePath: '/tmp/test.jpg',
        confidence: 0.5,
        answers: [
          AnswerMatch(
            questionNumber: 1,
            detectedAnswer: 'A',
            correctAnswer: 'A',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.5,
          ),
        ],
      );

      expect(result.needsReview, isTrue);
    });

    test('ScanResult needsReview is false for high confidence', () {
      final result = ScanResult(
        assessmentId: 'a1',
        studentId: 's1',
        studentName: 'Test',
        imagePath: '/tmp/test.jpg',
        confidence: 0.9,
        answers: [
          AnswerMatch(
            questionNumber: 1,
            detectedAnswer: 'A',
            correctAnswer: 'A',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.9,
          ),
        ],
      );

      expect(result.needsReview, isFalse);
    });

    test('AlignmentCheck detects missing answers', () {
      final result = ScanResult(
        assessmentId: 'a1',
        studentId: 's1',
        studentName: 'Test',
        imagePath: '/tmp/test.jpg',
        answers: [
          AnswerMatch(
            questionNumber: 1,
            detectedAnswer: 'A',
            correctAnswer: 'A',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.9,
          ),
          AnswerMatch(
            questionNumber: 2,
            detectedAnswer: '[MISSING]',
            correctAnswer: 'B',
            isCorrect: false,
            score: 0,
            maxScore: 1,
            confidence: 0.0,
          ),
          AnswerMatch(
            questionNumber: 3,
            detectedAnswer: '[MISSING]',
            correctAnswer: 'C',
            isCorrect: false,
            score: 0,
            maxScore: 1,
            confidence: 0.0,
          ),
        ],
      );

      // 2 missing out of 5 expected = 40% > 20% threshold
      final alignment = result.checkAlignment(5);
      expect(alignment.needsWarning, isTrue);
      expect(alignment.missingCount, 2);
      expect(alignment.detectedObjective, 1);
    });

    test('AlignmentCheck passes when few missing', () {
      final result = ScanResult(
        assessmentId: 'a1',
        studentId: 's1',
        studentName: 'Test',
        imagePath: '/tmp/test.jpg',
        answers: [
          AnswerMatch(
            questionNumber: 1,
            detectedAnswer: 'A',
            correctAnswer: 'A',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.9,
          ),
          AnswerMatch(
            questionNumber: 2,
            detectedAnswer: 'B',
            correctAnswer: 'B',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.9,
          ),
          AnswerMatch(
            questionNumber: 3,
            detectedAnswer: '[MISSING]',
            correctAnswer: 'C',
            isCorrect: false,
            score: 0,
            maxScore: 1,
            confidence: 0.0,
          ),
        ],
      );

      // 1 missing out of 5 expected = 20% <= 20% threshold
      final alignment = result.checkAlignment(5);
      expect(alignment.needsWarning, isFalse);
      expect(alignment.missingCount, 1);
    });

    test('AlignmentCheck handles zero expected count', () {
      final result = ScanResult(
        assessmentId: 'a1',
        studentId: 's1',
        studentName: 'Test',
        imagePath: '/tmp/test.jpg',
        answers: [],
      );

      final alignment = result.checkAlignment(0);
      expect(alignment.needsWarning, isFalse);
    });

    test('ScanResult copyWith preserves fields', () {
      final original = ScanResult(
        id: 'r1',
        assessmentId: 'a1',
        studentId: 's1',
        studentName: 'Test',
        imagePath: '/tmp/test.jpg',
        totalScore: 3,
        maxScore: 5,
        percentage: 60,
        grade: 'C',
        confidence: 0.8,
      );

      final updated = original.copyWith(
        totalScore: 4,
        grade: 'B',
        teacherComment: 'Good work',
      );

      expect(updated.totalScore, 4);
      expect(updated.grade, 'B');
      expect(updated.teacherComment, 'Good work');
      // Preserved fields
      expect(updated.id, 'r1');
      expect(updated.studentName, 'Test');
      expect(updated.maxScore, 5);
      expect(updated.confidence, 0.8);
    });

    test('ScanResult toMap/fromMap round-trip', () {
      final original = ScanResult(
        assessmentId: 'a1',
        studentId: 's1',
        studentName: 'Test',
        imagePath: '/tmp/test.jpg',
        totalScore: 4,
        maxScore: 5,
        percentage: 80,
        grade: 'A',
        confidence: 0.9,
        answers: [
          AnswerMatch(
            questionNumber: 1,
            detectedAnswer: 'A',
            correctAnswer: 'A',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.95,
          ),
        ],
      );

      final map = original.toMap();
      final restored = ScanResult.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.studentName, 'Test');
      expect(restored.totalScore, 4);
      expect(restored.maxScore, 5);
      expect(restored.percentage, 80);
      expect(restored.grade, 'A');
      expect(restored.answers.length, 1);
      expect(restored.answers.first.detectedAnswer, 'A');
    });
  });
}
