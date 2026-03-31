import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Pure Dart perspective correction for document images.
///
/// Detects document edges, computes a perspective transform, and warps
/// the image so the document appears flat — even if the teacher held
/// the phone at an angle.
///
/// Design decisions:
/// - Pure Dart + image package — no OpenCV, no native deps
/// - Works on enhanced (grayscale) images from OcrService
/// - Corner detection runs at reduced resolution for speed
/// - Bilinear interpolation for quality on the final warp
/// - Graceful fallback: returns original image if detection fails
///
/// Memory budget: <50MB for a 1600px image (worst case).
/// Time budget: <1s for corner detection + warp on 2GB device.
class PerspectiveCorrectionService {
  static final PerspectiveCorrectionService _instance =
      PerspectiveCorrectionService._();
  factory PerspectiveCorrectionService() => _instance;
  PerspectiveCorrectionService._();

  /// Resolution for edge/corner detection (px on longest side).
  /// Lower = faster detection, less accurate. Higher = slower, more accurate.
  /// 400px is the sweet spot: fast enough for real-time, accurate for A4 docs.
  static const int _detectionResolution = 400;

  /// Brightness threshold for edge detection (0-255).
  /// Pixels darker than this are considered "document edge" candidates.
  static const int _edgeThreshold = 128;

  /// Minimum edge length as fraction of image dimension.
  /// Filters out noise edges that are too short to be document borders.
  static const double _minEdgeFraction = 0.3;

  /// Canny-style gradient magnitude threshold (0-255).
  static const int _gradientThreshold = 30;

  /// Result of perspective correction.
  final img.Image? image;
  final List<Point>? corners;
  final double confidence;
  final String? error;

  PerspectiveResult._({this.image, this.corners, required this.confidence, this.error});

