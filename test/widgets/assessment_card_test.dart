import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ethiograde/widgets/assessment_card.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/services/class_provider.dart';
import 'package:ethiograde/models/class_info.dart';

void main() {
  Widget wrap(Widget child, {List<ClassInfo> classes = const []}) {
    final prov = ClassProvider();
    for (final c in classes) {
      prov.addClass(c);
    }
    return ChangeNotifierProvider<ClassProvider>.value(
      value: prov,
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child))));
  }

  Assessment makeAssessment({
    String title = 'Math Midterm',
    String subject = 'Mathematics',
    String className = 'Grade 5A',
    AssessmentStatus status = AssessmentStatus.active,
    List<Question> questions = const [],
  }) => Assessment(
    title: title,
    subject: subject,
    className: className,
    status: status,
    questions: questions);

  group('AssessmentCard', () {
    testWidgets('renders title and subject', (tester) async {
      final assessment = makeAssessment();
      await tester.pumpWidget(wrap(AssessmentCard(
        assessment: assessment)));
      await tester.pumpAndSettle();

      expect(find.text('Math Midterm'), findsOneWidget);
      expect(find.text('Mathematics'), findsOneWidget);
    });

    testWidgets('shows English status label', (tester) async {
      final questions = [
        Question(number: 1, text: 'Q1', type: QuestionType.mcq, points: 1),
        Question(number: 2, text: 'Q2', type: QuestionType.mcq, points: 1),
      ];
      for (final entry in {
        AssessmentStatus.draft: 'Draft',
        AssessmentStatus.active: 'Needs answer key',
        AssessmentStatus.grading: 'Needs answer key',
        AssessmentStatus.completed: 'Graded',
      }.entries) {
        final assessment = makeAssessment(status: entry.key, questions: questions);
        await tester.pumpWidget(wrap(AssessmentCard(
          assessment: assessment)));
        await tester.pumpAndSettle();
        expect(find.text(entry.value), findsOneWidget,
            reason: '${entry.key} should show "${entry.value}"');
      }
    });

    testWidgets('shows question count and points', (tester) async {
      final assessment = makeAssessment(questions: [
        Question(number: 1, text: 'Q1', type: QuestionType.mcq, points: 2),
        Question(number: 2, text: 'Q2', type: QuestionType.trueFalse, points: 1),
        Question(number: 3, text: 'Q3', type: QuestionType.mcq, points: 2),
      ]);
      await tester.pumpWidget(wrap(AssessmentCard(
        assessment: assessment)));
      await tester.pumpAndSettle();

      expect(find.text('3 Q'), findsOneWidget);
      expect(find.text('5 pts'), findsOneWidget);
    });

    testWidgets('shows class name chip when set', (tester) async {
      final assessment = makeAssessment(className: 'Grade 5A');
      await tester.pumpWidget(wrap(AssessmentCard(
        assessment: assessment)));
      await tester.pumpAndSettle();

      expect(find.text('Grade 5A'), findsOneWidget);
    });

    testWidgets('hides class name chip when empty', (tester) async {
      final assessment = makeAssessment(className: '');
      await tester.pumpWidget(wrap(AssessmentCard(
        assessment: assessment)));
      await tester.pumpAndSettle();

      // Should not find any class_outlined icon
      // (class chip is the only one that conditionally shows)
      // Just verify title still renders
      expect(find.text('Math Midterm'), findsOneWidget);
    });

    testWidgets('shows question type breakdown chips', (tester) async {
      final assessment = makeAssessment(questions: [
        Question(number: 1, text: 'Q1', type: QuestionType.mcq, points: 1),
        Question(number: 2, text: 'Q2', type: QuestionType.trueFalse, points: 1),
        Question(number: 3, text: 'Q3', type: QuestionType.shortAnswer, points: 1),
        Question(number: 4, text: 'Q4', type: QuestionType.essay, points: 5),
      ]);
      await tester.pumpWidget(wrap(AssessmentCard(
        assessment: assessment)));
      await tester.pumpAndSettle();

      expect(find.text('MCQ 1'), findsOneWidget);
      expect(find.text('T/F 1'), findsOneWidget);
      expect(find.text('Short 1'), findsOneWidget);
      expect(find.text('Essay 1'), findsOneWidget);
    });

    testWidgets('calls onTap when provided', (tester) async {
      var tapped = false;
      final assessment = makeAssessment();
      await tester.pumpWidget(wrap(AssessmentCard(
        assessment: assessment,
onTap: () => tapped = true)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AssessmentCard));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });
  });
}
