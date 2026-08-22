import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/screens/scanning/camera_processor.dart';
import 'package:ethiograde/widgets/paper_guide_overlay.dart';

void main() {
  group('CameraProcessor', () {
    late List<PaperGuideState> guideStates;
    late List<String?> feedbackTexts;

    CameraProcessor buildProcessor() {
      guideStates = [];
      feedbackTexts = [];
      return CameraProcessor(
        callbacks: CameraProcessorCallbacks(
          onCapturingChanged: (_) {},
          onCaptureFeedbackChanged: (_, __) {},
          onGuideStateChanged: (s) => guideStates.add(s),
          onBatchChanged: (_, __) {},
          onAutoGradedResultsChanged: (_) {},
          onBatchStartedChanged: (_) {},
          onShowDuplicateDialog: () async => true,
          onFeedbackTextChanged: (t) => feedbackTexts.add(t),
        ),
      );
    }

    test('auto-capture defaults to off (manual mode)', () {
      final processor = buildProcessor();
      expect(processor.autoCaptureEnabled, isFalse);
    });

    test('toggleAutoCapture flips the flag both directions', () {
      final processor = buildProcessor();

      processor.toggleAutoCapture(null);
      expect(processor.autoCaptureEnabled, isTrue);

      processor.toggleAutoCapture(null);
      expect(processor.autoCaptureEnabled, isFalse);
    });

    test('disabling auto-capture resets guide state to idle', () {
      final processor = buildProcessor();
      processor.toggleAutoCapture(null); // on
      processor.toggleAutoCapture(null); // off

      expect(guideStates, contains(PaperGuideState.idle));
      expect(feedbackTexts, contains('Manual mode \u2014 tap to capture'));
    });

    test('startFrameObservation is safe with a null controller', () {
      final processor = buildProcessor();
      processor.startFrameObservation(null);
      processor.startFrameObservation(null);
      // No exception thrown; auto-capture flag unchanged.
      expect(processor.autoCaptureEnabled, isFalse);
    });
  });
}