import 'dart:math' as math;
import 'dart:typed_data';

import 'auto_scan_engine.dart';

class AutoScanFrameAnalyzer {
  final int sampleStride;
  final double minPaperBrightness;
  final double minPaperContrast;

  List<int>? _previousSample;

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

    final horizontalInset = math.max(0, width ~/ 10);
    final verticalInset = math.max(0, height ~/ 10);
    final startX = horizontalInset;
    final endX = math.max(startX + 1, width - horizontalInset);
    final startY = verticalInset;
    final endY = math.max(startY + 1, height - verticalInset);

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

    _previousSample = sample;

    return AutoScanFrameSignal(
      paperVisible:
          brightness >= minPaperBrightness && contrast >= minPaperContrast,
      brightness: brightness,
      movement: movement,
      contentHash: hash,
    );
  }

  void reset() {
    _previousSample = null;
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