  /// Apply perspective correction to an image file.
  ///
  /// Returns the path to the corrected image, or the original path if
  /// correction fails. Never crashes the grading pipeline.
  ///
  /// Steps:
  /// 1. Load image
  /// 2. Detect document corners (at reduced resolution)
  /// 3. Compute perspective transform
  /// 4. Warp image to rectangular output
  /// 5. Save and return path
  Future<String> correctPerspective(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return imagePath;

      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return imagePath;

      final result = await detectAndWarp(image);
      if (result.image == null || result.confidence < 0.4) {
        debugPrint(
          'Perspective: detection failed or low confidence '
          '(${result.confidence.toStringAsFixed(2)}), keeping original',
        );
        return imagePath;
      }

      // Save corrected image
      final dotIndex = imagePath.lastIndexOf('.');
      final basePath =
          dotIndex > 0 ? imagePath.substring(0, dotIndex) : imagePath;
      final correctedPath = '${basePath}_perspective.jpg';
      await File(correctedPath)
          .writeAsBytes(img.encodeJpg(result.image!, quality: 92));

      debugPrint(
        'Perspective: corrected with confidence '
        '${result.confidence.toStringAsFixed(2)}',
      );
      return correctedPath;
    } catch (e, st) {
      debugPrint('Perspective: correction failed ($e)\n$st');
      return imagePath;
    }
  }

  /// Detect document corners and warp the image.
  ///
  /// [source] — the full-resolution input image.
  /// Returns the warped image + detected corners + confidence.
  Future<PerspectiveResult> detectAndWarp(img.Image source) async {
    // Step 1: Detect corners at reduced resolution
    final corners = await detectCorners(source);
    if (corners == null || corners.length != 4) {
      return PerspectiveResult._(confidence: 0.0, error: 'Could not detect 4 corners');
    }

    // Step 2: Compute confidence from corner positions
    final confidence = _computeConfidence(corners, source.width, source.height);
    if (confidence < 0.3) {
      return PerspectiveResult._(
        corners: corners,
        confidence: confidence,
        error: 'Low confidence in corner detection',
      );
    }

    // Step 3: Compute output dimensions (A4-ish aspect ratio)
    final outputSize = _computeOutputSize(corners);

    // Step 4: Warp the full-resolution image
    final warped = _warpImage(
      source,
      corners,
      outputSize.width,
      outputSize.height,
    );

    if (warped == null) {
      return PerspectiveResult._(
        corners: corners,
        confidence: confidence,
        error: 'Warp failed',
      );
    }

    return PerspectiveResult._(
      image: warped,
      corners: corners,
      confidence: confidence,
    );
  }

  /// Detect the 4 corners of a document in an image.
  ///
  /// Algorithm:
  /// 1. Resize to detection resolution for speed
  /// 2. Compute gradient magnitude (Sobel-like)
  /// 3. Threshold to get edge pixels
  /// 4. Find edge pixels near image borders (document edges)
  /// 5. Fit lines to border edges using Hough-like accumulation
  /// 6. Find intersections of the 4 strongest lines = corners
  ///
  /// Returns 4 corners ordered: top-left, top-right, bottom-right, bottom-left,
  /// or null if detection fails.
  Future<List<Point>?> detectCorners(img.Image source) async {
    // Resize for detection
    final longer = source.width > source.height ? source.width : source.height;
    final scale = _detectionResolution / longer;
    final detectWidth = (source.width * scale).round();
    final detectHeight = (source.height * scale).round();

    final small = img.copyResize(
      source,
      width: detectWidth,
      height: detectHeight,
      interpolation: img.Interpolation.nearest, // fast, we just need structure
    );

    // Ensure grayscale
    final gray = small.numChannels > 1 ? img.grayscale(small) : small;

    // Compute gradient magnitude using Sobel
    final gradients = _computeGradients(gray);

    // Threshold to edge pixels
    final edgePixels = <Point>[];
    for (int y = 1; y < detectHeight - 1; y++) {
      for (int x = 1; x < detectWidth - 1; x++) {
        if (gradients[y * detectWidth + x] > _gradientThreshold) {
          edgePixels.add(Point(x.toDouble(), y.toDouble()));
        }
      }
    }

    if (edgePixels.length < 20) return null; // Not enough edges

    // Find edges near image borders (top, bottom, left, right)
    final borderEdges = _findBorderEdges(
      edgePixels,
      detectWidth,
      detectHeight,
    );

    if (borderEdges.length < 4) {
      // Fallback: use image rectangle as corners
      debugPrint('Perspective: insufficient border edges, using image rect');
      return _imageCorners(source.width.toDouble(), source.height.toDouble());
    }

    // Fit lines to each border edge cluster
    final lines = _fitLines(borderEdges, detectWidth, detectHeight);
    if (lines.length < 4) {
      return _imageCorners(source.width.toDouble(), source.height.toDouble());
    }

    // Find intersections of pairs of lines (one horizontal-ish, one vertical-ish)
    final corners = _findIntersections(lines, scale);

    if (corners.length != 4) {
      return _imageCorners(source.width.toDouble(), source.height.toDouble());
    }

    // Order corners: TL, TR, BR, BL
    return _orderCorners(corners);
  }

  /// Compute gradient magnitude using a simplified Sobel operator.
  List<int> _computeGradients(img.Image gray) {
    final w = gray.width;
    final h = gray.height;
    final gradients = List<int>.filled(w * h, 0);

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        // Sobel X: [-1 0 1; -2 0 2; -1 0 1]
        final gx = -_getGray(gray, x - 1, y - 1) +
            _getGray(gray, x + 1, y - 1) -
            2 * _getGray(gray, x - 1, y) +
            2 * _getGray(gray, x + 1, y) -
            _getGray(gray, x - 1, y + 1) +
            _getGray(gray, x + 1, y + 1);

        // Sobel Y: [-1 -2 -1; 0 0 0; 1 2 1]
        final gy = -_getGray(gray, x - 1, y - 1) -
            2 * _getGray(gray, x, y - 1) -
            _getGray(gray, x + 1, y - 1) +
            _getGray(gray, x - 1, y + 1) +
            2 * _getGray(gray, x, y + 1) +
            _getGray(gray, x + 1, y + 1);

        gradients[y * w + x] =
            ((gx.abs() + gy.abs()) / 2).round().clamp(0, 255);
      }
    }

    return gradients;
  }

  int _getGray(img.Image image, int x, int y) {
    final pixel = image.getPixel(x, y);
    return pixel.r.toInt(); // grayscale, R=G=B
  }

  /// Find edge pixels clustered near each image border.
  ///
  /// Returns a map of border → edge pixels on that border.
  Map<String, List<Point>> _findBorderEdges(
    List<Point> edges,
    int width,
    int height,
  ) {
    final margin = (width * 0.15).round(); // 15% margin from border
    final result = <String, List<Point>>{
      'top': [],
      'bottom': [],
      'left': [],
      'right': [],
    };

    for (final p in edges) {
      if (p.y < margin) result['top']!.add(p);
      if (p.y > height - margin) result['bottom']!.add(p);
      if (p.x < margin) result['left']!.add(p);
      if (p.x > width - margin) result['right']!.add(p);
    }

    // Filter: each border needs enough points to be meaningful
    final minPoints = (width * _minEdgeFraction / 4).round();
    result.removeWhere((_, pts) => pts.length < minPoints);

    return result;
  }

  /// Fit a line (y = mx + b) to a set of points using least squares.
  /// Returns the line parameters, or null if fitting fails.
  ({double m, double b})? _fitLine(List<Point> points) {
    if (points.length < 3) return null;

    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    for (final p in points) {
      sumX += p.x;
      sumY += p.y;
      sumXY += p.x * p.y;
      sumX2 += p.x * p.x;
    }

    final n = points.length.toDouble();
    final denom = n * sumX2 - sumX * sumX;
    if (denom.abs() < 0.001) {
      // Vertical line: x = constant
      final avgX = sumX / n;
      return (m: double.infinity, b: avgX);
    }

    final m = (n * sumXY - sumX * sumY) / denom;
    final b = (sumY - m * sumX) / n;
    return (m: m, b: b);
  }

  /// Fit lines to all border edge clusters.
  List<({String border, double m, double b})> _fitLines(
    Map<String, List<Point>> borderEdges,
    int width,
    int height,
  ) {
    final lines = <({String border, double m, double b})>[];

    for (final entry in borderEdges.entries) {
      final line = _fitLine(entry.value);
      if (line != null) {
        lines.add((border: entry.key, m: line.m, b: line.b));
      }
    }

    return lines;
  }

  /// Find intersections between horizontal-ish and vertical-ish lines.
  /// Scales points back to original image coordinates.
  List<Point> _findIntersections(
    List<({String border, double m, double b})> lines,
    double scale,
  ) {
    final hLines = lines
        .where((l) =>
            l.border == 'top' || l.border == 'bottom' || l.m.abs() < 1.5)
        .toList();
    final vLines = lines
        .where((l) =>
            l.border == 'left' || l.border == 'right' ||
            l.m.abs() >= 1.5 || l.m.isInfinite)
        .toList();

    final intersections = <Point>[];

    for (final h in hLines) {
      for (final v in vLines) {
        Point? p;
        if (v.m.isInfinite) {
          // Vertical line: x = b
          final x = v.b;
          final y = h.m * x + h.b;
          p = Point(x / scale, y / scale);
        } else if (h.m.isInfinite) {
          // H is vertical, V is horizontal (shouldn't happen normally)
          final x = h.b;
          final y = v.m * x + v.b;
          p = Point(x / scale, y / scale);
        } else {
          // Both are normal lines
          final denom = h.m - v.m;
          if (denom.abs() < 0.001) continue; // Parallel
          final x = (v.b - h.b) / denom;
          final y = h.m * x + h.b;
          p = Point(x / scale, y / scale);
        }

        // Only keep intersections that are reasonably close to the image
        if (p.x > -500 && p.y > -500) {
          intersections.add(p);
        }
      }
    }

    return intersections;
  }

  /// Order 4 corners as: top-left, top-right, bottom-right, bottom-left.
  List<Point> _orderCorners(List<Point> corners) {
    if (corners.length != 4) return corners;

    // Sort by Y to find top/bottom pairs
    final sorted = List<Point>.from(corners)..sort((a, b) => a.y.compareTo(b.y));
    final top = [sorted[0], sorted[1]]..sort((a, b) => a.x.compareTo(b.x));
    final bottom = [sorted[2], sorted[3]]..sort((a, b) => a.x.compareTo(b.x));

    return [top[0], top[1], bottom[1], bottom[0]]; // TL, TR, BR, BL
  }

  /// Default corners when detection fails (full image rectangle).
  List<Point> _imageCorners(double w, double h) {
    return [
      Point(0, 0), // TL
      Point(w, 0), // TR
      Point(w, h), // BR
      Point(0, h), // BL
    ];
  }

  /// Compute output size maintaining aspect ratio of the detected quadrilateral.
  ({int width, int height}) _computeOutputSize(List<Point> corners) {
    // Average width (top + bottom edges)
    final topWidth = (corners[1].x - corners[0].x).abs();
    final bottomWidth = (corners[2].x - corners[3].x).abs();
    final avgWidth = ((topWidth + bottomWidth) / 2).round();

    // Average height (left + right edges)
    final leftHeight = (corners[3].y - corners[0].y).abs();
    final rightHeight = (corners[2].y - corners[1].y).abs();
    final avgHeight = ((leftHeight + rightHeight) / 2).round();

    return (
      width: avgWidth.clamp(100, 4000),
      height: avgHeight.clamp(100, 4000),
    );
  }

  /// Warp the source image using perspective transform.
  ///
  /// Uses inverse mapping: for each output pixel, find the source position
  /// using the perspective transform, then sample with bilinear interpolation.
  img.Image? _warpImage(
    img.Image source,
    List<Point> corners,
    int outWidth,
    int outHeight,
  ) {
    if (outWidth <= 0 || outHeight <= 0) return null;

    try {
      final dst = img.Image(width: outWidth, height: outHeight, numChannels: source.numChannels);

      // Compute homography matrix (source → destination)
      final srcPoints = corners;
      final dstPoints = [
        Point(0.0, 0.0),
        Point(outWidth.toDouble(), 0.0),
        Point(outWidth.toDouble(), outHeight.toDouble()),
        Point(0.0, outHeight.toDouble()),
      ];

      final h = _computeHomography(dstPoints, srcPoints); // inverse: dst→src
      if (h == null) return null;

      // Warp each output pixel
      for (int y = 0; y < outHeight; y++) {
        for (int x = 0; x < outWidth; x++) {
          final srcCoord = _applyHomography(h, x.toDouble(), y.toDouble());
          if (srcCoord == null) continue;

          // Bilinear interpolation
          final pixel = _sampleBilinear(source, srcCoord.x, srcCoord.y);
          if (pixel != null) {
            dst.setPixel(x, y, pixel);
          }
        }
      }

      return dst;
    } catch (e) {
      debugPrint('Perspective: warp failed ($e)');
      return null;
    }
  }

  /// Compute a 3x3 homography matrix mapping 4 source points to 4 destination points.
  ///
  /// Uses the Direct Linear Transform (DLT) algorithm.
  /// Returns the 9-element matrix as a flat list [h00, h01, h02, h10, h11, h12, h20, h21, h22].
  List<double>? _computeHomography(List<Point> src, List<Point> dst) {
    // Build the 8x8 linear system Ah = 0
    // We solve for h (8 unknowns, h22 = 1)
    final a = List.generate(8, (_) => List<double>.filled(8, 0));
    final b = List<double>.filled(8, 0);

    for (int i = 0; i < 4; i++) {
      final sx = src[i].x, sy = src[i].y;
      final dx = dst[i].x, dy = dst[i].y;

      final row = i * 2;
      a[row][0] = sx;
      a[row][1] = sy;
      a[row][2] = 1;
      a[row][3] = 0;
      a[row][4] = 0;
      a[row][5] = 0;
      a[row][6] = -sx * dx;
      a[row][7] = -sy * dx;
      b[row] = dx;

      a[row + 1][0] = 0;
      a[row + 1][1] = 0;
      a[row + 1][2] = 0;
      a[row + 1][3] = sx;
      a[row + 1][4] = sy;
      a[row + 1][5] = 1;
      a[row + 1][6] = -sx * dy;
      a[row + 1][7] = -sy * dy;
      b[row + 1] = dy;
    }

    // Solve with Gaussian elimination
    final h = _solveLinear(a, b);
    if (h == null) return null;

    return [h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], 1.0];
  }

  /// Solve an 8x8 linear system Ax = b using Gaussian elimination with partial pivoting.
  List<double>? _solveLinear(List<List<double>> a, List<double> b) {
    final n = 8;
    // Augmented matrix
    final aug = List.generate(
      n,
      (i) => [...a[i], b[i]],
    );

    // Forward elimination
    for (int col = 0; col < n; col++) {
      // Partial pivoting
      int maxRow = col;
      double maxVal = aug[col][col].abs();
      for (int row = col + 1; row < n; row++) {
        if (aug[row][col].abs() > maxVal) {
          maxVal = aug[row][col].abs();
          maxRow = row;
        }
      }

      if (maxVal < 1e-10) return null; // Singular

      if (maxRow != col) {
        final tmp = aug[col];
        aug[col] = aug[maxRow];
        aug[maxRow] = tmp;
      }

      // Eliminate below
      for (int row = col + 1; row < n; row++) {
        final factor = aug[row][col] / aug[col][col];
        for (int j = col; j <= n; j++) {
          aug[row][j] -= factor * aug[col][j];
        }
      }
    }

    // Back substitution
    final result = List<double>.filled(n, 0);
    for (int i = n - 1; i >= 0; i--) {
      result[i] = aug[i][n];
      for (int j = i + 1; j < n; j++) {
        result[i] -= aug[i][j] * result[j];
      }
      result[i] /= aug[i][i];
    }

    return result;
  }

  /// Apply homography to a point: project from destination to source.
  Point? _applyHomography(List<double> h, double x, double y) {
    final w = h[6] * x + h[7] * y + h[8];
    if (w.abs() < 1e-10) return null;
    return Point(
      (h[0] * x + h[1] * y + h[2]) / w,
      (h[3] * x + h[4] * y + h[5]) / w,
    );
  }

  /// Sample a pixel using bilinear interpolation.
  /// Returns null if the coordinate is outside the image.
  img.Pixel? _sampleBilinear(img.Image source, double x, double y) {
    final x0 = x.floor();
    final y0 = y.floor();
    final x1 = x0 + 1;
    final y1 = y0 + 1;

    if (x0 < 0 || y0 < 0 || x1 >= source.width || y1 >= source.height) {
      return null;
    }

    final fx = x - x0;
    final fy = y - y0;

    final p00 = source.getPixel(x0, y0);
    final p10 = source.getPixel(x1, y0);
    final p01 = source.getPixel(x0, y1);
    final p11 = source.getPixel(x1, y1);

    // Interpolate each channel
    num interp(num a, num b, num c, num d) {
      return a * (1 - fx) * (1 - fy) +
          b * fx * (1 - fy) +
          c * (1 - fx) * fy +
          d * fx * fy;
    }

    final r = interp(p00.r, p10.r, p01.r, p11.r).round().clamp(0, 255);
    final g = interp(p00.g, p10.g, p01.g, p11.g).round().clamp(0, 255);
    final b = interp(p00.b, p10.b, p01.b, p11.b).round().clamp(0, 255);

    if (source.numChannels >= 4) {
      final a = interp(p00.a, p10.a, p01.a, p11.a).round().clamp(0, 255);
      return img.ColorRgba8(r, g, b, a);
    }

    return img.ColorRgb8(r, g, b);
  }

  /// Compute confidence of corner detection (0.0 - 1.0).
  ///
  /// Factors:
  /// - Are corners spread across the image? (not all in one corner)
  /// - Is the detected quadrilateral convex?
  /// - Does it have reasonable area?
  double _computeConfidence(List<Point> corners, int imgW, int imgH) {
    if (corners.length != 4) return 0.0;

    // Check convexity (cross product sign consistency)
    double crossProduct(Point o, Point a, Point b) {
      return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    }

    final crosses = [
      crossProduct(corners[0], corners[1], corners[2]),
      crossProduct(corners[1], corners[2], corners[3]),
      crossProduct(corners[2], corners[3], corners[0]),
      crossProduct(corners[3], corners[0], corners[1]),
    ];

    final allPositive = crosses.every((c) => c > 0);
    final allNegative = crosses.every((c) => c < 0);
    if (!allPositive && !allNegative) return 0.2; // Not convex

    // Area of quadrilateral (shoelace formula)
    double area = 0;
    for (int i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      area += corners[i].x * corners[j].y;
      area -= corners[j].x * corners[i].y;
    }
    area = area.abs() / 2;

    final imgArea = imgW * imgH;
    final areaRatio = area / imgArea;

    // Good: area is 20-95% of image (document fills most of frame)
    if (areaRatio < 0.1 || areaRatio > 0.98) return 0.3;

    // Spread: are corners near image edges?
    double edgeDistance = 0;
    for (final c in corners) {
      final dLeft = c.x;
      final dRight = imgW - c.x;
      final dTop = c.y;
      final dBottom = imgH - c.y;
      edgeDistance += [dLeft, dRight, dTop, dBottom].reduce(math.min);
    }
    final avgEdgeDist = edgeDistance / 4;
    final edgeScore = (1.0 - avgEdgeDist / (imgW * 0.3)).clamp(0.0, 1.0);

    // Combined confidence
    return (0.4 + 0.3 * edgeScore + 0.3 * areaRatio.clamp(0.0, 1.0)).clamp(0.0, 1.0);
  }
}

/// A 2D point with double coordinates.
class Point {
  final double x;
  final double y;

  const Point(this.x, this.y);

  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

/// Result of perspective correction.
class PerspectiveResult {
  final img.Image? image;
  final List<Point>? corners;
  final double confidence;
  final String? error;

  PerspectiveResult._({
    this.image,
    this.corners,
    required this.confidence,
    this.error,
  });
}
