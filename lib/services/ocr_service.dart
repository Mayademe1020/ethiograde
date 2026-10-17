import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/scan_result.dart';
import '../models/assessment.dart';
import 'answer_parser.dart';
import 'scoring_service.dart';
import 'image_hash_service.dart';
import 'smart_ocr_service.dart';
import 'perspective_correction_service.dart';

// ── Isolate entry points ─────────────────────────────────────────────
// These must be top-level functions for compute() to use them.

/// Wrapper for perspective correction in a background isolate.
/// PerspectiveCorrectionService is pure Dart — safe for isolates.
Future<String> _perspectiveIsolate(String imagePath) async {
  final service = PerspectiveCorrectionService();
  return service.correctPerspective(imagePath);
}

/// Parameters for [_enhanceImageIsolate].
class _EnhanceParams {
  final String inputPath;
  final String outputPath;
  final int maxDim;
  const _EnhanceParams({
    required this.inputPath,
    required this.outputPath,
    required this.maxDim,
  });
}

/// Runs image enhancement in a background isolate.
/// Pure Dart (image package) — no platform channels needed.
///
/// Adaptive pipeline: detects whether the image has pencil (gray) marks
/// and applies a gentler enhancement that preserves them.
///
/// Ink-optimized pipeline (high contrast):
/// 1. Blue channel extraction: ink goes dark, paper stays bright
/// 2. Otsu binarization: pure black/white eliminates notebook lines
/// 3. Sharpening: crisp letter edges for ML Kit
///
/// Pencil-optimized pipeline (preserves gray marks):
/// 1. Grayscale conversion
/// 2. Adaptive contrast enhancement (CLAHE-like)
/// 3. Gentle sharpening (weaker kernel)
///
/// Returns the [outputPath] on success, [inputPath] on failure.
Future<String> _enhanceImageIsolate(_EnhanceParams params) async {
  try {
    final file = File(params.inputPath);
    if (!await file.exists()) return params.inputPath;

    final bytes = await file.readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return params.inputPath;

    // EXIF rotation correction
    image = img.bakeOrientation(image);

    // Downscale for memory protection + ML Kit speed
    if (image.width > params.maxDim || image.height > params.maxDim) {
      final longer = image.width > image.height ? image.width : image.height;
      final ratio = params.maxDim / longer;
      image = img.copyResize(
        image,
        width: (image.width * ratio).round(),
        height: (image.height * ratio).round(),
        interpolation: img.Interpolation.cubic,
      );
    }

    // ── Detect pencil vs ink ──
    // Sample brightness variance: pencil has lower variance (gray ~0.4-0.7)
    // Ink has high variance (black ~0.0-0.2, white ~0.9-1.0)
    final variance = _estimateBrightnessVariance(image);
    final isPencil = variance < 0.08;

    if (isPencil) {
      // ── Pencil-optimized pipeline ──
      // Preserves gray marks by avoiding binarization
      return await _enhancePencil(image, params.outputPath);
    } else {
      // ── Ink-optimized pipeline (original) ──
      return await _enhanceInk(image, params.outputPath);
    }
  } catch (_) {
    return params.inputPath;
  }
}

/// Estimate brightness variance across the image.
/// Low variance = pencil (gray marks), high variance = ink (black/white).
double _estimateBrightnessVariance(img.Image image) {
  double sum = 0;
  double sumSq = 0;
  int count = 0;

  // Sample every 10th pixel for speed
  for (int y = 0; y < image.height; y += 10) {
    for (int x = 0; x < image.width; x += 10) {
      final brightness = image.getPixel(x, y).r / 255.0;
      sum += brightness;
      sumSq += brightness * brightness;
      count++;
    }
  }

  if (count == 0) return 1.0;
  final mean = sum / count;
  return sumSq / count - mean * mean;
}

/// Ink-optimized enhancement: denoise → blue channel → Otsu binarize → sharpen.
Future<String> _enhanceInk(img.Image image, String outputPath) async {
  // ── Step 0: Gaussian denoise (3x3) ──
  // Reduces camera noise before binarization
  final w = image.width;
  final h = image.height;
  final denoised = img.Image(width: w, height: h, numChannels: 3);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final c = image.getPixel(x, y);
      final tl = (x > 0 && y > 0) ? image.getPixel(x - 1, y - 1) : c;
      final tc = (y > 0) ? image.getPixel(x, y - 1) : c;
      final tr = (x < w - 1 && y > 0) ? image.getPixel(x + 1, y - 1) : c;
      final ml = (x > 0) ? image.getPixel(x - 1, y) : c;
      final mr = (x < w - 1) ? image.getPixel(x + 1, y) : c;
      final bl = (x > 0 && y < h - 1) ? image.getPixel(x - 1, y + 1) : c;
      final bc = (y < h - 1) ? image.getPixel(x, y + 1) : c;
      final br = (x < w - 1 && y < h - 1) ? image.getPixel(x + 1, y + 1) : c;
      // Gaussian kernel: [1,2,1 / 2,4,2 / 1,2,1] / 16
      final rv = (tl.r + 2*tc.r + tr.r + 2*ml.r + 4*c.r + 2*mr.r + bl.r + 2*bc.r + br.r) ~/ 16;
      final gv = (tl.g + 2*tc.g + tr.g + 2*ml.g + 4*c.g + 2*mr.g + bl.g + 2*bc.g + br.g) ~/ 16;
      final bv = (tl.b + 2*tc.b + tr.b + 2*ml.b + 4*c.b + 2*mr.b + bl.b + 2*bc.b + br.b) ~/ 16;
      denoised.setPixel(x, y, img.ColorRgb8(rv, gv, bv));
    }
  }

  // ── Step 0: Lined paper background removal ──
  // Detect horizontal lines (ruled paper) and remove them
  // by replacing with local background color
  _removeLinedPaperBackground(denoised, w, h);

  // ── Step 1: Blue channel extraction ──
  for (final pixel in denoised) {
    final b = pixel.b;
    pixel.r = b;
    pixel.g = b;
  }

  // ── Step 2: Otsu binarization ──
  final histogram = List<int>.filled(256, 0);
  for (final pixel in denoised) {
    histogram[pixel.r.toInt()]++;
  }
  final totalPixels = denoised.width * denoised.height;
  final threshold = _otsuThreshold(histogram, totalPixels);

  for (final pixel in denoised) {
    final v = pixel.r.toInt() < threshold ? 0 : 255;
    pixel.r = v;
    pixel.g = v;
    pixel.b = v;
  }

  // ── Step 3: Sharpening kernel ──
  final sw = denoised.width;
  final sh = denoised.height;
  final sharpened = img.Image(width: sw, height: sh, numChannels: 3);
  for (int y = 0; y < sh; y++) {
    for (int x = 0; x < sw; x++) {
      final c = denoised.getPixel(x, y).r.toInt();
      final l = (x > 0) ? denoised.getPixel(x - 1, y).r.toInt() : c;
      final r = (x < sw - 1) ? denoised.getPixel(x + 1, y).r.toInt() : c;
      final t = (y > 0) ? denoised.getPixel(x, y - 1).r.toInt() : c;
      final b = (y < sh - 1) ? denoised.getPixel(x, y + 1).r.toInt() : c;
      // kernel: [0,-1,0 / -1,5,-1 / 0,-1,0]
      final v = (5 * c - l - r - t - b).clamp(0, 255);
      sharpened.setPixel(x, y, img.ColorRgb8(v, v, v));
    }
  }

  await File(outputPath).writeAsBytes(img.encodeJpg(sharpened, quality: 92));
  return outputPath;
}

