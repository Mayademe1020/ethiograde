import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

enum PaperImageSource { camera, upload }

enum PaperImageReadiness { ready, needsAttention, rejected }

class PaperImageReviewItem {
  final String path;
  final PaperImageSource source;
  final PaperImageReadiness readiness;
  final String message;

  const PaperImageReviewItem({
    required this.path,
    required this.source,
    required this.readiness,
    required this.message,
  });

  bool get isReady => readiness == PaperImageReadiness.ready;
  bool get canShowPreview => readiness != PaperImageReadiness.rejected;
}

class PaperImageIntakeResult {
  final PaperImageSource source;
  final List<String> imagePaths;
  final List<String> rejectedPaths;
  final List<PaperImageReviewItem> reviewItems;

  const PaperImageIntakeResult({
    required this.source,
    required this.imagePaths,
    this.rejectedPaths = const [],
    this.reviewItems = const [],
  });

  bool get hasImages => imagePaths.isNotEmpty;
  List<PaperImageReviewItem> get readyItems => reviewItems
      .where((item) => item.readiness == PaperImageReadiness.ready)
      .toList();
  List<PaperImageReviewItem> get attentionItems => reviewItems
      .where((item) => item.readiness == PaperImageReadiness.needsAttention)
      .toList();
  List<PaperImageReviewItem> get rejectedItems => reviewItems
      .where((item) => item.readiness == PaperImageReadiness.rejected)
      .toList();
}

class PaperImageIntakeService {
  static const String uploadStorageFolder = 'uploaded_papers';
  static const String temporaryRetention = 'temporary';

  static const Set<String> supportedExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
  };

  PaperImageIntakeResult fromPaths({
    required Iterable<String?> paths,
    required PaperImageSource source,
  }) {
    final reviewItems = reviewPaths(paths: paths, source: source);
    final accepted = reviewItems
        .where((item) => item.readiness != PaperImageReadiness.rejected)
        .map((item) => item.path)
        .toList();
    final rejected = reviewItems
        .where((item) => item.readiness == PaperImageReadiness.rejected)
        .map((item) => item.path)
        .toList();

    return PaperImageIntakeResult(
      source: source,
      imagePaths: accepted,
      rejectedPaths: rejected,
      reviewItems: reviewItems,
    );
  }

  List<PaperImageReviewItem> reviewPaths({
    required Iterable<String?> paths,
    required PaperImageSource source,
  }) {
    final items = <PaperImageReviewItem>[];
    final seen = <String>{};

    for (final rawPath in paths) {
      final path = rawPath?.trim();
      if (path == null || path.isEmpty || !seen.add(path)) continue;

      if (!_isSupportedImage(path) || !File(path).existsSync()) {
        items.add(
          PaperImageReviewItem(
            path: path,
            source: source,
            readiness: PaperImageReadiness.rejected,
            message: 'Unsupported or missing file',
          ),
        );
        continue;
      }

      items.add(_reviewImage(path: path, source: source));
    }

    return items;
  }

  Future<List<String>> copyReadyImagesForGrading({
    required Iterable<PaperImageReviewItem> items,
    Directory? targetDirectory,
  }) async {
    final readyItems = items.where((item) => item.isReady).toList();
    if (readyItems.isEmpty) return [];

    final directory = targetDirectory ?? await _defaultUploadDirectory();
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    final copiedPaths = <String>[];
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < readyItems.length; i++) {
      final source = File(readyItems[i].path);
      if (!source.existsSync()) continue;

      final extension = _extensionFor(source.path);
      final targetPath =
          '${directory.path}${Platform.pathSeparator}paper_${timestamp}_$i$extension';
      final copied = await source.copy(targetPath);
      copiedPaths.add(copied.path);
    }

    return copiedPaths;
  }

  Future<void> deleteManagedTemporaryFiles(Iterable<String?> paths) async {
    for (final path in paths) {
      if (path == null || path.isEmpty || !_isManagedTemporaryPath(path)) {
        continue;
      }
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  bool _isSupportedImage(String path) {
    final lower = path.toLowerCase();
    return supportedExtensions.any(lower.endsWith);
  }

  Future<Directory> _defaultUploadDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory(
      '${appDir.path}${Platform.pathSeparator}images'
      '${Platform.pathSeparator}$uploadStorageFolder',
    );
  }

  bool _isManagedTemporaryPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.contains('/$uploadStorageFolder/');
  }

  String _extensionFor(String path) {
    final lower = path.toLowerCase();
    for (final extension in supportedExtensions) {
      if (lower.endsWith(extension)) return extension;
    }
    return '.jpg';
  }

  PaperImageReviewItem _reviewImage({
    required String path,
    required PaperImageSource source,
  }) {
    try {
      final decoded = img.decodeImage(File(path).readAsBytesSync());
      if (decoded == null) {
        return PaperImageReviewItem(
          path: path,
          source: source,
          readiness: PaperImageReadiness.rejected,
          message: 'Could not read image',
        );
      }

      if (decoded.width < 400 || decoded.height < 400) {
        return PaperImageReviewItem(
          path: path,
          source: source,
          readiness: PaperImageReadiness.needsAttention,
          message: 'Small photo - answers may be hard to read',
        );
      }

      final brightness = _averageBrightness(decoded);
      if (brightness < 45) {
        return PaperImageReviewItem(
          path: path,
          source: source,
          readiness: PaperImageReadiness.needsAttention,
          message: 'Too dark - retake or improve light',
        );
      }

      return PaperImageReviewItem(
        path: path,
        source: source,
        readiness: PaperImageReadiness.ready,
        message: 'Ready for grading',
      );
    } catch (_) {
      return PaperImageReviewItem(
        path: path,
        source: source,
        readiness: PaperImageReadiness.rejected,
        message: 'Could not read image',
      );
    }
  }

  double _averageBrightness(img.Image image) {
    final stepX = (image.width / 24).ceil().clamp(1, image.width);
    final stepY = (image.height / 24).ceil().clamp(1, image.height);
    var total = 0.0;
    var count = 0;

    for (var y = 0; y < image.height; y += stepY) {
      for (var x = 0; x < image.width; x += stepX) {
        final pixel = image.getPixel(x, y);
        total += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
        count++;
      }
    }

    return count == 0 ? 0 : total / count;
  }
}
