import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/assessment.dart';
import '../../models/scan_result.dart';
import '../../services/auto_scan_engine.dart';
import '../../services/auto_scan_frame_analyzer.dart';
import '../../services/paper_image_intake_service.dart';
import '../../services/image_hash_service.dart';
import '../../services/hybrid_grading_service.dart';
import '../../services/ocr_service.dart';
import '../../services/voice_service.dart';
import '../../services/settings_provider.dart';
import '../../services/weighted_grade_provider.dart';
import '../../widgets/paper_guide_overlay.dart';

/// Callbacks for camera processor to communicate state changes back to the UI.
void _noopString(String? _) {}
void _noopInt(int? _) {}

class CameraProcessorCallbacks {
  final void Function(bool capturing) onCapturingChanged;
  final void Function(String title, String detail) onCaptureFeedbackChanged;
  final void Function(PaperGuideState guideState) onGuideStateChanged;
  final void Function(List<String> images, List<int?> hashes) onBatchChanged;
  final void Function(List<ScanResult> results) onAutoGradedResultsChanged;
  final void Function(bool batchStarted) onBatchStartedChanged;
  final Future<bool> Function() onShowDuplicateDialog;
  final void Function(String message, VoidCallback onRetry, Assessment assessment)? onCaptureError;
  final VoidCallback? onAutoCaptureTriggered;
  final void Function(String? feedbackText) onFeedbackTextChanged;
  final void Function(int? countdown) onCountdownChanged;

  const CameraProcessorCallbacks({
    required this.onCapturingChanged,
    required this.onCaptureFeedbackChanged,
    required this.onGuideStateChanged,
    required this.onBatchChanged,
    required this.onAutoGradedResultsChanged,
    required this.onBatchStartedChanged,
    required this.onShowDuplicateDialog,
    this.onCaptureError,
    this.onAutoCaptureTriggered,
    this.onFeedbackTextChanged = _noopString,
    this.onCountdownChanged = _noopInt,
  });
}

/// Encapsulates camera capture logic, auto-scan pipeline, and auto-grading.
class CameraProcessor {
  final CameraProcessorCallbacks callbacks;
  final AutoScanEngine _autoScanEngine = AutoScanEngine();
  final AutoScanFrameAnalyzer _autoScanFrameAnalyzer = AutoScanFrameAnalyzer();
  final PaperImageIntakeService _paperImageIntake = PaperImageIntakeService();

  bool _autoCaptureEnabled = true;
  int _countdownTicks = 1;
  bool _autoCaptureInFlight = false;
  bool _isImageStreamActive = false;
  bool _isStreamStopping = false;
  bool _isAnalyzingFrame = false;
  AutoScanDecision? _lastAutoScanDecision;
  int _frameCount = 0;

  CameraProcessor({required this.callbacks});

  bool get autoCaptureEnabled => _autoCaptureEnabled;
  AutoScanDecision? get lastAutoScanDecision => _lastAutoScanDecision;

  // ── Auto-scan pipeline ──

  void startFrameObservation(CameraController? controller) {
    if (controller == null) {
      debugPrint('AUTO_CAPTURE: startFrameObservation - controller is null');
      return;
    }
    if (!controller.value.isInitialized) {
      debugPrint('AUTO_CAPTURE: startFrameObservation - controller not initialized');
      return;
    }
    if (_isImageStreamActive) {
      debugPrint('AUTO_CAPTURE: startFrameObservation - stream already active');
      return;
    }

    _isStreamStopping = false;
    debugPrint('AUTO_CAPTURE: Starting image stream');
    controller.startImageStream((CameraImage image) {
      _observeCameraFrame(image, controller);
    });
    _isImageStreamActive = true;
  }

  void stopFrameObservation(CameraController? controller) {
    if (!_isImageStreamActive || controller == null) return;
    _isStreamStopping = true;
    _isImageStreamActive = false;
    try {
      controller.stopImageStream();
    } catch (_) {}
  }

