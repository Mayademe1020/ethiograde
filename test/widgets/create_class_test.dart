import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethiograde/screens/classes/create_class_sheet.dart';
import 'package:ethiograde/services/class_provider.dart';
import 'package:ethiograde/services/settings_provider.dart';
import 'package:ethiograde/services/teacher_provider.dart';
import 'package:ethiograde/models/teacher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('ethiograde_createclass_test_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Hive.openBox('students');
    await Hive.openBox('classes');
    await Hive.openBox('teachers');
    await Hive.openBox('settings_pii');
  });

  tearDown(() async {
    for (final name in ['students', 'classes', 'teachers', 'settings_pii']) {
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

  Future<TeacherProvider> seedTeacher(List<String> subjects) async {
    final provider = TeacherProvider();
    await provider.addTeacher(Teacher(name: 'Aster', subjects: subjects));
    return provider;
  }

  Widget wrap(TeacherProvider teachers, SettingsProvider settings) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ClassProvider()),
        ChangeNotifierProvider(create: (_) => teachers),
        ChangeNotifierProvider(create: (_) => settings),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  await CreateClassSheet.show(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openSheet(
    WidgetTester tester,
    TeacherProvider teachers,
    SettingsProvider settings,
  ) async {
    await tester.pumpWidget(wrap(teachers, settings));
    await tester.pump();

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('defaults Section A and single-teacher subject', (tester) async {
    late TeacherProvider teachers;
    late SettingsProvider settings;
    await tester.runAsync(() async {
      teachers = await seedTeacher(['Mathematics']);
      settings = SettingsProvider();
      await settings.loadSettings();
      await settings.setAcademicYear('2025-2026');
    });

    await openSheet(tester, teachers, settings);

    expect(find.text('Section A'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Mathematics'), findsOneWidget);
  });

  testWidgets('leaves subject empty when teacher has multiple subjects',
      (tester) async {
    late TeacherProvider teachers;
    late SettingsProvider settings;
    await tester.runAsync(() async {
      teachers = await seedTeacher(['Mathematics', 'English']);
      settings = SettingsProvider();
      await settings.loadSettings();
      await settings.setAcademicYear('2025-2026');
    });

    await openSheet(tester, teachers, settings);

    expect(find.text('Section A'), findsOneWidget);
    final subjectField = tester.widget<TextField>(find.byType(TextField).last);
    expect(subjectField.controller?.text, isEmpty);
  });
}