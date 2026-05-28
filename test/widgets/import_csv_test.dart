import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethiograde/screens/students/import_excel_screen.dart';
import 'package:ethiograde/services/student_provider.dart';
import 'package:ethiograde/services/class_provider.dart';
import 'package:ethiograde/services/settings_provider.dart';
import 'package:ethiograde/models/student.dart';
import 'package:ethiograde/config/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ethiograde_imp_test_');
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
    for (final name in ['students', 'assessments', 'settings_pii', 'metadata']) {
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

  Widget buildScreen({String? classId}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => StudentProvider()),
        ChangeNotifierProvider(create: (_) => ClassProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(
        home: ImportCsvScreen(classId: classId)),
    );
  }

  group('ImportCsvScreen — English', () {
    testWidgets('renders title and instructions', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Import Students'), findsOneWidget);
      expect(find.text('Instructions'), findsOneWidget);
      expect(find.textContaining('CSV file'), findsOneWidget);
      expect(find.textContaining('headers'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('shows select CSV file button', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Select CSV File'), findsOneWidget);
      expect(find.byIcon(Icons.upload_file), findsOneWidget);
    });

    testWidgets('shows add manually button', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Add Manually'), findsOneWidget);
      expect(find.byIcon(Icons.person_add), findsWidgets);
    });

    testWidgets('no students list shown initially', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Save All'), findsNothing);
    });
  });

  group('ImportCsvScreen — Manual Entry', () {
    testWidgets('opens manual entry sheet on tap', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Manually'));
      await tester.pumpAndSettle();

      // Bottom sheet should show form
      expect(find.text('New Student'), findsOneWidget);
      expect(find.text('Student ID (Roll No.) *'), findsOneWidget);
      expect(find.text('First Name'), findsWidgets);
      expect(find.text('Last Name'), findsWidgets);
      expect(find.text('Gender *'), findsOneWidget);
      expect(find.text('Male'), findsOneWidget);
      expect(find.text('Female'), findsOneWidget);
      expect(find.text('Add Student'), findsOneWidget);
    });

    testWidgets('validation: empty form shows errors', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Manually'));
      await tester.pumpAndSettle();

      // Tap Add Student without filling anything
      await tester.tap(find.text('Add Student'));
      await tester.pumpAndSettle();

      expect(find.text('Student ID is required'), findsOneWidget);
      expect(find.text('Required'), findsNWidgets(2)); // first + last name
    });

    testWidgets('validation: missing gender shows error', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Manually'));
      await tester.pumpAndSettle();

      // Fill student ID and names
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '001');
      await tester.enterText(fields.at(1), 'Abebe');
      await tester.enterText(fields.at(2), 'Kebede');

      // Don't select gender
      await tester.tap(find.text('Add Student'));
      await tester.pumpAndSettle();

      expect(find.text('Gender is required'), findsOneWidget);
    });

    testWidgets('validation: student ID too long', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Manually'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '123456789012345678901'); // 21 chars
      await tester.enterText(fields.at(1), 'Abebe');
      await tester.enterText(fields.at(2), 'Kebede');

      // Select gender
      await tester.tap(find.text('Male'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Student'));
      await tester.pumpAndSettle();

      expect(find.text('Max 20 characters'), findsOneWidget);
    });

    testWidgets('successful add: student appears in list', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Manually'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '001');
      await tester.enterText(fields.at(1), 'Abebe');
      await tester.enterText(fields.at(2), 'Kebede');

      await tester.tap(find.text('Male'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Student'));
      await tester.pumpAndSettle();

      // Sheet closes, student appears in list
      expect(find.text('Abebe Kebede'), findsOneWidget);
      expect(find.text('ID: 001'), findsOneWidget);
    });

    testWidgets('can remove imported student from list', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Manually'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '001');
      await tester.enterText(fields.at(1), 'Abebe');
      await tester.enterText(fields.at(2), 'Kebede');

      await tester.tap(find.text('Male'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Student'));
      await tester.pumpAndSettle();

      // Student is in list
      expect(find.text('Abebe Kebede'), findsOneWidget);

      // Remove student
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Abebe Kebede'), findsNothing);
    });

    testWidgets('save all shows count and snackbar', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // Add a student first
      await tester.tap(find.text('Add Manually'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '001');
      await tester.enterText(fields.at(1), 'Abebe');
      await tester.enterText(fields.at(2), 'Kebede');

      await tester.tap(find.text('Male'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Student'));
      await tester.pumpAndSettle();

      // Now save all
      expect(find.text('Save All'), findsOneWidget);

      await tester.tap(find.text('Save All'));
      await tester.pumpAndSettle();

      // Should show snackbar with count
      expect(find.textContaining('students saved'), findsOneWidget);
    });
  });
}
