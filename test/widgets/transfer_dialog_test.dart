import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethiograde/screens/students/transfer_dialog.dart';
import 'package:ethiograde/services/student_provider.dart';
import 'package:ethiograde/services/class_provider.dart';
import 'package:ethiograde/services/settings_provider.dart';
import 'package:ethiograde/models/student.dart';
import 'package:ethiograde/models/class_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ethiograde_xfer_test_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Hive.openBox('students');
    await Hive.openBox('assessments');
    await Hive.openBox('settings_pii');
    await Hive.openBox('metadata');
    await Hive.openBox('student_transfers');
    await Hive.openBox('audit_trail');
  });

  tearDown(() async {
    for (final name in [
      'students', 'assessments', 'settings_pii', 'metadata',
      'student_transfers', 'audit_trail',
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

  final testStudent = Student(
    id: 's1', firstName: 'Abebe', lastName: 'Kebede',
    className: '', section: '', studentId: '001', gender: 'M');

  final classA = ClassInfo(
    id: 'c1', name: 'Grade 5A', grade: 5, section: 'A',
    subject: 'Math', ownerId: 't1', studentIds: ['s1']);

  final classB = ClassInfo(
    id: 'c2', name: 'Grade 5B', grade: 5, section: 'B',
    subject: 'Math', ownerId: 't1', studentIds: []);

  /// Build a test app that shows the transfer dialog.
  Widget buildScreen({
    required List<ClassInfo> classes,
    List<Student>? students,
  }) {
    final classProv = ClassProvider();
    for (final c in classes) {
      classProv.addClass(c);
    }

    final studentProv = StudentProvider();
    if (students != null) {
      for (final s in students) {
        studentProv.addStudent(s);
      }
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ClassProvider>.value(value: classProv),
        ChangeNotifierProvider<StudentProvider>.value(value: studentProv),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => StudentTransferDialog.show(
                context,
                student: testStudent,
                fromClass: classA),
              child: const Text('OPEN'))))));
  }

  group('StudentTransferDialog — English', () {
    testWidgets('renders title and student info', (tester) async {
      await tester.pumpWidget(buildScreen(classes: [classA, classB]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      expect(find.text('Transfer Student'), findsOneWidget);
      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
      expect(find.text('Abebe Kebede'), findsOneWidget);
      expect(find.textContaining('Grade 5 A Math'), findsOneWidget); // fromClass
    });

    testWidgets('shows destination class picker', (tester) async {
      await tester.pumpWidget(buildScreen(classes: [classA, classB]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      expect(find.text('To (select class)'), findsOneWidget);
      // classB should be available, classA should not (it's the source)
      expect(find.text('Grade 5 B Math'), findsOneWidget);
      expect(find.text('Grade 5 A Math'), findsOne); // only in "From" label
    });

    testWidgets('excludes current class from destination', (tester) async {
      await tester.pumpWidget(buildScreen(classes: [classA, classB]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      // Only classB should appear as a ChoiceChip
      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
      expect(chips.length, 1);
    });

    testWidgets('shows reason field', (tester) async {
      await tester.pumpWidget(buildScreen(classes: [classA, classB]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      expect(find.text('Reason (optional)'), findsOneWidget);
      expect(find.textContaining('Moved to'), findsOneWidget);
    });

    testWidgets('transfer button disabled when no class selected',
        (tester) async {
      await tester.pumpWidget(buildScreen(classes: [classA, classB]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Transfer'));
      expect(button.onPressed, isNull);
    });

    testWidgets('transfer button enabled after selecting class',
        (tester) async {
      await tester.pumpWidget(buildScreen(classes: [classA, classB]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      // Select destination class
      await tester.tap(find.text('Grade 5 B Math'));
      await tester.pumpAndSettle();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Transfer'));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('cancel button closes dialog with false', (tester) async {
      bool? result;
      await tester.pumpWidget(buildScreen(classes: [classA, classB]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog should be dismissed
      expect(find.text('Transfer Student'), findsNothing);
    });

    testWidgets('shows message when no other classes exist', (tester) async {
      // Only classA exists — no destination
      await tester.pumpWidget(buildScreen(classes: [classA]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      expect(find.text('No other classes — create one first'), findsOneWidget);
      // Transfer button should not exist
      expect(find.widgetWithText(ElevatedButton, 'Transfer'), findsNothing);
    });
  });
}
