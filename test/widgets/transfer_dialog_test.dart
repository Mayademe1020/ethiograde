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

  Widget buildDialog({
    required List<ClassInfo> classes,
  }) {
    final classProv = ClassProvider();
    for (final c in classes) {
      classProv.addClass(c);
    }

    final studentProv = StudentProvider();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ClassProvider>.value(value: classProv),
        ChangeNotifierProvider<StudentProvider>.value(value: studentProv),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              StudentTransferDialog.show(
                context,
                student: testStudent,
                fromClass: classA,
              );
            });
            return const Scaffold();
          },
        ),
      ),
    );
  }

  group('StudentTransferDialog — English', () {
    testWidgets('renders title', (tester) async {
      await tester.pumpWidget(buildDialog(classes: [classA, classB]));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Transfer Student'), findsOneWidget);
      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    });

    testWidgets('shows destination class picker', (tester) async {
      await tester.pumpWidget(buildDialog(classes: [classA, classB]));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.byType(ChoiceChip), findsOneWidget);
    }, skip: true);

    testWidgets('excludes current class from destination', (tester) async {
      await tester.pumpWidget(buildDialog(classes: [classA, classB]));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
      expect(chips.length, 1);
    }, skip: true);

    testWidgets('shows reason field', (tester) async {
      await tester.pumpWidget(buildDialog(classes: [classA, classB]));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
    }, skip: true);

    testWidgets('transfer button disabled when no class selected',
        (tester) async {
      await tester.pumpWidget(buildDialog(classes: [classA, classB]));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Transfer'));
      expect(button.onPressed, isNull);
    }, skip: true);

    testWidgets('transfer button enabled after selecting class',
        (tester) async {
      await tester.pumpWidget(buildDialog(classes: [classA, classB]));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      await tester.tap(find.byType(ChoiceChip));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Transfer'));
      expect(button.onPressed, isNotNull);
    }, skip: true);

    testWidgets('cancel button closes dialog', (tester) async {
      await tester.pumpWidget(buildDialog(classes: [classA, classB]));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('Transfer Student'), findsNothing);
    });

    testWidgets('shows message when no other classes exist', (tester) async {
      await tester.pumpWidget(buildDialog(classes: [classA]));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('No other classes — create one first'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Transfer'), findsNothing);
    });
  });
}
