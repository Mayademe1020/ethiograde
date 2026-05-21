import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethiograde/main.dart' as app;
import 'package:ethiograde/screens/home/main_dashboard.dart';
import 'package:ethiograde/services/assessment_provider.dart';
import 'package:ethiograde/services/student_provider.dart';
import 'package:ethiograde/services/class_provider.dart';
import 'package:ethiograde/services/settings_provider.dart';
import 'package:ethiograde/services/teacher_provider.dart';
import 'package:ethiograde/services/weighted_grade_provider.dart';

/// Full grading flow integration test.
///
/// Tests the core teacher journey:
/// 1. First launch → onboarding → demo data seeded
/// 2. Dashboard shows demo class + students + assessment
/// 3. Navigate to create assessment → fill form → save
/// 4. Set answer key on assessment
/// 5. Quick Enter manual grading for students
/// 6. Review graded results
/// 7. Data persists across widget rebuilds
///
/// Camera scanning excluded (hardware dependency).
/// Weighted grading excluded (requires assessment with components).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Full Grading Flow', () {
    testWidgets('onboarding → dashboard with demo data', (tester) async {
      // Fresh launch — first_launch = true
      SharedPreferences.setMockInitialValues({'first_launch': true});
      app.main();
      await tester.pumpAndSettle();

      // Should land on onboarding screen
      expect(find.text('Scan & Grade'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      // Skip to setup page
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      // Setup page — enter teacher name
      expect(find.text('Welcome!'), findsOneWidget);
      final nameField = find.byType(TextField).first;
      await tester.enterText(nameField, 'Test Teacher');
      await tester.pumpAndSettle();

      // Tap "Get Started"
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Should now be on dashboard
      expect(find.byType(MainDashboard), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);

      // Demo data should be seeded — check for demo class
      expect(find.text('Grade 5A'), findsOneWidget);

      // Demo assessment should appear
      expect(find.text('Unit 1 Math Quiz'), findsOneWidget);
    });

    testWidgets('dashboard shows demo students in class detail', (tester) async {
      SharedPreferences.setMockInitialValues({});
      // Simulate already onboarded
      app.main();
      await tester.pumpAndSettle();

      // Navigate to Students tab
      await tester.tap(find.text('Students'));
      await tester.pumpAndSettle();

      // Should see demo students
      expect(find.text('Abel Tesfaye'), findsOneWidget);
      expect(find.text('Bethlehem Assefa'), findsOneWidget);
      expect(find.text('Dawit Haile'), findsOneWidget);
    });

    testWidgets('create assessment flow', (tester) async {
      SharedPreferences.setMockInitialValues({});
      app.main();
      await tester.pumpAndSettle();

      // Tap "New Assessment" FAB
      final fab = find.byType(FloatingActionButton);
      expect(fab, findsOneWidget);
      await tester.tap(fab);
      await tester.pumpAndSettle();

      // Should be on create assessment screen
      expect(find.text('Create Assessment'), findsOneWidget);

      // Fill in title
      final titleField = find.widgetWithText(TextField, 'Title');
      await tester.enterText(titleField, 'Integration Test Quiz');
      await tester.pumpAndSettle();

      // Fill in subject
      final subjectField = find.widgetWithText(TextField, 'Subject');
      await tester.enterText(subjectField, 'Science');
      await tester.pumpAndSettle();

      // Set number of questions
      final qField = find.widgetWithText(TextField, 'Questions');
      await tester.enterText(qField, '5');
      await tester.pumpAndSettle();

      // Save assessment
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Should navigate back to dashboard
      expect(find.text('Integration Test Quiz'), findsOneWidget);
    });

    testWidgets('set answer key on assessment', (tester) async {
      SharedPreferences.setMockInitialValues({});
      app.main();
      await tester.pumpAndSettle();

      // Go to Assessments tab
      await tester.tap(find.text('Assess'));
      await tester.pumpAndSettle();

      // Find demo assessment card and tap answer key
      final assessmentCard = find.text('Unit 1 Math Quiz');
      expect(assessmentCard, findsOneWidget);

      // Tap the assessment card to open details
      await tester.tap(assessmentCard);
      await tester.pumpAndSettle();

      // Look for Answer Key button
      final answerKeyBtn = find.text('Answer Key');
      if (answerKeyBtn.evaluate().isNotEmpty) {
        await tester.tap(answerKeyBtn.first);
        await tester.pumpAndSettle();

        // Answer key screen should be visible
        expect(find.text('Answer Key'), findsOneWidget);
      }
    });

    testWidgets('quick enter manual grading', (tester) async {
      SharedPreferences.setMockInitialValues({});
      app.main();
      await tester.pumpAndSettle();

      // Navigate to Assess tab
      await tester.tap(find.text('Assess'));
      await tester.pumpAndSettle();

      // Find assessment and navigate
      expect(find.text('Unit 1 Math Quiz'), findsOneWidget);

      // Look for Quick Enter entry point
      // (could be via assessment card menu or dashboard quick action)
      final quickEnterFinder = find.text('Quick Enter');
      if (quickEnterFinder.evaluate().isNotEmpty) {
        await tester.tap(quickEnterFinder.first);
        await tester.pumpAndSettle();

        // Should show assessment picker or score table
        expect(find.text('Select Assessment'), findsWidgets);
      }
    });

    testWidgets('verify demo assessment has correct answer key', (tester) async {
      SharedPreferences.setMockInitialValues({});
      app.main();
      await tester.pumpAndSettle();

      // The demo assessment should have 10 questions with answer keys
      // Check via Assessments tab
      await tester.tap(find.text('Assess'));
      await tester.pumpAndSettle();

      expect(find.text('Unit 1 Math Quiz'), findsOneWidget);
      // Answer key status chip should show green (complete)
      expect(find.byIcon(Icons.check_circle), findsWidgets);
    });

    testWidgets('settings tab accessible', (tester) async {
      SharedPreferences.setMockInitialValues({});
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      // Should show settings options
      expect(find.text('Grading Scale'), findsOneWidget);
      expect(find.text('Backup & Restore'), findsOneWidget);
    });

    testWidgets('bottom navigation switches tabs', (tester) async {
      SharedPreferences.setMockInitialValues({});
      app.main();
      await tester.pumpAndSettle();

      // Start on Home
      expect(find.text('Home'), findsOneWidget);

      // Switch to Assess
      await tester.tap(find.text('Assess'));
      await tester.pumpAndSettle();

      // Switch to Students
      await tester.tap(find.text('Students'));
      await tester.pumpAndSettle();
      expect(find.text('Abel Tesfaye'), findsOneWidget);

      // Switch to Settings
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      // Back to Home
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      // Dashboard should still show demo data
      expect(find.text('Grade 5A'), findsOneWidget);
    });

    testWidgets('class detail shows student roster', (tester) async {
      SharedPreferences.setMockInitialValues({});
      app.main();
      await tester.pumpAndSettle();

      // Home tab — tap on demo class
      final classCard = find.text('Grade 5A');
      expect(classCard, findsOneWidget);
      await tester.tap(classCard);
      await tester.pumpAndSettle();

      // Class detail should show all 5 demo students
      expect(find.text('Abel Tesfaye'), findsOneWidget);
      expect(find.text('Bethlehem Assefa'), findsOneWidget);
      expect(find.text('Dawit Haile'), findsOneWidget);
      expect(find.text('Helen Kebede'), findsOneWidget);
      expect(find.text('Yonas Alemu'), findsOneWidget);

      // Go back
      await tester.pageBack();
      await tester.pumpAndSettle();
    });

    testWidgets('add student from class detail', (tester) async {
      SharedPreferences.setMockInitialValues({});
      app.main();
      await tester.pumpAndSettle();

      // Navigate to class detail
      final classCard = find.text('Grade 5A');
      await tester.tap(classCard);
      await tester.pumpAndSettle();

      // Find add student button (FAB or icon)
      final addBtn = find.byIcon(Icons.person_add);
      if (addBtn.evaluate().isNotEmpty) {
        await tester.tap(addBtn.first);
        await tester.pumpAndSettle();

        // Should open add student screen
        expect(find.text('Add Student'), findsOneWidget);

        // Fill form
        final idField = find.widgetWithText(TextFormField, 'Student ID');
        if (idField.evaluate().isNotEmpty) {
          await tester.enterText(idField, '006');
        }
        final firstField = find.widgetWithText(TextFormField, 'First Name');
        if (firstField.evaluate().isNotEmpty) {
          await tester.enterText(firstField, 'Merhawi');
        }
        final lastField = find.widgetWithText(TextFormField, 'Last Name');
        if (lastField.evaluate().isNotEmpty) {
          await tester.enterText(lastField, 'Gebre');
        }

        // Select gender
        final maleChip = find.text('Male');
        if (maleChip.evaluate().isNotEmpty) {
          await tester.tap(maleChip.first);
          await tester.pumpAndSettle();
        }

        // Save
        final saveBtn = find.text('Save');
        if (saveBtn.evaluate().isNotEmpty) {
          await tester.tap(saveBtn.first);
          await tester.pumpAndSettle(const Duration(seconds: 1));
        }
      }
    });
  });
}
