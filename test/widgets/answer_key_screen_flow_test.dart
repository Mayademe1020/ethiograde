import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/services/assessment_provider.dart';
import 'package:ethiograde/screens/assessment/answer_key_screen.dart';

/// Minimal provider that skips Hive persistence so the screen can be pumped
/// in isolation. updateAssessment simply records the latest assessment.
class _FakeProvider extends AssessmentProvider {
  _FakeProvider() : super();

  @override
  Future<void> loadAssessments() async {
    // Skip Hive persistence in tests.
  }

  @override
  Future<Result<Assessment>> updateAssessment(Assessment assessment) async {
    setCurrentAssessment(assessment);
    return Result.success(assessment);
  }
}

Assessment _uniformExam({int count = 20}) => Assessment(
      title: 'Midterm',
      subject: 'Biology',
      questions: List.generate(
        count,
        (i) => Question(
          id: 'q-${i + 1}',
          number: i + 1,
          type: QuestionType.mcq,
          text: 'Question ${i + 1}',
          points: 1,
          options: const ['A', 'B', 'C', 'D', 'E'],
          correctAnswer: '',
        ),
      ),
    );

Future<void> _pump(WidgetTester tester, Assessment a) async {
  final provider = _FakeProvider()..setCurrentAssessment(a);
  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider<AssessmentProvider>.value(
        value: provider,
        child: const AnswerKeyScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('AnswerKeyScreen 3-stage flow', () {
    testWidgets('Stage 0 (Structure) shows first and allows Continue',
        (tester) async {
      await _pump(tester, _uniformExam());

      // Structure stage copy visible.
      expect(find.textContaining('how your exam is organized'), findsOneWidget);
      // Uniform quick-path info card.
      expect(find.textContaining('All 20 questions are'), findsOneWidget);

      // Continue to answers moves to Stage 1 (Enter).
      await tester.tap(find.textContaining('Continue to answers'));
      await tester.pumpAndSettle();

      // Enter stage: section-aware bulk entry is the primary flow.
      expect(find.widgetWithText(FilledButton, 'Enter answers'), findsWidgets);
      expect(
        find.widgetWithText(FilledButton, 'Continue to Review'),
        findsOneWidget,
      );
    });

    testWidgets('Stage 1 → Stage 2 (Review) shows the summary grid',
        (tester) async {
      await _pump(tester, _uniformExam());

      await tester.tap(find.textContaining('Continue to answers'));
      await tester.pumpAndSettle();

      // Footer "Continue to Review" advances to Stage 2 (Review).
      await tester.tap(find.widgetWithText(FilledButton, 'Continue to Review'));
      await tester.pumpAndSettle();

      // Review grid: unanswered cells use Icons.circle_outlined. Tapping a
      // cell returns to the Enter stage (proving review→edit navigation).
      final cells = find.byIcon(Icons.circle_outlined);
      expect(cells, findsAtLeastNWidgets(3));
      await tester.tap(cells.at(2));
      await tester.pumpAndSettle();

      // Back in the Enter stage, bulk entry is shown again.
      expect(find.widgetWithText(FilledButton, 'Enter answers'), findsWidgets);
    });

    testWidgets('Structure validation error blocks progression',
        (tester) async {
      // Overlapping sections → invalid structure → Continue disabled.
      final a = _uniformExam();
      final invalid = a.copyWith(
        sections: const [
          AnswerKeySection(start: 1, end: 12, type: QuestionType.mcq),
          AnswerKeySection(start: 10, end: 20, type: QuestionType.shortAnswer),
        ],
      );
      await _pump(tester, invalid);

      // Error message about overlap is shown.
      expect(find.textContaining('overlap'), findsOneWidget);
      // The Continue button exists but is disabled (validation blocks it).
      final continueBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Continue to answers'),
      );
      expect(continueBtn.onPressed, isNull);
    });
  });
}
