import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/scan_result.dart';
import '../models/assessment.dart';

/// Offline OCR and image processing service.
/// Uses local image processing + ML Kit text recognition.
/// In production, swap in TFLite models for Amharic handwriting.
class OcrService {
  static final OcrService _instance = OcrService._();
  factory OcrService() => _instance;
  OcrService._();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    // Load local TFLite model when available
    // await Tflite.loadModel(
    //   model: "assets/models/amharic_ocr.tflite",
    //   labels: "assets/models/labels.txt",
    // );
    _isInitialized = true;
  }

  /// Enhance image for better OCR: auto-contrast, denoise, sharpen
  /// Designed for poor classroom lighting, shadows, and glare
  Future<String> enhanceImage(String imagePath) async {
    final file = File(imagePath);
    final bytes = await file.readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return imagePath;

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
    // 1. Enhance image
    final enhancedPath = await enhanceImage(imagePath);

    // 2. Extract text regions using ML Kit or local model
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

  /// Mock OCR extraction — in production, replace with TFLite inference
  Future<List<TextRegion>> _extractTextRegions(String imagePath) async {
    // Simulated OCR results
    // In production: use google_mlkit_text_recognition or TFLite
    await Future.delayed(const Duration(milliseconds: 800));

    return [
      TextRegion(text: '1. A', confidence: 0.92, x: 100, y: 50),
      TextRegion(text: '2. B', confidence: 0.88, x: 100, y: 100),
      TextRegion(text: '3. እውነት', confidence: 0.85, x: 100, y: 150),
      TextRegion(text: '4. C', confidence: 0.91, x: 100, y: 200),
      TextRegion(text: '5. ሐሰት', confidence: 0.79, x: 100, y: 250),
    ];
  }

  List<DetectedAnswer> _parseAnswers(
    List<TextRegion> regions,
    Assessment assessment,
  ) {
    final answers = <DetectedAnswer>[];

    for (final region in regions) {
      final parsed = _parseQuestionAnswer(region.text);
      if (parsed != null) {
        answers.add(DetectedAnswer(
          questionNumber: parsed.$1,
          answer: parsed.$2,
          confidence: region.confidence,
          rawText: region.text,
        ));
      }
    }

    return answers;
  }

  /// Parse "1. A" or "1-A" or "1) እውነት" format
  (int, String)? _parseQuestionAnswer(String text) {
    final patterns = [
      RegExp(r'^(\d+)\s*[.\-):]\s*(.+)$'),  // "1. A" or "1-A" or "1) እውነት"
      RegExp(r'^(\d+)\s+(.+)$'),              // "1 A"
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text.trim());
      if (match != null) {
        final number = int.tryParse(match.group(1)!);
        final answer = _normalizeAnswer(match.group(2)!.trim());
        if (number != null && answer.isNotEmpty) {
          return (number, answer);
        }
      }
    }
    return null;
  }

  /// Normalize answer text (handle Amharic/English variants)
  String _normalizeAnswer(String raw) {
    final lower = raw.toLowerCase().trim();

    // Amharic True/False
    if (lower.contains('እውነት') || lower == 'ት') return 'True';
    if (lower.contains('ሐሰት') || lower == 'ሐ') return 'False';

    // English True/False
    if (lower == 't' || lower == 'true' || lower == 'ት rue') return 'True';
    if (lower == 'f' || lower == 'false') return 'False';

    // MCQ letters
    if (RegExp(r'^[a-eA-E]$').hasMatch(lower)) return lower.toUpperCase();

    // Amharic letters for MCQ (if used)
    const amharicLetters = {
      'ሀ': 'A', 'ለ': 'B', 'ሐ': 'C', 'መ': 'D', 'ሠ': 'E',
    };
    if (amharicLetters.containsKey(raw)) return amharicLetters[raw]!;

    return raw;
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

  // Image processing helpers

  img.Image _autoWhiteBalance(img.Image image) {
    // Simple gray-world white balance
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
    // Simple unsharp mask approximation
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

        // Local mean
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

  void dispose() {
    // Tflite.close();
  }
}

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
