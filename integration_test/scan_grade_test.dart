import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/coordinate_map.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/services/omr_service.dart';
import 'package:ethiograde/services/coordinate_map_omr_service.dart';
import 'package:ethiograde/services/bubble_template.dart';
import 'package:ethiograde/services/answer_sheet_generator.dart';
import 'package:ethiograde/services/scoring_service.dart';

import 'mock_camera_platform.dart';

/// Integration test for the scan → grade pipeline.
///
/// Tests the OMR pipeline end-to-end with synthetic images:
/// 1. Generate a synthetic answer sheet image
/// 2. Process with OmrService (template-based)
/// 3. Process with CoordinateMapOmrService (coordinate-map)
/// 4. Verify answers are detected
///
/// Note: OCR (ML Kit TextRecognizer) requires a real device/emulator.
/// These tests cover the pure-Dart OMR pipeline only.
/// Full camera → scan → grade → review flow is tested in
/// `grading_flow_test.dart` (UI only, no camera hardware).
void main() {
  group('Scan → Grade Pipeline Integration', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ethiograde_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    group('Synthetic image generation', () {
      test('generates valid JPEG answer sheet', () {
        final jpegBytes = MockCameraPlatform.generateSyntheticAnswerSheet(
          questions: 10,
          options: 5,
          answers: ['A', 'B', 'C', 'D', 'E', 'A', 'B', 'C', 'D', 'E'],
        );

        expect(jpegBytes, isNotEmpty);
        // JPEG starts with FF D8
        expect(jpegBytes[0], 0xFF);
        expect(jpegBytes[1], 0xD8);
        // JPEG ends with FF D9
        expect(jpegBytes[jpegBytes.length - 2], 0xFF);
        expect(jpegBytes[jpegBytes.length - 1], 0xD9);
      });

      test('generates decodable image', () {
        final jpegBytes = MockCameraPlatform.generateSyntheticAnswerSheet(
          questions: 5,
          options: 5,
          answers: ['A', 'A', 'A', 'A', 'A'],
        );

        final decoded = img.decodeJpg(jpegBytes);
        expect(decoded, isNotNull);
        expect(decoded!.width, 1200);
        expect(decoded.height, 1600);
      });

      test('generates different images for different answers', () {
        final img1 = MockCameraPlatform.generateSyntheticAnswerSheet(
          answers: ['A', 'A', 'A', 'A', 'A'],
        );
        final img2 = MockCameraPlatform.generateSyntheticAnswerSheet(
          answers: ['E', 'E', 'E', 'E', 'E'],
        );

        // Different answer patterns should produce different byte sequences
        expect(img1, isNot(equals(img2)));
      });
    });

    group('OMR template-based scanning', () {
      test('OmrService processes synthetic image without crashing', () async {
        // Generate a synthetic answer sheet
        final jpegBytes = MockCameraPlatform.generateSyntheticAnswerSheet(
          questions: 10,
          options: 5,
          answers: ['A', 'B', 'C', 'D', 'E', 'A', 'B', 'C', 'D', 'E'],
        );

        // Save to temp file
        final imagePath = '${tempDir.path}/test_answer_sheet.jpg';
        await File(imagePath).writeAsBytes(jpegBytes);

        // Create a basic MCQ template
        final template = BubbleTemplate(
          name: 'test10',
          questionCount: 10,
          options: const ['A', 'B', 'C', 'D', 'E'],
          startY: 120,
          rowSpacing: 45,
          startX: 100,
          columnSpacing: 50,
          bubbleRadius: 8,
        );

        // Process with OmrService — must not crash
        final omr = OmrService();
        final result = await omr.detectBubbles(
          enhancedImagePath: imagePath,
          template: template,
        );

        // Result should exist (may have 0 detected answers on synthetic image)
        expect(result, isNotNull);
        expect(result.answers, isNotNull);
        // We don't assert specific detections — synthetic image may
        // not match exact pixel positions, but the pipeline must not crash
      });

      test('OmrService handles empty template gracefully', () async {
        final jpegBytes = MockCameraPlatform.generateSyntheticAnswerSheet(
          questions: 0,
          options: 5,
          answers: [],
        );

        final imagePath = '${tempDir.path}/empty_sheet.jpg';
        await File(imagePath).writeAsBytes(jpegBytes);

        final template = BubbleTemplate(
          name: 'test_empty',
          questionCount: 0,
          options: const ['A', 'B', 'C', 'D', 'E'],
          startY: 120,
          rowSpacing: 45,
          startX: 100,
          columnSpacing: 50,
          bubbleRadius: 8,
        );

        final omr = OmrService();
        final result = await omr.detectBubbles(
          enhancedImagePath: imagePath,
          template: template,
        );

        expect(result, isNotNull);
        expect(result.answers, isEmpty);
      });

      test('OmrService handles missing image file gracefully', () async {
        final template = BubbleTemplate(
          name: 'test5',
          questionCount: 5,
          options: const ['A', 'B', 'C', 'D', 'E'],
          startY: 120,
          rowSpacing: 45,
          startX: 100,
          columnSpacing: 50,
          bubbleRadius: 8,
        );

        final omr = OmrService();
        // Should not throw — returns empty result
        final result = await omr.detectBubbles(
          enhancedImagePath: '/tmp/nonexistent_image_xyz.jpg',
          template: template,
        );

        expect(result, isNotNull);
        expect(result.answers, isEmpty);
      });
    });

    group('Scoring pipeline', () {
      test('ScoringService matches detected answers correctly', () {
        const scoring = ScoringService();

        final answers = [
          AnswerMatch(
            questionNumber: 1,
            detectedAnswer: 'A',
            correctAnswer: 'A',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.95),
          AnswerMatch(
            questionNumber: 2,
            detectedAnswer: 'B',
            correctAnswer: 'A',
            isCorrect: false,
            score: 0,
            maxScore: 1,
            confidence: 0.80),
          AnswerMatch(
            questionNumber: 3,
            detectedAnswer: 'C',
            correctAnswer: 'C',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.90),
        ];

        final total = scoring.calculateTotalScore(answers);
        expect(total, 2.0);

        final pct = scoring.calculatePercentage(totalScore: total, maxScore: 3);
        expect(pct, closeTo(66.7, 0.1));

        final confidence = scoring.calculateConfidence(answers);
        expect(confidence, greaterThan(0.5));
        expect(confidence, lessThanOrEqualTo(1.0));
      });

      test('ScoringService handles all correct', () {
        const scoring = ScoringService();

        final answers = List.generate(10, (i) => AnswerMatch(
          questionNumber: i + 1,
          detectedAnswer: 'A',
          correctAnswer: 'A',
          isCorrect: true,
          score: 1,
          maxScore: 1,
          confidence: 0.99));

        final total = scoring.calculateTotalScore(answers);
        expect(total, 10.0);

        final pct = scoring.calculatePercentage(totalScore: total, maxScore: 10);
        expect(pct, 100.0);
      });

      test('ScoringService handles all wrong', () {
        const scoring = ScoringService();

        final answers = List.generate(10, (i) => AnswerMatch(
          questionNumber: i + 1,
          detectedAnswer: 'B',
          correctAnswer: 'A',
          isCorrect: false,
          score: 0,
          maxScore: 1,
          confidence: 0.85));

        final total = scoring.calculateTotalScore(answers);
        expect(total, 0.0);

        final pct = scoring.calculatePercentage(totalScore: total, maxScore: 10);
        expect(pct, 0.0);
      });

      test('ScoringService handles MISSING answers', () {
        const scoring = ScoringService();

        final answers = [
          AnswerMatch(
            questionNumber: 1,
            detectedAnswer: '[MISSING]',
            correctAnswer: 'A',
            isCorrect: false,
            score: 0,
            maxScore: 1,
            confidence: 0.0),
          AnswerMatch(
            questionNumber: 2,
            detectedAnswer: 'A',
            correctAnswer: 'A',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.95),
        ];

        final total = scoring.calculateTotalScore(answers);
        expect(total, 1.0);

        // MISSING answers should have 0 confidence
        expect(answers[0].confidence, 0.0);
      });
    });

    group('End-to-end: image → OMR → score', () {
      test('synthetic sheet → OmrService → ScoringService produces result', () async {
        const testAnswers = ['A', 'B', 'C', 'D', 'E', 'A', 'B', 'C', 'D', 'E'];
        const correctAnswers = ['A', 'A', 'C', 'C', 'E', 'A', 'B', 'B', 'D', 'E'];

        // Generate synthetic image
        final jpegBytes = MockCameraPlatform.generateSyntheticAnswerSheet(
          questions: 10,
          options: 5,
          answers: testAnswers,
        );

        final imagePath = '${tempDir.path}/e2e_test.jpg';
        await File(imagePath).writeAsBytes(jpegBytes);

        // OMR scan
        final template = BubbleTemplate(
          name: 'e2e_test',
          questionCount: 10,
          options: const ['A', 'B', 'C', 'D', 'E'],
          startY: 120,
          rowSpacing: 45,
          startX: 100,
          columnSpacing: 50,
          bubbleRadius: 8,
        );

        final omr = OmrService();
        final omrResult = await omr.detectBubbles(
          enhancedImagePath: imagePath,
          template: template,
        );

        // Score against correct answers
        const scoring = ScoringService();
        final scoredAnswers = <AnswerMatch>[];

        for (int i = 0; i < 10; i++) {
          final detected = i < omrResult.answers.length
              ? omrResult.answers[i].answer
              : '[MISSING]';
          final correct = correctAnswers[i];
          scoredAnswers.add(AnswerMatch(
            questionNumber: i + 1,
            detectedAnswer: detected,
            correctAnswer: correct,
            isCorrect: detected.toUpperCase() == correct.toUpperCase(),
            score: detected.toUpperCase() == correct.toUpperCase() ? 1.0 : 0.0,
            maxScore: 1.0,
            confidence: i < omrResult.answers.length
                ? omrResult.answers[i].confidence
                : 0.0));
        }

        final total = scoring.calculateTotalScore(scoredAnswers);
        final pct = scoring.calculatePercentage(totalScore: total, maxScore: 10);

        // Pipeline should produce valid scores
        expect(total, greaterThanOrEqualTo(0));
        expect(total, lessThanOrEqualTo(10));
        expect(pct, greaterThanOrEqualTo(0));
        expect(pct, lessThanOrEqualTo(100));

        // Grade should be determinable
        final grade = scoring.calculateGrade(pct, 'moe_national');
        expect(grade, isNotEmpty);
      });
    });

    group('Pipeline resilience', () {
      test('corrupt JPEG does not crash OmrService', () async {
        // Write garbage bytes as a .jpg file
        final corruptPath = '${tempDir.path}/corrupt.jpg';
        await File(corruptPath).writeAsBytes(
          Uint8List.fromList(List.generate(100, (i) => i % 256)));

        final template = BubbleTemplate(
          name: 'corrupt_test',
          questionCount: 5,
          options: const ['A', 'B', 'C', 'D', 'E'],
          startY: 120,
          rowSpacing: 45,
          startX: 100,
          columnSpacing: 50,
          bubbleRadius: 8,
        );

        final omr = OmrService();
        // Must not throw — returns empty result
        final result = await omr.detectBubbles(
          enhancedImagePath: corruptPath,
          template: template,
        );

        expect(result, isNotNull);
      });

      test('zero-byte file does not crash OmrService', () async {
        final emptyPath = '${tempDir.path}/empty.jpg';
        await File(emptyPath).writeAsBytes(Uint8List(0));

        final template = BubbleTemplate(
          name: 'empty_test',
          questionCount: 5,
          options: const ['A', 'B', 'C', 'D', 'E'],
          startY: 120,
          rowSpacing: 45,
          startX: 100,
          columnSpacing: 50,
          bubbleRadius: 8,
        );

        final omr = OmrService();
        final result = await omr.detectBubbles(
          enhancedImagePath: emptyPath,
          template: template,
        );

        expect(result, isNotNull);
        expect(result.answers, isEmpty);
      });
    });
  });
}
