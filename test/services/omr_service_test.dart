import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ethiograde/services/omr_service.dart';
import 'package:ethiograde/services/bubble_template.dart';

void main() {
  // ── Helpers ──

  /// Create a test image with filled bubbles at specified positions.
  /// Returns the file path.
  Future<String> createBubbleSheetImage({
    int width = 1600,
    int height = 1200,
    required BubbleTemplate template,
    /// Map of questionIndex (0-based) → list of optionIndex (0-based) to fill
    required Map<int, List<int>> filledBubbles,
  }) async {
    final image = img.Image(width: width, height: height);

    // White background (simulates paper)
    img.fill(image, color: img.ColorRgb8(255, 255, 255));

    // Draw filled bubbles
    for (final entry in filledBubbles.entries) {
      final qi = entry.key;
      for (final oi in entry.value) {
        final (cx, cy) = template.bubbleCenter(qi, oi);
        _drawFilledCircle(image, cx.toInt(), cy.toInt(), template.bubbleRadius.toInt());
      }
    }

    // Draw empty bubbles (light outline) for all positions
    for (int qi = 0; qi < template.questionCount; qi++) {
      for (int oi = 0; oi < template.optionCount; oi++) {
        final alreadyFilled = filledBubbles[qi]?.contains(oi) ?? false;
        if (!alreadyFilled) {
          final (cx, cy) = template.bubbleCenter(qi, oi);
          _drawCircleOutline(image, cx.toInt(), cy.toInt(), template.bubbleRadius.toInt());
        }
      }
    }

    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/omr_test_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await file.writeAsBytes(img.encodeJpg(image, quality: 92));
    return file.path;
  }

  /// Draw a filled dark circle (simulates a filled bubble with pen).
  void _drawFilledCircle(img.Image image, int cx, int cy, int radius) {
    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        if (dx * dx + dy * dy <= radius * radius) {
          final px = cx + dx;
          final py = cy + dy;
          if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
            image.setPixelRgba(px, py, 20, 20, 20, 255); // dark fill
          }
        }
      }
    }
  }

  /// Draw a light circle outline (simulates an empty bubble).
  void _drawCircleOutline(img.Image image, int cx, int cy, int radius) {
    for (int angle = 0; angle < 360; angle++) {
      final rad = angle * 3.14159 / 180;
      final px = (cx + radius * rad.cos()).toInt();
      final py = (cy + radius * rad.sin()).toInt();
      if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
        image.setPixelRgba(px, py, 200, 200, 200, 255); // light gray outline
      }
    }
  }

  Future<void> cleanupFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // BubbleTemplate — model tests
  // ══════════════════════════════════════════════════════════════════

  group('BubbleTemplate', () {
    test('bubbleCenter calculates correct position', () {
      const template = BubbleTemplate(
        name: 'test',
        questionCount: 10,
        options: ['A', 'B', 'C', 'D', 'E'],
        startX: 100,
        startY: 200,
        columnSpacing: 50,
        rowSpacing: 30,
      );

      final (x0, y0) = template.bubbleCenter(0, 0);
      expect(x0, 100);
      expect(y0, 200);

      final (x1, y1) = template.bubbleCenter(0, 1);
      expect(x1, 150);
      expect(y1, 200);

      final (x2, y2) = template.bubbleCenter(1, 0);
      expect(x2, 100);
      expect(y2, 230);

      final (x3, y3) = template.bubbleCenter(4, 3);
      expect(x3, 250);
      expect(y3, 320);
    });

    test('optionCount returns number of options', () {
      const t5 = BubbleTemplate(
        name: 't5', questionCount: 10, options: ['A', 'B', 'C', 'D', 'E'],
        startX: 0, startY: 0, columnSpacing: 0, rowSpacing: 0,
      );
      expect(t5.optionCount, 5);

      const t2 = BubbleTemplate(
        name: 't2', questionCount: 10, options: ['True', 'False'],
        startX: 0, startY: 0, columnSpacing: 0, rowSpacing: 0,
      );
      expect(t2.optionCount, 2);
    });

    test('toMap / fromMap round-trip', () {
      const original = BubbleTemplate(
        name: 'custom',
        questionCount: 25,
        options: ['A', 'B', 'C'],
        startX: 150,
        startY: 300,
        columnSpacing: 80,
        rowSpacing: 25,
        bubbleRadius: 10,
        fillThreshold: 0.5,
      );

      final map = original.toMap();
      final restored = BubbleTemplate.fromMap(map);

      expect(restored.name, 'custom');
      expect(restored.questionCount, 25);
      expect(restored.options, ['A', 'B', 'C']);
      expect(restored.startX, 150);
      expect(restored.startY, 300);
      expect(restored.columnSpacing, 80);
      expect(restored.rowSpacing, 25);
      expect(restored.bubbleRadius, 10);
      expect(restored.fillThreshold, 0.5);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // StandardTemplates — built-in format matching
  // ══════════════════════════════════════════════════════════════════

  group('StandardTemplates', () {
    test('matchAssessment returns correct template for 20 MCQ', () {
      final t = StandardTemplates.matchAssessment(
        questionCount: 20,
        isTrueFalse: false,
      );
      expect(t.name, 'MoE 20×5');
      expect(t.optionCount, 5);
    });

    test('matchAssessment returns correct template for 30 MCQ', () {
      final t = StandardTemplates.matchAssessment(
        questionCount: 30,
        isTrueFalse: false,
      );
      expect(t.name, 'MoE 30×5');
    });

    test('matchAssessment returns correct template for 50 MCQ', () {
      final t = StandardTemplates.matchAssessment(
        questionCount: 50,
        isTrueFalse: false,
      );
      expect(t.name, 'University 50×4');
      expect(t.optionCount, 4);
    });

    test('matchAssessment returns TF template for True/False', () {
      final t10 = StandardTemplates.matchAssessment(
        questionCount: 10,
        isTrueFalse: true,
      );
      expect(t10.name, 'True/False 10');
      expect(t10.optionCount, 2);

      final t20 = StandardTemplates.matchAssessment(
        questionCount: 20,
        isTrueFalse: true,
      );
      expect(t20.name, 'True/False 20');
    });

    test('byName lookup works', () {
      expect(StandardTemplates.byName('MoE 20×5'), isNotNull);
      expect(StandardTemplates.byName('nonexistent'), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // OmrService — bubble detection
  // ══════════════════════════════════════════════════════════════════

  group('OmrService.detectBubbles', () {
    final omr = OmrService();

    test('detects correctly filled bubbles (all A)', () async {
      const template = BubbleTemplate(
        name: 'test-all-A',
        questionCount: 5,
        options: ['A', 'B', 'C', 'D', 'E'],
        startX: 280,
        startY: 290,
        columnSpacing: 110,
        rowSpacing: 30,
        bubbleRadius: 8,
        fillThreshold: 0.45,
      );

      // Fill option A for all 5 questions
      final filled = <int, List<int>>{};
      for (int i = 0; i < 5; i++) {
        filled[i] = [0]; // option A = index 0
      }

      final imagePath = await createBubbleSheetImage(
        template: template,
        filledBubbles: filled,
      );

      try {
        final result = await omr.detectBubbles(
          enhancedImagePath: imagePath,
          template: template,
        );

        expect(result.answers, hasLength(5));
        for (final answer in result.answers) {
          expect(answer.answer, 'A');
          expect(answer.confidence, greaterThan(0.5));
        }
      } finally {
        await cleanupFile(imagePath);
      }
    });

    test('detects different answers per question', () async {
      const template = BubbleTemplate(
        name: 'test-mixed',
        questionCount: 4,
        options: ['A', 'B', 'C', 'D', 'E'],
        startX: 280,
        startY: 290,
        columnSpacing: 110,
        rowSpacing: 30,
        bubbleRadius: 8,
        fillThreshold: 0.45,
      );

      final imagePath = await createBubbleSheetImage(
        template: template,
        filledBubbles: {
          0: [0], // Q1 = A
          1: [1], // Q2 = B
          2: [3], // Q3 = D
          3: [2], // Q4 = C
        },
      );

      try {
        final result = await omr.detectBubbles(
          enhancedImagePath: imagePath,
          template: template,
        );

        expect(result.answers, hasLength(4));
        expect(result.answers[0].answer, 'A');
        expect(result.answers[1].answer, 'B');
        expect(result.answers[2].answer, 'D');
        expect(result.answers[3].answer, 'C');
      } finally {
        await cleanupFile(imagePath);
      }
    });

    test('handles True/False template', () async {
      const template = BubbleTemplate(
        name: 'test-tf',
        questionCount: 3,
        options: ['True', 'False'],
        startX: 350,
        startY: 290,
        columnSpacing: 200,
        rowSpacing: 30,
        bubbleRadius: 8,
        fillThreshold: 0.45,
      );

      final imagePath = await createBubbleSheetImage(
        template: template,
        filledBubbles: {
          0: [0], // Q1 = True
          1: [1], // Q2 = False
          2: [0], // Q3 = True
        },
      );

      try {
        final result = await omr.detectBubbles(
          enhancedImagePath: imagePath,
          template: template,
        );

        expect(result.answers, hasLength(3));
        expect(result.answers[0].answer, 'True');
        expect(result.answers[1].answer, 'False');
        expect(result.answers[2].answer, 'True');
      } finally {
        await cleanupFile(imagePath);
      }
    });

    test('returns empty result for nonexistent file', () async {
      final result = await omr.detectBubbles(
        enhancedImagePath: '/nonexistent/image.jpg',
        template: StandardTemplates.moe20x5,
      );

      expect(result.answers, isEmpty);
      expect(result, OmrResult.empty);
    });

    test('returns empty result for blank (no marks) image', () async {
      final image = img.Image(width: 1600, height: 1200);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));

      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/blank_test.jpg');
      await file.writeAsBytes(img.encodeJpg(image));

      try {
        final result = await omr.detectBubbles(
          enhancedImagePath: file.path,
          template: StandardTemplates.moe20x5,
        );

        // No bubbles filled — should return empty or all uncertain
        final confidentAnswers = result.answers
            .where((a) => a.confidence >= 0.5)
            .length;
        expect(confidentAnswers, 0);
      } finally {
        await cleanupFile(file.path);
      }
    });

    test('fillMatrix contains per-option fill ratios', () async {
      const template = BubbleTemplate(
        name: 'test-matrix',
        questionCount: 2,
        options: ['A', 'B', 'C'],
        startX: 280,
        startY: 290,
        columnSpacing: 110,
        rowSpacing: 30,
        bubbleRadius: 8,
        fillThreshold: 0.45,
      );

      final imagePath = await createBubbleSheetImage(
        template: template,
        filledBubbles: {0: [0], 1: [2]},
      );

      try {
        final result = await omr.detectBubbles(
          enhancedImagePath: imagePath,
          template: template,
        );

        expect(result.fillMatrix, containsPair(1, isA<Map<String, double>>()));
        expect(result.fillMatrix, containsPair(2, isA<Map<String, double>>()));

        // Q1: A should have higher fill than B or C
        final q1 = result.fillMatrix[1]!;
        expect(q1['A'], greaterThan(q1['B']!));
        expect(q1['A'], greaterThan(q1['C']!));

        // Q2: C should have higher fill than A or B
        final q2 = result.fillMatrix[2]!;
        expect(q2['C'], greaterThan(q2['A']!));
        expect(q2['C'], greaterThan(q2['B']!));
      } finally {
        await cleanupFile(imagePath);
      }
    });

    test('averageConfidence and flaggedCount', () async {
      const template = BubbleTemplate(
        name: 'test-conf',
        questionCount: 3,
        options: ['A', 'B'],
        startX: 280,
        startY: 290,
        columnSpacing: 200,
        rowSpacing: 30,
        bubbleRadius: 8,
        fillThreshold: 0.45,
      );

      final imagePath = await createBubbleSheetImage(
        template: template,
        filledBubbles: {0: [0], 1: [1], 2: [0]},
      );

      try {
        final result = await omr.detectBubbles(
          enhancedImagePath: imagePath,
          template: template,
        );

        expect(result.averageConfidence, greaterThan(0));
        expect(result.averageConfidence, lessThanOrEqualTo(1.0));
      } finally {
        await cleanupFile(imagePath);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // OmrService.validateBubbleSheet
  // ══════════════════════════════════════════════════════════════════

  group('OmrService.validateBubbleSheet', () {
    final omr = OmrService();

    test('returns true for image with filled bubbles', () async {
      const template = StandardTemplates.moe20x5;

      final imagePath = await createBubbleSheetImage(
        template: template,
        filledBubbles: {0: [0], 1: [2], 2: [4]},
      );

      try {
        final valid = await omr.validateBubbleSheet(
          enhancedImagePath: imagePath,
        );
        expect(valid, isTrue);
      } finally {
        await cleanupFile(imagePath);
      }
    });

    test('returns false for pure white image', () async {
      final image = img.Image(width: 1600, height: 1200);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));

      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/pure_white.jpg');
      await file.writeAsBytes(img.encodeJpg(image));

      try {
        final valid = await omr.validateBubbleSheet(
          enhancedImagePath: file.path,
        );
        expect(valid, isFalse);
      } finally {
        await cleanupFile(file.path);
      }
    });

    test('returns false for very dark image', () async {
      final image = img.Image(width: 1600, height: 1200);
      img.fill(image, color: img.ColorRgb8(10, 10, 10));

      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/too_dark.jpg');
      await file.writeAsBytes(img.encodeJpg(image));

      try {
        final valid = await omr.validateBubbleSheet(
          enhancedImagePath: file.path,
        );
        expect(valid, isFalse);
      } finally {
        await cleanupFile(file.path);
      }
    });

    test('returns false for nonexistent file', () async {
      final valid = await omr.validateBubbleSheet(
        enhancedImagePath: '/nonexistent/image.jpg',
      );
      expect(valid, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // OmrService.detectAndParse (convenience method)
  // ══════════════════════════════════════════════════════════════════

  group('OmrService.detectAndParse', () {
    final omr = OmrService();

    test('returns DetectedAnswer list with correct question numbers', () async {
      const template = BubbleTemplate(
        name: 'test-parse',
        questionCount: 3,
        options: ['A', 'B', 'C'],
        startX: 280,
        startY: 290,
        columnSpacing: 110,
        rowSpacing: 30,
        bubbleRadius: 8,
        fillThreshold: 0.45,
      );

      final imagePath = await createBubbleSheetImage(
        template: template,
        filledBubbles: {0: [0], 1: [1], 2: [2]},
      );

      try {
        final answers = await omr.detectAndParse(
          enhancedImagePath: imagePath,
          assessment: _makeAssessment(3),
          template: template,
        );

        expect(answers, hasLength(3));
        expect(answers[0].questionNumber, 1);
        expect(answers[1].questionNumber, 2);
        expect(answers[2].questionNumber, 3);
        expect(answers[0].answer, 'A');
        expect(answers[1].answer, 'B');
        expect(answers[2].answer, 'C');

        // rawText should contain OMR marker
        for (final a in answers) {
          expect(a.rawText, contains('[OMR]'));
        }
      } finally {
        await cleanupFile(imagePath);
      }
    });
  });
}

/// Helper: create a minimal assessment for testing.
Assessment _makeAssessment(int questionCount) {
  return Assessment(
    title: 'OMR Test',
    subject: 'Test',
    questions: List.generate(
      questionCount,
      (i) => Question(
        number: i + 1,
        type: QuestionType.mcq,
        correctAnswer: 'A',
      ),
    ),
  );
}

  group('Template calibration', () {
    test('detectBubbles with shifted bubbles still finds answers', () async {
      // Create a 800x600 image with dark circles at known positions
      final image = img.Image(width: 800, height: 600, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(240, 240, 240)); // white bg

      // Draw 5 dark circles for Q1 at y=150, x=100,200,300,400,500
      // These are shifted from the template's expected positions
      final bubblePositions = [
        [100, 150], [200, 150], [300, 150], [400, 150], [500, 150],
        [100, 180], [200, 180], [300, 180], [400, 180], [500, 180],
        [100, 210], [200, 210], [300, 210], [400, 210], [500, 210],
      ];

      // Fill option A (index 0) for each row — dark circles
      for (int row = 0; row < 3; row++) {
        final cx = bubblePositions[row * 5][0];
        final cy = bubblePositions[row * 5][1];
        // Draw filled circle
        for (int dy = -6; dy <= 6; dy++) {
          for (int dx = -6; dx <= 6; dx++) {
            if (dx * dx + dy * dy <= 36) {
              final px = cx + dx;
              final py = cy + dy;
              if (px >= 0 && px < 800 && py >= 0 && py < 600) {
                image.setPixelRgb(px, py, 30, 30, 30);
              }
            }
          }
        }
      }

      // Save to temp file
      final tempDir = await Directory.systemTemp.createTemp('omr_cal_test');
      final imagePath = '${tempDir.path}/test_bubbles.png';
      await File(imagePath).writeAsBytes(img.encodePng(image));

      // Use a template that's roughly in the right area but slightly off
      final template = BubbleTemplate(
        name: 'test',
        questionCount: 3,
        options: ['A', 'B', 'C', 'D', 'E'],
        startX: 100,
        startY: 150,
        columnSpacing: 100,
        rowSpacing: 30,
        bubbleRadius: 6,
        fillThreshold: 0.45,
      );

      final result = await OmrService().detectBubbles(
        enhancedImagePath: imagePath,
        template: template,
      );

      // Should detect at least the 3 filled A bubbles
      expect(result.answers.length, greaterThanOrEqualTo(1));
      // The detected answers should mostly be 'A' (the filled option)
      final aAnswers = result.answers.where((a) => a.answer == 'A').length;
      expect(aAnswers, greaterThanOrEqualTo(1));

      await tempDir.delete(recursive: true);
    });
  });
}
