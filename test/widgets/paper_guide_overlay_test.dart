import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/widgets/paper_guide_overlay.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('PaperGuideOverlay', () {
    testWidgets('renders hint text for every state', (tester) async {
      const states = {
        PaperGuideState.idle: 'Place paper inside the frame',
        PaperGuideState.detected: 'Align paper within the frame',
        PaperGuideState.aligned: 'Hold steady \u2014 preparing to capture',
        PaperGuideState.tooDark: 'Too dark \u2014 use flash or more light',
        PaperGuideState.moving: 'Hold still',
        PaperGuideState.outsideFrame: 'Move paper into the frame',
      };

      for (final entry in states.entries) {
        await tester.pumpWidget(
          wrap(PaperGuideOverlay(state: entry.key)),
        );
        await tester.pump();
        expect(
          find.text(entry.value),
          findsOneWidget,
          reason: 'expected hint for ${entry.key}',
        );
      }
    });

    testWidgets('renders feedback text when provided', (tester) async {
      await tester.pumpWidget(
        wrap(
          const PaperGuideOverlay(
            state: PaperGuideState.detected,
            feedbackText: 'Move closer',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Move closer'), findsOneWidget);
    });

    testWidgets('shows countdown display during countdown', (tester) async {
      await tester.pumpWidget(
        wrap(
          const PaperGuideOverlay(
            state: PaperGuideState.aligned,
            countdown: 2,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('shows Turn on flash button when too dark', (tester) async {
      var flashTapped = false;
      await tester.pumpWidget(
        wrap(
          PaperGuideOverlay(
            state: PaperGuideState.tooDark,
            onEnableFlash: () => flashTapped = true,
          ),
        ),
      );
      await tester.pump();

      final button = find.text('Turn on flash');
      expect(button, findsOneWidget);
      await tester.tap(button);
      expect(flashTapped, isTrue);
    });

    testWidgets('hides Turn on flash button when not too dark', (tester) async {
      await tester.pumpWidget(
        wrap(
          PaperGuideOverlay(
            state: PaperGuideState.aligned,
            onEnableFlash: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Turn on flash'), findsNothing);
    });

    testWidgets('idle state without callback shows no flash button',
        (tester) async {
      await tester.pumpWidget(
        wrap(const PaperGuideOverlay(state: PaperGuideState.idle)),
      );
      await tester.pump();
      expect(find.text('Turn on flash'), findsNothing);
    });
  });
}