import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/assessment.dart';
import 'bubble_template.dart';
import 'scoring_service.dart';

class _DetectBubblesParams {
  const _DetectBubblesParams({
    required this.enhancedImagePath,
    required this.template,
  });

  final String enhancedImagePath;
  final BubbleTemplate template;
}

class _ValidateBubbleSheetParams {
  const _ValidateBubbleSheetParams({
    required this.enhancedImagePath,
    required this.template,
  });

  final String enhancedImagePath;
  final BubbleTemplate template;
}

OmrResult _detectBubblesIsolate(_DetectBubblesParams params) {
  try {
    final file = File(params.enhancedImagePath);
    if (!file.existsSync()) return OmrResult.empty;

    final image = img.decodeImage(file.readAsBytesSync());
    if (image == null) return OmrResult.empty;

    final scaleFactor = image.width / 1600.0;
    final scaledTemplate = scaleFactor != 1.0
        ? _scaleTemplate(params.template, scaleFactor)
        : params.template;

    final detectedAnswers = <OmrAnswer>[];
    final fillMatrix = <int, Map<String, double>>{};

    for (int qi = 0; qi < scaledTemplate.questionCount; qi++) {
      final optionFills = <String, double>{};
      String? bestOption;
      double bestFill = 0;

      for (int oi = 0; oi < scaledTemplate.optionCount; oi++) {
        final (cx, cy) = scaledTemplate.bubbleCenter(qi, oi);
        final fillRatio = _sampleFillRatio(
          image,
          cx.toInt(),
          cy.toInt(),
          scaledTemplate.bubbleRadius.toInt(),
        );

        final option = scaledTemplate.options[oi];
        optionFills[option] = fillRatio;

        if (fillRatio > scaledTemplate.fillThreshold && fillRatio > bestFill) {
          bestOption = option;
          bestFill = fillRatio;
        }
      }

      fillMatrix[qi + 1] = optionFills;

      if (bestOption != null) {
        final filledOptions = optionFills.entries
            .where((e) => e.value > scaledTemplate.fillThreshold)
            .toList();

        if (filledOptions.length > 1) {
          // Multiple marks detected — invalid response, requires teacher review
          detectedAnswers.add(
            OmrAnswer(
              questionNumber: qi + 1,
              answer: '[MULTIPLE]',
              confidence: 0,
              fillRatio: bestFill,
              flagged: true,
            ),
          );
        } else {
          final confidence = _fillConfidence(bestFill, scaledTemplate.fillThreshold);
          detectedAnswers.add(
            OmrAnswer(
              questionNumber: qi + 1,
              answer: bestOption,
              confidence: confidence,
              fillRatio: bestFill,
            ),
          );
        }
      } else {
        final mostFilled = optionFills.entries.reduce(
          (a, b) => a.value > b.value ? a : b,
        );

        if (mostFilled.value > scaledTemplate.fillThreshold * 0.6) {
          detectedAnswers.add(
            OmrAnswer(
              questionNumber: qi + 1,
              answer: mostFilled.key,
              confidence: 0.4,
              fillRatio: mostFilled.value,
              flagged: true,
            ),
          );
        }
      }
    }

    return OmrResult(
      answers: detectedAnswers,
      fillMatrix: fillMatrix,
      templateName: scaledTemplate.name,
      scaleFactor: scaleFactor,
    );
  } catch (_) {
    return OmrResult.empty;
  }
}

