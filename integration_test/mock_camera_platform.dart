import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Mock camera platform for integration tests.
///
/// Replaces the real camera plugin with a fake that returns
/// pre-loaded test images instead of capturing from hardware.
///
/// Usage in tests:
/// ```dart
/// setUp(() {
///   MockCameraPlatform.register();
/// });
/// tearDown(() {
///   MockCameraPlatform.reset();
/// });
/// ```
///
/// Limitations:
/// - Only supports single rear camera
/// - Image returned is a synthetic test image (white with black marks)
/// - No flash, zoom, or focus simulation
/// - Video recording not supported
class MockCameraPlatform extends CameraPlatform {
  /// Pre-loaded image bytes to return from takePicture().
  /// Set this before calling takePicture to return a specific test image.
  static Uint8List? nextImageBytes;

  static int _cameraIdCounter = 0;
  static final List<CameraDescription> _cameras = [
    const CameraDescription(
      name: 'Mock Rear Camera',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90),
  ];

  /// Register this mock as the camera platform implementation.
  static void register() {
    CameraPlatform.instance = MockCameraPlatform();
  }

  /// Reset state between tests.
  static void reset() {
    _cameraIdCounter = 0;
    nextImageBytes = null;
  }

  @override
  Future<List<CameraDescription>> availableCameras() async {
    return _cameras;
  }

  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) async {
    return ++_cameraIdCounter;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    // No-op — mock camera is instantly ready
  }

  @override
  Future<void> dispose(int cameraId) async {}

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) {
    return Stream.value(CameraInitializedEvent(
      cameraId,
      1200,
      1600,
      ExposureMode.auto,
      true,
      FocusMode.auto,
      true,
    ));
  }

  @override
  Stream<CameraClosingEvent> onCameraClosing(int cameraId) {
    return const Stream.empty();
  }

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) {
    return const Stream.empty();
  }

  @override
  Future<XFile> takePicture(int cameraId) async {
    final bytes = nextImageBytes ?? generateSyntheticAnswerSheet();
    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/mock_capture_$cameraId.jpg');
    await file.writeAsBytes(bytes);
    return XFile(file.path);
  }

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {}

  @override
  Future<void> setExposureMode(int cameraId, ExposureMode mode) async {}

  @override
  Future<void> setExposurePoint(int cameraId, Point<double>? point) async {}

  @override
  Future<void> setFocusMode(int cameraId, FocusMode mode) async {}

  @override
  Future<void> setFocusPoint(int cameraId, Point<double>? point) async {}

  @override
  Future<double> getMinExposureOffset(int cameraId) async => 0.0;

  @override
  Future<double> getMaxExposureOffset(int cameraId) async => 1.0;

  @override
  Future<void> setZoomLevel(int cameraId, double zoom) async {}

  @override
  Future<double> getMaxZoomLevel(int cameraId) async => 1.0;

  @override
  Future<double> getMinZoomLevel(int cameraId) async => 1.0;

  @override
  Future<void> lockCaptureOrientation(int cameraId, [DeviceOrientation? orientation]) async {}

  @override
  Future<void> unlockCaptureOrientation(int cameraId) async {}

  @override
  Future<void> pausePreview(int cameraId) async {}

  @override
  Future<void> resumePreview(int cameraId) async {}

  @override
  Widget buildPreview(int cameraId) {
    return const SizedBox(width: 1200, height: 1600);
  }

  @override
  Future<void> setDescriptionWhileRecording(CameraDescription description) async {}

  @override
  Future<void> startVideoRecording(int cameraId, {Duration? maxVideoDuration}) async {}

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    throw UnimplementedError('Video not supported in mock');
  }

  @override
  Future<void> pauseVideoRecording(int cameraId) async {}

  @override
  Future<void> resumeVideoRecording(int cameraId) async {}

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() {
    return const Stream.empty();
  }

  @override
  Stream<VideoRecordingEvent> onVideoRecordingEvent(int cameraId) {
    return const Stream.empty();
  }

  // ── Test image generation ──────────────────────────────────────────

  /// Generate a synthetic answer sheet image (white paper with dark marks).
  ///
  /// Creates a 1200x1600 white image with:
  /// - 4 corner anchor squares (for coordinate-map OMR testing)
  /// - Simulated filled bubbles in an MCQ grid pattern
  ///
  /// Returns JPEG bytes.
  static Uint8List generateSyntheticAnswerSheet({
    int width = 1200,
    int height = 1600,
    int questions = 10,
    int options = 5,
    List<String>? answers, // e.g., ['A', 'B', 'C', 'A', 'D', ...]
  }) {
    final image = img.Image(width: width, height: height);

    // White background
    img.fill(image, color: img.ColorRgb8(255, 255, 255));

    // Draw corner anchors (20x20 black squares)
    const anchorSize = 20;
    final anchors = [
      (40, 40), // top-left
      (width - 40 - anchorSize, 40), // top-right
      (40, height - 40 - anchorSize), // bottom-left
      (width - 40 - anchorSize, height - 40 - anchorSize), // bottom-right
    ];
    for (final (ax, ay) in anchors) {
      img.fillRect(image,
        x1: ax, y1: ay,
        x2: ax + anchorSize, y2: ay + anchorSize,
        color: img.ColorRgb8(0, 0, 0));
    }

    // Draw answer bubbles grid
    final startX = 100;
    final startY = 120;
    final bubbleRadius = 8;
    final rowHeight = 45;
    final colWidth = 50;

    final answerList = answers ?? List.generate(questions, (i) {
      // Alternate between A-E for test answers
      return String.fromCharCode(65 + (i % options));
    });

    for (int q = 0; q < questions && q < answerList.length; q++) {
      final y = startY + q * rowHeight;
      final correctOpt = answerList[q].codeUnitAt(0) - 65;

      for (int o = 0; o < options; o++) {
        final x = startX + o * colWidth;
        final isFilled = o == correctOpt;

        if (isFilled) {
          // Filled bubble — dark circle
          img.fillCircle(image,
            cx: x, cy: y,
            radius: bubbleRadius,
            color: img.ColorRgb8(30, 30, 30));
        } else {
          // Empty bubble — thin outline
          img.drawCircle(image,
            cx: x, cy: y,
            radius: bubbleRadius,
            color: img.ColorRgb8(180, 180, 180),
            thickness: 1);
        }
      }

      // Question number label
      img.drawString(image, '${q + 1}',
        font: img.arial14,
        x: startX - 50, y: y - 7,
        color: img.ColorRgb8(0, 0, 0));
    }

    // Encode as JPEG
    final jpegBytes = Uint8List.fromList(img.encodeJpg(image, quality: 85));
    return jpegBytes;
  }
}
