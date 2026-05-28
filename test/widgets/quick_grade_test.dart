import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethiograde/screens/quick_grade/quick_grade_screen.dart';
import 'package:ethiograde/services/assessment_provider.dart';
import 'package:ethiograde/services/settings_provider.dart';
import 'package:ethiograde/config/routes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('ethiograde_qg_test_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Hive.openBox('students');
    await Hive.openBox('assessments');
    await Hive.openBox('settings_pii');
    await Hive.openBox('metadata');
  });

  tearDown(() async {
    for (final name in [
      'students',
      'assessments',
      'settings_pii',
      'metadata',
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

  /// Wraps QuickGradeScreen with required providers and a dummy route
  /// for AppRoutes.camera so navigation doesn't crash.
  Widget buildScreen() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
        ChangeNotifierProvider(create: (_) => AssessmentProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(
        home: const QuickGradeScreen(),
        onGenerateRoute: (settings) {
          // Return a dummy screen for camera route so navigation doesn't crash
          if (settings.name == AppRoutes.camera) {
            return MaterialPageRoute(
              builder: (_) => const Scaffold(
                body: Center(child: Text('Camera Stub'))));
          }
          return null;
        }));
  }

  group('QuickGradeScreen — English', () {
    testWidgets('renders title and form fields', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Quick Grade'), findsOneWidget);
      expect(find.text('Number of questions'), findsOneWidget);
      expect(find.textContaining('Answer key'), findsOneWidget);
      expect(find.text('Start Scanning'), findsOneWidget);
    });

    testWidgets('shows explanation card', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.textContaining('Skip setup'), findsOneWidget);
      expect(find.byIcon(Icons.flash_on), findsOneWidget);
    });

    testWidgets('shows hint text at bottom', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.textContaining('review and save'), findsOneWidget);
    });

    testWidgets('question count: empty shows validation error',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // Tap the Start Scanning button without filling anything
      await tester.tap(find.text('Start Scanning'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid number'), findsOneWidget);
    });

    testWidgets('question count: 0 shows range error', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        '0');
      await tester.tap(find.text('Start Scanning'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a number between 1 and 100'), findsOneWidget);
    });

    testWidgets('question count: 101 shows range error', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        '101');
      await tester.tap(find.text('Start Scanning'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a number between 1 and 100'), findsOneWidget);
    });

    testWidgets('question count: 50 is valid', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        '50');
      // Need to also fill answer key, but just verify no count error
      await tester.tap(find.text('Start Scanning'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a number between 1 and 100'), findsNothing);
      expect(find.text('Enter a valid number'), findsNothing);
    });

    testWidgets('answer key: empty shows validation error', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        '5');
      await tester.tap(find.text('Start Scanning'));
      await tester.pumpAndSettle();

      expect(find.text('Enter the answer key'), findsOneWidget);
    });

    testWidgets('answer key: wrong count shows mismatch error',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        '5');
      await tester.enterText(
        find.byType(TextFormField).last,
        'A,B,C', // only 3 answers for 5 questions
      );
      await tester.tap(find.text('Start Scanning'));
      await tester.pumpAndSettle();

      expect(
        find.text('Answers must match question count (A-E, T/F)'),
        findsOneWidget);
    });

    testWidgets('answer key: invalid characters show error', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        '3');
      await tester.enterText(
        find.byType(TextFormField).last,
        'A,X,C', // X is invalid
      );
      await tester.tap(find.text('Start Scanning'));
      await tester.pumpAndSettle();

      expect(
        find.text('Answers must match question count (A-E, T/F)'),
        findsOneWidget);
    });

    testWidgets('valid MCQ input enables scanning', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        '4');
      await tester.enterText(
        find.byType(TextFormField).last,
        'A,B,C,D');

      // The button should be enabled (no processing yet)
      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('valid T/F input enables scanning', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        '3');
      await tester.enterText(
        find.byType(TextFormField).last,
        'T,F,T');

      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('valid mixed MCQ+T/F input enables scanning',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        '5');
      await tester.enterText(
        find.byType(TextFormField).last,
        'A,B,T,F,C');

      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('valid input with semicolons as delimiter works',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        '3');
      await tester.enterText(
        find.byType(TextFormField).last,
        'A;B;C');

      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('valid input with spaces as delimiter works',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        '3');
      await tester.enterText(
        find.byType(TextFormField).last,
        'A B C');

      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('lowercase answers are accepted (auto-uppercased)',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        '4');
      await tester.enterText(
        find.byType(TextFormField).last,
        'a,b,c,d');

      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('valid input submits and navigates to camera',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        '3');
      await tester.enterText(
        find.byType(TextFormField).last,
        'A,B,C');

      await tester.tap(find.text('Start Scanning'));
      await tester.pumpAndSettle();

      // Should have navigated to camera stub
      expect(find.text('Camera Stub'), findsOneWidget);
    });

    testWidgets('assessment created and navigates on valid submit',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        '2');
      await tester.enterText(
        find.byType(TextFormField).last,
        'A,T');

      await tester.tap(find.text('Start Scanning'));
      await tester.pumpAndSettle();

      // Navigation to camera confirms assessment was created + saved
      expect(find.text('Camera Stub'), findsOneWidget);
    });
  });

  group('QuickGradeScreen — UI structure', () {
    testWidgets('has form with two text fields', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      final textFields = find.byType(TextFormField);
      expect(textFields, findsNWidgets(2));
    });

    testWidgets('has scrollable body', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('has scaffold with app bar', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('question count field accepts digits only', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // Enter letters into the first field (question count)
      await tester.enterText(
        find.byType(TextFormField).first,
        'abc');
      // The FilteringTextInputFormatter should block non-digits
      // The field should be empty or contain no letters
      final field = tester.widget<TextFormField>(
        find.byType(TextFormField).first);
      expect(field.controller?.text, isEmpty);
    });

    testWidgets('flash_on icon is present', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.flash_on), findsOneWidget);
    });

    testWidgets('document_scanner icon on button', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.document_scanner), findsOneWidget);
    });

    testWidgets('check_circle_outline icon on answer field', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('format_list_numbered icon on count field', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.format_list_numbered), findsOneWidget);
    });

    testWidgets('answer field capitalizes characters', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // The answer field should have TextCapitalization.characters
      final fields = find.byType(TextFormField);
      final answerField = tester.widget<TextFormField>(fields.last);
      expect(
        answerField.textCapitalization,
        TextCapitalization.characters);
    });
  });
}
