import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/scan_result.dart';
import '../models/assessment.dart';
import 'answer_parser.dart';

/// Offline OCR and image processing service.
/// Uses ML Kit text recognition (runs on-device, no internet required).
class OcrService {
  static final OcrService _instance = OcrService._();
  factory OcrService() => _instance;
  OcrService._();

  late final TextRecognizer _textRecognizer;
  final AnswerParser _parser = const AnswerParser();
  bool _isInitialized = false;

  /// Minimum confidence to accept a detected text line.
  /// Below this, the line is discarded as noise.
  static const double _minConfidence = 0.5;

  /// Maximum image dimension before enhancement.
  /// Larger images are downscaled to protect 2GB devices from OOM.
  static const int _maxImageDimension = 2048;

  Future<void> initialize() async {
    if (_isInitialized) return;
    // Latin script handles English A/B/C/D/E and numbers
    // ML Kit's Latin recognizer also handles mixed scripts reasonably
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    _isInitialized = true;
  }

  /// Enhance image for better OCR: auto-contrast, denoise, sharpen
  /// Designed for poor classroom lighting, shadows, and glare.
  /// Downscales large images to [_maxImageDimension] to protect low-spec devices.
  Future<String> enhanceImage(String imagePath) async {
    final file = File(imagePath);
    final bytes = await file.readAsBytes();
    img.Image? image = img.decodeImage(bytes); // auto-applies EXIF rotation
    if (image == null) return imagePath;

    // Downscale to protect 2GB devices from OOM during pixel-loop processing
    if (image.width > _maxImageDimension || image.height > _maxImageDimension) {
      final ratio = _maxImageDimension / (image.width > image.height ? image.width : image.height);
      image = img.copyResize(
        image,
        width: (image.width * ratio).round(),
        height: (image.height * ratio).round(),
        interpolation: img.Interpolation.cubic,
      );
    }

    // Auto white balance
    image = _autoWhiteBalance(image);

    // Increase contrast
    image = img.adjustColor(
      image,
      contrast: 1.3,
      brightness: 1.05,
      saturation: 0.9,
    );

    // Sharpen for text clarity
    image = _sharpen(image);

    // Remove noise (simple median-like approach)
    image = _denoise(image);

    // Convert to grayscale for OCR
    final grayscale = img.grayscale(image);

    // Binarize (adaptive threshold)
    final binarized = _adaptiveThreshold(grayscale);

    // Save enhanced image
    final enhancedPath = imagePath.replaceFirst('.jpg', '_enhanced.png');
    await File(enhancedPath).writeAsBytes(img.encodePng(binarized));

    return enhancedPath;
  }

