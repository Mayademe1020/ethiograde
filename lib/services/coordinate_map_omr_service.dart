import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/assessment.dart';
import '../models/coordinate_map.dart';
import '../services/answer_sheet_generator.dart';

/// Coordinate-map-aware OMR scanning service.
///
/// Phase 4 of the OMR pipeline. Consumes:
/// - A photo of a filled answer sheet
/// - The CoordinateMap (mm positions from Phase 1)
///
/// Pipeline:
/// 1. Find 4 anchor squares in the image
/// 2. Compute perspective transform from anchors
/// 3. Map mm coordinates → pixel positions
/// 4. Sample bubble darkness at each position
/// 5. Detect filled answers with confidence
///
/// Design decisions:
/// - Anchor-based correction (not generic edge detection) — more reliable
/// - Pure Dart + image package — no ML, no network
/// - Returns CoordinateMapResult with per-question answers + confidence
/// - Never throws — returns empty result on failure
class CoordinateMapOmrService {
  static final CoordinateMapOmrService _instance =
      CoordinateMapOmrService._();
  factory CoordinateMapOmrService() => _instance;
  CoordinateMapOmrService._();

  /// Scan a filled answer sheet image using a coordinate map.
  ///
  /// [imagePath] — path to the photo (raw or enhanced)
  /// [coordinateMap] — the mm-position map from Phase 1 generation
  /// [assessment] — the assessment for answer comparison
  ///
  /// Returns [CoordinateMapOmrResult] with detected answers.
  Future<CoordinateMapOmrResult> scan({
    required String imagePath,
    required CoordinateMap coordinateMap,
    required Assessment assessment,
  }) async {
    try {
      // 1. Load image
      final file = File(imagePath);
      if (!await file.exists()) {
        debugPrint('CM-OMR: image not found: $imagePath');
        return CoordinateMapOmrResult.empty;
      }

      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        debugPrint('CM-OMR: could not decode image');
        return CoordinateMapOmrResult.empty;
      }

      // 2. Detect anchors
      final anchors = _detectAnchors(image, coordinateMap);
      if (anchors.length < 4) {
        debugPrint('CM-OMR: only ${anchors.length}/4 anchors found');
        return CoordinateMapOmrResult.empty;
      }

      // 3. Compute perspective transform (anchors → page mm)
      final transform = _computeTransform(anchors, coordinateMap);
      if (transform == null) {
        debugPrint('CM-OMR: perspective transform failed');
        return CoordinateMapOmrResult.empty;
      }

      // 4. Check answer key checkbox (if present in coordinate map)
      bool isAnswerKey = false;
      final checkboxMeta = coordinateMap.metadata['answerKeyCheckbox'];
      if (checkboxMeta != null && checkboxMeta is Map) {
        final cbXm = (checkboxMeta['xMm'] ?? 0).toDouble();
        final cbYm = (checkboxMeta['yMm'] ?? 0).toDouble();
        final cbWm = (checkboxMeta['widthMm'] ?? 5.0).toDouble();
        final cbHm = (checkboxMeta['heightMm'] ?? 5.0).toDouble();

        // Sample center of checkbox
        final cbCenter = _mmToPixel(
          cbXm + cbWm / 2,
          cbYm + cbHm / 2,
          image.width,
          image.height,
          transform);
        if (cbCenter != null) {
          final cbRadius = _mmToPixels(cbWm / 2, image.width, transform);
          final cbFill = _sampleFillRatio(
            image,
            cbCenter.x.toInt(),
            cbCenter.y.toInt(),
            cbRadius.toInt().clamp(3, 25));
          // Checkbox threshold is higher than bubble — must be clearly filled
          if (cbFill > 0.50) {
            isAnswerKey = true;
            debugPrint('CM-OMR: ANSWER KEY detected (checkbox fill: ${cbFill.toStringAsFixed(2)})');
          }
        }
      }

      // 5. Sample bubbles
      final detected = <CoordinateMapAnswer>[];
      int objectiveCount = 0;

      for (final qMap in coordinateMap.questions) {
        final assessmentQ = assessment.questions.firstWhere(
          (q) => q.number == qMap.number,
          orElse: () => Question(number: 0, type: QuestionType.mcq));

        if (assessmentQ.number == 0) continue; // Question not in assessment
        if (!assessmentQ.isObjective) continue; // Skip essay/short answer

        objectiveCount++;

        // Find the filled bubble
        double bestFill = 0;
        String? bestOption;
        final fillRatios = <String, double>{};

        for (final bubble in qMap.bubbles) {
          // Convert mm → pixel
          final pixelPos = _mmToPixel(
            bubble.xMm,
            bubble.yMm,
            image.width,
            image.height,
            transform);
          if (pixelPos == null) continue;

          // Sample fill ratio
          final radius = _mmToPixels(bubble.widthMm / 2, image.width, transform);
          final fillRatio = _sampleFillRatio(
            image,
            pixelPos.x.toInt(),
            pixelPos.y.toInt(),
            radius.toInt().clamp(2, 20));

          fillRatios[bubble.option] = fillRatio;

          if (fillRatio > bestFill) {
            bestFill = fillRatio;
            bestOption = bubble.option;
          }
        }

        // Determine if a bubble is filled (threshold-based)
        const fillThreshold = 0.35;
        const pencilThreshold = 0.20;

        String? answer;
        double confidence = 0;

        if (bestFill > fillThreshold) {
          answer = bestOption;
          // Count how many are above threshold
          final filledCount =
              fillRatios.values.where((f) => f > fillThreshold).length;
          if (filledCount > 1) {
            confidence = 0.5; // Ambiguous
          } else {
            confidence = _fillConfidence(bestFill, fillThreshold);
          }
        } else if (bestFill > pencilThreshold) {
          // Pencil mark — lower confidence
          answer = bestOption;
          confidence = 0.4;
        }
        // else: no fill detected → answer stays null → MISSING in scoring

        detected.add(CoordinateMapAnswer(
          questionNumber: qMap.number,
          detectedAnswer: answer ?? '',
          correctAnswer: assessmentQ.correctAnswer?.toString() ?? '',
          confidence: confidence,
          fillRatio: bestFill,
          fillRatios: fillRatios,
          isCorrect: answer != null &&
              answer.toUpperCase() ==
                  (assessmentQ.correctAnswer?.toString() ?? '').toUpperCase(),
          questionType: qMap.type == SheetQuestionType.trueFalse
              ? 'T/F'
              : 'MCQ'));
      }

      final correct = detected.where((a) => a.isCorrect).length;
      final total = detected.length;
      final avgConfidence = detected.isEmpty
          ? 0.0
          : detected.fold(0.0, (s, a) => s + a.confidence) / detected.length;

      debugPrint(
        'CM-OMR: $correct/$total correct, '
        'avg confidence: ${avgConfidence.toStringAsFixed(2)}');

      return CoordinateMapOmrResult(
        answers: detected,
        totalQuestions: total,
        correctAnswers: correct,
        averageConfidence: avgConfidence,
        anchorsDetected: 4,
        isAnswerKey: isAnswerKey);
    } catch (e, st) {
      debugPrint('CM-OMR: scan failed ($e)\n$st');
      return CoordinateMapOmrResult.empty;
    }
  }

  // ── Anchor Detection ──────────────────────────────────────────────

  /// Detect anchor squares in the image.
  ///
  /// Returns detected anchors mapped to their coordinate map corners.
  /// Uses the known mm positions from the coordinate map to search
  /// in approximate regions of the image.
  List<_DetectedAnchor> _detectAnchors(
    img.Image image,
    CoordinateMap coordMap) {
    final detected = <_DetectedAnchor>[];

    for (final anchor in coordMap.anchors) {
      // Convert anchor mm position to approximate pixel position
      // (assuming no distortion as initial guess)
      final approxX = _mmToPixelRaw(
          anchor.position.xMm + anchor.position.widthMm / 2, image.width);
      final approxY = _mmToPixelRaw(
          anchor.position.yMm + anchor.position.heightMm / 2, image.height);

      // Search in a region around the approximate position
      final searchRadius = _mmToPixelRaw(15, image.width); // 15mm search radius
      final anchorSizePx =
          _mmToPixelRaw(anchor.position.widthMm, image.width).toInt();

      final bestMatch = _findDarkestSquare(
        image,
        approxX.toInt(),
        approxY.toInt(),
        searchRadius.toInt(),
        anchorSizePx);

      if (bestMatch != null) {
        detected.add(_DetectedAnchor(
          corner: anchor.corner,
          pixelX: bestMatch.x,
          pixelY: bestMatch.y,
          mmX: anchor.position.xMm + anchor.position.widthMm / 2,
          mmY: anchor.position.yMm + anchor.position.heightMm / 2,
          darkness: bestMatch.darkness));
      }
    }

    return detected;
  }

  /// Find the darkest square region near a given position.
  ///
  /// Scans a grid of positions within the search radius and returns
  /// the position with the darkest average pixel value.
  ({double x, double y, double darkness})? _findDarkestSquare(
    img.Image image,
    int centerX,
    int centerY,
    int searchRadius,
    int squareSize) {
    double bestDarkness = 0;
    int bestX = centerX;
    int bestY = centerY;

    final step = math.max(2, squareSize ~/ 3);

    for (int dy = -searchRadius; dy <= searchRadius; dy += step) {
      for (int dx = -searchRadius; dx <= searchRadius; dx += step) {
        final px = centerX + dx;
        final py = centerY + dy;

        final darkness = _measureDarkness(image, px, py, squareSize);
        if (darkness > bestDarkness) {
          bestDarkness = darkness;
          bestX = px;
          bestY = py;
        }
      }
    }

    // Must be significantly dark to be an anchor (anchors are black squares)
    if (bestDarkness < 0.5) return null;

    return (x: bestX.toDouble(), y: bestY.toDouble(), darkness: bestDarkness);
  }

  /// Measure average darkness of a square region (0.0 = white, 1.0 = black).
  double _measureDarkness(
    img.Image image,
    int cx,
    int cy,
    int size) {
    final half = size ~/ 2;
    int darkCount = 0;
    int total = 0;

    for (int dy = -half; dy <= half; dy++) {
      for (int dx = -half; dx <= half; dx++) {
        final px = cx + dx;
        final py = cy + dy;
        if (px < 0 || px >= image.width || py < 0 || py >= image.height)
          continue;

        final brightness = image.getPixel(px, py).r / 255.0;
        if (brightness < 0.3) darkCount++;
        total++;
      }
    }

    return total > 0 ? darkCount / total : 0.0;
  }

  // ── Perspective Transform ─────────────────────────────────────────

  /// Compute a perspective transform from detected anchors to page mm.
  ///
  /// Maps mm coordinates to pixel coordinates using the 4 anchor correspondences.
  _MmTransform? _computeTransform(
    List<_DetectedAnchor> anchors,
    CoordinateMap coordMap) {
    if (anchors.length < 4) return null;

    // Order anchors by corner name
    final ordered = <String, _DetectedAnchor>{};
    for (final a in anchors) {
      ordered[a.corner] = a;
    }

    // Need all 4 corners
    final tl = ordered['topLeft'];
    final tr = ordered['topRight'];
    final br = ordered['bottomRight'];
    final bl = ordered['bottomLeft'];

    if (tl == null || tr == null || br == null || bl == null) return null;

    // Source: mm positions (what we know from coordinate map)
    final srcMm = [
      (tl.mmX, tl.mmY),
      (tr.mmX, tr.mmY),
      (br.mmX, br.mmY),
      (bl.mmX, bl.mmY),
    ];

    // Destination: pixel positions (where we detected anchors)
    final dstPixels = [
      (tl.pixelX, tl.pixelY),
      (tr.pixelX, tr.pixelY),
      (br.pixelX, br.pixelY),
      (bl.pixelX, bl.pixelY),
    ];

    // Compute homography: mm → pixel
    final h = _computeHomography(srcMm, dstPixels);
    if (h == null) return null;

    return _MmTransform(h);
  }

  /// Compute homography matrix from 4 point correspondences.
  List<double>? _computeHomography(
    List<(double, double)> src,
    List<(double, double)> dst) {
    final a = List.generate(8, (_) => List<double>.filled(8, 0));
    final b = List<double>.filled(8, 0);

    for (int i = 0; i < 4; i++) {
      final (sx, sy) = src[i];
      final (dx, dy) = dst[i];

      final row = i * 2;
      a[row][0] = sx;
      a[row][1] = sy;
      a[row][2] = 1;
      a[row][3] = 0;
      a[row][4] = 0;
      a[row][5] = 0;
      a[row][6] = -sx * dx;
      a[row][7] = -sy * dx;
      b[row] = dx;

      a[row + 1][0] = 0;
      a[row + 1][1] = 0;
      a[row + 1][2] = 0;
      a[row + 1][3] = sx;
      a[row + 1][4] = sy;
      a[row + 1][5] = 1;
      a[row + 1][6] = -sx * dy;
      a[row + 1][7] = -sy * dy;
      b[row + 1] = dy;
    }

    return _solveLinear(a, b);
  }

  List<double>? _solveLinear(List<List<double>> a, List<double> b) {
    final n = 8;
    final aug = List.generate(n, (i) => [...a[i], b[i]]);

    for (int col = 0; col < n; col++) {
      int maxRow = col;
      double maxVal = aug[col][col].abs();
      for (int row = col + 1; row < n; row++) {
        if (aug[row][col].abs() > maxVal) {
          maxVal = aug[row][col].abs();
          maxRow = row;
        }
      }
      if (maxVal < 1e-10) return null;

      if (maxRow != col) {
        final tmp = aug[col];
        aug[col] = aug[maxRow];
        aug[maxRow] = tmp;
      }

      for (int row = col + 1; row < n; row++) {
        final factor = aug[row][col] / aug[col][col];
        for (int j = col; j <= n; j++) {
          aug[row][j] -= factor * aug[col][j];
        }
      }
    }

    final result = List<double>.filled(n, 0);
    for (int i = n - 1; i >= 0; i--) {
      result[i] = aug[i][n];
      for (int j = i + 1; j < n; j++) {
        result[i] -= aug[i][j] * result[j];
      }
      result[i] /= aug[i][i];
    }

    return result;
  }

  // ── Coordinate Conversion ─────────────────────────────────────────

  /// Convert mm coordinates to pixel position using perspective transform.
  ({double x, double y})? _mmToPixel(
    double mmX,
    double mmY,
    int imageWidth,
    int imageHeight,
    _MmTransform transform) {
    final result = transform.mmToPixel(mmX, mmY);
    if (result == null) return null;

    // Clamp to image bounds
    return (
      x: result.x.clamp(0, imageWidth - 1).toDouble(),
      y: result.y.clamp(0, imageHeight - 1).toDouble());
  }

  /// Convert mm to raw pixels (no transform, assuming 1:1 mapping).
  double _mmToPixelRaw(double mm, int imageSize) {
    // Assume image covers ~210mm (A4 width)
    return mm / 210.0 * imageSize;
  }

  double _mmToPixels(double mm, int imageSize, _MmTransform transform) {
    return _mmToPixelRaw(mm, imageSize);
  }

  // ── Fill Sampling ─────────────────────────────────────────────────

  /// Sample fill ratio at a pixel position.
  double _sampleFillRatio(img.Image image, int cx, int cy, int radius) {
    int darkCount = 0;
    int total = 0;

    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        final px = cx + dx;
        final py = cy + dy;
        if (px < 0 || px >= image.width || py < 0 || py >= image.height)
          continue;

        final brightness = image.getPixel(px, py).r / 255.0;
        if (brightness < 0.4) darkCount++;
        total++;
      }
    }

    return total > 0 ? darkCount / total : 0.0;
  }

  double _fillConfidence(double fillRatio, double threshold) {
    if (fillRatio <= threshold) return 0.0;
    final excess = (fillRatio - threshold) / (1.0 - threshold);
    return 0.5 + excess * 0.5;
  }
}

