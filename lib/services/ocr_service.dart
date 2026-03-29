import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/scan_result.dart';
import '../models/assessment.dart';
import 'answer_parser.dart';

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
  bool _isInitialized = false;

  /// Minimum confidence to accept a detected text line.
  static const double _minConfidence = 0.5;

  /// Maximum image dimension for enhancement.
  /// Scales down to protect 2GB devices and speed up processing.
  static const int _maxImageDimension = 1600;

  /// Skew angle threshold — beyond this, we warn the teacher.
  static const double _skewWarningDegrees = 8.0;

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
  Future<String> enhanceImage(String imagePath) async {
    final file = File(imagePath);
    final bytes = await file.readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return imagePath;

    // Downscale — protects memory on cheap phones, speeds up ML Kit
    if (image.width > _maxImageDimension || image.height > _maxImageDimension) {
      final longer = image.width > image.height ? image.width : image.height;
      final ratio = _maxImageDimension / longer;
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
    final enhancedPath = imagePath.replaceFirst('.jpg', '_enhanced.jpg');
    await File(enhancedPath).writeAsBytes(img.encodeJpg(image, quality: 92));

    return enhancedPath;
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

    // 1. Enhance image (downscale + grayscale + contrast)
    final enhancedPath = await enhanceImage(imagePath);

    // 2. Extract text regions using ML Kit (on-device, offline)
    final extractionResult = await _extractTextRegions(enhancedPath);

    // 3. Parse question numbers and answers
    final detectedAnswers = _parseAnswers(extractionResult.regions, assessment);

    // 4. Deduplicate — if ML Kit reads the same Q# twice, keep highest confidence
    final deduplicated = _deduplicateAnswers(detectedAnswers);

    // 5. Score against answer key
    final scoredAnswers = _scoreAnswers(deduplicated, assessment);

    // 6. Calculate totals
    final totalScore = scoredAnswers.fold(0.0, (sum, a) => sum + a.score);
    final maxScore = assessment.maxScore;
    final percentage = maxScore > 0 ? (totalScore / maxScore * 100) : 0.0;
    final overallConfidence = _calculateConfidence(scoredAnswers);

    // 7. Build metadata with quality signals
    final metadata = <String, dynamic>{
      'textLinesDetected': extractionResult.regions.length,
      'questionsDetected': deduplicated.length,
      'duplicatesRemoved': detectedAnswers.length - deduplicated.length,
      'skewAngle': extractionResult.skewAngle,
      'skewWarning': extractionResult.skewAngle.abs() > _skewWarningDegrees,
    };

    return ScanResult(
      assessmentId: assessment.id,
      studentId: studentId,
      studentName: studentName,
      imagePath: imagePath,
      enhancedImagePath: enhancedPath,
      answers: scoredAnswers,
      totalScore: totalScore,
      maxScore: maxScore,
      percentage: percentage,
      grade: _calculateGrade(percentage.toDouble(), assessment.rubricType),
      status: overallConfidence < 0.6 ? ScanStatus.needsRescan : ScanStatus.graded,
      confidence: overallConfidence,
      metadata: metadata,
    );
  }

  /// Extract text regions from an image using ML Kit.
  /// Also estimates paper skew angle from text block alignment.
  Future<({List<TextRegion> regions, double skewAngle})> _extractTextRegions(
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

  /// Remove duplicate answers for the same question number.
  /// Keeps the one with highest confidence.
  List<DetectedAnswer> _deduplicateAnswers(List<DetectedAnswer> answers) {
    final Map<int, DetectedAnswer> best = {};
    for (final answer in answers) {
      final existing = best[answer.questionNumber];
      if (existing == null || answer.confidence > existing.confidence) {
        best[answer.questionNumber] = answer;
      }
    }
    return best.values.toList()
      ..sort((a, b) => a.questionNumber.compareTo(b.questionNumber));
  }

  List<AnswerMatch> _scoreAnswers(
    List<DetectedAnswer> detected,
    Assessment assessment,
  ) {
    final matches = <AnswerMatch>[];

    for (final question in assessment.questions) {
      final detectedAnswer = detected
          .where((d) => d.questionNumber == question.number)
          .firstOrNull;

      if (detectedAnswer == null) {
        matches.add(AnswerMatch(
          questionNumber: question.number,
          detectedAnswer: '[MISSING]',
          correctAnswer: question.correctAnswer?.toString() ?? '',
          isCorrect: false,
          score: 0,
          maxScore: question.points,
          confidence: 0,
        ));
        continue;
      }

      final isCorrect = _checkAnswer(
        detectedAnswer.answer,
        question.correctAnswer,
        question.type,
      );

      matches.add(AnswerMatch(
        questionNumber: question.number,
        detectedAnswer: detectedAnswer.answer,
        correctAnswer: question.correctAnswer?.toString() ?? '',
        isCorrect: isCorrect,
        score: isCorrect ? question.points : 0,
        maxScore: question.points,
        confidence: detectedAnswer.confidence,
        ocrRawText: detectedAnswer.rawText,
      ));
    }

    return matches;
  }

  bool _checkAnswer(dynamic detected, dynamic correct, QuestionType type) {
    if (detected == null || correct == null) return false;

    if (type == QuestionType.mcq || type == QuestionType.trueFalse) {
      return detected.toString().toUpperCase() ==
          correct.toString().toUpperCase();
    }

    if (type == QuestionType.shortAnswer) {
      if (correct is List) {
        return correct.any(
          (c) => c.toString().toLowerCase() == detected.toString().toLowerCase(),
        );
      }
      return detected.toString().toLowerCase() ==
          correct.toString().toLowerCase();
    }

    return false;
  }

  String _calculateGrade(double percentage, String rubricType) {
    final scale = _getGradingScale(rubricType);
    for (final entry in scale.entries) {
      final range = entry.value as List<int>;
      if (percentage >= range[0] && percentage <= range[1]) {
        return entry.key;
      }
    }
    return 'F';
  }

  Map<String, dynamic> _getGradingScale(String rubricType) {
    const scales = {
      'moe_national': {
        'A+': [95, 100], 'A': [90, 94], 'A-': [85, 89],
        'B+': [80, 84], 'B': [75, 79], 'B-': [70, 74],
        'C+': [65, 69], 'C': [60, 64], 'C-': [55, 59],
        'D': [50, 54], 'F': [0, 49],
      },
      'private_international': {
        'A*': [90, 100], 'A': [80, 89], 'B': [70, 79],
        'C': [60, 69], 'D': [50, 59], 'F': [0, 49],
      },
      'university': {
        'A': [90, 100], 'A-': [85, 89], 'B+': [80, 84],
        'B': [75, 79], 'B-': [70, 74], 'C+': [65, 69],
        'C': [60, 64], 'C-': [55, 59], 'D': [50, 54], 'F': [0, 49],
      },
    };
    return scales[rubricType] ?? scales['moe_national']!;
  }

  double _calculateConfidence(List<AnswerMatch> answers) {
    if (answers.isEmpty) return 0;
    return answers.fold(0.0, (sum, a) => sum + a.confidence) / answers.length;
  }

  /// Release ML Kit resources. Call when app is shutting down.
  void dispose() {
    if (_isInitialized) {
      _textRecognizer.close();
      _isInitialized = false;
    }
  }
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

/// A detected question-answer pair from OCR.
class DetectedAnswer {
  final int questionNumber;
  final String answer;
  final double confidence;
  final String rawText;

  DetectedAnswer({
    required this.questionNumber,
    required this.answer,
    required this.confidence,
    required this.rawText,
  });
}
