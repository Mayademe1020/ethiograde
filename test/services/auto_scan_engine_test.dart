import 'package:ethiograde/services/auto_scan_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AutoScanEngine', () {
    late AutoScanEngine engine;
    late DateTime now;

    setUp(() {
      engine = AutoScanEngine(
        stableDuration: const Duration(milliseconds: 900),
        captureCooldown: const Duration(seconds: 2),
      );
      now = DateTime(2026, 1, 1, 8);
    });

    test('stays quiet when auto mode is disabled', () {
      final decision = engine.observe(
        frame: const AutoScanFrameSignal(
          paperVisible: true,
          brightness: 0.8,
          movement: 0.0,
          contentHash: 1,
        ),
        now: now,
        enabled: false,
      );

      expect(decision.shouldCapture, isFalse);
      expect(decision.readiness, AutoScanReadiness.disabled);
    });

    test('does not capture without a visible paper', () {
      final decision = engine.observe(
        frame: const AutoScanFrameSignal(
          paperVisible: false,
          brightness: 0.8,
          movement: 0.0,
        ),
        now: now,
        enabled: true,
      );

      expect(decision.shouldCapture, isFalse);
      expect(decision.readiness, AutoScanReadiness.noPaper);
    });

    test('blocks capture when the image is too dark', () {
      final decision = engine.observe(
        frame: const AutoScanFrameSignal(
          paperVisible: true,
          brightness: 0.1,
          movement: 0.0,
        ),
        now: now,
        enabled: true,
      );

      expect(decision.shouldCapture, isFalse);
      expect(decision.readiness, AutoScanReadiness.tooDark);
    });

    test('waits until paper is steady long enough before capture', () {
      var decision = engine.observe(
        frame: const AutoScanFrameSignal(
          paperVisible: true,
          brightness: 0.8,
          movement: 0.0,
          contentHash: 10,
        ),
        now: now,
        enabled: true,
      );

      expect(decision.shouldCapture, isFalse);
      expect(decision.readiness, AutoScanReadiness.steady);

      decision = engine.observe(
        frame: const AutoScanFrameSignal(
          paperVisible: true,
          brightness: 0.8,
          movement: 0.0,
          contentHash: 10,
        ),
        now: now.add(const Duration(milliseconds: 950)),
        enabled: true,
      );

      expect(decision.shouldCapture, isTrue);
      expect(decision.readiness, AutoScanReadiness.capture);
    });

    test('waits for a new paper after a capture', () {
      engine.recordCapture(now: now, contentHash: 42);

      final decision = engine.observe(
        frame: const AutoScanFrameSignal(
          paperVisible: true,
          brightness: 0.8,
          movement: 0.0,
          contentHash: 42,
        ),
        now: now.add(const Duration(seconds: 3)),
        enabled: true,
      );

      expect(decision.shouldCapture, isFalse);
      expect(decision.readiness, AutoScanReadiness.waitingForNewPaper);
    });

    test('uses cooldown after a capture even with a new paper', () {
      engine.recordCapture(now: now, contentHash: 42);

      final decision = engine.observe(
        frame: const AutoScanFrameSignal(
          paperVisible: true,
          brightness: 0.8,
          movement: 0.0,
          contentHash: 43,
        ),
        now: now.add(const Duration(milliseconds: 500)),
        enabled: true,
      );

      expect(decision.shouldCapture, isFalse);
      expect(decision.readiness, AutoScanReadiness.coolingDown);
    });
  });
}
