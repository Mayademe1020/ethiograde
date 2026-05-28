import 'dart:io';

import 'package:ethiograde/services/paper_image_intake_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('PaperImageIntakeService', () {
    late Directory tempDir;
    late PaperImageIntakeService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('paper_intake_test_');
      service = PaperImageIntakeService();
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('accepts supported existing image paths', () {
      final image = _writeImage('${tempDir.path}/paper.JPG');

      final result = service.fromPaths(
        paths: [image.path],
        source: PaperImageSource.upload,
      );

      expect(result.hasImages, isTrue);
      expect(result.imagePaths, [image.path]);
      expect(result.rejectedPaths, isEmpty);
      expect(result.readyItems.single.message, 'Ready for grading');
    });

    test('rejects unsupported or missing files', () {
      final textFile = File('${tempDir.path}/notes.txt')
        ..writeAsStringSync('x');
      final missing = '${tempDir.path}/missing.png';

      final result = service.fromPaths(
        paths: [textFile.path, missing],
        source: PaperImageSource.upload,
      );

      expect(result.imagePaths, isEmpty);
      expect(result.rejectedPaths, [textFile.path, missing]);
    });

    test('removes duplicate selected paths', () {
      final image = _writeImage('${tempDir.path}/paper.png');

      final result = service.fromPaths(
        paths: [image.path, image.path],
        source: PaperImageSource.upload,
      );

      expect(result.imagePaths, [image.path]);
      expect(result.rejectedPaths, isEmpty);
    });

    test('marks small readable images as needing attention', () {
      final image = _writeImage('${tempDir.path}/small.png', size: 120);

      final result = service.fromPaths(
        paths: [image.path],
        source: PaperImageSource.upload,
      );

      expect(result.imagePaths, [image.path]);
      expect(result.readyItems, isEmpty);
      expect(result.attentionItems.single.message, contains('Small photo'));
    });

    test('marks dark readable images as needing attention', () {
      final image = _writeImage(
        '${tempDir.path}/dark.png',
        color: img.ColorRgb8(20, 20, 20),
      );

      final result = service.fromPaths(
        paths: [image.path],
        source: PaperImageSource.upload,
      );

      expect(result.imagePaths, [image.path]);
      expect(result.readyItems, isEmpty);
      expect(result.attentionItems.single.message, contains('Too dark'));
    });
  });
}

File _writeImage(String path, {int size = 600, img.Color? color}) {
  final image = img.Image(width: size, height: size);
  img.fill(image, color: color ?? img.ColorRgb8(230, 230, 230));
  final encoded = path.toLowerCase().endsWith('.jpg')
      ? img.encodeJpg(image)
      : img.encodePng(image);
  return File(path)..writeAsBytesSync(encoded);
}