  /// Process a scanned paper and extract answers
  /// Returns answers matched against the assessment's answer key
  Future<ScanResult> processScannedPaper({
    required String imagePath,
    required Assessment assessment,
    required String studentId,
    required String studentName,
  }) async {
    await initialize();

    // 1. Enhance image
    final enhancedPath = await enhanceImage(imagePath);

    // 2. Extract text regions using ML Kit (on-device, offline)
    final textRegions = await _extractTextRegions(enhancedPath);

    // 3. Parse question numbers and answers
    final detectedAnswers = _parseAnswers(textRegions, assessment);

    // 4. Score against answer key
    final scoredAnswers = _scoreAnswers(detectedAnswers, assessment);

    // 5. Calculate totals
    final totalScore = scoredAnswers.fold(0.0, (sum, a) => sum + a.score);
    final maxScore = assessment.maxScore;
    final percentage = maxScore > 0 ? (totalScore / maxScore * 100) : 0.0;

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
      status: ScanStatus.graded,
      confidence: _calculateConfidence(scoredAnswers),
    );
  }

  /// Extract text regions from an image using ML Kit.
  /// Runs entirely on-device — no internet required.
  /// Returns text lines sorted by vertical position (top to bottom).
  Future<List<TextRegion>> _extractTextRegions(String imagePath) async {
    await initialize();

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognized = await _textRecognizer.processImage(inputImage);

      final regions = <TextRegion>[];

      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          final text = line.text.trim();
          if (text.isEmpty) continue;

          // ML Kit confidence: average of character-level confidences
          // Elements may not always have confidence, default to 0.8
          double confidence = 0.8;
          if (line.elements.isNotEmpty) {
            final confidences = line.elements
                .map((e) => e.confidence ?? 0.8)
                .toList();
            confidence = confidences.reduce((a, b) => a + b) / confidences.length;
          }

          // Skip low-confidence detections — likely noise, not real text
          if (confidence < _minConfidence) continue;

          // Position: use top-left corner of bounding box
          final rect = line.cornerPoints;
          double x = 0, y = 0;
          if (rect != null && rect.isNotEmpty) {
            // Find topmost-leftmost point
            x = rect.map((p) => p.x.toDouble()).reduce((a, b) => a < b ? a : b);
            y = rect.map((p) => p.y.toDouble()).reduce((a, b) => a < b ? a : b);
          }

          regions.add(TextRegion(
            text: text,
            confidence: confidence.clamp(0.0, 1.0),
            x: x,
            y: y,
          ));
        }
      }

      // Sort by vertical position (top to bottom), then horizontal (left to right)
      // Lines within 5% of max Y span are treated as same line
      double yTolerance = 10.0;
      if (regions.length > 1) {
        final ys = regions.map((r) => r.y);
        yTolerance = (ys.reduce((a, b) => a > b ? a : b) -
                      ys.reduce((a, b) => a < b ? a : b)) * 0.05;
      }
      regions.sort((a, b) {
        if ((a.y - b.y).abs() < yTolerance) {
          return a.x.compareTo(b.x); // same line, sort left to right
        }
        return a.y.compareTo(b.y);
      });

      debugPrint('OCR: detected ${regions.length} text lines');
      return regions;
    } catch (e) {
      debugPrint('OCR: text recognition failed (${e.runtimeType})');
      // Graceful failure — return empty so the pipeline continues
      // Teacher can manually enter answers via review screen
      return [];
    }
  }

  List<DetectedAnswer> _parseAnswers(
    List<TextRegion> regions,
    Assessment assessment,
  ) {
    final inputs = regions
        .map((r) => TextRegionInput(text: r.text, confidence: r.confidence, x: r.x, y: r.y))
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

  // ──── Image processing helpers ────

  img.Image _autoWhiteBalance(img.Image image) {
    num totalR = 0, totalG = 0, totalB = 0;
    final pixelCount = image.width * image.height;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        totalR += pixel.r;
        totalG += pixel.g;
        totalB += pixel.b;
      }
    }

    final avgR = totalR / pixelCount;
    final avgG = totalG / pixelCount;
    final avgB = totalB / pixelCount;
    final avg = (avgR + avgG + avgB) / 3;

    final scaleR = avg / avgR;
    final scaleG = avg / avgG;
    final scaleB = avg / avgB;

    return img.adjustColor(image,
      red: scaleR.toDouble(),
      green: scaleG.toDouble(),
      blue: scaleB.toDouble(),
    );
  }

  img.Image _sharpen(img.Image image) {
    final blurred = img.gaussianBlur(image, radius: 2);
    final result = img.Image.from(image);

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final orig = image.getPixel(x, y);
        final blur = blurred.getPixel(x, y);
        final r = (orig.r * 1.5 - blur.r * 0.5).clamp(0, 255).toInt();
        final g = (orig.g * 1.5 - blur.g * 0.5).clamp(0, 255).toInt();
        final b = (orig.b * 1.5 - blur.b * 0.5).clamp(0, 255).toInt();
        result.setPixelRgba(x, y, r, g, b, orig.a.toInt());
      }
    }

    return result;
  }

  img.Image _denoise(img.Image image) {
    return img.gaussianBlur(image, radius: 1);
  }

  img.Image _adaptiveThreshold(img.Image grayscale) {
    final result = img.Image.from(grayscale);
    const blockSize = 15;
    const c = 10;

    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final intensity = pixel.r.toInt();

        num sum = 0;
        int count = 0;
        for (int dy = -blockSize ~/ 2; dy <= blockSize ~/ 2; dy++) {
          for (int dx = -blockSize ~/ 2; dx <= blockSize ~/ 2; dx++) {
            final nx = (x + dx).clamp(0, grayscale.width - 1);
            final ny = (y + dy).clamp(0, grayscale.height - 1);
            sum += grayscale.getPixel(nx, ny).r;
            count++;
          }
        }

        final mean = sum / count;
        final threshold = mean - c;
        final value = intensity > threshold ? 255 : 0;
        result.setPixelRgba(x, y, value, value, value, 255);
      }
    }

    return result;
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
