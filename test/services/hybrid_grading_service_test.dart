import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ethiograde/services/hybrid_grading_service.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';

void main() {
  // ── Helpers ──

  Assessment makeAssessment({
    String rubricType = 'moe_national',
    List<Question>? questions,
  }) {
    return Assessment(
      title: 'Test',
      subject: 'Math',
      rubricType: rubricType,
      questions: questions ??
          [
            Question(number: 1, type: QuestionType.mcq, correctAnswer: 'A'),
            Question(number: 2, type: QuestionType.mcq, correctAnswer: 'B'),
          ],
    );
  }

  /// Create a test image with some text-like content.
  Future<String> createTestImage({
    int width = 400,
    int height = 600,
    String name = 'test.jpg',
  }) async {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    // Add dark horizontal lines (simulates printed text)
    for (int y = 50; y < height - 50; y += 40) {
      for (int x = 50; x < 200; x++) {
        image.setPixelRgba(x, y, 0, 0, 0, 255);
      }
    }
    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(img.encodeJpg(image, quality: 92));
    return file.path;
  }

  /// Clean up test files.
  Future<void> cleanupFiles(List<String> paths) async {
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
      // Also clean enhanced versions
      final enhanced = File(path.replaceFirst('.jpg', '_enhanced.jpg'));
      if (await enhanced.exists()) await enhanced.delete();
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // gradePaper — single paper grading
  // ══════════════════════════════════════════════════════════════════

  group('gradePaper', () {
    test('returns needsRescan when image file does not exist', () async {
      final service = HybridGradingService();
      final assessment = makeAssessment();

      final result = await service.gradePaper(
        imagePath: '/nonexistent/image.jpg',
        assessment: assessment,
        studentId: 's1',
        studentName: 'Test Student',
      );

      expect(result.status, ScanStatus.needsRescan);
      expect(result.confidence, 0);
      expect(result.metadata['error'], contains('not found'));
      expect(result.studentName, 'Test Student');
    });

    test('processes existing image file (may return empty results with real OCR)',
        () async {
      final service = HybridGradingService();
      final assessment = makeAssessment();
      final imagePath = await createTestImage();

      try {
        final result = await service.gradePaper(
          imagePath: imagePath,
          assessment: assessment,
          studentId: 's1',
          studentName: 'Abebe',
        );

        // Should complete without throwing
        expect(result.studentName, 'Abebe');
        expect(result.assessmentId, assessment.id);
        // Status should be either graded or needsRescan
        expect(
          result.status,
          anyOf(ScanStatus.graded, ScanStatus.needsRescan),
        );
      } finally {
        await cleanupFiles([imagePath]);
      }
    });

    test('returns proper ScanResult structure', () async {
      final service = HybridGradingService();
      final assessment = makeAssessment();
      final imagePath = await createTestImage();

      try {
        final result = await service.gradePaper(
          imagePath: imagePath,
          assessment: assessment,
          studentId: 'student_42',
          studentName: 'Kebede Alemu',
        );

        expect(result.studentId, 'student_42');
        expect(result.studentName, 'Kebede Alemu');
        expect(result.imagePath, imagePath);
        expect(result.maxScore, assessment.maxScore);
        expect(result.id, isNotEmpty);
        expect(result.scannedAt, isNotNull);
      } finally {
        await cleanupFiles([imagePath]);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // gradeBatch — batch processing
  // ══════════════════════════════════════════════════════════════════

  group('gradeBatch', () {
    test('processes empty list without error', () async {
      final service = HybridGradingService();
      final assessment = makeAssessment();

      final results = await service.gradeBatch(
        imagePaths: [],
        assessment: assessment,
      );

      expect(results, isEmpty);
    });

    test('reports progress callbacks', () async {
      final service = HybridGradingService();
      final assessment = makeAssessment();
      final paths = <String>[];
      final progressLog = <List<int>>[];

      // Create 3 test images
      for (int i = 0; i < 3; i++) {
        paths.add(await createTestImage(name: 'batch_$i.jpg'));
      }

      try {
        await service.gradeBatch(
          imagePaths: paths,
          assessment: assessment,
          onProgress: (processed, total) {
            progressLog.add([processed, total]);
          },
        );

        expect(progressLog, hasLength(3));
        expect(progressLog[0], [1, 3]);
        expect(progressLog[1], [2, 3]);
        expect(progressLog[2], [3, 3]);
      } finally {
        await cleanupFiles(paths);
      }
    });

    test('uses custom student names when provided', () async {
      final service = HybridGradingService();
      final assessment = makeAssessment();
      final paths = <String>[];

      for (int i = 0; i < 2; i++) {
        paths.add(await createTestImage(name: 'names_$i.jpg'));
      }

      try {
        final results = await service.gradeBatch(
          imagePaths: paths,
          assessment: assessment,
          studentNames: ['Abebe Kebede', 'Sara Tadesse'],
        );

        expect(results, hasLength(2));
        expect(results[0].studentName, 'Abebe Kebede');
        expect(results[1].studentName, 'Sara Tadesse');
      } finally {
        await cleanupFiles(paths);
      }
    });

    test('auto-generates student names when not provided', () async {
      final service = HybridGradingService();
      final assessment = makeAssessment();
      final paths = <String>[];

      for (int i = 0; i < 2; i++) {
        paths.add(await createTestImage(name: 'auto_$i.jpg'));
      }

      try {
        final results = await service.gradeBatch(
          imagePaths: paths,
          assessment: assessment,
        );

        expect(results, hasLength(2));
        expect(results[0].studentName, 'Student 1');
        expect(results[1].studentName, 'Student 2');
      } finally {
        await cleanupFiles(paths);
      }
    });

    test('partial names list falls back to auto-generated', () async {
      final service = HybridGradingService();
      final assessment = makeAssessment();
      final paths = <String>[];

      for (int i = 0; i < 3; i++) {
        paths.add(await createTestImage(name: 'partial_$i.jpg'));
      }

      try {
        final results = await service.gradeBatch(
          imagePaths: paths,
          assessment: assessment,
          studentNames: ['Abebe'], // Only 1 name for 3 images
        );

        expect(results, hasLength(3));
        expect(results[0].studentName, 'Abebe');
        expect(results[1].studentName, 'Student 2');
        expect(results[2].studentName, 'Student 3');
      } finally {
        await cleanupFiles(paths);
      }
    });

    test('handles mixed valid and invalid images', () async {
      final service = HybridGradingService();
      final assessment = makeAssessment();
      final validPath = await createTestImage(name: 'valid_batch.jpg');
      final paths = [validPath, '/nonexistent/image.jpg'];

      try {
        final results = await service.gradeBatch(
          imagePaths: paths,
          assessment: assessment,
        );

        expect(results, hasLength(2));
        // First should process normally
        expect(results[0].studentName, 'Student 1');
        // Second should be needsRescan (file not found)
        expect(results[1].status, ScanStatus.needsRescan);
      } finally {
        await cleanupFiles([validPath]);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // regradePaper — re-scanning a single paper
  // ══════════════════════════════════════════════════════════════════

  group('regradePaper', () {
    test('produces same result structure as gradePaper', () async {
      final service = HybridGradingService();
      final assessment = makeAssessment();

      final result = await service.regradePaper(
        imagePath: '/nonexistent/regrade.jpg',
        assessment: assessment,
        studentId: 's1',
        studentName: 'Regrade Test',
      );

      expect(result.studentName, 'Regrade Test');
      expect(result.status, ScanStatus.needsRescan);
    });
  });
}
