import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ethiograde/widgets/language_toggle.dart';
import 'package:ethiograde/widgets/stat_card.dart';
import 'package:ethiograde/config/theme.dart';

void main() {
  Widget _wrapWithLocale(Widget child) {
    return MaterialApp(
      home: ChangeNotifierProvider(
        child: Scaffold(body: child)));
  }

  group('LanguageToggle', () {
    testWidgets('toggles to show EN text after tap', (tester) async {
      await tester.pumpWidget(_wrapWithLocale(const LanguageToggle()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(LanguageToggle));
      await tester.pumpAndSettle();

      // Now should show 'EN' to switch back
      expect(find.text('EN'), findsOneWidget);
    });

    testWidgets('has language icon', (tester) async {
      await tester.pumpWidget(_wrapWithLocale(const LanguageToggle()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.language), findsOneWidget);
    });
  });

  group('StatCard', () {
    testWidgets('renders label and value', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatCard(
              label: 'Students',
              value: '42',
              icon: Icons.people,
              color: AppTheme.primaryGreen))));
      await tester.pumpAndSettle();

      expect(find.text('Students'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('renders icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatCard(
              label: 'Tests',
              value: '10',
              icon: Icons.assignment,
              color: AppTheme.primaryYellow))));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.assignment), findsOneWidget);
    });
  });
}
