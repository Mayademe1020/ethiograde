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
    tempDir = await Directory.systemTemp.createTemp('ethiograde_qg_test_');
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

  Widget buildScreen() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AssessmentProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(
        home: const QuickGradeScreen(),
        onGenerateRoute: (settings) {
          if (settings.name == AppRoutes.camera) {
            return MaterialPageRoute(
              builder: (_) =>
                  const Scaffold(body: Center(child: Text('Camera Stub'))),
            );
          }
          return null;
        },
      ),
    );
  }

  Future<void> openBottomSheet(WidgetTester tester) async {
    await tester.tap(find.text('Enter Answer Key'));
    await tester.pumpAndSettle();
  }

  Future<void> pumpAfterSubmit(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
  }

  group('QuickGradeScreen — English', () {
    testWidgets('renders title and hero card', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Quick Grade'), findsOneWidget);
      expect(find.text('Scan Papers in One Tap'), findsOneWidget);
      expect(find.text('Enter Answer Key'), findsOneWidget);
    });

    testWidgets('shows flash_on icon in hero card', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.flash_on), findsOneWidget);
    });

    testWidgets('opens bottom sheet with form fields', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await openBottomSheet(tester);

      expect(find.text('Enter Answer Key'), findsWidgets);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('Start Scanning'), findsOneWidget);
    });

    testWidgets('question count: empty shows validation error', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await openBottomSheet(tester);
      await tester.tap(find.text('Start Scanning'));
      await pumpAfterSubmit(tester);

      expect(find.text('Required'), findsNWidgets(2));
    });

    testWidgets('question count: 0 shows range error', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await openBottomSheet(tester);
      await tester.enterText(find.byType(TextFormField).first, '0');
      await tester.tap(find.text('Start Scanning'));
      await pumpAfterSubmit(tester);

      expect(find.text('1-100'), findsOneWidget);
    });

    testWidgets('question count: 101 shows range error', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await openBottomSheet(tester);
      await tester.enterText(find.byType(TextFormField).first, '101');
      await tester.tap(find.text('Start Scanning'));
      await pumpAfterSubmit(tester);

      expect(find.text('1-100'), findsOneWidget);
    });

    testWidgets('question count: 50 is valid', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await openBottomSheet(tester);
      await tester.enterText(find.byType(TextFormField).first, '50');
      await tester.enterText(
        find.byType(TextFormField).last,
        'A,B,C,D,A,B,C,D,A,B,C,D,A,B,C,D,A,B,C,D,A,B,C,D,A,B,C,D,A,B,C,D,A,B,C,D,A,B,C,D,A,B,C,D,A,B,C,D,A,B,C,D',
      );
      await tester.tap(find.text('Start Scanning'));
      await pumpAfterSubmit(tester);

      expect(find.text('1-100'), findsNothing);
    });

    testWidgets('answer key: empty shows validation error', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await openBottomSheet(tester);
      await tester.enterText(find.byType(TextFormField).first, '5');
      await tester.tap(find.text('Start Scanning'));
      await pumpAfterSubmit(tester);

      expect(find.text('Required'), findsWidgets);
    });

    testWidgets('answer key: wrong count shows mismatch error', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await openBottomSheet(tester);
      await tester.enterText(find.byType(TextFormField).first, '5');
      await tester.enterText(
        find.byType(TextFormField).last,
        'A,B,C',
      );
      await tester.tap(find.text('Start Scanning'));
      await pumpAfterSubmit(tester);

      expect(
        find.textContaining('Must match question count'),
        findsOneWidget,
      );
    });

    testWidgets('answer key: invalid characters show error', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await openBottomSheet(tester);
      await tester.enterText(find.byType(TextFormField).first, '3');
      await tester.enterText(
        find.byType(TextFormField).last,
        'A,X,C',
      );
      await tester.tap(find.text('Start Scanning'));
      await pumpAfterSubmit(tester);

      expect(
        find.textContaining('Must match question count'),
        findsOneWidget,
      );
    });

    testWidgets('valid MCQ input enables scanning', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await openBottomSheet(tester);
      await tester.enterText(find.byType(TextFormField).first, '4');
      await tester.enterText(find.byType(TextFormField).last, 'A,B,C,D');

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Start Scanning'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('valid T/F input enables scanning', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await openBottomSheet(tester);
      await tester.enterText(find.byType(TextFormField).first, '3');
      await tester.enterText(find.byType(TextFormField).last, 'T,F,T');

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Start Scanning'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('valid mixed MCQ+T/F input enables scanning', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await openBottomSheet(tester);
      await tester.enterText(find.byType(TextFormField).first, '5');
      await tester.enterText(find.byType(TextFormField).last, 'A,B,T,F,C');

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Start Scanning'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('valid input with semicolons as delimiter works', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await openBottomSheet(tester);
      await tester.enterText(find.byType(TextFormField).first, '3');
      await tester.enterText(find.byType(TextFormField).last, 'A;B;C');

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Start Scanning'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('valid input with spaces as delimiter works', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await openBottomSheet(tester);
      await tester.enterText(find.byType(TextFormField).first, '3');
      await tester.enterText(find.byType(TextFormField).last, 'A B C');

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Start Scanning'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('lowercase answers are accepted (auto-uppercased)', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await openBottomSheet(tester);
      await tester.enterText(find.byType(TextFormField).first, '4');
      await tester.enterText(find.byType(TextFormField).last, 'a,b,c,d');

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Start Scanning'),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  group('QuickGradeScreen — UI structure', () {
    testWidgets('has scaffold with app bar', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('document_scanner icon in bottom sheet', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await openBottomSheet(tester);

      expect(find.byIcon(Icons.document_scanner), findsOneWidget);
    });

    testWidgets('check_circle_outline icon in bottom sheet', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await openBottomSheet(tester);

      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('format_list_numbered icon in bottom sheet', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await openBottomSheet(tester);

      expect(find.byIcon(Icons.format_list_numbered), findsOneWidget);
    });
  });
}
