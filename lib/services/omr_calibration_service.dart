import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'bubble_template.dart';
import 'hive_box_mixin.dart';
import 'app_log.dart';
import 'error_handler.dart';

/// Calibration result from a scan of a blank bubble sheet.
class CalibrationResult {
  final String templateName;
  final double detectedStartX;
  final double detectedStartY;
  final double detectedColumnSpacing;
  final double detectedRowSpacing;
  final double detectedBubbleRadius;
  final int detectedBubbles;
  final int expectedBubbles;
  final double alignmentScore; // 0.0 = perfect, higher = worse
  final List<BubbleError> errors;
  final DateTime calibratedAt;

  const CalibrationResult({
    required this.templateName,
    required this.detectedStartX,
    required this.detectedStartY,
    required this.detectedColumnSpacing,
    required this.detectedRowSpacing,
    required this.detectedBubbleRadius,
    required this.detectedBubbles,
    required this.expectedBubbles,
    required this.alignmentScore,
    required this.errors,
    required this.calibratedAt,
  });

  bool get isGood => alignmentScore < 5.0 && detectedBubbles >= expectedBubbles * 0.8;
  bool get isAcceptable => alignmentScore < 10.0 && detectedBubbles >= expectedBubbles * 0.6;
}

/// Error for a specific bubble position.
class BubbleError {
  final int questionNumber;
  final String option;
  final double expectedX;
  final double expectedY;
  final double actualX;
  final double actualY;
  final double distance;

  const BubbleError({
    required this.questionNumber,
    required this.option,
    required this.expectedX,
    required this.expectedY,
    required this.actualX,
    required this.actualY,
    required this.distance,
  });
}

/// Calibration parameters for adjusting template coordinates.
class CalibrationParams {
  final double offsetX; // pixels to shift X
  final double offsetY; // pixels to shift Y
  final double scaleX; // scale factor for X spacing
  final double scaleY; // scale factor for Y spacing
  final double bubbleRadiusScale; // scale factor for bubble radius

  const CalibrationParams({
    this.offsetX = 0,
    this.offsetY = 0,
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.bubbleRadiusScale = 1.0,
  });

  /// Apply calibration to a template.
  BubbleTemplate apply(BubbleTemplate original) {
    return BubbleTemplate(
      name: '${original.name} (calibrated)',
      questionCount: original.questionCount,
      options: original.options,
      startX: (original.startX + offsetX) * scaleX,
      startY: (original.startY + offsetY) * scaleY,
      columnSpacing: original.columnSpacing * scaleX,
      rowSpacing: original.rowSpacing * scaleY,
      bubbleRadius: original.bubbleRadius * bubbleRadiusScale,
      fillThreshold: original.fillThreshold,
    );
  }

  Map<String, dynamic> toMap() => {
    'offsetX': offsetX,
    'offsetY': offsetY,
    'scaleX': scaleX,
    'scaleY': scaleY,
    'bubbleRadiusScale': bubbleRadiusScale,
  };

  factory CalibrationParams.fromMap(Map<String, dynamic> map) =>
      CalibrationParams(
        offsetX: (map['offsetX'] ?? 0).toDouble(),
        offsetY: (map['offsetY'] ?? 0).toDouble(),
        scaleX: (map['scaleX'] ?? 1.0).toDouble(),
        scaleY: (map['scaleY'] ?? 1.0).toDouble(),
        bubbleRadiusScale: (map['bubbleRadiusScale'] ?? 1.0).toDouble(),
      );
}

class _DetectParams {
  const _DetectParams({
    required this.imagePath,
    required this.template,
  });

  final String imagePath;
  final BubbleTemplate template;
}