bool _validateBubbleSheetIsolate(_ValidateBubbleSheetParams params) {
  try {
    final file = File(params.enhancedImagePath);
    if (!file.existsSync()) return false;

    final image = img.decodeImage(file.readAsBytesSync());
    if (image == null) return false;

    final avgBrightness = _averageBrightness(image);
    if (avgBrightness < 0.3) return false;

    final scaleFactor = image.width / 1600.0;
    final scaled = scaleFactor != 1.0
        ? _scaleTemplate(params.template, scaleFactor)
        : params.template;

    int bubblesWithMarks = 0;
    final sampleCount = math.min(5, scaled.questionCount);
    for (int qi = 0; qi < sampleCount; qi++) {
      for (int oi = 0; oi < scaled.optionCount; oi++) {
        final (cx, cy) = scaled.bubbleCenter(qi, oi);
        final fill = _sampleFillRatio(
          image,
          cx.toInt(),
          cy.toInt(),
          scaled.bubbleRadius.toInt(),
        );
        if (fill > 0.1) bubblesWithMarks++;
      }
    }

    return bubblesWithMarks > 0;
  } catch (_) {
    return false;
  }
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

double _fillConfidence(double fillRatio, double threshold) {
  if (fillRatio <= threshold) return 0.0;
  final excess = (fillRatio - threshold) / (1.0 - threshold);
  return 0.5 + excess * 0.5;
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

double _averageBrightness(img.Image image) {
  int totalBrightness = 0;
  int count = 0;

  for (int y = 0; y < image.height; y += 10) {
    for (int x = 0; x < image.width; x += 10) {
      totalBrightness += image.getPixel(x, y).r.toInt();
      count++;
    }
  }

  return count > 0 ? totalBrightness / (count * 255.0) : 1.0;
}

/// Optical Mark Recognition service for template-based bubble sheets.
class OmrService {
  static final OmrService _instance = OmrService._();
  factory OmrService() => _instance;
  OmrService._();

  /// Process an enhanced image and extract bubble-filled answers.
  ///
  /// Image decoding and pixel sampling run in a background isolate so camera
  /// and review screens stay responsive on slower Android phones.
  Future<OmrResult> detectBubbles({
    required String enhancedImagePath,
    required BubbleTemplate template,
  }) async {
    final result = await compute(
      _detectBubblesIsolate,
      _DetectBubblesParams(
        enhancedImagePath: enhancedImagePath,
        template: template,
      ),
    );

    debugPrint(
      'OMR: ${result.answers.length}/${template.questionCount} detected, '
      'avg confidence: ${result.averageConfidence.toStringAsFixed(2)}',
    );
    return result;
  }

  /// Grade a paper using OMR against an assessment's answer key.
  Future<List<DetectedAnswer>> detectAndParse({
    required String enhancedImagePath,
    required Assessment assessment,
    BubbleTemplate? template,
  }) async {
    final effectiveTemplate =
        template ??
        StandardTemplates.matchAssessment(
          questionCount: assessment.questionCount,
          isTrueFalse:
              assessment.mcqCount == 0 && assessment.trueFalseCount > 0,
        );

    final result = await detectBubbles(
      enhancedImagePath: enhancedImagePath,
      template: effectiveTemplate,
    );

    return result.answers
        .map(
          (a) => DetectedAnswer(
            questionNumber: a.questionNumber,
            answer: a.answer,
            confidence: a.confidence,
            rawText: '[OMR] fill=${(a.fillRatio * 100).toStringAsFixed(0)}%',
          ),
        )
        .toList();
  }

  /// Validate whether an enhanced image is plausibly a bubble sheet.
  Future<bool> validateBubbleSheet({
    required String enhancedImagePath,
    BubbleTemplate? template,
  }) {
    return compute(
      _validateBubbleSheetIsolate,
      _ValidateBubbleSheetParams(
        enhancedImagePath: enhancedImagePath,
        template: template ?? StandardTemplates.moe20x5,
      ),
    );
  }
}

/// A single detected answer from OMR.
class OmrAnswer {
  final int questionNumber;
  final String answer;
  final double confidence;
  final double fillRatio;
  final bool flagged;

  const OmrAnswer({
    required this.questionNumber,
    required this.answer,
    required this.confidence,
    required this.fillRatio,
    this.flagged = false,
  });
}

/// Full result from OMR detection.
class OmrResult {
  final List<OmrAnswer> answers;
  final Map<int, Map<String, double>> fillMatrix;
  final String templateName;
  final double scaleFactor;

  const OmrResult({
    required this.answers,
    required this.fillMatrix,
    required this.templateName,
    this.scaleFactor = 1.0,
  });

  static const OmrResult empty = OmrResult(
    answers: [],
    fillMatrix: {},
    templateName: 'none',
  );

  /// Average confidence across all detected answers.
  double get averageConfidence {
    if (answers.isEmpty) return 0;
    return answers.fold(0.0, (s, a) => s + a.confidence) / answers.length;
  }

  /// Count of answers flagged for review.
  int get flaggedCount => answers.where((a) => a.flagged).length;
}
