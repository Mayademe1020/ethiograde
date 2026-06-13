import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ethiograde/widgets/stat_card.dart';
import 'package:ethiograde/config/theme.dart';

void main() {
  Widget _wrapWithLocale(Widget child) {
    return MaterialApp(
      home: Scaffold(body: child));
  }

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
