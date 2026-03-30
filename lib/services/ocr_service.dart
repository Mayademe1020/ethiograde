import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/scan_result.dart';
import '../models/assessment.dart';
import 'answer_parser.dart';
import 'scoring_service.dart';
import 'image_hash_service.dart';

/// Offline OCR and image processing service.
/// Uses ML Kit text recognition (runs on-device, no internet required).
///
/// Image enhancement philosophy:
/// ML Kit's TextRecognizer has its own preprocessing pipeline. We do the
/// minimum that helps it: downscale for memory, boost contrast for ink/paper
/// separation, and convert to grayscale. Everything else (sharpen, denoise,
/// binarize) is counterproductive — it destroys information ML Kit could use.
class OcrService {
  static final OcrService _instance = OcrService._();
  factory OcrService() => _instance;
  OcrService._();

  late final TextRecognizer _textRecognizer;
  final AnswerParser _parser = const AnswerParser();
  final ScoringService _scoring = const ScoringService();
  final ImageHashService _hasher = ImageHashService();
  bool _isInitialized = false;

  /// Minimum confidence to accept a detected text line.
  static const double _minConfidence = 0.5;

  /// Maximum image dimension for enhancement.
  /// Scales down to protect 2GB devices and speed up processing.
  static const int _maxImageDimension = 1600;

  /// Fallback dimension when OOM occurs during enhancement.
  /// 1080p is still readable by ML Kit while using ~4x less memory than 1600px.
  static const int _oomRetryDimension = 1080;

  /// Skew angle threshold — beyond this, we warn the teacher.
  static const double _skewWarningDegrees = 8.0;

