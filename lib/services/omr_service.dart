import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/assessment.dart';
import 'scoring_service.dart';
import 'bubble_template.dart';

/// Optical Mark Recognition (OMR) service.
///
/// Detects filled bubbles on exam answer sheets. Uses pixel sampling
/// on enhanced images — no ML, no network, no heavy dependencies.
///
/// How it works:
/// 1. Load the enhanced image (already downscale + grayscale + contrast)
/// 2. For each expected bubble position (from template):
///    a. Sample a small region at the bubble center
///    b. Count dark pixels (below brightness threshold)
///    c. If dark ratio > template's fillThreshold → bubble is filled
/// 3. For each question, pick the option with the highest fill ratio
/// 4. If no option is clearly filled → mark as uncertain
///
/// Design decisions:
/// - Template-based (not auto-detect) — matches our PDF generator output
/// - Pure Dart + image package — no new dependencies
/// - Pixel sampling is cheap: ~20×20×questions×options reads
///   (20 Q × 5 opts = 2000 samples × 25 pixels = 50K reads — sub-ms)
/// - Works on grayscale enhanced images (same pipeline as OCR)
class OmrService {
  static final OmrService _instance = OmrService._();
  factory OmrService() => _instance;
  OmrService._();

  /// Process an enhanced image and extract bubble-filled answers.
  ///
  /// [enhancedImagePath] — path to the already-enhanced image
  ///   (output of OcrService.enhanceImage — EXIF corrected, downscaled, grayscale)
  /// [template] — describes where bubbles are expected
  ///
  /// Returns an [OmrResult] with detected answers and fill metadata.
  ///
  /// Never throws — returns empty result on failure so the pipeline
  /// can fall back to OCR-only.
  Future<OmrResult> detectBubbles({
    required String enhancedImagePath,
    required BubbleTemplate template,
  }) async {
    try {
      final file = File(enhancedImagePath);
      if (!await file.exists()) {
        debugPrint('OMR: enhanced image not found: $enhancedImagePath');
        return OmrResult.empty;
      }

      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        debugPrint('OMR: could not decode image');
        return OmrResult.empty;
      }

      // Auto-scale template if the image dimensions differ from the
      // template's expected 1600px reference. Teachers' phones produce
      // different sizes after enhancement.
      final scaleFactor = image.width / 1600.0;
      final scaledTemplate = scaleFactor != 1.0
          ? _scaleTemplate(template, scaleFactor)
          : template;

      // Auto-calibrate: detect actual bubble positions and adjust template
      final calibratedTemplate = _calibrateTemplate(image, scaledTemplate);

      final detectedAnswers = <OmrAnswer>[];
      final fillMatrix = <int, Map<String, double>>{};

      for (int qi = 0; qi < calibratedTemplate.questionCount; qi++) {
        final optionFills = <String, double>{};
        double maxFill = 0;
        String? bestOption;
        double bestFill = 0;

        for (int oi = 0; oi < calibratedTemplate.optionCount; oi++) {
          final (cx, cy) = calibratedTemplate.bubbleCenter(qi, oi);
          final fillRatio = _sampleFillRatio(
            image,
            cx.toInt(),
            cy.toInt(),
            calibratedTemplate.bubbleRadius.toInt(),
          );

          final option = calibratedTemplate.options[oi];
          optionFills[option] = fillRatio;

          if (fillRatio > maxFill) {
            maxFill = fillRatio;
          }

          if (fillRatio > calibratedTemplate.fillThreshold && fillRatio > bestFill) {
            bestOption = option;
            bestFill = fillRatio;
          }
        }

        fillMatrix[qi + 1] = optionFills;

        if (bestOption != null) {
          // Check if multiple options are close to the threshold — ambiguous
          final filledOptions = optionFills.entries
              .where((e) => e.value > calibratedTemplate.fillThreshold)
              .length;

          double confidence;
          if (filledOptions > 1) {
            // Multiple filled → lower confidence, might be eraser marks or smudges
            confidence = 0.5;
          } else {
            // Single clear fill — confidence based on how decisively above threshold
            confidence = _fillConfidence(bestFill, calibratedTemplate.fillThreshold);
          }

          detectedAnswers.add(OmrAnswer(
            questionNumber: qi + 1,
            answer: bestOption,
            confidence: confidence,
            fillRatio: bestFill,
          ));
        } else {
          // No option clearly filled — student may have skipped or used pencil
          // Check if there's a "most filled" option even below threshold
          // (pencil marks are lighter than pen)
          final mostFilled = optionFills.entries.reduce(
            (a, b) => a.value > b.value ? a : b,
          );

          if (mostFilled.value > calibratedTemplate.fillThreshold * 0.6) {
            // Possibly pencil — flag with low confidence
            detectedAnswers.add(OmrAnswer(
              questionNumber: qi + 1,
              answer: mostFilled.key,
              confidence: 0.4,
              fillRatio: mostFilled.value,
              flagged: true,
            ));
          }
          // else: truly empty, skip — will show as MISSING in scoring
        }
      }

      debugPrint(
        'OMR: ${detectedAnswers.length}/${calibratedTemplate.questionCount} detected, '
        'avg confidence: ${detectedAnswers.isEmpty ? 0 : (detectedAnswers.fold(0.0, (s, a) => s + a.confidence) / detectedAnswers.length).toStringAsFixed(2)}',
      );

      return OmrResult(
        answers: detectedAnswers,
        fillMatrix: fillMatrix,
        templateName: calibratedTemplate.name,
        scaleFactor: scaleFactor,
      );
    } catch (e) {
      debugPrint('OMR: detection failed (${e.runtimeType})');
      return OmrResult.empty;
    }
  }

  /// Grade a paper using OMR against an assessment's answer key.
  ///
  /// Convenience method that runs detectBubbles + scoreAnswers.
  /// The HybridGradingService calls this in parallel with OCR.
  Future<List<DetectedAnswer>> detectAndParse({
    required String enhancedImagePath,
    required Assessment assessment,
    BubbleTemplate? template,
  }) async {
    // Auto-select template based on assessment if not provided
    final effectiveTemplate = template ??
        StandardTemplates.matchAssessment(
          questionCount: assessment.questionCount,
          isTrueFalse: assessment.mcqCount == 0 && assessment.trueFalseCount > 0,
        );

    final result = await detectBubbles(
      enhancedImagePath: enhancedImagePath,
      template: effectiveTemplate,
    );

    return result.answers
        .map((a) => DetectedAnswer(
              questionNumber: a.questionNumber,
              answer: a.answer,
              confidence: a.confidence,
              rawText: '[OMR] fill=${(a.fillRatio * 100).toStringAsFixed(0)}%',
            ))
        .toList();
  }

  /// Validate a bubble sheet image — is it a plausible answer sheet?
  ///
  /// Quick check before full OMR processing. Returns false if the image
  /// doesn't look like a bubble sheet (e.g., too dark, too bright, no
  /// circular patterns). This prevents wasting time on non-answer images
  /// in batch scans.
  Future<bool> validateBubbleSheet({
    required String enhancedImagePath,
    BubbleTemplate? template,
  }) async {
    try {
      final file = File(enhancedImagePath);
      if (!await file.exists()) return false;

      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return false;

      // Check overall brightness — a valid answer sheet should have
      // mostly white/light background with dark marks
      final avgBrightness = _averageBrightness(image);
      if (avgBrightness < 0.3) return false; // too dark — probably not a paper
      if (avgBrightness > 0.98) return false; // pure white — blank page

      // Check that at least some dark spots exist at expected bubble positions
      final testTemplate = template ?? StandardTemplates.moe20x5;
      final scaleFactor = image.width / 1600.0;
      final scaled = scaleFactor != 1.0
          ? _scaleTemplate(testTemplate, scaleFactor)
          : testTemplate;

      int bubblesWithMarks = 0;
      final sampleCount = math.min(5, scaled.questionCount);
      for (int qi = 0; qi < sampleCount; qi++) {
        for (int oi = 0; oi < scaled.optionCount; oi++) {
          final (cx, cy) = scaled.bubbleCenter(qi, oi);
          final fill = _sampleFillRatio(image, cx.toInt(), cy.toInt(), scaled.bubbleRadius.toInt());
          if (fill > 0.1) bubblesWithMarks++;
        }
      }

      // If no bubbles have ANY marks, probably not a filled answer sheet
      return bubblesWithMarks > 0;
    } catch (e) {
      return false;
    }
  }

  // ── Internal ──────────────────────────────────────────────────────

  /// Sample the fill ratio at a specific position with adaptive thresholding.
  ///
  /// Instead of a hardcoded brightness threshold, this samples the background
  /// brightness from a ring around the bubble and sets the threshold relative
  /// to it. This handles bright sunlight (paper at 0.9+), dim classrooms
  /// (paper at 0.5), and everything in between.
  ///
  /// Algorithm:
  /// 1. Sample an outer ring (radius*2 to radius*3) for background brightness
  /// 2. Set threshold = backgroundBrightness - 0.25 (ink is ~25% darker than paper)
  /// 3. Count pixels inside the bubble that are darker than threshold
  /// 4. Return fill ratio (0.0 = empty, 1.0 = fully filled)
  double _sampleFillRatio(img.Image image, int cx, int cy, int radius) {
    final halfSize = radius;

    // ── Step 1: Sample background brightness from outer ring ──
    // Ring between radius*2 and radius*3 from center — this is paper, not bubble
    int bgBrightnessSum = 0;
    int bgCount = 0;
    final innerR = (radius * 2).clamp(1, 50);
    final outerR = (radius * 3).clamp(2, 80);

    for (int dy = -outerR; dy <= outerR; dy++) {
      for (int dx = -outerR; dx <= outerR; dx++) {
        final dist2 = dx * dx + dy * dy;
        if (dist2 < innerR * innerR || dist2 > outerR * outerR) continue;
        final px = cx + dx;
        final py = cy + dy;
        if (px < 0 || px >= image.width || py < 0 || py >= image.height) continue;
        bgBrightnessSum += image.getPixel(px, py).r.toInt();
        bgCount++;
      }
    }

    // Fallback if ring is out of bounds
    final bgBrightness = bgCount > 0
        ? bgBrightnessSum / (bgCount * 255.0)
        : 0.85; // assume white paper

    // ── Step 2: Adaptive threshold ──
    // Ink/pencil is typically 0.2-0.4 darker than paper
    // Use adaptive delta: higher background → larger gap needed
    final adaptiveThreshold = (bgBrightness - 0.25).clamp(0.15, 0.85);

    // ── Step 3: Count dark pixels inside bubble ──
    int darkCount = 0;
    int totalCount = 0;

    for (int dy = -halfSize; dy <= halfSize; dy++) {
      for (int dx = -halfSize; dx <= halfSize; dx++) {
        final px = cx + dx;
        final py = cy + dy;

        if (px < 0 || px >= image.width || py < 0 || py >= image.height) continue;

        final pixel = image.getPixel(px, py);
        final brightness = pixel.r / 255.0;

        if (brightness < adaptiveThreshold) darkCount++;
        totalCount++;
      }
    }

    return totalCount > 0 ? darkCount / totalCount : 0.0;
  }

  /// Calculate confidence from fill ratio and threshold.
  ///
  /// Returns 0.0–1.0. Higher fill = higher confidence.
  /// Sigmoid-like mapping: barely above threshold = ~0.5, fully filled = ~0.95
  double _fillConfidence(double fillRatio, double threshold) {
    if (fillRatio <= threshold) return 0.0;
    final excess = (fillRatio - threshold) / (1.0 - threshold);
    return 0.5 + excess * 0.5; // 0.5 at threshold, 1.0 at full fill
  }

  /// Auto-calibrate template positions by detecting actual bubble locations.
  ///
  /// Scans 3 rows (first, middle, last) of the answer grid to find where
  /// bubbles actually are vs where the template expects them. Computes
  /// per-axis scale and offset corrections, returns a calibrated template.
  ///
  /// Algorithm:
  /// 1. For each calibration row, sample a horizontal band at the expected Y
  /// 2. Slide a small window across, counting dark pixels at each X
  /// 3. Find the N darkest peaks (= bubble centers)
  /// 4. Compare detected positions vs expected
  /// 5. Compute linear correction: correctedX = expectedX * scaleX + offsetX
  ///    Same for Y across rows
  /// 6. Return calibrated template
  ///
  /// Returns the original template if calibration fails (never breaks OMR).
  BubbleTemplate _calibrateTemplate(img.Image image, BubbleTemplate template) {
    try {
      final scaleFactor = image.width / 1600.0;
      final scaled = scaleFactor != 1.0
          ? _scaleTemplate(template, scaleFactor)
          : template;

      final optCount = scaled.optionCount;
      final sampleRadius = scaled.bubbleRadius.toInt().clamp(4, 12);
      final halfBand = (scaled.rowSpacing * 0.4).round().clamp(3, 15);

      // Sample rows: first, middle, last
      final sampleIndices = <int>[0];
      if (scaled.questionCount > 2) {
        sampleIndices.add(scaled.questionCount ~/ 2);
      }
      if (scaled.questionCount > 1) {
        sampleIndices.add(scaled.questionCount - 1);
      }

      final detectedCenters = <double, double>{}; // detectedX → expectedX
      final detectedYs = <double, double>{};       // row index → detectedY

      for (final qi in sampleIndices) {
        final expectedY = scaled.startY + qi * scaled.rowSpacing;
        final yInt = expectedY.round();

        // Scan horizontally for each expected option position
        for (int oi = 0; oi < optCount; oi++) {
          final expectedX = scaled.startX + oi * scaled.columnSpacing;
          final xInt = expectedX.round();

          // Search window: ±columnSpacing/2 around expected position
          final searchRadius = (scaled.columnSpacing * 0.5).round().clamp(10, 100);
          final startX = (xInt - searchRadius).clamp(sampleRadius, image.width - sampleRadius - 1);
          final endX = (xInt + searchRadius).clamp(sampleRadius, image.width - sampleRadius - 1);

          double bestFill = 0;
          int bestX = xInt;

          // Scan with step size for speed (every 2-3 pixels)
          final step = (sampleRadius / 2).ceil().clamp(1, 4);
          for (int sx = startX; sx <= endX; sx += step) {
            final fill = _sampleFillRatio(
              image, sx, yInt, sampleRadius,
            );
            if (fill > bestFill) {
              bestFill = fill;
              bestX = sx;
            }
          }

          // Only use if fill is meaningful (> 0.1 — some dark pixels exist)
          if (bestFill > 0.1) {
            detectedCenters[bestX.toDouble()] = expectedX;
          }
        }

        // Also detect the actual Y by scanning vertically at the best X
        if (detectedCenters.isNotEmpty) {
          final sampleX = detectedCenters.keys.first.round();
          double bestYFill = 0;
          int bestY = yInt;
          for (int sy = (yInt - halfBand).clamp(1, image.height - 2);
               sy <= (yInt + halfBand).clamp(1, image.height - 2);
               sy++) {
            final fill = _sampleFillRatio(image, sampleX, sy, sampleRadius);
            if (fill > bestYFill) {
              bestYFill = fill;
              bestY = sy;
            }
          }
          if (bestYFill > 0.1) {
            detectedYs[qi.toDouble()] = bestY.toDouble();
          }
        }
      }

      // Compute corrections
      if (detectedCenters.length < optCount) {
        // Not enough detections — use original template
        return scaled;
      }

      // X correction: linear fit (detectedX = expectedX * scaleX + offsetX)
      final xEntries = detectedCenters.entries.toList();
      double sumDetX = 0, sumExpX = 0;
      for (final e in xEntries) {
        sumDetX += e.key;
        sumExpX += e.value;
      }
      final avgDetX = sumDetX / xEntries.length;
      final avgExpX = sumExpX / xEntries.length;

      // Compute X scale from first and last detected option
      double xScale = 1.0;
      if (xEntries.length >= 2) {
        final detRange = xEntries.last.key - xEntries.first.key;
        final expRange = xEntries.last.value - xEntries.first.value;
        if (expRange.abs() > 1) {
          xScale = detRange / expRange;
        }
      }
      final xOffset = avgDetX - avgExpX * xScale;

      // Y correction: from detected row positions
      double yScale = 1.0;
      double yOffset = 0;
      if (detectedYs.length >= 2) {
        final yEntries = detectedYs.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
        final detRange = yEntries.last.value - yEntries.first.value;
        final expRange = yEntries.last.key - yEntries.first.key;
        if (expRange.abs() > 1) {
          yScale = detRange / expRange;
        }
        final avgDetY = yEntries.fold(0.0, (s, e) => s + e.value) / yEntries.length;
        final avgExpY = yEntries.fold(0.0, (s, e) => s + e.key) / yEntries.length;
        yOffset = avgDetY - avgExpY * yScale;
      } else if (detectedYs.length == 1) {
        final entry = detectedYs.entries.first;
        final expectedY = scaled.startY + entry.key * scaled.rowSpacing;
        yOffset = entry.value - expectedY;
      }

      // Apply corrections: newStart = oldStart * scale + offset
      final correctedStartX = scaled.startX * xScale + xOffset;
      final correctedStartY = scaled.startY * yScale + yOffset;
      final correctedColSpacing = scaled.columnSpacing * xScale;
      final correctedRowSpacing = scaled.rowSpacing * yScale;

      // Sanity check: corrections should be reasonable
      final xCorrectionMagnitude = (correctedStartX - scaled.startX).abs();
      final yCorrectionMagnitude = (correctedStartY - scaled.startY).abs();
      if (xCorrectionMagnitude > scaled.columnSpacing * 3 ||
          yCorrectionMagnitude > scaled.rowSpacing * scaled.questionCount * 0.5) {
        // Correction too large — likely a detection error, use original
        debugPrint('OMR: calibration rejected — corrections too large '
            '(dx=${xCorrectionMagnitude.toStringAsFixed(0)}, '
            'dy=${yCorrectionMagnitude.toStringAsFixed(0)})');
        return scaled;
      }

      debugPrint(
        'OMR: calibrated — offset(${xOffset.toStringAsFixed(1)}, '
        '${yOffset.toStringAsFixed(1)}), scale(${xScale.toStringAsFixed(3)}, '
        '${yScale.toStringAsFixed(3)})',
      );

      return BubbleTemplate(
        name: '${scaled.name} [calibrated]',
        questionCount: scaled.questionCount,
        options: scaled.options,
        startX: correctedStartX,
        startY: correctedStartY,
        columnSpacing: correctedColSpacing,
        rowSpacing: correctedRowSpacing,
        bubbleRadius: scaled.bubbleRadius,
        fillThreshold: scaled.fillThreshold,
      );
    } catch (e) {
      debugPrint('OMR: calibration failed ($e), using original template');
      return template;
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

  /// Average brightness of the entire image (0.0 = black, 1.0 = white).
  double _averageBrightness(img.Image image) {
    int totalBrightness = 0;
    int count = 0;

    // Sample every 10th pixel for speed
    for (int y = 0; y < image.height; y += 10) {
      for (int x = 0; x < image.width; x += 10) {
        totalBrightness += image.getPixel(x, y).r.toInt();
        count++;
      }
    }

    return count > 0 ? totalBrightness / (count * 255.0) : 1.0;
  }
}

/// A single detected answer from OMR.
class OmrAnswer {
  final int questionNumber;
  final String answer;
  final double confidence;
  final double fillRatio;
  final bool flagged; // true if detected with low certainty (pencil, smudge)

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

  /// Fill ratio matrix: questionNumber → {option → fillRatio}
  /// Useful for debugging and the review screen.
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

  /// Count of answers flagged for review (pencil, ambiguity).
  int get flaggedCount => answers.where((a) => a.flagged).length;
}
