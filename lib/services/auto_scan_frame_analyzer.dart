import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'auto_scan_engine.dart';

class AutoScanFrameAnalyzer {
  final int sampleStride;
  final double minPaperBrightness;
  final double minPaperContrast;

  List<int>? _previousSample;

  // Sliding window for paperVisible smoothing (last 5 frames)
  static const int _windowSize = 5;
  final List<bool> _paperVisibleWindow = [];

  AutoScanFrameAnalyzer({
    this.sampleStride = 12,
    this.minPaperBrightness = 0.32,
    this.minPaperContrast = 0.08,
  });

  AutoScanFrameSignal analyzeLumaPlane({
    required Uint8List lumaBytes,
    required int width,
    required int height,
    int? bytesPerRow,
  }) {
    if (lumaBytes.isEmpty || width <= 0 || height <= 0) {
      _previousSample = null;
      return const AutoScanFrameSignal(
        paperVisible: false,
        brightness: 0,
        movement: 1,
      );
    }

    final rowStride = bytesPerRow ?? width;
    final sample = <int>[];
    var sum = 0.0;
    var sumSquares = 0.0;
    var hash = 0x811c9dc5;

    // Track paper pixel position for centering feedback
    var brightPixelCount = 0;
    var brightPixelSumX = 0.0;
    var brightPixelSumY = 0.0;
    var totalSampleCount = 0;

    final horizontalInset = math.max(0, width ~/ 10);
    final verticalInset = math.max(0, height ~/ 10);
    final startX = horizontalInset;
    final endX = math.max(startX + 1, width - horizontalInset);
    final startY = verticalInset;
    final endY = math.max(startY + 1, height - verticalInset);

    final centerX = width / 2.0;
    final centerY = height / 2.0;

    for (var y = startY; y < endY; y += sampleStride) {
      final rowOffset = y * rowStride;
      for (var x = startX; x < endX; x += sampleStride) {
        final index = rowOffset + x;
        if (index >= lumaBytes.length) continue;
        final value = lumaBytes[index];
        sample.add(value);
        sum += value;
        sumSquares += value * value;
        hash = ((hash ^ value) * 0x01000193) & 0x7fffffff;
        totalSampleCount++;

        // Track bright (paper) pixels for coverage and position
        if (value > 140) {
          brightPixelCount++;
          brightPixelSumX += x;
          brightPixelSumY += y;
        }
      }
    }

    if (sample.isEmpty) {
      _previousSample = null;
      return const AutoScanFrameSignal(
        paperVisible: false,
        brightness: 0,
        movement: 1,
      );
    }

    final average = sum / sample.length;
    final brightness = (average / 255).clamp(0.0, 1.0);
    final variance = (sumSquares / sample.length) - (average * average);
    final contrast = (math.sqrt(math.max(0, variance)) / 255).clamp(0.0, 1.0);
    final movement = _movementFromPrevious(sample);

    // Raw paperVisible from this frame
    final rawPaperVisible =
        brightness >= minPaperBrightness && contrast >= minPaperContrast;

    // Smoothed paperVisible: sliding window of last 5 frames
    _paperVisibleWindow.add(rawPaperVisible);
    if (_paperVisibleWindow.length > _windowSize) {
      _paperVisibleWindow.removeAt(0);
    }
    final trueCount = _paperVisibleWindow.where((v) => v).length;
    // Need 3 out of 5 frames to say paper is visible
    final smoothedPaperVisible = trueCount >= 3;

    // Paper coverage: what fraction of sampled area is bright enough
    final paperCoverage = totalSampleCount > 0
        ? (brightPixelCount / totalSampleCount).clamp(0.0, 1.0)
        : 0.0;

    // Paper center offset: normalized -1..1 (0 = centered)
    double offsetX = 0;
    double offsetY = 0;
    if (brightPixelCount > 10) {
      final paperCenterX = brightPixelSumX / brightPixelCount;
      final paperCenterY = brightPixelSumY / brightPixelCount;
      offsetX = ((paperCenterX - centerX) / (width / 2)).clamp(-1.0, 1.0);
      offsetY = ((paperCenterY - centerY) / (height / 2)).clamp(-1.0, 1.0);
    }

    _previousSample = sample;

    debugPrint('PAPER_VISIBLE: raw=$rawPaperVisible, smoothed=$smoothedPaperVisible, '
        'window=$_paperVisibleWindow, brightness=${brightness.toStringAsFixed(3)}, '
        'contrast=${contrast.toStringAsFixed(3)}');

    return AutoScanFrameSignal(
      paperVisible: smoothedPaperVisible,
      brightness: brightness,
      movement: movement,
      contentHash: hash,
      paperCoverage: paperCoverage,
      offsetX: offsetX,
      offsetY: offsetY,
    );
  }

  void reset() {
    _previousSample = null;
    _paperVisibleWindow.clear();
  }

  double _movementFromPrevious(List<int> sample) {
    final previous = _previousSample;
    if (previous == null || previous.length != sample.length) return 1;

    var diff = 0.0;
    for (var i = 0; i < sample.length; i++) {
      diff += (sample[i] - previous[i]).abs();
    }
    return (diff / sample.length / 255).clamp(0.0, 1.0);
  }
}
