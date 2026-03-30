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

      final detectedAnswers = <OmrAnswer>[];
      final fillMatrix = <int, Map<String, double>>{};

      for (int qi = 0; qi < scaledTemplate.questionCount; qi++) {
        final optionFills = <String, double>{};
        double maxFill = 0;
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

          if (fillRatio > maxFill) {
            maxFill = fillRatio;
          }

          if (fillRatio > scaledTemplate.fillThreshold && fillRatio > bestFill) {
            bestOption = option;
            bestFill = fillRatio;
          }
        }

        fillMatrix[qi + 1] = optionFills;

        if (bestOption != null) {
          // Check if multiple options are close to the threshold — ambiguous
          final filledOptions = optionFills.entries
              .where((e) => e.value > scaledTemplate.fillThreshold)
              .length;

          double confidence;
          if (filledOptions > 1) {
            // Multiple filled → lower confidence, might be eraser marks or smudges
            confidence = 0.5;
          } else {
            // Single clear fill — confidence based on how decisively above threshold
            confidence = _fillConfidence(bestFill, scaledTemplate.fillThreshold);
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

          if (mostFilled.value > scaledTemplate.fillThreshold * 0.6) {
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
        'OMR: ${detectedAnswers.length}/${scaledTemplate.questionCount} detected, '
        'avg confidence: ${detectedAnswers.isEmpty ? 0 : (detectedAnswers.fold(0.0, (s, a) => s + a.confidence) / detectedAnswers.length).toStringAsFixed(2)}',
      );

      return OmrResult(
        answers: detectedAnswers,
        fillMatrix: fillMatrix,
        templateName: scaledTemplate.name,
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

  /// Sample the fill ratio at a specific position.
  ///
  /// Returns 0.0 (empty) to 1.0 (fully filled).
  /// Uses a square sampling region centered at (cx, cy) with the
  /// given radius. Counts pixels below a brightness threshold.
  double _sampleFillRatio(img.Image image, int cx, int cy, int radius) {
    final halfSize = radius;
    int darkCount = 0;
    int totalCount = 0;

    for (int dy = -halfSize; dy <= halfSize; dy++) {
      for (int dx = -halfSize; dx <= halfSize; dx++) {
        final px = cx + dx;
        final py = cy + dy;

        if (px < 0 || px >= image.width || py < 0 || py >= image.height) continue;

        final pixel = image.getPixel(px, py);
        // Grayscale image — all channels equal, use red
        final brightness = pixel.r / 255.0;

        if (brightness < 0.4) darkCount++; // darker than 40% = likely filled
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

  /// Scale all coordinates in a template by a factor.
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