/// Perspective transform mapping mm → pixel.
class _MmTransform {
  final List<double> h; // 3x3 homography (mm → pixel)

  _MmTransform(this.h);

  /// Convert mm coordinates to pixel coordinates.
  ({double x, double y})? mmToPixel(double mmX, double mmY) {
    final w = h[6] * mmX + h[7] * mmY + 1.0;
    if (w.abs() < 1e-10) return null;
    return (
      x: (h[0] * mmX + h[1] * mmY + h[2]) / w,
      y: (h[3] * mmX + h[4] * mmY + h[5]) / w);
  }
}

/// A detected anchor in pixel space.
class _DetectedAnchor {
  final String corner;
  final double pixelX;
  final double pixelY;
  final double mmX;
  final double mmY;
  final double darkness;

  _DetectedAnchor({
    required this.corner,
    required this.pixelX,
    required this.pixelY,
    required this.mmX,
    required this.mmY,
    required this.darkness,
  });
}

/// A single detected answer from coordinate-map OMR.
class CoordinateMapAnswer {
  final int questionNumber;
  final String detectedAnswer;
  final String correctAnswer;
  final double confidence;
  final double fillRatio;
  final Map<String, double> fillRatios;
  final bool isCorrect;
  final String questionType; // 'MCQ' or 'T/F'