/// Detect bubble positions in an image (for calibration).
CalibrationResult _detectForCalibration(_DetectParams params) {
  try {
    final file = File(params.imagePath);
    if (!file.existsSync()) {
      return CalibrationResult(
        templateName: params.template.name,
        detectedStartX: 0,
        detectedStartY: 0,
        detectedColumnSpacing: 0,
        detectedRowSpacing: 0,
        detectedBubbleRadius: 0,
        detectedBubbles: 0,
        expectedBubbles: params.template.questionCount * params.template.optionCount,
        alignmentScore: 999,
        errors: [],
        calibratedAt: DateTime.now(),
      );
    }

    final image = img.decodeImage(file.readAsBytesSync());
    if (image == null) {
      return CalibrationResult(
        templateName: params.template.name,
        detectedStartX: 0,
        detectedStartY: 0,
        detectedColumnSpacing: 0,
        detectedRowSpacing: 0,
        detectedBubbleRadius: 0,
        detectedBubbles: 0,
        expectedBubbles: params.template.questionCount * params.template.optionCount,
        alignmentScore: 999,
        errors: [],
        calibratedAt: DateTime.now(),
      );
    }

    final scaleFactor = image.width / 1600.0;
    final template = scaleFactor != 1.0
        ? _scaleTemplate(params.template, scaleFactor)
        : params.template;

    // Sample bubble positions and detect filled areas
    int detectedBubbles = 0;
    double totalError = 0;
    int errorCount = 0;
    final errors = <BubbleError>[];

    for (int qi = 0; qi < template.questionCount; qi++) {
      for (int oi = 0; oi < template.optionCount; oi++) {
        final (cx, cy) = template.bubbleCenter(qi, oi);
        final fill = _sampleFillRatio(
          image,
          cx.toInt(),
          cy.toInt(),
          template.bubbleRadius.toInt(),
        );

        // For calibration, we look for ANY mark (even partial)
        if (fill > 0.1) {
          detectedBubbles++;

          // Calculate offset from expected position
          // In calibration, we use the grid position as reference
          final expectedX = template.startX + oi * template.columnSpacing;
          final expectedY = template.startY + qi * template.rowSpacing;
          final distance = math.sqrt(
            math.pow(cx - expectedX, 2) + math.pow(cy - expectedY, 2),
          );

          if (distance > 5) {
            totalError += distance;
            errorCount++;
            errors.add(BubbleError(
              questionNumber: qi + 1,
              option: template.options[oi],
              expectedX: expectedX,
              expectedY: expectedY,
              actualX: cx,
              actualY: cy,
              distance: distance,
            ));
          }
        }
      }
    }

    final expectedBubbles = template.questionCount * template.optionCount;
    final alignmentScore = errorCount > 0 ? totalError / errorCount : 0;

    return CalibrationResult(
      templateName: template.name,
      detectedStartX: template.startX,
      detectedStartY: template.startY,
      detectedColumnSpacing: template.columnSpacing,
      detectedRowSpacing: template.rowSpacing,
      detectedBubbleRadius: template.bubbleRadius,
      detectedBubbles: detectedBubbles,
      expectedBubbles: expectedBubbles,
      alignmentScore: alignmentScore.toDouble(),
      errors: errors,
      calibratedAt: DateTime.now(),
    );
  } catch (e, st) {
    AppErrorHandler.catchError('OmrCalibrationService', 'detectForCalibration', e, st);
    return CalibrationResult(
      templateName: params.template.name,
      detectedStartX: 0,
      detectedStartY: 0,
      detectedColumnSpacing: 0,
      detectedRowSpacing: 0,
      detectedBubbleRadius: 0,
      detectedBubbles: 0,
      expectedBubbles: params.template.questionCount * params.template.optionCount,
      alignmentScore: 999,
      errors: [],
      calibratedAt: DateTime.now(),
    );
  }
}

BubbleTemplate _scaleTemplate(BubbleTemplate t, double factor) {
  return BubbleTemplate(
    name: t.name,
    questionCount: t.questionCount,
    options: t.options,
    startX: t.startX * factor,
    startY: t.startY * factor,
    columnSpacing: t.columnSpacing * factor,
    rowSpacing: t.rowSpacing * factor,
    bubbleRadius: t.bubbleRadius * factor,
    fillThreshold: t.fillThreshold,
  );
}

double _sampleFillRatio(img.Image image, int cx, int cy, int radius) {
  final halfSize = radius;
  int darkCount = 0;
  int totalCount = 0;

  for (int dy = -halfSize; dy <= halfSize; dy++) {
    for (int dx = -halfSize; dx <= halfSize; dx++) {
      final px = cx + dx;
      final py = cy + dy;

      if (px < 0 || px >= image.width || py < 0 || py >= image.height) {
        continue;
      }

      final pixel = image.getPixel(px, py);
      final brightness = pixel.r / 255.0;

      if (brightness < 0.4) darkCount++;
      totalCount++;
    }
  }

  return totalCount > 0 ? darkCount / totalCount : 0.0;
}

