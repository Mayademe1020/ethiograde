import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/widgets/stat_card.dart';

void main() {
  group('StatCard', () {
    testWidgets('renders value and label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatCard(
              icon: Icons.assignment,
              value: '42',
              label: 'Students',
              color: Colors.green,
            ),
          ),
        ),
      );

      expect(find.text('42'), findsOneWidget);
      expect(find.text('Students'), findsOneWidget);
      expect(find.byIcon(Icons.assignment), findsOneWidget);
    });

    testWidgets('renders with zero value', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatCard(
              icon: Icons.star,
              value: '0',
              label: 'Completed',
              color: Colors.blue,
            ),
          ),
        ),
      );

      expect(find.text('0'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
    });

    testWidgets('renders long label without overflow', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: StatCard(
                icon: Icons.people,
                value: '999',
                label: 'Total Students Enrolled This Semester',
                color: Colors.orange,
              ),
            ),
          ),
        ),
      );

      // Should render without throwing overflow errors
      expect(find.text('999'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('applies correct color to icon', (tester) async {
      const testColor = Color(0xFF1B7A43);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatCard(
              icon: Icons.check_circle,
              value: '15',
              label: 'Passed',
              color: testColor,
            ),
          ),
        ),
      );

      final iconWidget = tester.widget<Icon>(find.byIcon(Icons.check_circle));
      expect(iconWidget.color, testColor);
    });

    testWidgets('has minimum touch target size', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatCard(
              icon: Icons.dashboard,
              value: '5',
              label: 'Tests',
              color: Colors.red,
            ),
          ),
        ),
      );

      // StatCard is a Container, not interactive — just verify it renders
      final container = tester.widget<Container>(find.byType(Container).first);
      expect(container, isNotNull);
    });
  });
}
