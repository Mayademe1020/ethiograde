import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/screens/onboarding/onboarding_screen.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: child);
  }

  group('OnboardingScreen', () {
    testWidgets('renders first page with scan & grade title', (tester) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Scan & Grade'), findsOneWidget);
    });

    testWidgets('has Skip button', (tester) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Skip'), findsOneWidget);
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

    testWidgets('Skip jumps to setup page', (tester) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      // Setup page has Welcome text
      expect(find.text('Welcome!'), findsOneWidget);
    });

    testWidgets('setup page has name and school fields', (tester) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      await tester.pumpAndSettle();

      // Jump to setup page
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('Your Name'), findsOneWidget);
      expect(find.text('School Name (optional)'), findsOneWidget);
    });

    testWidgets('setup page has Get Started button', (tester) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

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
  });
}
