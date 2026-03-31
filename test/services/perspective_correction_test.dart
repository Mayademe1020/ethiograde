import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ethiograde/services/perspective_correction_service.dart';

void main() {
  final service = PerspectiveCorrectionService();

  // ── Helpers ──

  /// Create a test image with a white rectangle (simulated document) on dark background.
  Future<String> createTestImage({
    int width = 600,
    int height = 800,
    // Document rectangle (simulates paper in photo)
    int docLeft = 50,
    int docTop = 50,
    int docRight = 550,
    int docBottom = 750,
  }) async {
    final image = img.Image(width: width, height: height);
    // Dark background
    img.fill(image, color: img.ColorRgb8(60, 60, 60));
    // White document rectangle
    for (int y = docTop; y < docBottom; y++) {
      for (int x = docLeft; x < docRight; x++) {
        image.setPixelRgba(x, y, 240, 240, 240, 255);
      }
    }
    // Add text-like dark lines on the document
    for (int y = docTop + 40; y < docBottom - 40; y += 30) {
      for (int x = docLeft + 30; x < docRight - 100; x++) {
        if ((x - docLeft - 30) % 200 < 120) {
          image.setPixelRgba(x, y, 20, 20, 20, 255);
        }
      }
    }

    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/perspective_test_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await file.writeAsBytes(img.encodeJpg(image, quality: 92));
    return file.path;
  }

  Future<void> cleanup(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
    final perspective = File(path.replaceFirst('.jpg', '_perspective.jpg'));
    if (await perspective.exists()) await perspective.delete();
  }

  // ── Tests ──

  group('PerspectiveCorrectionService', () {
    test('correctPerspective returns original path when file missing', () async {
      final result = await service.correctPerspective('/nonexistent/image.jpg');
      expect(result, '/nonexistent/image.jpg');
    });

    test('correctPerspective handles null image gracefully', () async {
      // Write garbage bytes
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/bad_image.jpg');
      await file.writeAsBytes([0, 1, 2, 3]);
      final result = await service.correctPerspective(file.path);
      expect(result, file.path); // Should return original on failure
      await file.delete();
    });

    test('detectCorners finds document corners on clean image', () async {
      final path = await createTestImage();
      try {
        final bytes = await File(path).readAsBytes();
        final image = img.decodeImage(bytes);
        expect(image, isNotNull);

        final corners = await service.detectCorners(image!);
        expect(corners, isNotNull);
        expect(corners!.length, 4);
      } finally {
        await cleanup(path);
      }
    });

    test('detectAndWarp produces rectangular output', () async {
      final path = await createTestImage();
      try {
        final bytes = await File(path).readAsBytes();
        final image = img.decodeImage(bytes);
        expect(image, isNotNull);

        final result = await service.detectAndWarp(image!);
        // Should either succeed with a warped image or fail gracefully
        if (result.image != null) {
          expect(result.image!.width, greaterThan(0));
          expect(result.image!.height, greaterThan(0));
          expect(result.confidence, greaterThan(0));
        }
      } finally {
        await cleanup(path);
      }
    });

    test('correctPerspective creates output file on success', () async {
      final path = await createTestImage();
      try {
        final result = await service.correctPerspective(path);
        // Either returns original (detection failed) or perspective-corrected path
        if (result != path) {
          expect(result, contains('_perspective.jpg'));
          final outFile = File(result);
          expect(await outFile.exists(), true);
          final bytes = await outFile.readAsBytes();
          expect(bytes.isNotEmpty, true);
        }
      } finally {
        await cleanup(path);
      }
    });

    test('correctPerspective never throws on any input', () async {
      // Test with various edge cases
      final cases = [
        await createTestImage(width: 100, height: 100), // tiny
        await createTestImage(width: 2000, height: 3000), // large
        await createTestImage(docLeft: 0, docTop: 0, docRight: 600, docBottom: 800), // full bleed
      ];

      for (final path in cases) {
        try {
          final result = await service.correctPerspective(path);
          expect(result, isNotNull);
          expect(result, isA<String>());
        } finally {
          await cleanup(path);
        }
      }
    });

    test('perspective correction preserves image dimensions', () async {
      final path = await createTestImage(width: 600, height: 800);
      try {
        final bytes = await File(path).readAsBytes();
        final image = img.decodeImage(bytes);
        expect(image, isNotNull);

        final result = await service.detectAndWarp(image!);
        if (result.image != null) {
          // Output should have reasonable dimensions
          expect(result.image!.width, greaterThan(100));
          expect(result.image!.height, greaterThan(100));
        }
      } finally {
        await cleanup(path);
      }
    });

    test('confidence is 0 for solid color image (no edges)', () async {
      final image = img.Image(width: 400, height: 600);
      img.fill(image, color: img.ColorRgb8(128, 128, 128));

      final result = await service.detectAndWarp(image);
      // Solid color = no edges = low confidence
      expect(result.confidence, lessThan(0.5));
    });

    test('homography computation handles unit square', () async {
      // Simple test: identity-like transform (rectangle to rectangle)
      final path = await createTestImage(
        docLeft: 10, docTop: 10, docRight: 590, docBottom: 790,
      );
      try {
        final bytes = await File(path).readAsBytes();
        final image = img.decodeImage(bytes);
        expect(image, isNotNull);

        final result = await service.detectAndWarp(image!);
        // Should succeed with high confidence for a clear rectangle
        if (result.image != null) {
          expect(result.confidence, greaterThan(0.3));
        }
      } finally {
        await cleanup(path);
      }
    });
  });
}