/// Pencil-optimized enhancement: grayscale → denoise → CLAHE → Sauvola → dilate → clean.
/// Uses adaptive thresholding which handles uneven lighting much better than Otsu.
/// Preserves gray marks that global binarization would destroy.
Future<String> _enhancePencil(img.Image image, String outputPath) async {
  // ── Step 0: Gamma correction ──
  // Gamma < 1 brightens shadows, reveals faint pencil marks
  // Pencil marks are often in the 80-150 brightness range; gamma 0.7 stretches them
  for (final pixel in image) {
    final r = (255.0 * _pow(pixel.r / 255.0, 0.7)).round().clamp(0, 255);
    final g = (255.0 * _pow(pixel.g / 255.0, 0.7)).round().clamp(0, 255);
    final b = (255.0 * _pow(pixel.b / 255.0, 0.7)).round().clamp(0, 255);
    pixel..r = r..g = g..b = b;
  }

  // ── Step 1: Convert to grayscale ──
  for (final pixel in image) {
    final r = pixel.r.toInt();
    final g = pixel.g.toInt();
    final b = pixel.b.toInt();
    // Luminosity method
    final gray = (0.299 * r + 0.587 * g + 0.114 * b).toInt().clamp(0, 255);
    pixel.r = gray;
    pixel.g = gray;
    pixel.b = gray;
  }

  // ── Step 2: Gaussian denoise (3x3) ──
  // Reduces camera noise that interferes with handwriting recognition
  final w = image.width;
  final h = image.height;
  final denoised = img.Image(width: w, height: h, numChannels: 3);
  // Gaussian kernel: [1,2,1 / 2,4,2 / 1,2,1] / 16
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final c = image.getPixel(x, y).r.toInt();
      final l = (x > 0) ? image.getPixel(x - 1, y).r.toInt() : c;
      final r = (x < w - 1) ? image.getPixel(x + 1, y).r.toInt() : c;
      final t = (y > 0) ? image.getPixel(x, y - 1).r.toInt() : c;
      final b = (y < h - 1) ? image.getPixel(x, y + 1).r.toInt() : c;
      final tl = (x > 0 && y > 0) ? image.getPixel(x - 1, y - 1).r.toInt() : c;
      final tr = (x < w - 1 && y > 0) ? image.getPixel(x + 1, y - 1).r.toInt() : c;
      final bl = (x > 0 && y < h - 1) ? image.getPixel(x - 1, y + 1).r.toInt() : c;
      final br = (x < w - 1 && y < h - 1) ? image.getPixel(x + 1, y + 1).r.toInt() : c;
      final v = (tl + 2 * t + tr + 2 * l + 4 * c + 2 * r + bl + 2 * b + br) ~/ 16;
      denoised.setPixel(x, y, img.ColorRgb8(v, v, v));
    }
  }

  // ── Step 3: CLAHE (Contrast Limited Adaptive Histogram Equalization) ──
  // Boosts local contrast of faint pencil marks without over-amplifying noise
  final claheResult = _applyClahe(denoised, w, h, gridX: 8, gridY: 8, clipLimit: 2.0);

  // ── Step 4: Sauvola adaptive thresholding ──
  // Unlike Otsu (global), Sauvola uses local mean+std in a window
  // to handle uneven lighting — critical for phone photos of paper
  const windowSize = 15; // ~2mm on a 2000px A4 image
  const k = 0.2; // Threshold adjustment factor
  const R = 128; // Dynamic range of standard deviation
  const halfWin = windowSize ~/ 2;

  // Compute integral image and integral of squared image for fast local stats
  final integral = List<List<double>>.generate(
    h, (_) => List<double>.filled(w, 0));
  final integralSq = List<List<double>>.generate(
    h, (_) => List<double>.filled(w, 0));

  for (int y = 0; y < h; y++) {
    double rowSum = 0;
    double rowSumSq = 0;
    for (int x = 0; x < w; x++) {
      final v = claheResult.getPixel(x, y).r.toDouble();
      rowSum += v;
      rowSumSq += v * v;
      integral[y][x] = rowSum + (y > 0 ? integral[y - 1][x] : 0);
      integralSq[y][x] = rowSumSq + (y > 0 ? integralSq[y - 1][x] : 0);
    }
  }

  // Apply Sauvola threshold
  final thresholded = img.Image(width: w, height: h, numChannels: 3);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      // Window bounds
      final y1 = (y - halfWin).clamp(0, h - 1);
      final y2 = (y + halfWin).clamp(0, h - 1);
      final x1 = (x - halfWin).clamp(0, w - 1);
      final x2 = (x + halfWin).clamp(0, w - 1);

      // Count pixels in window
      final count = (y2 - y1 + 1) * (x2 - x1 + 1);
      if (count == 0) {
        thresholded.setPixel(x, y, img.ColorRgb8(255, 255, 255));
        continue;
      }

      // Sum from integral images
      double sum = integral[y2][x2];
      double sumSq = integralSq[y2][x2];
      if (y1 > 0) { sum -= integral[y1 - 1][x2]; sumSq -= integralSq[y1 - 1][x2]; }
      if (x1 > 0) { sum -= integral[y2][x1 - 1]; sumSq -= integralSq[y2][x1 - 1]; }
      if (y1 > 0 && x1 > 0) { sum += integral[y1 - 1][x1 - 1]; sumSq += integralSq[y1 - 1][x1 - 1]; }

      final mean = sum / count;
      final variance = (sumSq / count) - (mean * mean);
      final std = variance > 0 ? math.sqrt(variance.abs()) : 0;

      // Sauvola threshold: T = mean * (1 + k * (std/R - 1))
      final threshold = mean * (1.0 + k * (std / R - 1.0));

      final pixelVal = claheResult.getPixel(x, y).r.toDouble();
      final v = pixelVal > threshold ? 255 : 0;
      thresholded.setPixel(x, y, img.ColorRgb8(v, v, v));
    }
  }

  // ── Step 5: Morphological dilation ──
  // Thickens thin pencil strokes that are fragmented after binarization
  final dilated = _morphologicalDilate(thresholded, w, h);

  // ── Step 6: Light morphological cleanup (opening) ──
  // Remove isolated noise pixels (erosion then dilation = opening)
  final cleaned = _morphologicalOpen(dilated, w, h);

  await File(outputPath).writeAsBytes(img.encodeJpg(cleaned, quality: 92));
  return outputPath;
}

