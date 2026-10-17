import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ethiograde/config/routes.dart';
import 'package:ethiograde/screens/onboarding/onboarding_screen.dart';
import 'package:ethiograde/services/settings_provider.dart';
import 'package:ethiograde/services/teacher_provider.dart';
import 'package:ethiograde/services/class_provider.dart';
import 'package:ethiograde/services/student_provider.dart';
import 'package:ethiograde/services/assessment_provider.dart';

void main() {
  Widget wrap(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => TeacherProvider()),
        ChangeNotifierProvider(create: (_) => ClassProvider()..loadClasses()),
        ChangeNotifierProvider(create: (_) => StudentProvider()),
        ChangeNotifierProvider(create: (_) => AssessmentProvider()),
      ],
      child: MaterialApp(
        home: child,
        onGenerateRoute: (settings) {
          if (settings.name == AppRoutes.dashboard) {
            return MaterialPageRoute<void>(
              builder: (_) =>
                  const Scaffold(body: Center(child: Text('DASHBOARD'))),
            );
          }
          return null;
        },
      ),
    );
  }

  group('OnboardingScreen', () {
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('ethiograde_onboard_');
      Hive.init(tempDir.path);
      // Pre-open the boxes _completeSetup touches so it uses the in-memory
      // registry instead of real disk I/O (which hangs under FakeAsync).
      for (final name in [
        'settings_pii',
        'scan_results',
        'classes',
        'students',
        'assessments',
        'teachers',
      ]) {
        if (!Hive.isBoxOpen(name)) {
          await Hive.openBox(name);
        }
      }
    });

    tearDown(() async {
      await Hive.close();
      await tempDir.delete(recursive: true);
    });
    testWidgets('renders first page with scan & grade title', (tester) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Scan & Grade'), findsOneWidget);
    });

    testWidgets('has Next button', (tester) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('navigates to next page on Next tap', (tester) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      await tester.pumpAndSettle();

      // First page
      expect(find.text('Scan & Grade'), findsOneWidget);

      // Tap Next
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      // Second page
    });

    testWidgets('shows Back button on second page', (tester) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      await tester.pumpAndSettle();

      // Navigate to page 2
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('setup page has name and school fields', (tester) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      await tester.pumpAndSettle();

      // Navigate to setup page via Next
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }

      expect(find.text('Your Name'), findsOneWidget);
      expect(find.text('School Name (optional)'), findsOneWidget);
    });

    testWidgets('Get Started without a name shows an error', (tester) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      await tester.pumpAndSettle();

      // Navigate to the setup page via Next so the name stays empty.
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();

      // Still on onboarding — not the dashboard — with a validation error.
      expect(find.text('Please enter your name'), findsOneWidget);
      expect(find.text('DASHBOARD'), findsNothing);
    });

    testWidgets('Get Started with a name finishes setup', (tester) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      await tester.pumpAndSettle();

      // Navigate to setup page and enter a name.
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }

      await tester.enterText(
        find.widgetWithText(TextField, 'Your Name'),
        'Abebe',
      );
      // _completeSetup does real Hive I/O, so run the whole interaction
      // inside runAsync where those futures can actually complete.
      await tester.runAsync(() async {
        await tester.tap(find.text('Get Started'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pumpAndSettle();

      // Lands on the dashboard route.
      expect(find.text('DASHBOARD'), findsOneWidget);
      expect(find.text('Please enter your name'), findsNothing);
      expect(find.text('Welcome!'), findsNothing);
    });

    testWidgets('setup page has Get Started button', (tester) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      await tester.pumpAndSettle();

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }

      expect(find.text('Get Started'), findsOneWidget);
    });

    testWidgets('dot indicator shows correct number of pages', (tester) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      await tester.pumpAndSettle();

      // 4 info pages + 1 setup page = 5 dots
      // AnimatedContainers are used for dots
      expect(find.byType(AnimatedContainer), findsNWidgets(5));
    });

    testWidgets('does not overflow on a narrow phone', (tester) async {
      tester.view.physicalSize = const Size(360, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(wrap(const OnboardingScreen()));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final ex = tester.takeException();
      expect(ex, isNull, reason: 'Onboarding overflowed at 360x360: $ex');
    });

    testWidgets(
      'academic year selector renders with a selectable chip',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final settings = SettingsProvider();
        // Seed a current year so the chip is visible & preselected.
        // Hive I/O must run inside runAsync or it never resolves under the
        // test's virtual clock (same as _completeSetup does).
        await tester.runAsync(() async {
          await settings.setAcademicYear('2026-2027');
        });

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsProvider>.value(value: settings),
              ChangeNotifierProvider(create: (_) => TeacherProvider()),
              ChangeNotifierProvider(create: (_) => ClassProvider()..loadClasses()),
              ChangeNotifierProvider(create: (_) => StudentProvider()),
              ChangeNotifierProvider(create: (_) => AssessmentProvider()),
            ],
            child: MaterialApp(
              home: const OnboardingScreen(),
              onGenerateRoute: (s) {
                if (s.name == AppRoutes.dashboard) {
                  return MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Center(child: Text('DASHBOARD'))),
                  );
                }
                return null;
              },
            ),
          ),
        );
        // The Academic Year section lives on the final setup page.
        for (var i = 0; i < 4; i++) {
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
        }

        expect(find.text('Academic Year'), findsOneWidget);
        // The seeded year is shown as a selectable chip.
        expect(find.text('2026-2027'), findsOneWidget);
      },
    );
  });
}
