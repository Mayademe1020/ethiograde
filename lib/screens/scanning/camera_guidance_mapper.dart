import 'package:flutter/material.dart';
import '../../widgets/paper_guide_overlay.dart';
import '../../models/assessment.dart';

/// Computes camera guidance text, detail, and icon based on scan state.
class CameraGuidanceMapper {
  final bool isCapturing;
  final PaperGuideState guideState;
  final bool isFlashOn;
  final bool autoCaptureEnabled;
  final Assessment? selectedAssessment;
  final bool isReScanMode;
  final int capturedCount;

  const CameraGuidanceMapper({
    required this.isCapturing,
    required this.guideState,
    required this.isFlashOn,
    required this.autoCaptureEnabled,
    required this.selectedAssessment,
    required this.isReScanMode,
    required this.capturedCount,
  });

  String get titleText {
    if (isReScanMode) return 'Re-Scan';
    if (selectedAssessment != null) return selectedAssessment!.title;
    return 'Choose assessment';
  }

  String get subtitleText {
    if (isReScanMode) return 'Review before saving';
    if (selectedAssessment == null) return 'Select an active assessment';
    final keyStatus = selectedAssessment!.isAnswerKeyComplete
        ? 'Answer key ready'
        : 'Answer key needed';
    return '$keyStatus · $capturedCount papers captured';
  }

  String get guidanceTitle {
    if (isCapturing) return 'Capturing paper';
    switch (guideState) {
      case PaperGuideState.idle:
        return 'Place paper inside the frame';
      case PaperGuideState.detected:
        return 'Almost there';
      case PaperGuideState.aligned:
        return 'Hold steady';
      case PaperGuideState.tooDark:
        return 'Too dark';
      case PaperGuideState.moving:
        return 'Hold still';
      case PaperGuideState.outsideFrame:
        return 'Move paper into the frame';
    }
  }

  String get guidanceDetail {
    if (isCapturing) return 'Keep the phone steady until capture finishes.';
    switch (guideState) {
      case PaperGuideState.idle:
        return isFlashOn
            ? 'Flash is on. Align the full paper before capture.'
            : 'Align the full paper. Tap flash if the room is dark.';
      case PaperGuideState.detected:
        return 'Straighten the paper so all corners are inside the guide.';
      case PaperGuideState.aligned:
        return autoCaptureEnabled
            ? 'Paper looks ready. Auto capture will take it.'
            : 'Paper looks ready. Tap capture when you are ready.';
      case PaperGuideState.tooDark:
        return 'Turn on flash or move to better light before capture.';
      case PaperGuideState.moving:
        return 'Wait for the paper and phone to stop moving.';
      case PaperGuideState.outsideFrame:
        return 'Move the paper until all edges fit inside the guide.';
    }
  }

  IconData get guidanceIcon {
    if (isCapturing) return Icons.camera;
    switch (guideState) {
      case PaperGuideState.idle:
        return Icons.center_focus_strong;
      case PaperGuideState.detected:
      case PaperGuideState.outsideFrame:
        return Icons.crop_free;
      case PaperGuideState.aligned:
        return Icons.check_circle_outline;
      case PaperGuideState.tooDark:
        return Icons.light_mode_outlined;
      case PaperGuideState.moving:
        return Icons.vibration;
    }
  }
}