/// Fast power function using dart:math.
double _pow(double base, double exp) => math.pow(base, exp).toDouble();

/// CLAHE (Contrast Limited Adaptive Histogram Equalization).
/// Boosts local contrast without over-amplifying noise.
/// Uses integral images for fast tile computation.
img.Image _applyClahe(img.Image src, int w, int h, {
  int gridX = 8,
  int gridY = 8,
  double clipLimit = 2.0,
}) {
  final result = img.Image(width: w, height: h, numChannels: 3);
  final tileW = (w / gridX).ceil();
  final tileH = (h / gridY).ceil();

  // Build lookup tables for each tile
  final luts = List.generate(gridY, (_) =>
    List.generate(gridX, (_) => List<int>.filled(256, 0)));

  for (int ty = 0; ty < gridY; ty++) {
    for (int tx = 0; tx < gridX; tx++) {
      final x0 = tx * tileW;
      final y0 = ty * tileH;
      final x1 = (x0 + tileW).clamp(0, w);
      final y1 = (y0 + tileH).clamp(0, h);

      // Compute histogram for this tile
      final hist = List<int>.filled(256, 0);
      int pixelCount = 0;
      for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
          final v = src.getPixel(x, y).r.toInt();
          hist[v]++;
          pixelCount++;
        }
      }

      // Clip histogram
      final limit = (clipLimit * pixelCount / 256).round();
      int excess = 0;
      for (int i = 0; i < 256; i++) {
        if (hist[i] > limit) {
          excess += hist[i] - limit;
          hist[i] = limit;
        }
      }
      // Redistribute excess uniformly
      final redistribute = excess ~/ 256;
      final remainder = excess % 256;
      for (int i = 0; i < 256; i++) {
        hist[i] += redistribute;
        if (i < remainder) hist[i]++;
      }

      // Build CDF
      final cdf = List<int>.filled(256, 0);
      cdf[0] = hist[0];
      for (int i = 1; i < 256; i++) {
        cdf[i] = cdf[i - 1] + hist[i];
      }

      // Normalize CDF to 0-255
      final cdfMin = cdf.firstWhere((v) => v > 0, orElse: () => 0);
      for (int i = 0; i < 256; i++) {
        luts[ty][tx][i] = cdfMin < pixelCount
            ? ((cdf[i] - cdfMin) * 255 / (pixelCount - cdfMin)).round().clamp(0, 255)
            : i;
      }
    }
  }

  // Apply with bilinear interpolation between tiles
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final v = src.getPixel(x, y).r.toInt();

      // Find surrounding tiles
      final tx = (x / tileW).clamp(0, gridX - 1).toDouble();
      final ty = (y / tileH).clamp(0, gridY - 1).toDouble();
      final txi = tx.floor();
      final tyi = ty.floor();
      final txf = tx - txi;
      final tyf = ty - tyi;
      final tx2 = (txi + 1).clamp(0, gridX - 1);
      final ty2 = (tyi + 1).clamp(0, gridY - 1);

      // Bilinear interpolation
      final v00 = luts[tyi][txi][v];
      final v10 = luts[tyi][tx2][v];
      final v01 = luts[ty2][txi][v];
      final v11 = luts[ty2][tx2][v];
      final interpolated = (v00 * (1 - txf) * (1 - tyf) +
          v10 * txf * (1 - tyf) +
          v01 * (1 - txf) * tyf +
          v11 * txf * tyf).round().clamp(0, 255);

      result.setPixel(x, y, img.ColorRgb8(interpolated, interpolated, interpolated));
    }
  }

  return result;
}

/// Morphological dilation with 3x3 cross kernel.
/// Thickens thin pencil strokes that were fragmented during binarization.
img.Image _morphologicalDilate(img.Image src, int w, int h) {
  final dilated = img.Image(width: w, height: h, numChannels: 3);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      bool anyBlack = false;
      // 3x3 cross kernel: center + 4 neighbors
      for (final [dx, dy] in [
        [0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]
      ]) {
        final nx = x + dx;
        final ny = y + dy;
        if (nx >= 0 && nx < w && ny >= 0 && ny < h &&
            src.getPixel(nx, ny).r == 0) {
          anyBlack = true;
          break;
        }
      }
      final v = anyBlack ? 0 : 255;
      dilated.setPixel(x, y, img.ColorRgb8(v, v, v));
    }
  }
  return dilated;
}

