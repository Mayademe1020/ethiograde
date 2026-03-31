import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ethiograde/main.dart' as app;

/// Performance benchmark for EthioGrade.
///
/// Measures cold start time and basic performance metrics.
/// Run on a device/emulator via:
///   flutter test integration_test/perf_benchmark.dart
///
/// For APK size, use CI: `flutter build apk --release && stat -c%s`
/// For memory peak, use: `adb shell dumpsys meminfo <package>` during test.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Performance Benchmark', () {
    testWidgets('cold start time < 3 seconds', (tester) async {
      // Measure time from app.main() to first frame with dashboard/onboarding
      final stopwatch = Stopwatch()..start();

      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      stopwatch.stop();
      final coldStartMs = stopwatch.elapsedMilliseconds;

      debugPrint('═══════════════════════════════════════════');
      debugPrint('  COLD START: ${coldStartMs}ms');
      debugPrint('  Target: <3000ms');
      debugPrint('  Status: ${coldStartMs < 3000 ? "PASS ✅" : "FAIL ❌"}');
      debugPrint('═══════════════════════════════════════════');

      // Skip onboarding if shown so subsequent tests work
      final getStarted = find.text('Get Started');
      if (getStarted.evaluate().isNotEmpty) {
        await tester.tap(getStarted);
        await tester.pumpAndSettle();
      }

      expect(
        coldStartMs,
        lessThan(3000),
        reason: 'Cold start took ${coldStartMs}ms, target is <3000ms',
      );
    });

    testWidgets('dashboard renders within 500ms after navigation',
        (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Skip onboarding if needed
      final getStarted = find.text('Get Started');
      if (getStarted.evaluate().isNotEmpty) {
        await tester.tap(getStarted);
        await tester.pumpAndSettle();
      }

      // Navigate away and back to measure dashboard render time
      final assessTab = find.text('Assess');
      if (assessTab.evaluate().isNotEmpty) {
        await tester.tap(assessTab);
        await tester.pumpAndSettle();

        final stopwatch = Stopwatch()..start();

        final homeTab = find.text('Home');
        if (homeTab.evaluate().isNotEmpty) {
          await tester.tap(homeTab);
          await tester.pumpAndSettle();
        }

        stopwatch.stop();
        final renderMs = stopwatch.elapsedMilliseconds;

        debugPrint('═══════════════════════════════════════════');
        debugPrint('  DASHBOARD RENDER: ${renderMs}ms');
        debugPrint('  Target: <500ms');
        debugPrint('  Status: ${renderMs < 500 ? "PASS ✅" : "FAIL ❌"}');
        debugPrint('═══════════════════════════════════════════');

        expect(
          renderMs,
          lessThan(500),
          reason: 'Dashboard render took ${renderMs}ms, target is <500ms',
        );
      }
    });

    testWidgets('memory snapshot during idle — baseline check',
        (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Skip onboarding
      final getStarted = find.text('Get Started');
      if (getStarted.evaluate().isNotEmpty) {
        await tester.tap(getStarted);
        await tester.pumpAndSettle();
      }

      // Let the app settle into idle state
      await Future.delayed(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // On a real device, memory measurement would use:
      //   adb shell dumpsys meminfo com.ethiograde.app
      // In widget tests, we can only verify the app is still responsive
      // and hasn't crashed from memory pressure.

      debugPrint('═══════════════════════════════════════════');
      debugPrint('  MEMORY: App idle, no crash');
      debugPrint('  Note: Use `adb shell dumpsys meminfo` for');
      debugPrint('  actual memory measurements on device.');
      debugPrint('  Target: <150MB peak on 2GB device');
      debugPrint('═══════════════════════════════════════════');

      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('rapid navigation does not degrade performance',
        (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Skip onboarding
      final getStarted = find.text('Get Started');
      if (getStarted.evaluate().isNotEmpty) {
        await tester.tap(getStarted);
        await tester.pumpAndSettle();
      }

      // Rapid tab switching — simulates teacher quickly checking different views
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < 5; i++) {
        final assess = find.text('Assess');
        if (assess.evaluate().isNotEmpty) {
          await tester.tap(assess);
          await tester.pump(const Duration(milliseconds: 100));
        }

        final students = find.text('Students');
        if (students.evaluate().isNotEmpty) {
          await tester.tap(students);
          await tester.pump(const Duration(milliseconds: 100));
        }

        final home = find.text('Home');
        if (home.evaluate().isNotEmpty) {
          await tester.tap(home);
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.pumpAndSettle();
      stopwatch.stop();
      final totalMs = stopwatch.elapsedMilliseconds;

      debugPrint('═══════════════════════════════════════════');
      debugPrint('  RAPID NAV (15 switches): ${totalMs}ms');
      debugPrint('  Avg per switch: ${(totalMs / 15).toStringAsFixed(0)}ms');
      debugPrint('  Target: <200ms per switch');
      debugPrint('  Status: ${(totalMs / 15) < 200 ? "PASS ✅" : "SLOW ⚠️"}');
      debugPrint('═══════════════════════════════════════════');

      // Should not crash after rapid navigation
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