  const CoordinateMapAnswer({
    required this.questionNumber,
    required this.detectedAnswer,
    required this.correctAnswer,
    required this.confidence,
    required this.fillRatio,
    required this.fillRatios,
    required this.isCorrect,
    required this.questionType,
  });

  bool get isEmpty => detectedAnswer.isEmpty;
}

/// Full result from coordinate-map OMR scanning.
class CoordinateMapOmrResult {
  final List<CoordinateMapAnswer> answers;
  final int totalQuestions;
  final int correctAnswers;
  final double averageConfidence;
  final int anchorsDetected;
  final bool isAnswerKey; // true if the answer key checkbox was filled

  const CoordinateMapOmrResult({
    required this.answers,
    required this.totalQuestions,
    required this.correctAnswers,
    required this.averageConfidence,
    required this.anchorsDetected,
    this.isAnswerKey = false,
  });

  static const CoordinateMapOmrResult empty = CoordinateMapOmrResult(
    answers: [],
    totalQuestions: 0,
    correctAnswers: 0,
    averageConfidence: 0,
    anchorsDetected: 0,
    isAnswerKey: false);

  double get percentage =>
      totalQuestions > 0 ? (correctAnswers / totalQuestions) * 100 : 0;

  int get missingAnswers =>
      answers.where((a) => a.isEmpty).length;

  int get lowConfidenceAnswers =>
      answers.where((a) => a.confidence < 0.6 && !a.isEmpty).length;

  /// Extract answer key as a map of questionNumber → answer.
  /// Used when isAnswerKey is true.
  Map<int, String> get answerKey {
    final key = <int, String>{};
    for (final a in answers) {
      if (a.detectedAnswer.isNotEmpty) {
        key[a.questionNumber] = a.detectedAnswer;
      }
    }
    return key;
  }
}