/// Simple morphological opening (erosion → dilation) with a 3x3 cross kernel.
/// Removes isolated noise pixels while preserving letter strokes.
img.Image _morphologicalOpen(img.Image src, int w, int h) {
  // Erode: pixel is black only if center AND all 4 neighbors are black
  final eroded = img.Image(width: w, height: h, numChannels: 3);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final c = src.getPixel(x, y).r;
      if (c > 0) {
        eroded.setPixel(x, y, img.ColorRgb8(255, 255, 255));
        continue;
      }
      // Check 4-connected neighbors
      bool allBlack = true;
      if (x > 0 && src.getPixel(x - 1, y).r > 0) allBlack = false;
      if (x < w - 1 && src.getPixel(x + 1, y).r > 0) allBlack = false;
      if (y > 0 && src.getPixel(x, y - 1).r > 0) allBlack = false;
      if (y < h - 1 && src.getPixel(x, y + 1).r > 0) allBlack = false;
      final v = allBlack ? 0 : 255;
      eroded.setPixel(x, y, img.ColorRgb8(v, v, v));
    }
  }

  // Dilate: pixel is black if center OR any neighbor is black
  final dilated = img.Image(width: w, height: h, numChannels: 3);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final c = eroded.getPixel(x, y).r;
      if (c == 0) {
        dilated.setPixel(x, y, img.ColorRgb8(0, 0, 0));
        continue;
      }
      // Check 4-connected neighbors
      bool anyBlack = false;
      if (x > 0 && eroded.getPixel(x - 1, y).r == 0) anyBlack = true;
      if (x < w - 1 && eroded.getPixel(x + 1, y).r == 0) anyBlack = true;
      if (y > 0 && eroded.getPixel(x, y - 1).r == 0) anyBlack = true;
      if (y < h - 1 && eroded.getPixel(x, y + 1).r == 0) anyBlack = true;
      final v = anyBlack ? 0 : 255;
      dilated.setPixel(x, y, img.ColorRgb8(v, v, v));
    }
  }

  return dilated;
}

/// Otsu's method: find optimal threshold to separate foreground/background.
/// Minimizes intra-class variance (maximizes inter-class variance).
int _otsuThreshold(List<int> histogram, int totalPixels) {
  double sum = 0;
  for (int i = 0; i < 256; i++) {
    sum += i * histogram[i];
  }

  double sumB = 0;
  int wB = 0;
  double maxVariance = 0;
  int bestThreshold = 0;

  for (int t = 0; t < 256; t++) {
    wB += histogram[t];
    if (wB == 0) continue;
    final wF = totalPixels - wB;
    if (wF == 0) break;

    sumB += t * histogram[t];
    final mB = sumB / wB;
    final mF = (sum - sumB) / wF;
    final variance = wB * wF * (mB - mF) * (mB - mF);
    if (variance > maxVariance) {
      maxVariance = variance;
      bestThreshold = t;
    }
  }
  return bestThreshold;
}

/// Remove horizontal ruled lines from lined paper.
///
/// Works by detecting horizontal runs of similar brightness (the lines)
/// and replacing them with the local background color (the paper between lines).
/// This prevents ruled lines from interfering with OCR.
void _removeLinedPaperBackground(img.Image image, int w, int h) {
  // Build a row-by-row brightness profile
  final rowBrightness = List<double>.filled(h, 0);
  for (int y = 0; y < h; y++) {
    double sum = 0;
    for (int x = 0; x < w; x++) {
      sum += image.getPixel(x, y).r.toDouble();
    }
    rowBrightness[y] = sum / w;
  }

  // Detect lines: rows that are significantly darker than neighbors
  // A ruled line is typically 1-3px wide and consistently darker
  final isLine = List<bool>.filled(h, false);
  for (int y = 2; y < h - 2; y++) {
    final prev1 = rowBrightness[y - 1];
    final curr = rowBrightness[y];
    final next1 = rowBrightness[y + 1];

    // Line detection: current row is darker than both neighbors
    // and the darkness is consistent across the row
    if (curr < prev1 - 5 && curr < next1 - 5) {
      // Check horizontal consistency: most pixels should be similar brightness
      int consistentCount = 0;
      final sampleBrightness = image.getPixel(w ~/ 2, y).r.toDouble();
      for (int x = 0; x < w; x += 10) {
        final px = image.getPixel(x, y).r.toDouble();
        if ((px - sampleBrightness).abs() < 20) {
          consistentCount++;
        }
      }
      if (consistentCount > w / 10 * 0.7) {
        isLine[y] = true;
      }
    }
  }

  // Replace line pixels with interpolated background
  // Use the brightness of the nearest non-line row as background
  for (int y = 1; y < h - 1; y++) {
    if (!isLine[y]) continue;

    // Find the background color from the nearest non-line row (search both up and down)
    double bgBrightness = 200; // Default: light gray
    for (int dy = 1; dy <= 5; dy++) {
      // Search downward first (more likely to find non-line)
      if (y + dy < h && !isLine[y + dy]) {
        bgBrightness = rowBrightness[y + dy];
        break;
      }
      // Search upward
      if (y - dy >= 0 && !isLine[y - dy]) {
        bgBrightness = rowBrightness[y - dy];
        break;
      }
    }

    // Replace the line with background color
    final bg = bgBrightness.toInt().clamp(0, 255);
    for (int x = 0; x < w; x++) {
      final pixel = image.getPixel(x, y);
      // Only replace if the pixel is part of the line (darker than background)
      if (pixel.r.toDouble() < bgBrightness - 10) {
        pixel.r = bg;
        pixel.g = bg;
        pixel.b = bg;
      }
    }
  }
}

/// Runs image rotation correction in a background isolate.
Future<String> _correctRotationIsolate(_CorrectRotationParams params) async {
  try {
    final file = File(params.inputPath);
    if (!await file.exists()) return params.inputPath;

    final bytes = await file.readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return params.inputPath;

    image = img.copyRotate(image, angle: -params.angleDegrees);
    await File(
      params.outputPath,
    ).writeAsBytes(img.encodeJpg(image, quality: 92));
    return params.outputPath;
  } catch (_) {
    return params.inputPath;
  }
}

