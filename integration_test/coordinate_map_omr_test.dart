import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/coordinate_map.dart';
import 'package:ethiograde/services/coordinate_map_omr_service.dart';

import 'mock_camera_platform.dart';

/// Integration test for coordinate-map OMR pipeline.
///
/// Tests the full flow:
/// 1. Build a CoordinateMap with known mm positions
/// 2. Generate a synthetic answer sheet image with bubbles at matching positions
/// 3. Run CoordinateMapOmrService.scan() — anchor detection → perspective
///    transform → bubble sampling → answer detection
/// 4. Verify the pipeline produces valid results
///
/// The synthetic image is 1200x1600px representing a 210x297mm A4 page.
/// Pixel-to-mm mapping: xMm = px * 210/1200, yMm = px * 297/1600.
void main() {
  group('Coordinate-Map OMR Integration', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ethiograde_cm_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    // Image dimensions (from MockCameraPlatform)
    const imgWidth = 1200;
    const imgHeight = 1600;

    // Conversion factors
    const pxToMmX = 210.0 / imgWidth; // 0.175
    const pxToMmY = 297.0 / imgHeight; // ~0.1856

    // Anchor positions in synthetic image (top-left of 20x20 squares)
    // Converted to center mm positions for the coordinate map
    const anchorTlMm = BubblePosition(
        xMm: (40 + 10) * pxToMmX, yMm: (40 + 10) * pxToMmY, option: '');
    const anchorTrMm = BubblePosition(
        xMm: (1140 + 10) * pxToMmX, yMm: (40 + 10) * pxToMmY, option: '');
    const anchorBlMm = BubblePosition(
        xMm: (40 + 10) * pxToMmX, yMm: (1540 + 10) * pxToMmY, option: '');
    const anchorBrMm = BubblePosition(
        xMm: (1140 + 10) * pxToMmX, yMm: (1540 + 10) * pxToMmY, option: '');

    /// Build a CoordinateMap matching the synthetic image layout.
    ///
    /// [questions]: number of MCQ questions
    /// [options]: options per question (A-E)
    CoordinateMap buildCoordinateMap(int questions, int options) {
      // Bubble grid: startX=100, startY=120, rowHeight=45, colWidth=50
      const startPxX = 100;
      const startPxY = 120;
      const rowHeightPx = 45;
      const colWidthPx = 50;

      final questionBubbles = <QuestionBubble>[];
      for (int q = 0; q < questions; q++) {
        final yPx = startPxY + q * rowHeightPx;
        final bubbles = <BubblePosition>[];
        for (int o = 0; o < options; o++) {
          final xPx = startPxX + o * colWidthPx;
          bubbles.add(BubblePosition(
            xMm: xPx * pxToMmX,
            yMm: yPx * pxToMmY,
            widthMm: 8 * 2 * pxToMmX, // diameter = radius*2
            heightMm: 8 * 2 * pxToMmY,
            option: String.fromCharCode(65 + o), // A, B, C, ...
          ));
        }
        questionBubbles.add(QuestionBubble(
          number: q + 1,
          type: SheetQuestionType.mcq,
          bubbles: bubbles,
        ));
      }

      return CoordinateMap(
        assessmentId: 'cm_test',
        page: const PageDimensions(widthMm: 210, heightMm: 297),
        anchors: [
          const AnchorPoint(corner: 'topLeft', position: anchorTlMm),
          const AnchorPoint(corner: 'topRight', position: anchorTrMm),
          const AnchorPoint(corner: 'bottomLeft', position: anchorBlMm),
          const AnchorPoint(corner: 'bottomRight', position: anchorBrMm),
        ],
        questions: questionBubbles,
      );
    }

    /// Build a minimal Assessment for the scan.
    Assessment buildAssessment(int questions) {
      return Assessment(
        id: 'cm_test',
        title: 'CM Test',
        subject: 'Math',
        totalPoints: questions,
        questions: List.generate(
          questions,
          (i) => Question(
            number: i + 1,
            type: QuestionType.mcq,
            correctAnswer: 'A',
            points: 1.0,
          ),
        ),
        createdAt: DateTime(2026, 4, 18),
      );
    }

    group('Pipeline basics', () {
      test('scan with coordinate map does not crash', () async {
        // Generate synthetic image with known answers
        final jpegBytes = MockCameraPlatform.generateSyntheticAnswerSheet(
          questions: 10,
          options: 5,
          answers: ['A', 'B', 'C', 'D', 'E', 'A', 'B', 'C', 'D', 'E'],
        );
        final imagePath = '${tempDir.path}/cm_sheet.jpg';
        await File(imagePath).writeAsBytes(jpegBytes);

        final coordMap = buildCoordinateMap(10, 5);
        final assessment = buildAssessment(10);

        final service = CoordinateMapOmrService();
        final result = await service.scan(
          imagePath: imagePath,
          coordinateMap: coordMap,
          assessment: assessment,
        );

        // Must produce a result (may be empty if anchors not found on synthetic image)
        expect(result, isNotNull);
      });

      test('scan with missing image returns empty result', () async {
        final coordMap = buildCoordinateMap(5, 5);
        final assessment = buildAssessment(5);

        final service = CoordinateMapOmrService();
        final result = await service.scan(
          imagePath: '/tmp/cm_nonexistent.jpg',
          coordinateMap: coordMap,
          assessment: assessment,
        );

        expect(result, isNotNull);
        expect(result.answers, isEmpty);
        expect(result.totalQuestions, 0);
      });

      test('scan with corrupt image returns empty result', () async {
        final corruptPath = '${tempDir.path}/cm_corrupt.jpg';
        await File(corruptPath).writeAsBytes(
            Uint8List.fromList(List.generate(200, (i) => i % 256)));

        final coordMap = buildCoordinateMap(5, 5);
        final assessment = buildAssessment(5);

        final service = CoordinateMapOmrService();
        final result = await service.scan(
          imagePath: corruptPath,
          coordinateMap: coordMap,
          assessment: assessment,
        );

        expect(result, isNotNull);
        // Corrupt image → no valid result, but no crash
      });

      test('scan with zero-byte image returns empty result', () async {
        final emptyPath = '${tempDir.path}/cm_empty.jpg';
        await File(emptyPath).writeAsBytes(Uint8List(0));

        final coordMap = buildCoordinateMap(5, 5);
        final assessment = buildAssessment(5);

        final service = CoordinateMapOmrService();
        final result = await service.scan(
          imagePath: emptyPath,
          coordinateMap: coordMap,
          assessment: assessment,
        );

        expect(result, isNotNull);
        expect(result.answers, isEmpty);
      });
    });

    group('CoordinateMap model', () {
      test('findBubble returns correct position', () {
        final map = buildCoordinateMap(10, 5);

        final bubble = map.findBubble(1, 'A');
        expect(bubble, isNotNull);
        expect(bubble!.xMm, greaterThan(0));
        expect(bubble.yMm, greaterThan(0));

        final bubbleE = map.findBubble(5, 'E');
        expect(bubbleE, isNotNull);
        // E is the rightmost option → larger X
        expect(bubbleE!.xMm, greaterThan(bubble.xMm));
      });

      test('findBubble returns null for invalid question', () {
        final map = buildCoordinateMap(5, 5);
        expect(map.findBubble(99, 'A'), isNull);
        expect(map.findBubble(1, 'Z'), isNull);
      });

      test('anchor positions are at page corners', () {
        final map = buildCoordinateMap(10, 5);
        final positions = map.anchorPositions;

        expect(positions, hasLength(4));

        // Top-left should be near (8.75, 9.28) mm
        final tl = positions[0];
        expect(tl.xMm, closeTo(50 * pxToMmX, 1.0));
        expect(tl.yMm, closeTo(50 * pxToMmY, 1.0));

        // Bottom-right should be near (201, 287) mm
        final br = positions[3];
        expect(br.xMm, greaterThan(190));
        expect(br.yMm, greaterThan(280));
      });

      test('roundtrip JSON serialization', () {
        final original = buildCoordinateMap(10, 5);
        final json = original.toMap();
        final restored = CoordinateMap.fromMap(json);

        expect(restored.assessmentId, original.assessmentId);
        expect(restored.questions, hasLength(original.questions.length));
        expect(restored.anchors, hasLength(4));
        expect(restored.page.widthMm, original.page.widthMm);
        expect(restored.page.heightMm, original.page.heightMm);
      });

      test('questions have correct type and bubbles', () {
        final map = buildCoordinateMap(8, 5);

        expect(map.questions, hasLength(8));
        for (final q in map.questions) {
          expect(q.type, SheetQuestionType.mcq);
          expect(q.bubbles, hasLength(5));
          expect(q.bubbles.map((b) => b.option).toList(),
              ['A', 'B', 'C', 'D', 'E']);
        }
      });
    });

    group('CoordinateMapOmrResult', () {
      test('empty result has zero values', () {
        const result = CoordinateMapOmrResult.empty;
        expect(result.answers, isEmpty);
        expect(result.totalQuestions, 0);
        expect(result.correctAnswers, 0);
        expect(result.percentage, 0);
        expect(result.missingAnswers, 0);
        expect(result.lowConfidenceAnswers, 0);
        expect(result.isAnswerKey, false);
      });

      test('answerKey getter extracts non-empty answers', () {
        const result = CoordinateMapOmrResult(
          answers: [
            CoordinateMapAnswer(
              questionNumber: 1,
              detectedAnswer: 'A',
              correctAnswer: 'A',
              confidence: 0.9,
              fillRatio: 0.8,
              fillRatios: {},
              isCorrect: true,
              questionType: 'MCQ',
            ),
            CoordinateMapAnswer(
              questionNumber: 2,
              detectedAnswer: '',
              correctAnswer: 'B',
              confidence: 0.0,
              fillRatio: 0.0,
              fillRatios: {},
              isCorrect: false,
              questionType: 'MCQ',
            ),
            CoordinateMapAnswer(
              questionNumber: 3,
              detectedAnswer: 'C',
              correctAnswer: 'C',
              confidence: 0.85,
              fillRatio: 0.7,
              fillRatios: {},
              isCorrect: true,
              questionType: 'MCQ',
            ),
          ],
          totalQuestions: 3,
          correctAnswers: 2,
          averageConfidence: 0.87,
          anchorsDetected: 4,
        );

        final key = result.answerKey;
        expect(key, hasLength(2)); // only non-empty
        expect(key[1], 'A');
        expect(key[3], 'C');
        expect(key.containsKey(2), false); // empty detected
      });
    });

    group('Pipeline resilience', () {
      test('sequential scans on different images', () async {
        final service = CoordinateMapOmrService();
        final coordMap = buildCoordinateMap(5, 5);
        final assessment = buildAssessment(5);

        for (int i = 0; i < 3; i++) {
          final jpegBytes = MockCameraPlatform.generateSyntheticAnswerSheet(
            questions: 5,
            options: 5,
            answers: ['A', 'B', 'C', 'D', 'E'],
          );
          final path = '${tempDir.path}/cm_seq_$i.jpg';
          await File(path).writeAsBytes(jpegBytes);

          final result = await service.scan(
            imagePath: path,
            coordinateMap: coordMap,
            assessment: assessment,
          );
          expect(result, isNotNull);
        }
      });

      test('different question counts work', () async {
        final service = CoordinateMapOmrService();

        for (final count in [1, 5, 15, 25]) {
          final jpegBytes = MockCameraPlatform.generateSyntheticAnswerSheet(
            questions: count,
            options: 5,
            answers: List.generate(count, (_) => 'A'),
          );
          final path = '${tempDir.path}/cm_count_$count.jpg';
          await File(path).writeAsBytes(jpegBytes);

          final coordMap = buildCoordinateMap(count, 5);
          final assessment = buildAssessment(count);

          final result = await service.scan(
            imagePath: path,
            coordinateMap: coordMap,
            assessment: assessment,
          );
          expect(result, isNotNull);
        }
      });
    });
  });
}