/// OMR calibration service for verifying template alignment.
///
/// Teachers scan a blank bubble sheet to verify that the template
/// coordinates match the actual bubble positions on the scanned image.
class OmrCalibrationService with HiveBoxMixin {
  static final OmrCalibrationService _instance = OmrCalibrationService._();
  factory OmrCalibrationService() => _instance;
  OmrCalibrationService._();

  static const String _calibrationBoxName = 'omr_calibration';

  /// Detect bubble positions in a scanned blank sheet.
  ///
  /// Runs in a background isolate to keep UI responsive.
  Future<CalibrationResult> detectBubbles({
    required String imagePath,
    required BubbleTemplate template,
  }) async {
    final result = await compute(
      _detectForCalibration,
      _DetectParams(
        imagePath: imagePath,
        template: template,
      ),
    );

    AppLog.info(this, 'detectBubbles',
        'detected ${result.detectedBubbles}/${result.expectedBubbles} bubbles, '
        'alignment score: ${result.alignmentScore.toStringAsFixed(1)}');

    return result;
  }

  /// Auto-calibrate by detecting the best template for a scanned sheet.
  ///
  /// Tries all standard templates and returns the best match.
  Future<CalibrationResult> autoCalibrate({
    required String imagePath,
    int? expectedQuestionCount,
  }) async {
    final templates = expectedQuestionCount != null
        ? [StandardTemplates.matchAssessment(
            questionCount: expectedQuestionCount,
            isTrueFalse: false,
          )]
        : StandardTemplates.all;

    CalibrationResult? bestResult;

    for (final template in templates) {
      final result = await detectBubbles(
        imagePath: imagePath,
        template: template,
      );

      if (bestResult == null || result.alignmentScore < bestResult.alignmentScore) {
        bestResult = result;
      }
    }

    return bestResult!;
  }

  /// Save calibrated template for an assessment.
  Future<void> saveCalibration({
    required String assessmentId,
    required BubbleTemplate template,
    required CalibrationParams params,
  }) async {
    try {
      final box = await openBox(_calibrationBoxName);
      final data = {
        'assessmentId': assessmentId,
        'template': template.toMap(),
        'params': params.toMap(),
        'calibratedAt': DateTime.now().toIso8601String(),
      };
      await box.put(assessmentId, data);
      AppLog.info(this, 'saveCalibration', 'saved calibration for $assessmentId');
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'saveCalibration', e, st);
    }
  }

  /// Load calibrated template for an assessment.
  Future<BubbleTemplate?> loadCalibration(String assessmentId) async {
    try {
      final box = await openBox(_calibrationBoxName);
      final data = await box.get(assessmentId);
      if (data == null) return null;

      final map = Map<String, dynamic>.from(data as Map);
      final params = CalibrationParams.fromMap(
        Map<String, dynamic>.from(map['params'] ?? {}),
      );
      final template = BubbleTemplate.fromMap(
        Map<String, dynamic>.from(map['template'] ?? {}),
      );

      return params.apply(template);
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'loadCalibration', e, st);
      return null;
    }
  }

  /// Delete calibration for an assessment.
  Future<void> deleteCalibration(String assessmentId) async {
    try {
      final box = await openBox(_calibrationBoxName);
      await box.delete(assessmentId);
      AppLog.info(this, 'deleteCalibration', 'deleted calibration for $assessmentId');
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'deleteCalibration', e, st);
    }
  }

  /// Get all saved calibrations.
  Future<List<Map<String, dynamic>>> getAllCalibrations() async {
    try {
      final box = await openBox(_calibrationBoxName);
      final results = <Map<String, dynamic>>[];

      for (final key in box.keys) {
        final data = await box.get(key);
        if (data != null) {
          results.add(Map<String, dynamic>.from(data as Map));
        }
      }

      return results;
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'getAllCalibrations', e, st);
      return [];
    }
  }
}