class _CorrectRotationParams {
  final String inputPath;
  final String outputPath;
  final double angleDegrees;
  const _CorrectRotationParams({
    required this.inputPath,
    required this.outputPath,
    required this.angleDegrees,
  });
}

/// Offline OCR and image processing service.
/// Uses ML Kit text recognition (runs on-device, no internet required).
///
/// Image enhancement philosophy:
/// ML Kit's TextRecognizer has its own preprocessing pipeline. We do the
/// minimum that helps it: downscale for memory, boost contrast for ink/paper
/// separation, and convert to grayscale. Everything else (sharpen, denoise,
/// binarize) is counterproductive — it destroys information ML Kit could use.
class OcrService {
  static final OcrService _instance = OcrService._();
  factory OcrService() => _instance;
  OcrService._();

  static OcrService get instance => _instance;

  late final TextRecognizer _textRecognizer;
  late final TextRecognizer _amharicRecognizer;
  final AnswerParser _parser = const AnswerParser();
  final ScoringService _scoring = const ScoringService();
  final ImageHashService _hasher = ImageHashService();
  bool _isInitialized = false;

  /// Standard confidence floor for detected text lines (printed text /
  /// objective-only exams). Lines below this were historically discarded.
  ///
  /// Lowered from 0.5 to 0.35 to retain handwritten text that ML Kit
  /// scores lower due to irregular letterforms, pencil contrast, or
  /// non-standard spacing. Handwritten text often scores 0.3-0.5.
  static const double standardMinConfidence = 0.35;

  /// Lower retention floor used ONLY when the assessment contains
  /// subjective questions (short answer / essay / multi-answer).
  ///
  /// Handwriting often scores below the printed-text floor. Discarding
  /// those lines made handwritten short answers vanish before parsing.
  /// Lines retained between [subjectiveMinConfidence] and
  /// [standardMinConfidence] stay eligible for question association and
  /// are surfaced through the existing review workflow via their low
  /// per-answer confidence (< 0.6 triggers needsReview gating).
  ///
  /// Lowered from 0.25 to 0.15 to capture very faint pencil marks.
  static const double subjectiveMinConfidence = 0.15;

  /// Maximum image dimension for enhancement.
  /// 2000px preserves handwriting detail that 1600px loses.
  /// Handwriting is finer than printed text — needs more pixels.
  static const int _maxImageDimension = 2000;

  /// Fallback dimension when OOM occurs during enhancement.
  /// 1080p is still readable by ML Kit while using ~4x less memory than 1600px.
  static const int _oomRetryDimension = 1080;

