import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

import 'package:ethiograde/screens/analytics/analytics_screen.dart';
import 'package:ethiograde/screens/sms/sms_compose_screen.dart';
import 'package:ethiograde/screens/sms/sms_history_screen.dart';
import 'package:ethiograde/services/assessment_provider.dart';
import 'package:ethiograde/services/student_provider.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('sms_screens_test_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    await Hive.openBox('students');
    await Hive.openBox('assessments');
    await Hive.openBox('sms_history');
    await Hive.openBox('scan_results');
    await Hive.openBox('metadata');
  });

  tearDown(() async {
    for (final name in [
      'students',
      'assessments',
      'sms_history',
      'scan_results',
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

  Widget wrap(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => StudentProvider()),
        ChangeNotifierProvider(create: (_) => AssessmentProvider()),
      ],
      child: MaterialApp(home: child),
    );
  }

  /// Let real async Hive I/O started by the widget complete outside the
  /// fake-async zone, then rebuild.
  Future<void> settleIoScreen(WidgetTester tester) async {
    await tester.pumpWidget(wrap(const SmsHistoryScreen()));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }

  group('SmsHistoryScreen', () {
    testWidgets('shows empty state when no history', (tester) async {
      await settleIoScreen(tester);

      expect(find.text('SMS History'), findsOneWidget);
      expect(find.text('No SMS history'), findsOneWidget);
    });

    testWidgets('lists logged messages', (tester) async {
      await tester.runAsync(() async {
        final box = Hive.box('sms_history');
        await box.put('1', {
          'id': '1',
          'studentName': 'Abebe',
          'phoneNumber': '+251911234567',
          'message': 'Abebe scored 85.0% in Math. - School',
          'templateName': 'Result Notification',
          'success': true,
          'errorMessage': null,
          'sentAt': DateTime(2026, 1, 15, 10, 0).toIso8601String(),
        });
      });

      await settleIoScreen(tester);

      expect(find.text('Abebe'), findsOneWidget);
      expect(find.textContaining('85.0%'), findsOneWidget);
      expect(find.textContaining('+251911234567'), findsOneWidget);
    });

    testWidgets('clears history via dialog', (tester) async {
      await tester.runAsync(() async {
        final box = Hive.box('sms_history');
        await box.put('1', {
          'id': '1',
          'studentName': 'Abebe',
          'phoneNumber': '+251911234567',
          'message': 'hi',
          'templateName': 'Result Notification',
          'success': true,
          'errorMessage': null,
          'sentAt': DateTime(2026, 1, 15, 10, 0).toIso8601String(),
        });
      });

      await settleIoScreen(tester);
      expect(find.text('Abebe'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_sweep));
      await tester.pumpAndSettle();
      expect(find.text('Clear History'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Abebe'), findsOneWidget);
      expect(find.text('Clear History'), findsNothing);
    });
  });

  group('SmsComposeScreen', () {
    testWidgets('renders template picker and send button', (tester) async {
      await tester.pumpWidget(wrap(const SmsComposeScreen()));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Send Parent SMS'), findsOneWidget);
      expect(find.text('Result Notification'), findsOneWidget);
      expect(find.text('At-Risk Warning'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Amharic'), findsOneWidget);
    });

    testWidgets('shows no-recipients message without student data', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const SmsComposeScreen()));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No students with parent phone numbers found.'),
        findsOneWidget,
      );
    });
  });

  group('AnalyticsScreen', () {
    testWidgets('shows empty state without assessments', (tester) async {
      await tester.pumpWidget(wrap(const AnalyticsScreen()));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Class Analytics'), findsOneWidget);
      expect(
        find.textContaining('No assessments yet'),
        findsOneWidget,
      );
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('At-Risk'), findsOneWidget);
      expect(find.text('Trends'), findsOneWidget);
    });

    testWidgets('switches tabs', (tester) async {
      await tester.pumpWidget(wrap(const AnalyticsScreen()));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('At-Risk'));
      await tester.pumpAndSettle();
      expect(find.text('At-Risk'), findsOneWidget);

      await tester.tap(find.text('Trends'));
      await tester.pumpAndSettle();
      expect(find.text('Trends'), findsOneWidget);
    });
  });

  group('SmsLogEntry', () {
    test('serializes and deserializes', () {
      final e = SmsLogEntry(
        id: 'e1',
        studentName: 'Sara',
        phoneNumber: '+251900000000',
        message: 'hello',
        templateName: 't',
        success: true,
        sentAt: DateTime(2026, 1, 1),
      );
      final restored = SmsLogEntry.fromMap(e.toMap());
      expect(restored.id, e.id);
      expect(restored.studentName, 'Sara');
      expect(restored.phoneNumber, '+251900000000');
      expect(restored.sentAt, DateTime(2026, 1, 1));
    });
  });
}