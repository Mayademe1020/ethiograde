import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethiograde/services/class_provider.dart';
import 'package:ethiograde/services/student_provider.dart';
import 'package:ethiograde/services/settings_provider.dart';
import 'package:ethiograde/screens/students/transfer_dialog.dart';
import 'package:ethiograde/models/student.dart';
import 'package:ethiograde/models/class_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ethiograde_xfer_test6_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Hive.openBox('students');
    await Hive.openBox('classes');
  });

  tearDown(() async {
    for (final name in ['students', 'classes']) {
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

  group('StudentTransferDialog', () {
    testWidgets('renders title', (tester) async {
      final classProv = ClassProvider();
      // Add classes via async addClass — real Hive file I/O must run in
      // runAsync, otherwise it deadlocks inside the FakeAsync test zone.
      await tester.runAsync(() async {
        await classProv.addClass(classA);
        await classProv.addClass(classB);
      });
      await tester.pump();

      final studentProv = StudentProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ClassProvider>.value(value: classProv),
            ChangeNotifierProvider<StudentProvider>.value(value: studentProv),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => StudentTransferDialog.show(
                    context,
                    student: testStudent,
                    fromClass: classA,
                  ),
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Transfer Student'), findsOneWidget);
    });

    testWidgets('shows ChoiceChip', (tester) async {
      final classProv = ClassProvider();
      await tester.runAsync(() async {
        await classProv.addClass(classA);
        await classProv.addClass(classB);
      });
      await tester.pump();

      final studentProv = StudentProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ClassProvider>.value(value: classProv),
            ChangeNotifierProvider<StudentProvider>.value(value: studentProv),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => StudentTransferDialog.show(
                    context,
                    student: testStudent,
                    fromClass: classA,
                  ),
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      expect(find.byType(ChoiceChip), findsOneWidget);
    });

    testWidgets('cancel closes dialog', (tester) async {
      final classProv = ClassProvider();
      await tester.runAsync(() async {
        await classProv.addClass(classA);
        await classProv.addClass(classB);
      });
      await tester.pump();

      final studentProv = StudentProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ClassProvider>.value(value: classProv),
            ChangeNotifierProvider<StudentProvider>.value(value: studentProv),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => StudentTransferDialog.show(
                    context,
                    student: testStudent,
                    fromClass: classA,
                  ),
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Transfer Student'), findsNothing);
    });
  });
}