  void _observeCameraFrame(CameraImage image, CameraController controller) {
    if (_isAnalyzingFrame || !_autoCaptureEnabled || _isStreamStopping) return;
    _isAnalyzingFrame = true;

    try {
      final planes = image.planes;
      if (planes.isEmpty) {
        _isAnalyzingFrame = false;
        return;
      }

      final luma = planes.first.bytes;
      // Log frame info once every 30 frames to avoid spam
      _frameCount++;
      if (_frameCount % 30 == 1) {
        debugPrint('FRAME_INFO: planes=${planes.length}, '
            'width=${image.width}, height=${image.height}, '
            'lumaSize=${luma.length}, bytesPerRow=${planes.first.bytesPerRow}, '
            'format=${image.format.group}');
      }

      final signal = _autoScanFrameAnalyzer.analyzeLumaPlane(
        lumaBytes: luma,
        width: image.width,
        height: image.height,
        bytesPerRow: planes.first.bytesPerRow,
      );

      debugPrint('FRAME: brightness=${signal.brightness.toStringAsFixed(3)}, '
          'movement=${signal.movement.toStringAsFixed(3)}, '
          'paperVisible=${signal.paperVisible}');

      final now = DateTime.now();
      final decision = _autoScanEngine.observe(
        frame: signal,
        now: now,
        enabled: _autoCaptureEnabled,
      );

      _lastAutoScanDecision = decision;

      // Map to guide state
      final newGuideState = _guideStateForDecision();
      callbacks.onGuideStateChanged(newGuideState);

      // Pass real-time feedback text to UI
      callbacks.onFeedbackTextChanged(decision.message);
    
      debugPrint('DECISION: ${decision.readiness}, shouldCapture=${decision.shouldCapture}');

      // Auto-capture decision — start countdown instead of instant capture
      if (decision.shouldCapture && !_autoCaptureInFlight && !_countdownActive) {
        debugPrint('AUTO_CAPTURE: Starting countdown!');
        _autoCaptureInFlight = true;
        _consecutiveFalseDuringCountdown = 0;
        _signalCaptureSuccess();
        callbacks.onCaptureFeedbackChanged('Capturing...', 'Hold steady');
        _startCountdown();
      }

      // During countdown: only cancel after 3 CONSECUTIVE bad frames (friction tolerance)
      if (_countdownActive && !decision.shouldCapture) {
        if (decision.readiness == AutoScanReadiness.steady ||
            decision.readiness == AutoScanReadiness.capture) {
          // Good frame — reset counter
          _consecutiveFalseDuringCountdown = 0;
        } else {
          _consecutiveFalseDuringCountdown++;
          debugPrint('COUNTDOWN: step=$_countdownValue, '
              'consecutiveFalse=$_consecutiveFalseDuringCountdown, '
              'readiness=${decision.readiness}');
          if (_consecutiveFalseDuringCountdown >= 3) {
            debugPrint('AUTO_CAPTURE: Countdown cancelled — 3 consecutive bad frames');
            cancelCountdown();
            _autoCaptureInFlight = false;
          }
        }
      }

      // Reset counter when countdown isn't active
      if (!_countdownActive) {
        _consecutiveFalseDuringCountdown = 0;
      }
    } catch (e) {
      debugPrint('FRAME ERROR: $e');
    } finally {
      _isAnalyzingFrame = false;
    }
  }

  /// Returns true if auto-capture was triggered (caller should capture).
  bool checkAutoCaptureTrigger() {
    if (_lastAutoScanDecision == null) return false;
    if (!_lastAutoScanDecision!.shouldCapture) return false;
    if (_autoCaptureInFlight) return false;

    _autoCaptureInFlight = true;
    _signalCaptureSuccess();
    _startCountdown();
    return true;
  }

  void recordAutoCapture() {
    _autoScanEngine.recordCapture(
      now: DateTime.now(),
      contentHash: _lastAutoScanDecision?.readiness.index ?? 0,
    );
    _autoCaptureInFlight = false;
    cancelCountdown();
  }

