import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/screens/scanning/camera_controls.dart';

void main() {
  Widget buildControls({
    bool isMasterKeyMode = false,
    bool isAutoCapture = false,
    List<String> capturedImages = const [],
    VoidCallback? onCapture,
    VoidCallback? onFinishBatch,
    VoidCallback? onToggleAutoCapture,
    VoidCallback? onToggleFlash,
    VoidCallback? onFlipCamera,
    VoidCallback? onPickUploaded,
    bool canFlipCamera = true,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: CameraControls(
          isCapturing: false,
          capturedImages: capturedImages,
          lastCaptureTitle: '',
          lastCaptureDetail: '',
          isMasterKeyMode: isMasterKeyMode,
          isAutoCapture: isAutoCapture,
          onCapture: onCapture ?? () {},
          onFinishBatch: onFinishBatch ?? () {},
          onViewCaptured: () {},
          onCaptureMasterKey: () {},
          onToggleAutoCapture: onToggleAutoCapture ?? () {},
          onToggleFlash: onToggleFlash ?? () {},
          isFlashTorchOn: false,
          canFlipCamera: canFlipCamera,
          onFlipCamera: onFlipCamera ?? () {},
          onPickUploaded: onPickUploaded ?? () {},
        ),
      ),
    );
  }

  group('CameraControls', () {
    testWidgets('batch mode shows shutter, import, flash, and flip buttons',
        (tester) async {
      await tester.pumpWidget(buildControls());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.camera), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);
      expect(find.text('Flash'), findsOneWidget);
      expect(find.text('Flip'), findsOneWidget);
    });

    testWidgets('batch mode shows Manual/Auto toggle', (tester) async {
      await tester.pumpWidget(buildControls());
      await tester.pumpAndSettle();

      expect(find.text('Manual'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
    });

    testWidgets('tapping capture invokes onCapture', (tester) async {
      var captured = false;
      await tester.pumpWidget(buildControls(onCapture: () => captured = true));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.camera));
      expect(captured, isTrue);
    });

    testWidgets('tapping import invokes onPickUploaded', (tester) async {
      var imported = false;
      await tester.pumpWidget(
        buildControls(onPickUploaded: () => imported = true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Import'));
      expect(imported, isTrue);
    });

    testWidgets('tapping flash invokes onToggleFlash', (tester) async {
      var toggled = false;
      await tester.pumpWidget(
        buildControls(onToggleFlash: () => toggled = true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Flash'));
      expect(toggled, isTrue);
    });

    testWidgets('tapping flip invokes onFlipCamera', (tester) async {
      var flipped = false;
      await tester.pumpWidget(
        buildControls(onFlipCamera: () => flipped = true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Flip'));
      expect(flipped, isTrue);
    });

    testWidgets('flip disabled when only one camera', (tester) async {
      var flipped = false;
      await tester.pumpWidget(
        buildControls(
          canFlipCamera: false,
          onFlipCamera: () => flipped = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Flip'));
      expect(flipped, isFalse);
    });

    testWidgets('done button fires when images captured', (tester) async {
      var finished = false;
      await tester.pumpWidget(
        buildControls(
          capturedImages: ['/tmp/fake.png'],
          onFinishBatch: () => finished = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Done'));
      expect(finished, isTrue);
    });

    testWidgets('master key mode shows shutter-style document icon',
        (tester) async {
      await tester.pumpWidget(buildControls(isMasterKeyMode: true));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.document_scanner_outlined), findsOneWidget);
    });
  });
}