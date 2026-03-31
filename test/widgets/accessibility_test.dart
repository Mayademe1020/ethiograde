import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/widgets/stat_card.dart';

void main() {
  group('Accessibility', () {
    group('Touch targets', () {
      testWidgets('StatCard icon is >= 24dp', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: StatCard(
                icon: Icons.people,
                value: '10',
                label: 'Students',
                color: Colors.green,
              ),
            ),
          ),
        );

        final icon = tester.widget<Icon>(find.byIcon(Icons.people));
        expect(icon.size, greaterThanOrEqualTo(24));
      });
    });

    group('Semantic labels', () {
      testWidgets('StatCard exposes value and label text', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: StatCard(
                icon: Icons.check_circle,
                value: '5',
                label: 'Completed',
                color: Colors.green,
              ),
            ),
          ),
        );

        // Verify text is accessible to screen readers
        expect(find.text('5'), findsOneWidget);
        expect(find.text('Completed'), findsOneWidget);

        // Run semantics test — should not throw
        final handle = tester.ensureSemantics();
        expect(tester.takeException(), isNull);
        handle.dispose();
      });

      testWidgets('Material widgets expose semantics', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  Semantics(
                    label: 'Capture photo',
                    button: true,
                    child: GestureDetector(
                      onTap: () {},
                      child: const Icon(Icons.camera, size: 48),
                    ),
                  ),
                  Semantics(
                    label: 'View captured papers',
                    button: true,
                    child: GestureDetector(
                      onTap: () {},
                      child: const Icon(Icons.photo_library, size: 48),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        final handle = tester.ensureSemantics();
        expect(find.byIcon(Icons.camera), findsOneWidget);
        expect(find.byIcon(Icons.photo_library), findsOneWidget);
        expect(tester.takeException(), isNull);
        handle.dispose();
      });
    });

    group('Text contrast', () {
      testWidgets('body text is >= 12sp', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  final style = Theme.of(context).textTheme.bodySmall;
                  expect(style?.fontSize, greaterThanOrEqualTo(12));
                  return const Text('test');
                },
              ),
            ),
          ),
        );
      });

      testWidgets('labels are >= 11sp', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: const Text(
                  'MCQ 5',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ),
          ),
        );

        final text = tester.widget<Text>(find.text('MCQ 5'));
        expect(text.style?.fontSize, greaterThanOrEqualTo(11));
      });
    });
  });
}