  // ── Countdown state ──
  int? _countdownValue;
  Timer? _countdownTimer;
  bool _countdownActive = false;
  int _consecutiveFalseDuringCountdown = 0;

  PaperGuideState _guideStateForDecision() {
    if (_lastAutoScanDecision == null) return PaperGuideState.idle;
    switch (_lastAutoScanDecision!.readiness) {
      case AutoScanReadiness.capture:
      case AutoScanReadiness.steady:
        return PaperGuideState.aligned;
      case AutoScanReadiness.noPaper:
        return PaperGuideState.idle;
      case AutoScanReadiness.tooDark:
        return PaperGuideState.tooDark;
      case AutoScanReadiness.moving:
        return PaperGuideState.moving;
      case AutoScanReadiness.coolingDown:
      case AutoScanReadiness.waitingForNewPaper:
        return PaperGuideState.detected;
      case AutoScanReadiness.disabled:
        return PaperGuideState.idle;
    }
  }

  /// Start a countdown before capture. Ticks are configurable (0 = instant).
  void _startCountdown() {
    if (_countdownActive) return;
    if (_countdownTicks <= 0) {
      callbacks.onAutoCaptureTriggered?.call();
      return;
    }
    _countdownActive = true;
    _countdownValue = _countdownTicks;
    callbacks.onCountdownChanged(_countdownTicks);

    _countdownTimer = Timer.periodic(const Duration(milliseconds: 700), (timer) {
      if (_countdownValue == null || _countdownValue! <= 1) {
        timer.cancel();
        _countdownValue = null;
        _countdownActive = false;
        callbacks.onCountdownChanged(null);
        callbacks.onAutoCaptureTriggered?.call();
        return;
      }
      _countdownValue = _countdownValue! - 1;
      callbacks.onCountdownChanged(_countdownValue);
    });
  }

  /// Set countdown ticks (0 = instant capture, 1 = 0.7s, 2 = 1.4s, 3 = 2.1s).
  void setCountdownTicks(int ticks) {
    _countdownTicks = ticks.clamp(0, 5);
  }