  /// Minimum skew angle to trigger automatic rotation correction (degrees).
  /// Below this, correction isn't worth the processing cost.
  static const double _skewCorrectionThreshold = 3.0;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    // Amharic (Ge'ez) script recognizer — uses Chinese script model which
    // has broader Unicode coverage including some Ge'ez characters.
    // Falls back gracefully if the model doesn't recognize the script.
    _amharicRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    _isInitialized = true;
  }

  /// Re-initialize (e.g., after language change). Closes old recognizer first.
  Future<void> reinitialize() async {
    if (_isInitialized) {
      _textRecognizer.close();
      _amharicRecognizer.close();
      _isInitialized = false;
    }
    await initialize();
  }

  /// Enhance image for OCR.
  ///
  /// Pipeline: blue channel extraction → Otsu binarization → sharpening.
  /// 1. EXIF rotation correction (camera orientation)
  /// 2. Downscale to [_maxImageDimension] (memory protection)
  /// 3. Blue channel extraction (ink dark, paper bright)
  /// 4. Otsu binarization (pure black/white, eliminates lines)
  /// 5. Sharpening (crisp edges for ML Kit)
  ///
  /// Image processing runs in a **background isolate** via [compute()]
  /// to keep the UI thread free. Only ML Kit stays on the main thread
  /// (platform channels).
  ///
  /// On [OutOfMemoryError], retries at [_oomRetryDimension] (1080p).
  /// Returns original path on total failure — never crashes the pipeline.
  Future<String> enhanceImage(String imagePath) async {
    final dotIndex = imagePath.lastIndexOf('.');
    final basePath = dotIndex > 0
        ? imagePath.substring(0, dotIndex)
        : imagePath;
    final enhancedPath = '${basePath}_enhanced.jpg';

    try {
      final result = await compute(
        _enhanceImageIsolate,
        _EnhanceParams(
          inputPath: imagePath,
          outputPath: enhancedPath,
          maxDim: _maxImageDimension,
        ),
      );
      return result;
    } catch (e) {
      debugPrint(
        'OCR: enhanceImage isolate failed at ${_maxImageDimension}px ($e)',
      );
      // OOM retry at lower resolution
      try {
        final result = await compute(
          _enhanceImageIsolate,
          _EnhanceParams(
            inputPath: imagePath,
            outputPath: enhancedPath,
            maxDim: _oomRetryDimension,
          ),
        );
        return result;
      } catch (e2, st) {
        debugPrint('OCR: enhanceImage OOM retry failed ($e2)\n$st');
        return imagePath;
      }
    }
  }

  /// Correct paper rotation by rotating the image by -[angleDegrees].
  ///
  /// Runs in a **background isolate** to keep the UI responsive.
  /// Returns the path to the corrected image, or the original path if
  /// correction fails (never crashes the grading pipeline).
  Future<String> correctRotation(String imagePath, double angleDegrees) async {
    try {
      final dotIndex = imagePath.lastIndexOf('.');
      final basePath = dotIndex > 0
          ? imagePath.substring(0, dotIndex)
          : imagePath;
      final correctedPath = '${basePath}_corrected.jpg';

      final result = await compute(
        _correctRotationIsolate,
        _CorrectRotationParams(
          inputPath: imagePath,
          outputPath: correctedPath,
          angleDegrees: angleDegrees,
        ),
      );
      if (result != imagePath) {
        debugPrint(
          'OCR: rotation corrected by ${angleDegrees.toStringAsFixed(1)}°',
        );
      }
      return result;
    } catch (e, st) {
      debugPrint('OCR: correctRotation failed ($e)\n$st');
      return imagePath;
    }
  }

  /// Process a scanned paper and extract answers.
  /// Returns answers matched against the assessment's answer key.
  Future<ScanResult> processScannedPaper({
    required String imagePath,
    required Assessment assessment,
    required String studentId,
    required String studentName,
  }) async {
    await initialize();

    // 0. Compute perceptual hash for duplicate detection (before enhancement)
    final imageHash = await _hasher.computeHashAsync(imagePath);

    // 1. Enhance image (downscale + grayscale + contrast)
    final enhancedPath = await enhanceImage(imagePath);

    // 2. Smart OCR routing — ML Kit on-device, Gemini cloud for handwriting
    final smartResult = await SmartOcrService.instance.recognizeText(enhancedPath);

    // Convert SmartOcrResult to TextRegion list for existing pipeline
    final regions = smartResult.blocks.map((b) => TextRegion(
      text: b.text,
      confidence: b.confidence,
      x: b.x,
      y: b.y,
    )).toList();

    // 2b. If ML Kit was used and skew is high, try perspective/rotation correction
    var workingPath = enhancedPath;
    var workingRegions = regions;
    if (smartResult.source == OcrSource.mlKit && regions.isNotEmpty) {
      final skewAngle = _computeSkewFromRegions(regions);
      if (skewAngle.abs() > _skewCorrectionThreshold) {
        final perspectivePath = await compute(_perspectiveIsolate, enhancedPath);
        if (perspectivePath != enhancedPath) {
          final perspResult = await SmartOcrService.instance.recognizeText(perspectivePath);
          if (perspResult.blocks.length >= workingRegions.length) {
            workingPath = perspectivePath;
            workingRegions = perspResult.blocks.map((b) => TextRegion(
              text: b.text, confidence: b.confidence, x: b.x, y: b.y,
            )).toList();
          }
        }
        if (workingPath == enhancedPath) {
          final correctedPath = await correctRotation(enhancedPath, skewAngle);
          if (correctedPath != enhancedPath) {
            final reResult = await SmartOcrService.instance.recognizeText(correctedPath);
            if (reResult.blocks.length >= workingRegions.length) {
              workingPath = correctedPath;
              workingRegions = reResult.blocks.map((b) => TextRegion(
                text: b.text, confidence: b.confidence, x: b.x, y: b.y,
              )).toList();
            }
          }
        }
      }
    }

    // 3. Parse question numbers and answers
    final parsedAnswers = _parseAnswersFromRegions(workingRegions, assessment);

    // 4. Deduplicate — if ML Kit reads the same Q# twice, keep highest confidence
    final deduplicated = _scoring.deduplicateAnswers(parsedAnswers);

    // 5. Score against answer key
    final scoredAnswers = _scoring.scoreAnswers(
      detected: deduplicated,
      assessment: assessment,
    );

    // 6. Calculate totals
    final totalScore = _scoring.calculateTotalScore(scoredAnswers);
    final maxScore = assessment.maxScore;
    final percentage = _scoring.calculatePercentage(
      totalScore: totalScore,
      maxScore: maxScore,
    );

    // 6b. Multi-signal confidence scoring
    // Uses OCR confidence + parser confidence + spatial + length signals
    double overallConfidence = 0;
    if (scoredAnswers.isNotEmpty) {
      double totalConf = 0;
      for (final answer in scoredAnswers) {
        // Find the original OCR region for this answer
        final rawText = answer.ocrRawText ?? answer.detectedAnswer;
        final region = workingRegions.firstWhere(
          (r) => r.text.contains(rawText),
          orElse: () => TextRegion(text: '', confidence: 0, x: 0, y: 0),
        );
        totalConf += ConfidenceScorer.computeConfidence(
          ocrConfidence: region.confidence,
          answerText: answer.detectedAnswer,
          questionNumber: answer.questionNumber,
          pageHeight: null,
          answerY: region.y,
        );
      }
      overallConfidence = totalConf / scoredAnswers.length;
    }

    // 7. Build metadata with quality signals
    final metadata = <String, dynamic>{
      'textLinesDetected': workingRegions.length,
      'questionsDetected': deduplicated.length,
      'duplicatesRemoved': parsedAnswers.length - deduplicated.length,
      'ocrSource': smartResult.source.name,
      'isHandwriting': smartResult.isHandwriting,
      'rotationCorrected': workingPath != enhancedPath,
      'perspectiveCorrected': workingPath.contains('_perspective'),
    };

    return ScanResult(
      assessmentId: assessment.id,
      studentId: studentId,
      studentName: studentName,
      imagePath: imagePath,
      enhancedImagePath: workingPath,
      answers: scoredAnswers,
      totalScore: totalScore,
      maxScore: maxScore,
      percentage: percentage,
      grade: _scoring.calculateGrade(
        percentage.toDouble(),
        assessment.rubricType,
      ),
      // Lowered from 0.6 to 0.4 for handwritten answer support
      status: overallConfidence < 0.4
          ? ScanStatus.needsRescan
          : ScanStatus.graded,
      confidence: overallConfidence,
      imageHash: imageHash,
      metadata: metadata,
    );
  }

  /// Extract text regions from an enhanced image using ML Kit.
  /// Also estimates paper skew angle from text block alignment.
  ///
  /// [minConfidence] — floor below which lines are discarded. Defaults to
  /// [standardMinConfidence] (0.35). Callers grading subjective exams may
  /// pass [subjectiveMinConfidence] to retain low-confidence handwriting
  /// for review routing.
  ///
  /// Uses dual-recognizer strategy:
  /// 1. Latin script recognizer (printed English text)
  /// 2. Chinese script recognizer (fallback for Amharic/Ge'ez characters)
  ///
  /// Picks the result with more detected regions.
  ///
  /// Public so HybridGradingService can run OCR and OMR on the same
  /// enhanced image without double-enhancing.
  Future<({List<TextRegion> regions, double skewAngle})> extractTextRegions(
    String imagePath, {
    double? minConfidence,
  }) async {
    await initialize();

    final confidenceFloor = minConfidence ?? standardMinConfidence;

    try {
      final inputImage = InputImage.fromFilePath(imagePath);

      // Run Latin script recognizer first
      final latinResult = await _textRecognizer.processImage(inputImage);
      final latinRegions = _extractRegionsFromResult(
        latinResult,
        confidenceFloor,
      );

      // Run Amharic/Chinese script recognizer as fallback
      final amharicResult = await _amharicRecognizer.processImage(inputImage);
      final amharicRegions = _extractRegionsFromResult(
        amharicResult,
        confidenceFloor,
      );

      // Pick the result with more detected regions
      // (Amharic recognizer may find text that Latin misses)
      final bestRegions =
          latinRegions.length >= amharicRegions.length
              ? latinRegions
              : amharicRegions;

      // Compute skew from the best result's blocks
      final bestResult =
          latinRegions.length >= amharicRegions.length
              ? latinResult
              : amharicResult;
      final skewDegrees = _computeSkewFromResult(bestResult);

      debugPrint(
        'OCR: ${bestRegions.length} lines (latin: ${latinRegions.length}, amharic: ${amharicRegions.length}), skew ${skewDegrees.toStringAsFixed(1)}°',
      );
      // DEBUG: Show exactly what ML Kit detected
      debugPrint(
        'OCR RAW: ${bestRegions.map((r) => '"${r.text}" (${r.confidence.toStringAsFixed(2)})').join(', ')}',
      );
      return (regions: bestRegions, skewAngle: skewDegrees);
    } catch (e, st) {
      debugPrint('OCR: recognition failed ($e)\n$st');
      return (regions: <TextRegion>[], skewAngle: 0.0);
    }
  }

  /// Extract text regions from a RecognizedText result.
  List<TextRegion> _extractRegionsFromResult(
    RecognizedText recognized,
    double confidenceFloor,
  ) {
    final regions = <TextRegion>[];

    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        if (text.isEmpty) continue;

        // Confidence from character-level detection
        double confidence = 0.8;
        if (line.elements.isNotEmpty) {
          final confidences = line.elements
              .map((e) => e.confidence ?? 0.8)
              .toList();
          confidence =
              confidences.reduce((a, b) => a + b) / confidences.length;
        }

        if (confidence < confidenceFloor) continue;

        // Position from bounding box
        final points = line.cornerPoints;
        double x = 0, y = 0;
        if (points.isNotEmpty) {
          x = points.map((p) => p.x.toDouble()).reduce(math.min);
          y = points.map((p) => p.y.toDouble()).reduce(math.min);
        }

        regions.add(
          TextRegion(
            text: text,
            confidence: confidence.clamp(0.0, 1.0),
            x: x,
            y: y,
          ),
        );
      }
    }

    // Sort: top-to-bottom, left-to-right within same line
    double yTolerance = 10.0;
    if (regions.length > 1) {
      final ys = regions.map((r) => r.y);
      yTolerance = (ys.reduce(math.max) - ys.reduce(math.min)) * 0.05;
    }
    regions.sort((a, b) {
      if ((a.y - b.y).abs() < yTolerance) return a.x.compareTo(b.x);
      return a.y.compareTo(b.y);
    });

    return regions;
  }

  /// Compute skew angle from a RecognizedText result.
  double _computeSkewFromResult(RecognizedText recognized) {
    double totalAngle = 0;
    int angleCount = 0;

    for (final block in recognized.blocks) {
      if (block.cornerPoints.length >= 2) {
        final p1 = block.cornerPoints[0];
        final p2 = block.cornerPoints[1];
        final angle = math.atan2(
          (p2.y - p1.y).toDouble(),
          (p2.x - p1.x).toDouble(),
        );
        totalAngle += angle;
        angleCount++;
      }
    }

    return angleCount > 0
        ? (totalAngle / angleCount) * 180 / math.pi
        : 0.0;
  }

  /// Parse answers from a list of TextRegion (used by smart OCR routing).
  List<DetectedAnswer> _parseAnswersFromRegions(
    List<TextRegion> regions,
    Assessment assessment,
  ) {
    final inputs = regions
        .map(
          (r) => TextRegionInput(
            text: r.text,
            confidence: r.confidence,
            x: r.x,
            y: r.y,
          ),
        )
        .toList();

    final rawAnswers = _parser.parseAnswers(inputs);

    final questionTypes = <int, String>{};
    for (final q in assessment.questions) {
      final type = q.type.toString().split('.').last;
      questionTypes[q.number] = type;
    }

    final parsedAnswers = questionTypes.isNotEmpty
        ? _parser.parseAnswersWithContext(rawAnswers, questionTypes: questionTypes)
        : rawAnswers;

    return parsedAnswers
        .map(
          (p) => DetectedAnswer(
            questionNumber: p.questionNumber,
            answer: p.answer,
            confidence: p.confidence,
            rawText: p.rawText,
          ),
        )
        .toList();
  }

  /// Compute skew angle from a list of text regions (approximate).
  double _computeSkewFromRegions(List<TextRegion> regions) {
    if (regions.length < 2) return 0;
    // Simple heuristic: check vertical alignment variance
    final ys = regions.map((r) => r.y).toList();
    final avgY = ys.reduce((a, b) => a + b) / ys.length;
    final variance = ys.map((y) => (y - avgY) * (y - avgY)).reduce((a, b) => a + b) / ys.length;
    // If variance is high relative to text height, might be skewed
    return variance > 1000 ? 5.0 : 0.0; // Simplified — real impl would use Hough transform
  }

  /// Release ML Kit resources. Call when app is shutting down.
  void dispose() {
    if (_isInitialized) {
      _textRecognizer.close();
      _amharicRecognizer.close();
      _isInitialized = false;
    }
  }

  /// Delete enhanced/corrected images created during processing.
  ///
  /// Cleans up *_enhanced.jpg and *_corrected.jpg files alongside
  /// the original [imagePath]. Safe to call on any path — silently
  /// ignores missing files. Never throws.
  Future<void> cleanupEnhancedImages(String imagePath) async {
    try {
      final dotIndex = imagePath.lastIndexOf('.');
      final basePath = dotIndex > 0
          ? imagePath.substring(0, dotIndex)
          : imagePath;
      final enhanced = File('${basePath}_enhanced.jpg');
      if (await enhanced.exists()) await enhanced.delete();
      final corrected = File('${basePath}_corrected.jpg');
      if (await corrected.exists()) await corrected.delete();
      final perspective = File('${basePath}_perspective.jpg');
      if (await perspective.exists()) await perspective.delete();
    } catch (_) {
      // Never block the pipeline on cleanup failure
    }
  }

  /// Delete a list of image files and their enhanced variants.
  /// Safe to call on any paths — silently ignores missing files.
  Future<void> cleanupImages(List<String> imagePaths) async {
    for (final path in imagePaths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
        await cleanupEnhancedImages(path);
      } catch (_) {
        // Continue cleaning other files
      }
    }
  }

  /// Check if an image is a duplicate of any existing scan results.
  ///
  /// Computes the hash of [imagePath] and compares it against the
  /// `imageHash` field of each scan in [existingScans].
  ///
  /// Returns the index of the duplicate in [existingScans], or -1 if no
  /// duplicate found. Returns -2 if the hash couldn't be computed (file
  /// missing, corrupt) — caller should treat this as "no duplicate" and
  /// proceed normally.
  ///
  /// This is intentionally non-blocking: hash failure never stops scanning.
  Future<int> checkDuplicate(
    String imagePath,
    List<ScanResult> existingScans,
  ) async {
    final hash = await _hasher.computeHashAsync(imagePath);
    if (hash == null) return -2; // Can't compute — skip check
    final hashes = existingScans.map((s) => s.imageHash).toList();
    return _hasher.findDuplicate(hash, hashes);
  }

  /// Expose the hasher for UI-level duplicate checking.
  ImageHashService get hasher => _hasher;
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

