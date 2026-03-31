import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ethiograde/widgets/language_toggle.dart';
import 'package:ethiograde/services/locale_provider.dart';

void main() {
  group('LanguageToggle', () {
    /// Helper that wraps the toggle in MaterialApp + Provider.
    Widget buildToggle(LocaleProvider localeProvider) {
      return MaterialApp(
        home: ChangeNotifierProvider<LocaleProvider>.value(
          value: localeProvider,
          child: const Scaffold(
            body: LanguageToggle(),
          ),
        ),
      );
    }

    testWidgets('shows Amharic label in English mode', (tester) async {
      final locale = LocaleProvider();
      // Force English mode (default)
      await tester.pumpWidget(buildToggle(locale));
      await tester.pumpAndSettle();

      // In English mode, toggle should show "አማ" to switch TO Amharic
      expect(find.text('አማ'), findsOneWidget);
    });

    testWidgets('shows English label in Amharic mode', (tester) async {
      final locale = LocaleProvider();
      // Force to Amharic
      await locale.setLocale('am');
      await tester.pumpWidget(buildToggle(locale));
      await tester.pumpAndSettle();

      // In Amharic mode, toggle should show "EN" to switch TO English
      expect(find.text('EN'), findsOneWidget);
    });

    testWidgets('tapping toggles locale', (tester) async {
      final locale = LocaleProvider();
      await tester.pumpWidget(buildToggle(locale));
      await tester.pumpAndSettle();

      // Starts in English
      expect(find.text('አማ'), findsOneWidget);
      expect(locale.isAmharic, isFalse);

      // Tap to switch to Amharic
      await tester.tap(find.byType(LanguageToggle));
      await tester.pumpAndSettle();

      expect(locale.isAmharic, isTrue);
      expect(find.text('EN'), findsOneWidget);
    });

    testWidgets('renders language icon', (tester) async {
      final locale = LocaleProvider();
      await tester.pumpWidget(buildToggle(locale));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.language), findsOneWidget);
    });

    testWidgets('has animated container', (tester) async {
      final locale = LocaleProvider();
      await tester.pumpWidget(buildToggle(locale));
      await tester.pumpAndSettle();

      // Verify AnimatedContainer exists (animation on toggle)
      expect(find.byType(AnimatedContainer), findsOneWidget);
    });
  });
}
