import 'dart:typed_data';

import 'package:ethiograde/services/auto_scan_frame_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AutoScanFrameAnalyzer', () {
    test('returns no paper for empty input', () {
      final analyzer = AutoScanFrameAnalyzer();

      final signal = analyzer.analyzeLumaPlane(
        lumaBytes: Uint8List(0),
        width: 0,
        height: 0,
      );

      expect(signal.paperVisible, isFalse);
      expect(signal.brightness, 0);
      expect(signal.movement, 1);
    });

    test('detects dark frames as not visible enough', () {
      final analyzer = AutoScanFrameAnalyzer(sampleStride: 1);

      final signal = analyzer.analyzeLumaPlane(
        lumaBytes: Uint8List.fromList(List.filled(100, 20)),
        width: 10,
        height: 10,
      );

      expect(signal.paperVisible, isFalse);
      expect(signal.brightness, lessThan(0.32));
    });

    test('detects paper-like contrast in the center of the frame', () {
      final analyzer = AutoScanFrameAnalyzer(sampleStride: 1);
      final bytes = List<int>.filled(100, 40);
      for (var y = 2; y < 8; y++) {
        for (var x = 2; x < 8; x++) {
          bytes[(y * 10) + x] = (x + y).isEven ? 230 : 180;
        }
      }

      final signal = analyzer.analyzeLumaPlane(
        lumaBytes: Uint8List.fromList(bytes),
        width: 10,
        height: 10,
      );

      expect(signal.paperVisible, isTrue);
      expect(signal.brightness, greaterThan(0.32));
      expect(signal.contentHash, isNotNull);
    });

    test('reports low movement for repeated stable frames', () {
      final analyzer = AutoScanFrameAnalyzer(sampleStride: 1);
      final bytes = Uint8List.fromList(List.generate(100, (i) => 120 + i % 20));

      analyzer.analyzeLumaPlane(lumaBytes: bytes, width: 10, height: 10);
      final signal = analyzer.analyzeLumaPlane(
        lumaBytes: bytes,
        width: 10,
        height: 10,
      );

      expect(signal.movement, 0);
    });

    test('reports movement when frame brightness pattern changes', () {
      final analyzer = AutoScanFrameAnalyzer(sampleStride: 1);
      final first = Uint8List.fromList(List.generate(100, (i) => 80 + i % 20));
      final second = Uint8List.fromList(
        List.generate(100, (i) => 180 - i % 20),
      );

      analyzer.analyzeLumaPlane(lumaBytes: first, width: 10, height: 10);
      final signal = analyzer.analyzeLumaPlane(
        lumaBytes: second,
        width: 10,
        height: 10,
      );

      expect(signal.movement, greaterThan(0.2));
    });
  });
}
