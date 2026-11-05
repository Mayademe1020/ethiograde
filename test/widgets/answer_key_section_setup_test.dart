import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/screens/assessment/answer_key_section_setup.dart';

void main() {
  testWidgets('auto-fix resolves overlap into a clean split via confirmation', (tester) async {
    final assessment = Assessment(
      title: 'Overlap Exam',
      subject: 'Biology',
      questions: [for (var i = 1; i <= 20; i++) Question(number: i, type: QuestionType.mcq)],
      sections: const [
        AnswerKeySection(start: 1, end: 12, type: QuestionType.mcq),
        AnswerKeySection(start: 10, end: 20, type: QuestionType.trueFalse),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: AnswerKeySectionSetup(assessment: assessment)),
    );
    await tester.pumpAndSettle();

    // Invalid structure -> error banner shows the Fix automatically button.
    expect(find.text('Fix automatically'), findsOneWidget);
    final startDisabled =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start Answering'));
    expect(startDisabled.onPressed, isNull);

    // Open the confirmation dialog.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Fix automatically'));
    await tester.pumpAndSettle();

    expect(find.text('Fix sections automatically?'), findsOneWidget);
    expect(find.textContaining('A (MCQ): Questions 1–12'), findsOneWidget);
    expect(find.textContaining('B (T/F): Questions 13–20'), findsOneWidget);

    // Confirm the system-level fix.
    await tester.tap(find.widgetWithText(FilledButton, 'Fix & apply'));
    await tester.pumpAndSettle();

    // Structure is now valid: Start Answering is enabled, no error banner.
    final startEnabled =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start Answering'));
    expect(startEnabled.onPressed, isNotNull);
    expect(find.text('Fix automatically'), findsNothing);
  });
}
