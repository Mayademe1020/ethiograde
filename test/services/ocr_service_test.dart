import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ethiograde/services/ocr_service.dart';
import 'package:ethiograde/services/answer_parser.dart';
import 'package:ethiograde/services/scoring_service.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';

void main() {
  // ── Helpers ──

  /// Create a minimal test image and save to a temp file.
  /// Returns the file path.
  Future<String> createTestImage({
    int width = 400,
    int height = 600,
    String suffix = '.jpg',
  }) async {
    final image = img.Image(width: width, height: height);
    // Fill with white background (simulates paper)
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    // Add some dark text-like rectangles (simulates printed text)
    for (int y = 50; y < height - 50; y += 40) {
      for (int x = 50; x < width - 100; x += 3) {
        if (x < 200) {
          image.setPixelRgba(x, y, 0, 0, 0, 255);
        }
      }
    }
    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/test_image_$suffix');
    final encoded = suffix == '.png'
        ? img.encodePng(image)
        : img.encodeJpg(image, quality: 92);
    await file.writeAsBytes(encoded);
    return file.path;
  }

  /// Clean up temp files created during tests.
  Future<void> cleanupFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    // Also clean enhanced version
    final enhanced = File(path.replaceFirst('.jpg', '_enhanced.jpg'));
    if (await enhanced.exists()) {
      await enhanced.delete();
    }
    final enhancedPng = File(path.replaceFirst('.png', '_enhanced.jpg'));
    if (await enhancedPng.exists()) {
      await enhancedPng.delete();
    }
  }

  Assessment makeAssessment({
    String rubricType = 'moe_national',
    List<Question>? questions,
  }) {
    return Assessment(
      title: 'Test Assessment',
      subject: 'Math',
      rubricType: rubricType,
      questions: questions ??
          [
            Question(number: 1, type: QuestionType.mcq, correctAnswer: 'A'),
            Question(number: 2, type: QuestionType.mcq, correctAnswer: 'B'),
            Question(number: 3, type: QuestionType.trueFalse, correctAnswer: 'True'),
            Question(number: 4, type: QuestionType.mcq, correctAnswer: 'D'),
          ],
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // TextRegion — model tests
  // ══════════════════════════════════════════════════════════════════

  group('TextRegion', () {
    test('stores text, confidence, and position', () {
      final region = TextRegion(
        text: '1. A',
        confidence: 0.92,
        x: 100.0,
        y: 200.0,
      );
      expect(region.text, '1. A');
      expect(region.confidence, 0.92);
      expect(region.x, 100.0);
      expect(region.y, 200.0);
    });

    test('confidence can be zero', () {
      final region = TextRegion(
        text: 'noise',
        confidence: 0.0,
        x: 0,
        y: 0,
      );
      expect(region.confidence, 0.0);
    });

    test('position can be zero', () {
      final region = TextRegion(
        text: '1. B',
        confidence: 0.8,
        x: 0,
        y: 0,
      );
      expect(region.x, 0);
      expect(region.y, 0);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // enhanceImage — image processing pipeline
  // ══════════════════════════════════════════════════════════════════

  group('enhanceImage', () {
    test('returns enhanced path with _enhanced suffix', () async {
      final ocr = OcrService();
      final inputPath = await createTestImage();

      try {
        final enhancedPath = await ocr.enhanceImage(inputPath);
        expect(enhancedPath, contains('_enhanced'));
        expect(enhancedPath, endsWith('.jpg'));
        expect(await File(enhancedPath).exists(), isTrue);
      } finally {
        await cleanupFile(inputPath);
      }
    });

    test('enhanced image is smaller than original for large images', () async {
      final ocr = OcrService();
      // Create a 2000x1500 image (larger than _maxImageDimension=1600)
      final inputPath = await createTestImage(width: 2000, height: 1500);

      try {
        final originalSize = await File(inputPath).length();
        final enhancedPath = await ocr.enhanceImage(inputPath);
        final enhancedSize = await File(enhancedPath).length();

        // Enhanced should be smaller (downscaled + JPEG compression)
        expect(enhancedSize, lessThan(originalSize));
      } finally {
        await cleanupFile(inputPath);
      }
    });

    test('does not upscale small images', () async {
      final ocr = OcrService();
      final inputPath = await createTestImage(width: 200, height: 300);

      try {
        final enhancedPath = await ocr.enhanceImage(inputPath);
        final enhancedBytes = await File(enhancedPath).readAsBytes();
        final enhanced = img.decodeJpg(enhancedBytes);

        expect(enhanced, isNotNull);
        // Should remain at original dimensions (under 1600)
        expect(enhanced!.width, 200);
        expect(enhanced.height, 300);
      } finally {
        await cleanupFile(inputPath);
      }
    });

    test('downscales images exceeding max dimension', () async {
      final ocr = OcrService();
      // 3000x2000 → should scale to 1600x1067
      final inputPath = await createTestImage(width: 3000, height: 2000);

      try {
        final enhancedPath = await ocr.enhanceImage(inputPath);
        final enhancedBytes = await File(enhancedPath).readAsBytes();
        final enhanced = img.decodeJpg(enhancedBytes);

        expect(enhanced, isNotNull);
        expect(enhanced!.width, lessThanOrEqualTo(1600));
        expect(enhanced.height, lessThanOrEqualTo(1600));
      } finally {
        await cleanupFile(inputPath);
      }
    });

    test('enhanced image is grayscale', () async {
      final ocr = OcrService();
      // Create a color image
      final image = img.Image(width: 300, height: 300);
      img.fill(image, color: img.ColorRgb8(100, 150, 200));
      final tempDir = Directory.systemTemp;
      final inputPath = '${tempDir.path}/color_test.jpg';
      await File(inputPath).writeAsBytes(img.encodeJpg(image));

      try {
        final enhancedPath = await ocr.enhanceImage(inputPath);
        final enhancedBytes = await File(enhancedPath).readAsBytes();
        final enhanced = img.decodeJpg(enhancedBytes);

        expect(enhanced, isNotNull);
        // Check a pixel — in grayscale, R=G=B
        final pixel = enhanced!.getPixel(150, 150);
        expect(pixel.r.toInt(), equals(pixel.g.toInt()));
        expect(pixel.g.toInt(), equals(pixel.b.toInt()));
      } finally {
        await cleanupFile(inputPath);
      }
    });

    test('corrects EXIF orientation (rotated 90° image becomes upright)', () async {
      final ocr = OcrService();
      // Create a 200x400 image (tall/portrait)
      final image = img.Image(width: 200, height: 400);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      // Add text-like marks in the top half
      for (int y = 30; y < 200; y += 30) {
        for (int x = 20; x < 150; x++) {
          image.setPixelRgba(x, y, 0, 0, 0, 255);
        }
      }

      // Encode with EXIF orientation 6 (rotated 90° CW — phone held landscape)
      final tempDir = Directory.systemTemp;
      final inputPath = '${tempDir.path}/rotated_test.jpg';
      final encoded = img.encodeJpg(image, quality: 92);

      // Decode and re-encode with explicit EXIF orientation tag
      final exifImage = img.decodeJpg(encoded)!;
      exifImage.exif.orientation = 6; // 90° CW rotation
      final rotatedBytes = img.encodeJpg(exifImage, quality: 92);
      await File(inputPath).writeAsBytes(rotatedBytes);

      try {
        final enhancedPath = await ocr.enhanceImage(inputPath);
        final enhancedBytes = await File(enhancedPath).readAsBytes();
        final enhanced = img.decodeJpg(enhancedBytes);

        expect(enhanced, isNotNull);
        // After bakeOrientation, the image dimensions should reflect the
        // rotation: 200x400 with orientation 6 → 400x200
        expect(enhanced!.width, 400);
        expect(enhanced.height, 200);
      } finally {
        await cleanupFile(inputPath);
      }
    });

    test('handles PNG input (converts to JPEG output)', () async {
      final ocr = OcrService();
      final inputPath = await createTestImage(suffix: '.png');

      try {
        final enhancedPath = await ocr.enhanceImage(inputPath);
        expect(enhancedPath, endsWith('.jpg'));
        expect(await File(enhancedPath).exists(), isTrue);
      } finally {
        await cleanupFile(inputPath);
      }
    });

    test('returns original path if file is not a decodable image', () async {
      final ocr = OcrService();
      final tempDir = Directory.systemTemp;
      final fakePath = '${tempDir.path}/not_an_image.jpg';
      await File(fakePath).writeAsBytes(Uint8List.fromList([0, 1, 2, 3]));

      try {
        final result = await ocr.enhanceImage(fakePath);
        // Should return original path since decode fails
        expect(result, fakePath);
      } finally {
        await cleanupFile(fakePath);
      }
    });

    test('returns original path if file does not exist', () async {
      final ocr = OcrService();
      final result = await ocr.enhanceImage('/nonexistent/path/image.jpg');
      expect(result, '/nonexistent/path/image.jpg');
    });

    test('contrast is boosted (white becomes brighter, dark stays dark)',
        () async {
      final ocr = OcrService();
      // Create image with gray background
      final image = img.Image(width: 200, height: 200);
      img.fill(image, color: img.ColorRgb8(180, 180, 180));
      final tempDir = Directory.systemTemp;
      final inputPath = '${tempDir.path}/gray_test.jpg';
      await File(inputPath).writeAsBytes(img.encodeJpg(image));

      try {
        final enhancedPath = await ocr.enhanceImage(inputPath);
        final enhancedBytes = await File(enhancedPath).readAsBytes();
        final enhanced = img.decodeJpg(enhancedBytes);

        expect(enhanced, isNotNull);
        // With contrast boost, the center pixel should be brighter than original 180
        final pixel = enhanced!.getPixel(100, 100);
        // Grayscale so R=G=B; with contrast 1.2 on 180, expected ~210+
        expect(pixel.r.toInt(), greaterThan(180));
      } finally {
        await cleanupFile(inputPath);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // _parseAnswers integration — AnswerParser + TextRegion → DetectedAnswer
  // ══════════════════════════════════════════════════════════════════

  group('parseAnswers integration (AnswerParser + TextRegionInput)', () {
    const parser = AnswerParser();

    test('converts standard MCQ lines to ParsedAnswer', () {
      final inputs = [
        const TextRegionInput(text: '1. A', confidence: 0.9, x: 100, y: 50),
        const TextRegionInput(text: '2. B', confidence: 0.85, x: 100, y: 90),
        const TextRegionInput(text: '3. C', confidence: 0.88, x: 100, y: 130),
      ];

      final results = parser.parseAnswers(inputs);

      expect(results, hasLength(3));
      expect(results[0].questionNumber, 1);
      expect(results[0].answer, 'A');
      expect(results[1].questionNumber, 2);
      expect(results[1].answer, 'B');
      expect(results[2].questionNumber, 3);
      expect(results[2].answer, 'C');
    });

    test('preserves confidence from TextRegionInput', () {
      final inputs = [
        const TextRegionInput(text: '1. A', confidence: 0.95),
        const TextRegionInput(text: '2. B', confidence: 0.45),
      ];

      final results = parser.parseAnswers(inputs);

      expect(results[0].confidence, 0.95);
      expect(results[1].confidence, 0.45);
    });

    test('filters out non-answer lines', () {
      final inputs = [
        const TextRegionInput(text: '1. A', confidence: 0.9),
        const TextRegionInput(text: 'Name: Abebe', confidence: 0.95),
        const TextRegionInput(text: 'Math Exam 2026', confidence: 0.92),
        const TextRegionInput(text: '2. B', confidence: 0.88),
        const TextRegionInput(text: 'Page 1 of 3', confidence: 0.8),
      ];

      final results = parser.parseAnswers(inputs);

      // Only "1. A" and "2. B" should match
      expect(results, hasLength(2));
      expect(results[0].questionNumber, 1);
      expect(results[1].questionNumber, 2);
    });

    test('handles concatenated format (bubbled sheets)', () {
      final inputs = [
        const TextRegionInput(text: '1A', confidence: 0.9),
        const TextRegionInput(text: '2B', confidence: 0.85),
        const TextRegionInput(text: '10C', confidence: 0.8),
      ];

      final results = parser.parseAnswers(inputs);

      expect(results, hasLength(3));
      expect(results[0].answer, 'A');
      expect(results[1].answer, 'B');
      expect(results[2].questionNumber, 10);
      expect(results[2].answer, 'C');
    });

    test('handles True/False answers', () {
      final inputs = [
        const TextRegionInput(text: '1. True', confidence: 0.9),
        const TextRegionInput(text: '2. False', confidence: 0.85),
        const TextRegionInput(text: '3-T', confidence: 0.8),
      ];

      final results = parser.parseAnswers(inputs);

      expect(results, hasLength(3));
      expect(results[0].answer, 'True');
      expect(results[1].answer, 'False');
      expect(results[2].answer, 'True');
    });

    test('handles Amharic answers', () {
      final inputs = [
        const TextRegionInput(text: '1. ሀ', confidence: 0.9),
        const TextRegionInput(text: '2. ለ', confidence: 0.85),
        const TextRegionInput(text: '3. እውነት', confidence: 0.8),
      ];

      final results = parser.parseAnswers(inputs);

      expect(results, hasLength(3));
      expect(results[0].answer, 'A');
      expect(results[1].answer, 'B');
      expect(results[2].answer, 'True');
    });

    test('empty input returns empty list', () {
      final results = parser.parseAnswers([]);
      expect(results, isEmpty);
    });

    test('handles OCR noise (trailing punctuation)', () {
      final inputs = [
        const TextRegionInput(text: '1. A.', confidence: 0.9),
        const TextRegionInput(text: '2. B,', confidence: 0.85),
        const TextRegionInput(text: '3. C;', confidence: 0.8),
      ];

      final results = parser.parseAnswers(inputs);

      expect(results, hasLength(3));
      expect(results[0].answer, 'A');
      expect(results[1].answer, 'B');
      expect(results[2].answer, 'C');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // Deduplication — if ML Kit reads the same Q# twice
  // ══════════════════════════════════════════════════════════════════

  group('deduplicateAnswers (via ScoringService)', () {
    const scoring = ScoringService();

    test('keeps highest confidence when same Q# detected twice', () {
      final answers = [
        DetectedAnswer(questionNumber: 1, answer: 'A', confidence: 0.7, rawText: '1. A'),
        DetectedAnswer(questionNumber: 1, answer: 'A', confidence: 0.95, rawText: '1A'),
        DetectedAnswer(questionNumber: 2, answer: 'B', confidence: 0.8, rawText: '2. B'),
      ];

      final deduped = scoring.deduplicateAnswers(answers);

      expect(deduped, hasLength(2));
      // Q1 should keep the 0.95 confidence version
      final q1 = deduped.firstWhere((a) => a.questionNumber == 1);
      expect(q1.confidence, 0.95);
    });

    test('keeps different answers for different questions', () {
      final answers = [
        DetectedAnswer(questionNumber: 1, answer: 'A', confidence: 0.9, rawText: '1. A'),
        DetectedAnswer(questionNumber: 2, answer: 'B', confidence: 0.85, rawText: '2. B'),
        DetectedAnswer(questionNumber: 3, answer: 'C', confidence: 0.8, rawText: '3. C'),
      ];

      final deduped = scoring.deduplicateAnswers(answers);

      expect(deduped, hasLength(3));
    });

    test('handles conflicting answers for same Q# (keeps highest confidence)',
        () {
      final answers = [
        DetectedAnswer(questionNumber: 1, answer: 'A', confidence: 0.9, rawText: '1. A'),
        DetectedAnswer(questionNumber: 1, answer: 'B', confidence: 0.6, rawText: '1. B'),
      ];

      final deduped = scoring.deduplicateAnswers(answers);

      expect(deduped, hasLength(1));
      expect(deduped[0].answer, 'A');
      expect(deduped[0].confidence, 0.9);
    });

    test('empty list returns empty', () {
      final deduped = scoring.deduplicateAnswers([]);
      expect(deduped, isEmpty);
    });

    test('results sorted by question number', () {
      final answers = [
        DetectedAnswer(questionNumber: 3, answer: 'C', confidence: 0.8, rawText: '3. C'),
        DetectedAnswer(questionNumber: 1, answer: 'A', confidence: 0.9, rawText: '1. A'),
        DetectedAnswer(questionNumber: 2, answer: 'B', confidence: 0.85, rawText: '2. B'),
      ];

      final deduped = scoring.deduplicateAnswers(answers);

      expect(deduped[0].questionNumber, 1);
      expect(deduped[1].questionNumber, 2);
      expect(deduped[2].questionNumber, 3);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // Scoring pipeline — from detected answers to ScanResult
  // ══════════════════════════════════════════════════════════════════

  group('scoring pipeline (ScoringService + Assessment)', () {
    const scoring = ScoringService();

    test('perfect answers → full score and A+ grade', () {
      final assessment = makeAssessment();
      final detected = [
        DetectedAnswer(questionNumber: 1, answer: 'A', confidence: 0.9, rawText: '1. A'),
        DetectedAnswer(questionNumber: 2, answer: 'B', confidence: 0.9, rawText: '2. B'),
        DetectedAnswer(questionNumber: 3, answer: 'True', confidence: 0.9, rawText: '3. True'),
        DetectedAnswer(questionNumber: 4, answer: 'D', confidence: 0.9, rawText: '4. D'),
      ];

      final scored = scoring.scoreAnswers(detected: detected, assessment: assessment);

      expect(scored, hasLength(4));
      expect(scored.every((a) => a.isCorrect), isTrue);
      expect(scoring.calculateTotalScore(scored), 4.0);
      expect(scoring.calculatePercentage(totalScore: 4, maxScore: 4), 100);
      expect(scoring.calculateGrade(100, 'moe_national'), 'A+');
    });

    test('all wrong → zero score and F grade', () {
      final assessment = makeAssessment();
      final detected = [
        DetectedAnswer(questionNumber: 1, answer: 'B', confidence: 0.9, rawText: '1. B'),
        DetectedAnswer(questionNumber: 2, answer: 'A', confidence: 0.9, rawText: '2. A'),
        DetectedAnswer(questionNumber: 3, answer: 'False', confidence: 0.9, rawText: '3. False'),
        DetectedAnswer(questionNumber: 4, answer: 'A', confidence: 0.9, rawText: '4. A'),
      ];

      final scored = scoring.scoreAnswers(detected: detected, assessment: assessment);

      expect(scored.every((a) => !a.isCorrect), isTrue);
      expect(scoring.calculateTotalScore(scored), 0);
      expect(scoring.calculateGrade(0, 'moe_national'), 'F');
    });

    test('missing answers → marked as [MISSING]', () {
      final assessment = makeAssessment();
      final detected = [
        DetectedAnswer(questionNumber: 1, answer: 'A', confidence: 0.9, rawText: '1. A'),
        // Q2 and Q3 missing
        DetectedAnswer(questionNumber: 4, answer: 'D', confidence: 0.9, rawText: '4. D'),
      ];

      final scored = scoring.scoreAnswers(detected: detected, assessment: assessment);

      expect(scored, hasLength(4));
      expect(scored[1].detectedAnswer, '[MISSING]');
      expect(scored[1].isCorrect, isFalse);
      expect(scored[2].detectedAnswer, '[MISSING]');
      expect(scored[2].isCorrect, isFalse);
    });

    test('partial correct → correct percentage', () {
      final assessment = makeAssessment();
      final detected = [
        DetectedAnswer(questionNumber: 1, answer: 'A', confidence: 0.9, rawText: '1. A'),  // correct
        DetectedAnswer(questionNumber: 2, answer: 'A', confidence: 0.9, rawText: '2. A'),  // wrong
        DetectedAnswer(questionNumber: 3, answer: 'True', confidence: 0.9, rawText: '3. True'), // correct
        DetectedAnswer(questionNumber: 4, answer: 'A', confidence: 0.9, rawText: '4. A'),  // wrong
      ];

      final scored = scoring.scoreAnswers(detected: detected, assessment: assessment);
      final total = scoring.calculateTotalScore(scored);
      final pct = scoring.calculatePercentage(totalScore: total, maxScore: 4);

      expect(total, 2.0);
      expect(pct, 50.0);
      expect(scoring.calculateGrade(50, 'moe_national'), 'D');
    });

    test('confidence calculation averages across answers', () {
      final scored = [
        AnswerMatch(questionNumber: 1, detectedAnswer: 'A', correctAnswer: 'A', isCorrect: true, score: 1, maxScore: 1, confidence: 0.9),
        AnswerMatch(questionNumber: 2, detectedAnswer: 'B', correctAnswer: 'B', isCorrect: true, score: 1, maxScore: 1, confidence: 0.7),
        AnswerMatch(questionNumber: 3, detectedAnswer: 'C', correctAnswer: 'C', isCorrect: true, score: 1, maxScore: 1, confidence: 0.5),
      ];

      final avgConf = scoring.calculateConfidence(scored);
      expect(avgConf, closeTo(0.7, 0.01));
    });

    test('empty answers → zero confidence', () {
      expect(scoring.calculateConfidence([]), 0);
    });

    test('grade boundaries for all three rubric types', () {
      // MoE national
      expect(scoring.calculateGrade(95, 'moe_national'), 'A+');
      expect(scoring.calculateGrade(85, 'moe_national'), 'A-');
      expect(scoring.calculateGrade(70, 'moe_national'), 'B-');
      expect(scoring.calculateGrade(55, 'moe_national'), 'C-');
      expect(scoring.calculateGrade(50, 'moe_national'), 'D');
      expect(scoring.calculateGrade(49, 'moe_national'), 'F');

      // Private international
      expect(scoring.calculateGrade(90, 'private_international'), 'A*');
      expect(scoring.calculateGrade(80, 'private_international'), 'A');
      expect(scoring.calculateGrade(50, 'private_international'), 'D');
      expect(scoring.calculateGrade(49, 'private_international'), 'F');

      // University
      expect(scoring.calculateGrade(90, 'university'), 'A');
      expect(scoring.calculateGrade(75, 'university'), 'B');
      expect(scoring.calculateGrade(50, 'university'), 'D');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // Edge cases — real-world failures
  // ══════════════════════════════════════════════════════════════════

  group('edge cases', () {
    const parser = AnswerParser();
    const scoring = ScoringService();

    test('very high question numbers (>100) are accepted', () {
      final result = parser.parseQuestionAnswer('150. A');
      expect(result, isNotNull);
      expect(result!.$1, 150);
    });

    test('question number >200 is rejected', () {
      final result = parser.parseQuestionAnswer('201. A');
      expect(result, isNull);
    });

    test('question number 0 is rejected', () {
      final result = parser.parseQuestionAnswer('0. A');
      expect(result, isNull);
    });

    test('negative question numbers are rejected', () {
      final result = parser.parseQuestionAnswer('-1. A');
      expect(result, isNull);
    });

    test('empty string returns null', () {
      expect(parser.parseQuestionAnswer(''), isNull);
    });

    test('whitespace-only returns null', () {
      expect(parser.parseQuestionAnswer('   '), isNull);
    });

    test('long prose lines do not match', () {
      expect(parser.parseQuestionAnswer('This is a long sentence about something'), isNull);
    });

    test('percentage calculation with zero max returns 0', () {
      expect(scoring.calculatePercentage(totalScore: 5, maxScore: 0), 0);
    });

    test('percentage calculation with negative max returns 0', () {
      expect(scoring.calculatePercentage(totalScore: 5, maxScore: -1), 0);
    });

    test('unknown rubric type falls back to MoE national', () {
      expect(scoring.calculateGrade(85, 'unknown_rubric'), 'A-');
    });

    test('detected answer with null confidence handled gracefully', () {
      final assessment = makeAssessment();
      final detected = [
        DetectedAnswer(questionNumber: 1, answer: 'A', confidence: 0, rawText: ''),
      ];

      final scored = scoring.scoreAnswers(detected: detected, assessment: assessment);
      // scoreAnswers returns one match per question in assessment
      expect(scored, hasLength(4));
      expect(scored[0].confidence, 0);
    });

    test('special characters in OCR text are handled', () {
      // OCR sometimes produces weird characters
      final result = parser.parseQuestionAnswer('1. À'); // accented A
      // Should not match standard pattern (not a-e)
      expect(result, isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // ScanResult model — serialization
  // ══════════════════════════════════════════════════════════════════

  group('ScanResult model', () {
    test('round-trip serialization preserves data', () {
      final result = ScanResult(
        assessmentId: 'test-assessment',
        studentId: 'student_1',
        studentName: 'Abebe Kebede',
        imagePath: '/path/to/image.jpg',
        enhancedImagePath: '/path/to/enhanced.jpg',
        answers: [
          AnswerMatch(
            questionNumber: 1,
            detectedAnswer: 'A',
            correctAnswer: 'A',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.9,
            ocrRawText: '1. A',
          ),
        ],
        totalScore: 1,
        maxScore: 1,
        percentage: 100,
        grade: 'A+',
        status: ScanStatus.graded,
        confidence: 0.9,
        metadata: {'textLinesDetected': 5},
      );

      final map = result.toMap();
      final restored = ScanResult.fromMap(map);

      expect(restored.id, result.id);
      expect(restored.assessmentId, 'test-assessment');
      expect(restored.studentName, 'Abebe Kebede');
      expect(restored.totalScore, 1);
      expect(restored.grade, 'A+');
      expect(restored.answers, hasLength(1));
      expect(restored.answers[0].detectedAnswer, 'A');
      expect(restored.confidence, 0.9);
      expect(restored.metadata['textLinesDetected'], 5);
    });

    test('needsReview is true when confidence < 0.7', () {
      final result = ScanResult(
        assessmentId: 'test',
        studentId: 's1',
        studentName: 'Test',
        imagePath: '/img.jpg',
        confidence: 0.5,
        answers: [],
      );

      expect(result.needsReview, isTrue);
    });

    test('needsReview is true when any answer has low confidence', () {
      final result = ScanResult(
        assessmentId: 'test',
        studentId: 's1',
        studentName: 'Test',
        imagePath: '/img.jpg',
        confidence: 0.9,
        answers: [
          AnswerMatch(
            questionNumber: 1,
            detectedAnswer: 'A',
            correctAnswer: 'A',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.4, // low
          ),
        ],
      );

      expect(result.needsReview, isTrue);
    });

    test('needsReview is false when all confidences are high', () {
      final result = ScanResult(
        assessmentId: 'test',
        studentId: 's1',
        studentName: 'Test',
        imagePath: '/img.jpg',
        confidence: 0.9,
        answers: [
          AnswerMatch(
            questionNumber: 1,
            detectedAnswer: 'A',
            correctAnswer: 'A',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.85,
          ),
        ],
      );

      expect(result.needsReview, isFalse);
    });

    test('copyWith preserves id and overwrites specified fields', () {
      final original = ScanResult(
        assessmentId: 'test',
        studentId: 's1',
        studentName: 'Test',
        imagePath: '/img.jpg',
        grade: 'B',
        totalScore: 3,
        percentage: 75,
      );

      final copied = original.copyWith(
        grade: 'A',
        totalScore: 4,
        percentage: 100,
        status: ScanStatus.reviewed,
      );

      expect(copied.id, original.id);
      expect(copied.grade, 'A');
      expect(copied.totalScore, 4);
      expect(copied.status, ScanStatus.reviewed);
      expect(copied.studentName, 'Test'); // preserved
    });
  });
}