/// Multi-signal confidence scorer for OCR results.
///
/// Combines multiple signals to produce a more accurate confidence estimate
/// than ML Kit's raw confidence alone:
/// 1. OCR confidence (ML Kit's character-level confidence)
/// 2. Parser confidence (question number detection quality)
/// 3. Spatial confidence (position合理性 on the page)
/// 4. Length confidence (text length reasonableness for answer type)
class ConfidenceScorer {
  /// Compute multi-signal confidence for a parsed answer.
  ///
  /// [ocrConfidence] — ML Kit's raw confidence (0-1)
  /// [answerText] — the detected answer text
  /// [questionNumber] — detected question number (null if not found)
  /// [expectedType] — expected answer type (mcq, trueFalse, shortAnswer)
  /// [pageHeight] — height of the page image in pixels
  /// [answerY] — vertical position of the answer on the page
  static double computeConfidence({
    required double ocrConfidence,
    required String answerText,
    int? questionNumber,
    String? expectedType,
    double? pageHeight,
    double? answerY,
  }) {
    double score = ocrConfidence; // Start with OCR confidence

    // Signal 1: Parser confidence (question number detection)
    double parserSignal = 1.0;
    if (questionNumber == null) {
      parserSignal = 0.5; // No question number detected — penalty
    } else if (questionNumber < 1 || questionNumber > 100) {
      parserSignal = 0.7; // Unreasonable question number
    }

    // Signal 2: Text length reasonableness
    double lengthSignal = 1.0;
    if (answerText.isEmpty) {
      lengthSignal = 0.0;
    } else if (expectedType == 'mcq') {
      // MCQ should be 1-2 characters (letter + optional period)
      if (answerText.length > 5) lengthSignal = 0.4;
    } else if (expectedType == 'trueFalse') {
      // True/False should be 2-5 characters
      final lower = answerText.toLowerCase();
      if (lower.length > 10) lengthSignal = 0.5;
      if (!lower.startsWith('t') && !lower.startsWith('f') &&
          !lower.startsWith('y') && !lower.startsWith('n')) {
        lengthSignal = 0.6;
      }
    } else {
      // Short answer: 1-200 characters is reasonable
      if (answerText.length > 200) lengthSignal = 0.6;
    }

    // Signal 3: Spatial confidence (position on page)
    double spatialSignal = 1.0;
    if (pageHeight != null && answerY != null) {
      // Answers should be in the middle 80% of the page
      final relativeY = answerY / pageHeight;
      if (relativeY < 0.05 || relativeY > 0.95) {
        spatialSignal = 0.7; // Edge of page — less likely to be answer
      }
    }

    // Combine signals with weights
    // OCR confidence is primary (60%), others are secondary
    score = ocrConfidence * 0.6 +
            parserSignal * 0.15 +
            lengthSignal * 0.15 +
            spatialSignal * 0.10;

    return score.clamp(0.0, 1.0);
  }

  /// Compute confidence for a line of OCR text (before parsing).
  ///
  /// Uses character-level confidence from ML Kit elements.
  static double computeLineConfidence(String text, List<double> charConfidences) {
    if (charConfidences.isEmpty) return 0.8; // Default if no char confidences

    final avgConfidence = charConfidences.reduce((a, b) => a + b) / charConfidences.length;

    // Penalty for very short text (likely noise)
    double lengthBonus = 1.0;
    if (text.length < 3) {
      lengthBonus = 0.7;
    } else if (text.length < 6) {
      lengthBonus = 0.85;
    }

    // Bonus for consistent confidence (all chars similar confidence)
    double consistencyBonus = 1.0;
    if (charConfidences.length > 3) {
      final variance = charConfidences.map((c) => (c - avgConfidence) * (c - avgConfidence)).reduce((a, b) => a + b) / charConfidences.length;
      if (variance > 0.05) {
        consistencyBonus = 0.9; // High variance — inconsistent recognition
      }
    }

    return (avgConfidence * lengthBonus * consistencyBonus).clamp(0.0, 1.0);
  }
}
