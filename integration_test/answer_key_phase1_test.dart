import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/services/assessment_provider.dart';
import 'package:ethiograde/screens/assessment/answer_key_screen.dart';
import 'package:ethiograde/widgets/assessment/section_header.dart';

// Test-only provider. Avoids Hive/backend access: auto-save and Done hit these
// no-ops so the real AnswerKeyScreen flow runs unmodified against a fixture.
class FakeAssessmentProvider extends AssessmentProvider {
  FakeAssessmentProvider(this._fixed);

  final Assessment _fixed;

  @override
  Future<void> loadAssessments() async {}

  @override
  Assessment? get currentAssessment => _fixed;

  @override
  Future<Result<Assessment>> updateAssessment(Assessment assessment) async =>
      Result.success(assessment);

  @override
  Future<void> saveAssessment(Assessment assessment) async {}

  @override
  Future<Assessment> saveAnswerKeyChange(Assessment assessment) async =>
      assessment;
}

// Routes in this test resolve to a dummy page so Done/Tab navigation completes
// without a real route table.
class _DummyPage extends StatelessWidget {
  const _DummyPage();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('NAVIGATED')));
}

Assessment _mixedFixture() {
  final questions = <Question>[
    for (var i = 1; i <= 10; i++)
      Question(number: i, type: QuestionType.mcq),
    for (var i = 11; i <= 15; i++)
      Question(number: i, type: QuestionType.trueFalse),
    for (var i = 16; i <= 20; i++)
      Question(number: i, type: QuestionType.shortAnswer),
  ];
  return Assessment(
    title: 'Mixed Structure Exam',
    subject: 'Biology',
    questions: questions,
    sections: const [
      AnswerKeySection(start: 1, end: 10, type: QuestionType.mcq),
      AnswerKeySection(start: 11, end: 15, type: QuestionType.trueFalse),
      AnswerKeySection(start: 16, end: 20, type: QuestionType.shortAnswer),
    ],
  );
}

Assessment _incompleteFixture() {
  final questions = <Question>[
    for (var i = 1; i <= 10; i++)
      Question(number: i, type: QuestionType.mcq),
    for (var i = 11; i <= 15; i++)
      Question(number: i, type: QuestionType.trueFalse),
    for (var i = 16; i <= 20; i++)
      Question(number: i, type: QuestionType.shortAnswer),
  ];
  // Gap: questions 11-15 are not covered by any section.
  return Assessment(
    title: 'Incomplete Structure Exam',
    subject: 'Biology',
    questions: questions,
    sections: const [
      AnswerKeySection(start: 1, end: 10, type: QuestionType.mcq),
      AnswerKeySection(start: 16, end: 20, type: QuestionType.shortAnswer),
    ],
  );
}

Finder _questionRow(int number) => find.byWidgetPredicate(
      (w) =>
          w.runtimeType.toString() == '_QuestionRow' &&
          (w as dynamic).question.number == number,
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Required only for the Done path's scan-results lookup (returns empty).
    await Hive.initFlutter();
    await Hive.openBox('scan_results');
  });

  Future<void> pumpFixture(WidgetTester tester, Assessment fixture) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AssessmentProvider>.value(
        value: FakeAssessmentProvider(fixture),
        child: MaterialApp(
          onGenerateRoute: (_) =>
              MaterialPageRoute(builder: (_) => const _DummyPage()),
          home: const AnswerKeyScreen(),
        ),
      ),
    );
    // Use a tall surface so the Scrollable Review/Enter content (incl. the
    // "Back to answers" button and the full 20-cell grid) is on-screen and
    // fully built by the lazy lists.
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    await tester.pumpAndSettle();
  }

  testWidgets('incomplete structure cannot continue', (tester) async {
    await pumpFixture(tester, _incompleteFixture());

    // Validation error is surfaced.
    expect(find.textContaining('not covered'), findsOneWidget);

    // Continue button is disabled when the structure is invalid.
    final btn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue to answers'),
    );
    expect(btn.onPressed, isNull);
  });

  testWidgets('mixed structure: full flow, completion, review nav, save',
      (tester) async {
    await pumpFixture(tester, _mixedFixture());

    // --- Stage 0: Structure ---
    expect(find.textContaining('Tell us how your exam is organized'),
        findsOneWidget);
    final continueBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue to answers'),
    );
    expect(continueBtn.onPressed, isNotNull); // valid structure -> can proceed

    // --- Progression: Structure -> Enter ---
    await tester.tap(find.widgetWithText(FilledButton, 'Continue to answers'));
    await tester.pumpAndSettle();
    // Enter stage: bulk entry is primary; a clear "Continue to Review" CTA exists.
    expect(find.widgetWithText(FilledButton, 'Continue to Review'),
        findsOneWidget);

    // --- Expand Section A to reveal per-question rows, then answer Q1 = B ---
    await tester.tap(find.widgetWithText(TextButton, 'Edit individually').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: _questionRow(1), matching: find.text('B')).first,
    );
    await tester.pumpAndSettle();

    // --- Completion reflects the entered answer (via Review) ---
    await tester.tap(find.widgetWithText(TextButton, 'Review'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 20'), findsOneWidget); // Q1 answered
    final backBtn = find.widgetWithText(FilledButton, 'Back to answers');
    await tester.ensureVisible(backBtn);
    await tester.pumpAndSettle();
    await tester.tap(backBtn);
    await tester.pumpAndSettle();

    // --- Apply section-aware bulk to Section A (Q1-10 MCQ) ---
    final sectionA = find.byType(SectionHeader).first;
    await tester.tap(
      find.descendant(of: sectionA, matching: find.byIcon(Icons.content_paste)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'A, B, C, D, E, A, B, C, D, E',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    // --- Completion now reflects bulk-applied answers (via Review) ---
    await tester.tap(find.widgetWithText(TextButton, 'Review'));
    await tester.pumpAndSettle();
    expect(find.text('Question grid'), findsOneWidget);
    expect(find.text('10 / 20'), findsOneWidget); // Q1-10 answered

    // --- Tap review-grid question (Q16) -> back to Enter ---
    final grid = find.byType(Wrap); // unique in review stage
    await tester.ensureVisible(grid);
    await tester.pumpAndSettle();
    final cellQ16 = find
        .descendant(of: grid, matching: find.byType(GestureDetector))
        .at(15); // 0-based index 15 == Q16
    await tester.tap(cellQ16);
    await tester.pumpAndSettle();

    // Back on the Enter stage (bulk-primary). Expand Section C (last card) to
    // reveal the per-question row for Q16 and prove review->edit navigation.
    expect(find.widgetWithText(FilledButton, 'Continue to Review'),
        findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Edit individually').last);
    await tester.pumpAndSettle();
    expect(_questionRow(16), findsOneWidget);

    // --- Final save / Done path completes without runtime errors ---
    await tester.tap(find.widgetWithText(TextButton, 'Done'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('NAVIGATED'), findsOneWidget); // navigation succeeded
  });
}
