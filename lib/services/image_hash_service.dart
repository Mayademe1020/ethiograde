import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

int? _computeHashFromPathIsolate(String imagePath) {
  try {
    final file = File(imagePath);
    if (!file.existsSync()) return null;
    return _computeHashFromBytesSync(file.readAsBytesSync());
  } catch (_) {
    return null;
  }
}

int? _computeHashFromBytesIsolate(Uint8List bytes) {
  return _computeHashFromBytesSync(bytes);
}

int? _computeHashFromBytesSync(Uint8List bytes) {
  try {
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    return _dHash(image);
  } catch (_) {
    return null;
  }
}

int _dHash(img.Image source) {
  // Resize to 9x8: small enough to be fast, large enough to be accurate.
  final resized = img.copyResize(source, width: 9, height: 8);

  final bits = <int>[];
  for (int y = 0; y < 8; y++) {
    for (int x = 0; x < 8; x++) {
      final left = _luminance(resized.getPixel(x, y));
      final right = _luminance(resized.getPixel(x + 1, y));
      bits.add(left > right ? 1 : 0);
    }
  }

  int hash = 0;
  for (int i = 0; i < 64; i++) {
    if (bits[i] == 1) {
      hash |= (1 << i);
    }
  }
  return hash;
}

int _luminance(img.Pixel pixel) {
  // ITU-R BT.601 luma coefficients.
  return (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round();
}

/// Perceptual image hashing service for duplicate scan detection.
///
/// Uses dHash (difference hash): resize to 9x8 grayscale, compare adjacent
/// pixel brightness, and pack the result into a 64-bit hash.
class ImageHashService {
  static final ImageHashService _instance = ImageHashService._();
  factory ImageHashService() => _instance;
  ImageHashService._();

  /// Compute a 64-bit dHash for the image at [imagePath].
  ///
  /// Returns null if the image cannot be decoded. This synchronous API remains
  /// for tests and non-UI code; camera/scan screens should prefer
  /// [computeHashAsync] so image decoding does not stall the UI isolate.
  int? computeHash(String imagePath) {
    return _computeHashFromPathIsolate(imagePath);
  }

  /// Compute a 64-bit dHash for the image at [imagePath] off the UI isolate.
  Future<int?> computeHashAsync(String imagePath) {
    return compute(_computeHashFromPathIsolate, imagePath);
  }

  /// Compute dHash from raw image bytes.
  int? computeHashFromBytes(Uint8List bytes) {
    return _computeHashFromBytesSync(bytes);
  }

  /// Compute dHash from raw image bytes off the UI isolate.
  Future<int?> computeHashFromBytesAsync(Uint8List bytes) {
    return compute(_computeHashFromBytesIsolate, bytes);
  }

  /// Hamming distance between two hashes: count of differing bits.
  ///
  /// Returns -1 if either hash is null.
  int hammingDistance(int? hash1, int? hash2) {
    if (hash1 == null || hash2 == null) return -1;
    return _popcount(hash1 ^ hash2);
  }

  /// Count set bits using Kernighan's algorithm.
  int _popcount(int n) {
    int count = 0;
    while (n != 0) {
      n &= (n - 1);
      count++;
    }
    return count;
  }

  /// Images with Hamming distance <= this are treated as the same paper.
  static const int duplicateThreshold = 6;

  /// Check if two hashes represent the same paper.
  bool isDuplicate(int? hash1, int? hash2) {
    if (hash1 == null || hash2 == null) return false;
    return hammingDistance(hash1, hash2) <= duplicateThreshold;
  }

  /// Check a new image hash against a list of existing hashes.
  /// Returns the index of the first match, or -1 if no duplicate found.
  int findDuplicate(int? newHash, List<int?> existingHashes) {
    if (newHash == null) return -1;
    for (int i = 0; i < existingHashes.length; i++) {
      if (isDuplicate(newHash, existingHashes[i])) {
        return i;
      }
    }
    return -1;
  }
}