  /// Cancel any active countdown.
  void cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownValue = null;
    _countdownActive = false;
    callbacks.onCountdownChanged(null);
  }

  String get guidanceTitle {
    if (_lastAutoScanDecision == null) return 'Align paper';
    switch (_lastAutoScanDecision!.readiness) {
      case AutoScanReadiness.capture:
        return 'Hold steady \u2014 capturing';
      case AutoScanReadiness.steady:
        return 'Paper detected';
      case AutoScanReadiness.tooDark:
        return 'Too dark';
      case AutoScanReadiness.moving:
        return 'Hold still';
      case AutoScanReadiness.noPaper:
        return 'No paper detected';
      case AutoScanReadiness.coolingDown:
        return 'Preparing next capture';
      case AutoScanReadiness.waitingForNewPaper:
        return 'Waiting for new paper';
      case AutoScanReadiness.disabled:
        return 'Auto-capture disabled';
    }
  }

  String get guidanceDetail {
    if (_lastAutoScanDecision == null) return 'Place paper in the frame';
    return _lastAutoScanDecision!.message;
  }

  IconData get guidanceIcon {
    if (_lastAutoScanDecision == null) return Icons.center_focus_strong;
    switch (_lastAutoScanDecision!.readiness) {
      case AutoScanReadiness.capture:
        return Icons.camera_alt;
      case AutoScanReadiness.steady:
        return Icons.check_circle_outline;
      case AutoScanReadiness.tooDark:
        return Icons.brightness_low;
      case AutoScanReadiness.moving:
        return Icons.pan_tool_outlined;
      case AutoScanReadiness.noPaper:
        return Icons.search;
      case AutoScanReadiness.coolingDown:
        return Icons.hourglass_top;
      case AutoScanReadiness.waitingForNewPaper:
        return Icons.swap_horiz;
      case AutoScanReadiness.disabled:
        return Icons.pause_circle_outline;
    }
  }

  void toggleAutoCapture(CameraController? controller) {
    if (_autoCaptureEnabled) {
      debugPrint('AUTO_CAPTURE: Disabling auto-capture');
      _disableAutoCapture(controller);
    } else {
      debugPrint('AUTO_CAPTURE: Enabling auto-capture');
      _autoCaptureEnabled = true;
      _autoCaptureInFlight = false;
      _autoScanEngine.reset();
      _autoScanFrameAnalyzer.reset();
      _lastAutoScanDecision = null;
      callbacks.onGuideStateChanged(PaperGuideState.idle);
      startFrameObservation(controller);
    }
  }

  void _disableAutoCapture(CameraController? controller) {
    _autoCaptureEnabled = false;
    _autoCaptureInFlight = false;
    _lastAutoScanDecision = null;
    callbacks.onGuideStateChanged(PaperGuideState.idle);
    stopFrameObservation(controller);
  }

  // ── Capture logic ──

  /// Capture an image and add it to the batch.
  ///
  /// If online: processes immediately via cloud OCR or local OCR.
  /// If offline: saves to queue for batch processing later.
  Future<void> captureImage({
    required CameraController? controller,
    required Assessment? assessment,
    required List<int?> existingHashes,
    required List<String> capturedImages,
    required List<int?> capturedHashes,
  }) async {
    if (controller == null || !controller.value.isInitialized) return;
    if (assessment == null) return;

    callbacks.onCapturingChanged(true);

    try {
      final image = await controller.takePicture();

      // Skip auto-crop — use original image for answer sheet scanning
      final String capturedPath = image.path;

      final hash = ImageHashService().computeHash(capturedPath);

      // Check for duplicates
      if (hash != null) {
        final allHashes = [...existingHashes, ...capturedHashes];
        final dupIndex = ImageHashService().findDuplicate(hash, allHashes);

        if (dupIndex >= 0) {
          final isDuplicate = await callbacks.onShowDuplicateDialog();
          if (!isDuplicate) {
            callbacks.onCapturingChanged(false);
            return;
          }
        }
      }

      capturedImages.add(capturedPath);
      capturedHashes.add(hash);
      callbacks.onBatchChanged(capturedImages, capturedHashes);

      _signalCaptureSuccess();

      // Always grade locally — offline-first, no network required
      callbacks.onCaptureFeedbackChanged('Processing...', 'Reading answers');
      await gradeAutoCapturedPaper(
        imagePath: capturedPath,
        assessment: assessment,
      );
    } catch (e) {
      debugPrint('Capture error: $e');
    } finally {
      _autoCaptureInFlight = false;
      callbacks.onCapturingChanged(false);
    }
  }

  /// Capture master answer sheet.
  Future<void> captureMasterKey({
    required CameraController? controller,
    required Assessment? assessment,
  }) async {
    if (controller == null || !controller.value.isInitialized) return;
    if (assessment == null) return;

    callbacks.onCapturingChanged(true);

    try {
      await controller.takePicture();
      callbacks.onCapturingChanged(false);
      // Return the image path — caller handles navigation
      return;
    } catch (e) {
      debugPrint('Master key capture error: $e');
      callbacks.onCapturingChanged(false);
    }
  }

  // ── Auto-grading ──

  Future<void> gradeAutoCapturedPaper({
    required String imagePath,
    required Assessment assessment,
  }) async {
    try {
      final grading = HybridGradingService();
      final result = await grading.gradePaper(
        imagePath: imagePath,
        assessment: assessment,
      );

      if (result.status == ScanStatus.graded) {
        callbacks.onCaptureFeedbackChanged(
          '${result.percentage.toStringAsFixed(0)}%',
          result.studentName.isNotEmpty ? result.studentName : 'Paper captured',
        );
        await _speakAutoResult(result);
      } else {
        final errorMessage = _translateError(result);
        void onRetry() {
          callbacks.onCaptureFeedbackChanged('Retrying...', 'Place paper in frame');
        }

        if (callbacks.onCaptureError != null) {
          callbacks.onCaptureError!(errorMessage, onRetry, assessment);
        } else {
          callbacks.onCaptureFeedbackChanged(errorMessage, 'Tap capture to retry');
        }
      }
    } catch (e) {
      debugPrint('Auto-grade error: $e');
      callbacks.onCaptureFeedbackChanged(
        'Scanning failed',
        'Tap capture to try again',
      );
    }
  }

  String _translateError(ScanResult result) {
    final error = result.metadata['error'] as String?;

    if (error == null) {
      return 'Could not read answers. Try scanning again.';
    }

    if (error == 'Image file not found') {
      return 'Photo not saved. Try scanning again.';
    }

    if (error.startsWith('Processing error:')) {
      final type = error.substring('Processing error:'.length).trim();
      if (type.contains('FileSystemException')) {
        return 'File error. Try again.';
      }
      if (type.contains('OutOfMemoryError')) {
        return 'Phone memory low. Close other apps and retry.';
      }
      if (type.contains('TimeoutException')) {
        return 'Scanning took too long. Improve lighting and retry.';
      }
      return 'Scanning failed. Try again.';
    }

    return 'Scanning failed. Try again.';
  }

  Future<void> _speakAutoResult(ScanResult result) async {
    try {
      final settings = SettingsProvider();
      if (!settings.voiceFeedbackEnabled) return;

      final voice = VoiceService();
      if (result.status != ScanStatus.graded) return;

      await voice.readScore(
        studentName: result.studentName.isNotEmpty ? result.studentName : 'Student',
        score: result.totalScore,
        maxScore: result.maxScore,
        grade: result.grade,
        mode: settings.voiceFeedbackMode,
      );
    } catch (_) {}
  }

  // ── Re-scan ──

  /// Capture and re-grade a single paper (re-scan mode).
  Future<ScanResult?> captureAndReGrade({
    required CameraController? controller,
    required ScanResult existingResult,
    required Assessment assessment,
    required BuildContext context,
  }) async {
    if (controller == null || !controller.value.isInitialized) return null;

    final grading = HybridGradingService();
    final weightedScale = assessment.weightedScaleId != null
        ? context.read<WeightedGradeProvider>().getForExam(assessment.id)
        : null;

    callbacks.onCapturingChanged(true);

    try {
      final image = await controller.takePicture();
      callbacks.onCapturingChanged(false);

      // Skip auto-crop for re-scan — use original image
      final String reScanPath = image.path;

      final newResult = await grading.gradePaper(
        imagePath: reScanPath,
        assessment: assessment,
        studentId: existingResult.studentId,
        studentName: existingResult.studentName,
        weightedScale: weightedScale,
      );

      await grading.deleteScanResult(existingResult.id);
      return newResult;
    } catch (e) {
      debugPrint('Re-scan error: $e');
      callbacks.onCapturingChanged(false);
      return null;
    }
  }

  // ── File upload ──

  Future<void> pickUploadedPapers({
    required Assessment? assessment,
    required List<String> capturedImages,
    required List<int?> capturedHashes,
  }) async {
    if (assessment == null) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) return;

      final paths = result.files.map((f) => f.path).whereType<String>().toList();
      final intake = _paperImageIntake.fromPaths(
        paths: paths,
        source: PaperImageSource.upload,
      );

      if (!intake.hasImages) return;

      for (final item in intake.readyItems) {
        capturedImages.add(item.path);
        capturedHashes.add(ImageHashService().computeHash(item.path));
      }

      callbacks.onBatchChanged(capturedImages, capturedHashes);
    } catch (e) {
      debugPrint('File picker error: $e');
    }
  }

  // ── Haptic feedback ──

  void _signalCaptureSuccess() {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  void signalNeedsAttention() {
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  void signalCaptureFailure() {
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  // ── Cleanup ──

  void cleanup({required bool batchStarted, required List<String> capturedImages}) {
    if (!batchStarted && capturedImages.isNotEmpty) {
      OcrService().cleanupImages(capturedImages);
    }
  }
}

/// FilePicker import needed for upload functionality.
/// (imported at top of file)
