import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Post-capture auto-crop service.
///
/// Detects paper edges in a captured static image and crops/perspective-corrects.
/// Uses brightness thresholding to find the paper boundary — simple but effective
/// for well-lit classroom photos.
class AutoCropService {
  static final AutoCropService _instance = AutoCropService._();
  factory AutoCropService() => _instance;
  AutoCropService._();

  /// Detect paper edges and crop the captured image.
  ///
  /// Returns the path to the cropped image, or the original path if cropping fails.
  Future<String> cropPaper({
    required String imagePath,
    required String assessmentId,
  }) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return imagePath;

      final bytes = await file.readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return imagePath;

      // EXIF rotation
      image = img.bakeOrientation(image);

      // Find paper bounding box using brightness threshold
      final bbox = _findPaperBounds(image);
      if (bbox == null) {
        debugPrint('AutoCrop: No paper detected, using original image');
        return imagePath;
      }

      // Add generous margin around detected bounds
      final margin = 16;
      final x1 = (bbox.x1 - margin).clamp(0, image.width - 1);
      final y1 = (bbox.y1 - margin).clamp(0, image.height - 1);
      final x2 = (bbox.x2 + margin).clamp(0, image.width - 1);
      final y2 = (bbox.y2 + margin).clamp(0, image.height - 1);

      if (x2 <= x1 || y2 <= y1) return imagePath;

      // Crop
      final cropped = img.copyCrop(
        image,
        x: x1,
        y: y1,
        width: x2 - x1,
        height: y2 - y1,
      );

      // Save cropped image
      final croppedBytes = img.encodeJpg(cropped, quality: 92);
      final croppedPath = imagePath.replaceAll('.jpg', '_cropped.jpg');
      await File(croppedPath).writeAsBytes(croppedBytes);

      debugPrint('AutoCrop: Cropped from ${image.width}x${image.height} '
          'to ${cropped.width}x${cropped.height} '
          '(bounds: $x1,$y1 to $x2,$y2)');

      return croppedPath;
    } catch (e) {
      debugPrint('AutoCrop: Failed to crop: $e');
      return imagePath;
    }
  }

  /// Find the bounding box of the paper in the image.
  ///
  /// Uses brightness thresholding: paper is typically the largest bright region.
  _PaperBounds? _findPaperBounds(img.Image image) {
    final width = image.width;
    final height = image.height;

    // Sample grid — check brightness at grid points
    final gridStepX = width ~/ 15;
    final gridStepY = height ~/ 15;

    // Find rows and columns that have significant brightness
    final brightRows = <int>[];
    final brightCols = <int>[];

    for (var y = gridStepY; y < height - gridStepY; y += gridStepY) {
      var rowBrightCount = 0;
      for (var x = gridStepX; x < width - gridStepX; x += gridStepX) {
        final pixel = image.getPixel(x, y);
        final brightness = (pixel.r + pixel.g + pixel.b) / 3;
        if (brightness > 80) {
          rowBrightCount++;
        }
      }
      if (rowBrightCount > 2) {
        brightRows.add(y);
      }
    }

    for (var x = gridStepX; x < width - gridStepX; x += gridStepX) {
      var colBrightCount = 0;
      for (var y = gridStepY; y < height - gridStepY; y += gridStepY) {
        final pixel = image.getPixel(x, y);
        final brightness = (pixel.r + pixel.g + pixel.b) / 3;
        if (brightness > 80) {
          colBrightCount++;
        }
      }
      if (colBrightCount > 2) {
        brightCols.add(x);
      }
    }

    if (brightRows.length < 5 || brightCols.length < 5) {
      return null;
    }

    // Get bounding box from bright rows/cols
    final y1 = brightRows.first;
    final y2 = brightRows.last;
    final x1 = brightCols.first;
    final x2 = brightCols.last;

    // Sanity check: bounding box should be at least 20% of image
    final boxArea = (x2 - x1) * (y2 - y1);
    final imageArea = width * height;
    if (boxArea < imageArea * 0.2) {
      return null;
    }

    debugPrint('AutoCrop: Paper bounds: $x1,$y1 to $x2,$y2 '
        '(${((x2 - x1) / width * 100).round()}%x${((y2 - y1) / height * 100).round()}% of image)');

    return _PaperBounds(x1: x1, y1: y1, x2: x2, y2: y2);
  }
}

class _PaperBounds {
  final int x1, y1, x2, y2;
  const _PaperBounds({required this.x1, required this.y1, required this.x2, required this.y2});
}
