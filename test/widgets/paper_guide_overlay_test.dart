import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/widgets/paper_guide_overlay.dart';

void main() {
  group('PaperGuideOverlay', () {
    /// Helper to wrap the overlay in a sized MaterialApp.
    Widget buildOverlay({
      required PaperGuideState state,
      required bool isAmharic,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 640,
            child: PaperGuideOverlay(
              state: state,
              isAmharic: isAmharic,
            ),
          ),
        ),
      );
    }

    testWidgets('renders CustomPaint in idle state', (tester) async {
      await tester.pumpWidget(buildOverlay(
        state: PaperGuideState.idle,
        isAmharic: false,
      ));

      expect(find.byType(CustomPaint), findsOneWidget);
    });

    testWidgets('shows English hint text in idle state', (tester) async {
      await tester.pumpWidget(buildOverlay(
        state: PaperGuideState.idle,
        isAmharic: false,
      ));

      expect(find.text('Align paper within the frame'), findsOneWidget);
    });

    testWidgets('shows Amharic hint text in idle state', (tester) async {
      await tester.pumpWidget(buildOverlay(
        state: PaperGuideState.idle,
        isAmharic: true,
      ));

      expect(find.text('ወረቀቱን በአገባቡ ያስተካክሉ'), findsOneWidget);
    });

    testWidgets('shows "Hold steady" when aligned (English)', (tester) async {
      await tester.pumpWidget(buildOverlay(
        state: PaperGuideState.aligned,
        isAmharic: false,
      ));

      expect(find.text('Hold steady'), findsOneWidget);
    });

    testWidgets('shows Amharic equivalent when aligned', (tester) async {
      await tester.pumpWidget(buildOverlay(
        state: PaperGuideState.aligned,
        isAmharic: true,
      ));

      expect(find.text('የያዙትን ይቆዩ'), findsOneWidget);
    });

    testWidgets('detected state shows align prompt', (tester) async {
      await tester.pumpWidget(buildOverlay(
        state: PaperGuideState.detected,
        isAmharic: false,
      ));

      expect(find.text('Align paper within the frame'), findsOneWidget);
    });

    testWidgets('renders without overflow on small screen', (tester) async {
      // Simulate a 320px wide low-end device
      tester.view.physicalSize = const Size(320 * 3, 568 * 3);
      tester.view.devicePixelRatio = 3.0;

      await tester.pumpWidget(buildOverlay(
        state: PaperGuideState.idle,
        isAmharic: false,
      ));

      expect(tester.takeException(), isNull);

      // Reset
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('all three states render without error', (tester) async {
      for (final state in PaperGuideState.values) {
        await tester.pumpWidget(buildOverlay(
          state: state,
          isAmharic: false,
        ));
        await tester.pump();

        expect(tester.takeException(), isNull,
            reason: 'State $state should not throw');
      }
    });
  });
}
