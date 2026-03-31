import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ethiograde/widgets/assessment_card.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/services/locale_provider.dart';
import 'package:ethiograde/config/theme.dart';

void main() {
  group('AssessmentCard', () {
    /// Helper that wraps the card in MaterialApp + Provider context.
    Widget buildCard({
      required Assessment assessment,
      required bool isAmharic,
      VoidCallback? onTap,
    }) {
      final localeProvider = LocaleProvider();
      if (isAmharic) {
        localeProvider.setLocale('am');
      }

      return MaterialApp(
        theme: AppTheme.lightTheme,
        home: ChangeNotifierProvider<LocaleProvider>.value(
          value: localeProvider,
          child: Scaffold(
            body: AssessmentCard(
              assessment: assessment,
              isAmharic: isAmharic,
              onTap: onTap,
            ),
          ),
        ),
      );
    }

    /// Standard test assessment with mixed question types.
    Assessment makeAssessment({
      String title = 'Math Midterm',
      String titleAm = 'የሂሳብ መካከለኛ ፈተና',
      String subject = 'Mathematics',
      String className = 'Grade 10A',
      AssessmentStatus status = AssessmentStatus.active,
    }) {
      return Assessment(
        title: title,
        titleAmharic: titleAm,
        subject: subject,
        className: className,
        status: status,
        questions: [
          Question(number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 2),
          Question(number: 2, type: QuestionType.trueFalse, correctAnswer: 'true', points: 1),
          Question(number: 3, type: QuestionType.shortAnswer, correctAnswer: '42', points: 3),
        ],
      );
    }

    testWidgets('displays English title when isAmharic is false', (tester) async {
      await tester.pumpWidget(buildCard(
        assessment: makeAssessment(),
        isAmharic: false,
      ));

      expect(find.text('Math Midterm'), findsOneWidget);
      expect(find.text('Mathematics'), findsOneWidget);
    });

    testWidgets('displays Amharic title when isAmharic is true', (tester) async {
      await tester.pumpWidget(buildCard(
        assessment: makeAssessment(),
        isAmharic: true,
      ));

      expect(find.text('የሂሳብ መካከለኛ ፈተና'), findsOneWidget);
    });

    testWidgets('falls back to English title when Amharic is empty', (tester) async {
      final assessment = makeAssessment(titleAm: '');

      await tester.pumpWidget(buildCard(
        assessment: assessment,
        isAmharic: true,
      ));

      expect(find.text('Math Midterm'), findsOneWidget);
    });

    testWidgets('shows question count and max score', (tester) async {
      await tester.pumpWidget(buildCard(
        assessment: makeAssessment(),
        isAmharic: false,
      ));

      // 3 questions, max score = 2+1+3 = 6
      expect(find.text('3 Q'), findsOneWidget);
      expect(find.text('6 pts'), findsOneWidget);
    });

    testWidgets('shows Amharic question count labels', (tester) async {
      await tester.pumpWidget(buildCard(
        assessment: makeAssessment(),
        isAmharic: true,
      ));

      expect(find.text('3 ጥያቄ'), findsOneWidget);
      expect(find.text('6 ነጥብ'), findsOneWidget);
    });

    testWidgets('displays class name chip', (tester) async {
      await tester.pumpWidget(buildCard(
        assessment: makeAssessment(),
        isAmharic: false,
      ));

      expect(find.text('Grade 10A'), findsOneWidget);
    });

    testWidgets('shows correct status label', (tester) async {
      await tester.pumpWidget(buildCard(
        assessment: makeAssessment(status: AssessmentStatus.draft),
        isAmharic: false,
      ));

      expect(find.text('Draft'), findsOneWidget);
    });

    testWidgets('shows Amharic status labels', (tester) async {
      await tester.pumpWidget(buildCard(
        assessment: makeAssessment(status: AssessmentStatus.grading),
        isAmharic: true,
      ));

      expect(find.text('በመስጠት ላይ'), findsOneWidget);
    });

    testWidgets('shows question type breakdown chips', (tester) async {
      await tester.pumpWidget(buildCard(
        assessment: makeAssessment(),
        isAmharic: false,
      ));

      expect(find.text('MCQ 1'), findsOneWidget);
      expect(find.text('T/F 1'), findsOneWidget);
      expect(find.text('Short 1'), findsOneWidget);
    });

    testWidgets('does not show essay chip when no essays', (tester) async {
      await tester.pumpWidget(buildCard(
        assessment: makeAssessment(),
        isAmharic: false,
      ));

      expect(find.text('Essay'), findsNothing);
    });

    testWidgets('shows essay chip when essays exist', (tester) async {
      final assessment = Assessment(
        title: 'English Test',
        subject: 'English',
        questions: [
          Question(number: 1, type: QuestionType.essay, correctAnswer: null, points: 10),
        ],
      );

      await tester.pumpWidget(buildCard(
        assessment: assessment,
        isAmharic: false,
      ));

      expect(find.text('Essay 1'), findsOneWidget);
    });

    testWidgets('custom onTap callback fires', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(buildCard(
        assessment: makeAssessment(),
        isAmharic: false,
        onTap: () => tapped = true,
      ));

      await tester.tap(find.byType(AssessmentCard));
      expect(tapped, isTrue);
    });

    testWidgets('has proper card elevation and shape', (tester) async {
      await tester.pumpWidget(buildCard(
        assessment: makeAssessment(),
        isAmharic: false,
      ));

      final card = tester.widget<Card>(find.byType(Card));
      expect(card.elevation, 0); // Flat design per design system
    });

    testWidgets('renders completed status correctly', (tester) async {
      await tester.pumpWidget(buildCard(
        assessment: makeAssessment(status: AssessmentStatus.completed),
        isAmharic: false,
      ));

      expect(find.text('Completed'), findsOneWidget);
    });

    testWidgets('renders empty questions list without crash', (tester) async {
      final assessment = Assessment(
        title: 'Empty Test',
        subject: 'Science',
      );

      await tester.pumpWidget(buildCard(
        assessment: assessment,
        isAmharic: false,
      ));

      expect(find.text('Empty Test'), findsOneWidget);
      expect(find.text('0 Q'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
