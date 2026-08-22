import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:ethiograde/services/bubble_template.dart';
import 'package:ethiograde/services/omr_calibration_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('omr_calibration_test_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    await Hive.openBox('omr_calibration');
  });

  tearDown(() async {
    if (Hive.isBoxOpen('omr_calibration')) {
      await Hive.box('omr_calibration').clear();
      await Hive.box('omr_calibration').close();
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('CalibrationParams', () {
    test('apply adjusts template geometry', () {
      const template = BubbleTemplate(
        name: 'T',
        questionCount: 20,
                startX: 100,
        startY: 200,
        columnSpacing: 30,
        rowSpacing: 25,
        bubbleRadius: 8,
        fillThreshold: 0.4,
      );
      const params = CalibrationParams(
        offsetX: 5,
        offsetY: -3,
        scaleX: 1.1,
        scaleY: 0.9,
        bubbleRadiusScale: 1.2,
      );

      final result = params.apply(template);

      expect(result.name, 'T (calibrated)');
      expect(result.startX, closeTo(115.5, 0.01));
      expect(result.startY, closeTo(177.3, 0.01));
      expect(result.columnSpacing, closeTo(33, 0.01));
      expect(result.rowSpacing, closeTo(22.5, 0.01));
      expect(result.bubbleRadius, closeTo(9.6, 0.01));
      expect(result.fillThreshold, 0.4);
    });

    test('round-trips through map', () {
      const params = CalibrationParams(
        offsetX: 1.5,
        offsetY: -2.5,
        scaleX: 0.98,
        scaleY: 1.05,
        bubbleRadiusScale: 1.1,
      );
      final restored = CalibrationParams.fromMap(params.toMap());
      expect(restored.offsetX, 1.5);
      expect(restored.offsetY, -2.5);
      expect(restored.scaleX, 0.98);
      expect(restored.scaleY, 1.05);
      expect(restored.bubbleRadiusScale, 1.1);
    });
  });

  group('CalibrationResult', () {
    CalibrationResult makeResult({
      required double score,
      required int detected,
      required int expected,
    }) {
      return CalibrationResult(
        templateName: 'T',
        detectedStartX: 100,
        detectedStartY: 200,
        detectedColumnSpacing: 30,
        detectedRowSpacing: 25,
        detectedBubbleRadius: 8,
        detectedBubbles: detected,
        expectedBubbles: expected,
        alignmentScore: score,
        errors: const [],
        calibratedAt: DateTime(2026, 1, 1),
      );
    }

    test('isGood requires tight alignment and coverage', () {
      expect(
        makeResult(score: 2, detected: 18, expected: 20).isGood,
        isTrue,
      );
      expect(
        makeResult(score: 6, detected: 18, expected: 20).isGood,
        isFalse,
      );
      expect(
        makeResult(score: 2, detected: 14, expected: 20).isGood,
        isFalse,
      );
    });

    test('isAcceptable has looser thresholds', () {
      expect(
        makeResult(score: 8, detected: 14, expected: 20).isAcceptable,
        isTrue,
      );
      expect(
        makeResult(score: 15, detected: 14, expected: 20).isAcceptable,
        isFalse,
      );
      expect(
        makeResult(score: 2, detected: 8, expected: 20).isAcceptable,
        isFalse,
      );
    });
  });

  group('OmrCalibrationService', () {
    test('saves, loads and deletes calibration per assessment', () async {
      final service = OmrCalibrationService();
      const template = BubbleTemplate(
        name: 'S',
        questionCount: 10,
                startX: 50,
        startY: 60,
        columnSpacing: 28,
        rowSpacing: 22,
        bubbleRadius: 7,
        fillThreshold: 0.4,
      );
      const params = CalibrationParams(offsetX: 2, offsetY: 1);

      expect(await service.loadCalibration('a1'), isNull);

      await service.saveCalibration(
        assessmentId: 'a1',
        template: template,
        params: params,
      );

final loaded = await service.loadCalibration('a1');
      expect(loaded, isNotNull);
      expect(loaded!.questionCount, 10);
      expect(loaded.name, 'S (calibrated)');

      await service.deleteCalibration('a1');
      expect(await service.loadCalibration('a1'), isNull);
    });

    test('calibrations are isolated per assessment', () async {
      final service = OmrCalibrationService();
      const template = BubbleTemplate(
        name: 'S',
        questionCount: 10,
                startX: 50,
        startY: 60,
        columnSpacing: 28,
        rowSpacing: 22,
        bubbleRadius: 7,
        fillThreshold: 0.4,
      );
      const params = CalibrationParams();

      await service.saveCalibration(
        assessmentId: 'a1',
        template: template,
        params: params,
      );
      await service.saveCalibration(
        assessmentId: 'a2',
        template: template,
        params: params,
      );

      expect(await service.loadCalibration('a1'), isNotNull);
      expect(await service.loadCalibration('a2'), isNotNull);
      expect(await service.loadCalibration('a3'), isNull);

      final all = await service.getAllCalibrations();
      expect(all.length, 2);
    });
  });
}