  /// Minimum skew angle to trigger automatic rotation correction (degrees).
  /// Below this, correction isn't worth the processing cost.
  static const double _skewCorrectionThreshold = 3.0;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    _isInitialized = true;
  }

  /// Enhance image for OCR with minimal processing.
  ///
  /// Strategy: ML Kit does its own preprocessing. We only do what it can't:
  /// 1. EXIF rotation correction (camera orientation)
  /// 2. Downscale to [_maxImageDimension] (memory protection)
  /// 3. Grayscale (halves data, text is luminance)
  /// 4. Contrast boost (ink/paper separation in poor lighting)
  ///
  /// No pixel loops. No binarization. No sharpening. No denoising.
  /// All operations use the `image` package's native-compiled routines.
  ///
  /// On [OutOfMemoryError], retries at [_oomRetryDimension] (1080p).
  /// Returns original path on total failure — never crashes the pipeline.
  Future<String> enhanceImage(String imagePath) async {
    try {
      final result = await _enhanceImageAtDimension(imagePath, _maxImageDimension);
      return result;
    } on OutOfMemoryError {
      debugPrint('OCR: OOM at ${_maxImageDimension}px, retrying at ${_oomRetryDimension}px');
      try {
        final result = await _enhanceImageAtDimension(imagePath, _oomRetryDimension);
        return result;
      } catch (e) {
        debugPrint('OCR: enhanceImage OOM retry failed (${e.runtimeType})');
        return imagePath;
      }
    } catch (e) {
      debugPrint('OCR: enhanceImage failed (${e.runtimeType})');
      return imagePath;
    }
  }

  /// Core image enhancement at a given max dimension.
  /// Extracted so [enhanceImage] can retry at lower resolution on OOM.
  Future<String> _enhanceImageAtDimension(String imagePath, int maxDim) async {
    final file = File(imagePath);
    if (!await file.exists()) return imagePath;

    final bytes = await file.readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return imagePath;

    // ── EXIF rotation correction ──
    // Camera photos often have orientation metadata (phone held landscape,
    // front camera mirror, etc.). ML Kit reads raw pixels, not EXIF, so we
    // must bake the orientation into the pixel data first.
    image = img.bakeOrientation(image);

    // Downscale — protects memory on cheap phones, speeds up ML Kit
    if (image.width > maxDim || image.height > maxDim) {
      final longer = image.width > image.height ? image.width : image.height;
      final ratio = maxDim / longer;
      image = img.copyResize(
        image,
        width: (image.width * ratio).round(),
        height: (image.height * ratio).round(),
        interpolation: img.Interpolation.cubic, // best quality for text
      );
    }

    // Grayscale — text recognition is about luminance, not color
    image = img.grayscale(image);

    // Contrast boost — helps in dim classrooms, fluorescent lighting
    // Moderate values: too aggressive destroys subtle ink differences
    image = img.adjustColor(image, contrast: 1.2);

    // Save as JPEG (smaller than PNG, faster to load for ML Kit)
    final dotIndex = imagePath.lastIndexOf('.');
    final basePath = dotIndex > 0 ? imagePath.substring(0, dotIndex) : imagePath;
    final enhancedPath = '${basePath}_enhanced.jpg';
    await File(enhancedPath).writeAsBytes(img.encodeJpg(image, quality: 92));

    return enhancedPath;
  }

  /// Correct paper rotation by rotating the image by -[angleDegrees].
  ///
  /// Called after ML Kit detects significant skew (> [_skewCorrectionThreshold]).
  /// Uses the `image` package's native copyRotate — pure Dart, no pixel loops.
  ///
  /// Returns the path to the corrected image, or the original path if
  /// correction fails (never crashes the grading pipeline).
  Future<String> correctRotation(String imagePath, double angleDegrees) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return imagePath;

      final bytes = await file.readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return imagePath;

      // Rotate by negative angle (undo the skew)
      image = img.copyRotate(image, angle: -angleDegrees);

      // Save corrected image alongside the original
      final dotIndex = imagePath.lastIndexOf('.');
      final basePath = dotIndex > 0 ? imagePath.substring(0, dotIndex) : imagePath;
      final correctedPath = '${basePath}_corrected.jpg';
      await File(correctedPath).writeAsBytes(img.encodeJpg(image, quality: 92));

      debugPrint('OCR: rotation corrected by ${angleDegrees.toStringAsFixed(1)}°');
      return correctedPath;
    } catch (e) {
      debugPrint('OCR: correctRotation failed (${e.runtimeType})');
      return imagePath;
    }
  }

  /// Process a scanned paper and extract answers.
  /// Returns answers matched against the assessment's answer key.
  Future<ScanResult> processScannedPaper({
    required String imagePath,
    required Assessment assessment,
    required String studentId,
    required String studentName,
  }) async {
    await initialize();

    // 0. Compute perceptual hash for duplicate detection (before enhancement)
    final imageHash = _hasher.computeHash(imagePath);

    // 1. Enhance image (downscale + grayscale + contrast)
    final enhancedPath = await enhanceImage(imagePath);

    // 2. Extract text regions using ML Kit (on-device, offline)
    final extractionResult = await extractTextRegions(enhancedPath);

    // 2b. Rotation correction pass — if paper is tilted, correct and re-OCR
    // This improves accuracy on papers photographed at an angle (common on
    // cheap phones without OIS). Only re-run if skew is significant AND
    // correction might actually help (not already near-perfect).
    var workingPath = enhancedPath;
    var workingResult = extractionResult;
    if (extractionResult.skewAngle.abs() > _skewCorrectionThreshold) {
      final correctedPath = await correctRotation(
        enhancedPath,
        extractionResult.skewAngle,
      );
      // Only re-OCR if the file was actually changed
      if (correctedPath != enhancedPath) {
        final reOcrResult = await extractTextRegions(correctedPath);
        // Use corrected result if it found more regions (better detection)
        if (reOcrResult.regions.length >= workingResult.regions.length) {
          workingPath = correctedPath;
          workingResult = reOcrResult;
        }
      }
    }

    // 3. Parse question numbers and answers
    final parsedAnswers = _parseAnswers(workingResult.regions, assessment);

    // 4. Deduplicate — if ML Kit reads the same Q# twice, keep highest confidence
    final deduplicated = _scoring.deduplicateAnswers(parsedAnswers);

    // 5. Score against answer key
    final scoredAnswers = _scoring.scoreAnswers(
      detected: deduplicated,
      assessment: assessment,
    );

    // 6. Calculate totals
    final totalScore = _scoring.calculateTotalScore(scoredAnswers);
    final maxScore = assessment.maxScore;
    final percentage = _scoring.calculatePercentage(
      totalScore: totalScore,
      maxScore: maxScore,
    );
    final overallConfidence = _scoring.calculateConfidence(scoredAnswers);

    // 7. Build metadata with quality signals
    final metadata = <String, dynamic>{
      'textLinesDetected': workingResult.regions.length,
      'questionsDetected': deduplicated.length,
      'duplicatesRemoved': parsedAnswers.length - deduplicated.length,
      'skewAngle': workingResult.skewAngle,
      'skewWarning': workingResult.skewAngle.abs() > _skewWarningDegrees,
      'rotationCorrected': workingPath != enhancedPath,
    };

    return ScanResult(
      assessmentId: assessment.id,
      studentId: studentId,
      studentName: studentName,
      imagePath: imagePath,
      enhancedImagePath: workingPath,
      answers: scoredAnswers,
      totalScore: totalScore,
      maxScore: maxScore,
      percentage: percentage,
      grade: _scoring.calculateGrade(percentage.toDouble(), assessment.rubricType),
      status: overallConfidence < 0.6 ? ScanStatus.needsRescan : ScanStatus.graded,
      confidence: overallConfidence,
      imageHash: imageHash,
      metadata: metadata,
    );
  }

  /// Extract text regions from an enhanced image using ML Kit.
  /// Also estimates paper skew angle from text block alignment.
  ///
  /// Public so HybridGradingService can run OCR and OMR on the same
  /// enhanced image without double-enhancing.
  Future<({List<TextRegion> regions, double skewAngle})> extractTextRegions(
    String imagePath,
  ) async {
    await initialize();

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognized = await _textRecognizer.processImage(inputImage);

      final regions = <TextRegion>[];
      double totalAngle = 0;
      int angleCount = 0;

      for (final block in recognized.blocks) {
        // Estimate skew from block angle
        if (block.cornerPoints.length >= 2) {
          final p1 = block.cornerPoints[0];
          final p2 = block.cornerPoints[1];
          final angle = math.atan2(
            (p2.y - p1.y).toDouble(),
            (p2.x - p1.x).toDouble(),
          );
          totalAngle += angle;
          angleCount++;
        }

        for (final line in block.lines) {
          final text = line.text.trim();
          if (text.isEmpty) continue;

          // Confidence from character-level detection
          double confidence = 0.8;
          if (line.elements.isNotEmpty) {
            final confidences = line.elements
                .map((e) => e.confidence ?? 0.8)
                .toList();
            confidence = confidences.reduce((a, b) => a + b) / confidences.length;
          }

          if (confidence < _minConfidence) continue;

          // Position from bounding box
          final points = line.cornerPoints;
          double x = 0, y = 0;
          if (points != null && points.isNotEmpty) {
            x = points.map((p) => p.x.toDouble()).reduce(math.min);
            y = points.map((p) => p.y.toDouble()).reduce(math.min);
          }

          regions.add(TextRegion(
            text: text,
            confidence: confidence.clamp(0.0, 1.0),
            x: x,
            y: y,
          ));
        }
      }

      // Sort: top-to-bottom, left-to-right within same line
      double yTolerance = 10.0;
      if (regions.length > 1) {
        final ys = regions.map((r) => r.y);
        yTolerance = (ys.reduce(math.max) - ys.reduce(math.min)) * 0.05;
      }
      regions.sort((a, b) {
        if ((a.y - b.y).abs() < yTolerance) return a.x.compareTo(b.x);
        return a.y.compareTo(b.y);
      });

      // Average skew angle in degrees
      final skewDegrees = angleCount > 0
          ? (totalAngle / angleCount) * 180 / math.pi
          : 0.0;

      debugPrint('OCR: ${regions.length} lines, skew ${skewDegrees.toStringAsFixed(1)}°');
      return (regions: regions, skewAngle: skewDegrees);
    } catch (e) {
      debugPrint('OCR: recognition failed (${e.runtimeType})');
      return (regions: <TextRegion>[], skewAngle: 0.0);
    }
  }

  List<DetectedAnswer> _parseAnswers(
    List<TextRegion> regions,
    Assessment assessment,
  ) {
    final inputs = regions
        .map((r) => TextRegionInput(
              text: r.text,
              confidence: r.confidence,
              x: r.x,
              y: r.y,
            ))
        .toList();
    return _parser
        .parseAnswers(inputs)
        .map((p) => DetectedAnswer(
              questionNumber: p.questionNumber,
              answer: p.answer,
              confidence: p.confidence,
              rawText: p.rawText,
            ))
        .toList();
  }

  /// Release ML Kit resources. Call when app is shutting down.
  void dispose() {
    if (_isInitialized) {
      _textRecognizer.close();
      _isInitialized = false;
    }
  }

  /// Delete enhanced/corrected images created during processing.
  ///
  /// Cleans up *_enhanced.jpg and *_corrected.jpg files alongside
  /// the original [imagePath]. Safe to call on any path — silently
  /// ignores missing files. Never throws.
  Future<void> cleanupEnhancedImages(String imagePath) async {
    try {
      final dotIndex = imagePath.lastIndexOf('.');
      final basePath = dotIndex > 0 ? imagePath.substring(0, dotIndex) : imagePath;
      final enhanced = File('${basePath}_enhanced.jpg');
      if (await enhanced.exists()) await enhanced.delete();
      final corrected = File('${basePath}_corrected.jpg');
      if (await corrected.exists()) await corrected.delete();
    } catch (_) {
      // Never block the pipeline on cleanup failure
    }
  }

  /// Delete a list of image files and their enhanced variants.
  /// Safe to call on any paths — silently ignores missing files.
  Future<void> cleanupImages(List<String> imagePaths) async {
    for (final path in imagePaths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
        await cleanupEnhancedImages(path);
      } catch (_) {
        // Continue cleaning other files
      }
    }
  }

  /// Check if an image is a duplicate of any existing scan results.
  ///
  /// Computes the hash of [imagePath] and compares it against the
  /// `imageHash` field of each scan in [existingScans].
  ///
  /// Returns the index of the duplicate in [existingScans], or -1 if no
  /// duplicate found. Returns -2 if the hash couldn't be computed (file
  /// missing, corrupt) — caller should treat this as "no duplicate" and
  /// proceed normally.
  ///
  /// This is intentionally non-blocking: hash failure never stops scanning.
  int checkDuplicate(String imagePath, List<ScanResult> existingScans) {
    final hash = _hasher.computeHash(imagePath);
    if (hash == null) return -2; // Can't compute — skip check
    final hashes = existingScans.map((s) => s.imageHash).toList();
    return _hasher.findDuplicate(hash, hashes);
  }

  /// Expose the hasher for UI-level duplicate checking.
  ImageHashService get hasher => _hasher;
}

/// A detected text region from OCR.
class TextRegion {
  final String text;
  final double confidence;
  final double x;
  final double y;

  TextRegion({
    required this.text,
    required this.confidence,
    required this.x,
    required this.y,
  });
}
