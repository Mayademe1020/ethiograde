import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'settings_provider.dart';

/// Cloud OCR service using Qwen-VL vision API (DashScope compatible mode).
///
/// Sends compressed paper images to the API and receives structured
/// text recognition results. Handles compression, error recovery,
/// and response parsing.
class CloudOcrService {
  static final CloudOcrService _instance = CloudOcrService._();
  factory CloudOcrService() => _instance;
  CloudOcrService._();

  /// Maximum image file size in bytes after compression (300KB).
  /// Clear image at 300KB is better than blurry at 200KB.
  static const int _maxImageBytes = 300 * 1024;

  /// Maximum image dimension for compression.
  static const int _maxDimension = 1600;

  /// Minimum JPEG quality — below this, text becomes unreadable.
  static const int _minQuality = 70;

  /// API endpoint — set via [configure].
  String _apiEndpoint = '';
  String _apiKey = '';
  String _modelName = 'qwen-vl-plus';
  bool _configured = false;

  bool get isConfigured => _configured;

  /// Auto-configure from SettingsProvider (called before each scan).
  Future<bool> autoConfigure() async {
    try {
      final settings = SettingsProvider();
      await settings.loadSettings();
      if (settings.cloudOcrEnabled && settings.cloudOcrApiKey.isNotEmpty) {
        configure(
          apiEndpoint: settings.cloudOcrEndpoint,
          apiKey: settings.cloudOcrApiKey,
        );
        _modelName = settings.cloudOcrModel;
        return true;
      }
    } catch (e) {
      debugPrint('CloudOcr: autoConfigure failed: $e');
    }
    return false;
  }

  /// Configure the API credentials.
  void configure({required String apiEndpoint, required String apiKey}) {
    _apiEndpoint = apiEndpoint;
    _apiKey = apiKey;
    _configured = true;
    debugPrint('CloudOcr: configured with endpoint ${_apiEndpoint.substring(0, (_apiEndpoint.length - 10).clamp(0, _apiEndpoint.length))}...');
  }

  /// Process a paper image and return recognized text regions.
  ///
  /// 1. Compresses image to under 200KB
  /// 2. Sends to Qwen3-VL-Flash API
  /// 3. Returns structured text response
  ///
  /// Throws [CloudOcrException] on failure.
  Future<CloudOcrResult> processImage(String imagePath) async {
    if (!_configured) {
      throw CloudOcrException('Cloud OCR not configured');
    }

    final file = File(imagePath);
    if (!await file.exists()) {
      throw CloudOcrException('Image file not found');
    }

    // Compress image
    final compressedBytes = await _compressImage(imagePath);

    // Send to API
    final response = await _sendToApi(compressedBytes);

    return response;
  }

  /// Compress an image to under 300KB for API transmission.
  ///
  /// Strategy:
  /// 1. Decode and downscale to max 1600px
  /// 2. Try JPEG quality 90 → 80 → 70 (stop when under 300KB)
  /// 3. If quality 70 still too large, reduce resolution (1600→1200→800)
  /// 4. Minimum quality 70 — below this, text becomes unreadable
  Future<List<int>> _compressImage(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw CloudOcrException('Failed to decode image');

    // EXIF rotation
    image = img.bakeOrientation(image);

    // Downscale if needed
    if (image.width > _maxDimension || image.height > _maxDimension) {
      final longer = image.width > image.height ? image.width : image.height;
      final ratio = _maxDimension / longer;
      image = img.copyResize(
        image,
        width: (image.width * ratio).round(),
        height: (image.height * ratio).round(),
        interpolation: img.Interpolation.cubic,
      );
    }

    // Step 1: Try decreasing quality (90 → 80 → 70), stop when under target
    for (int quality = 90; quality >= _minQuality; quality -= 10) {
      final encoded = img.encodeJpg(image, quality: quality);
      if (encoded.lengthInBytes <= _maxImageBytes) {
        debugPrint('CloudOcr: compressed to ${encoded.lengthInBytes ~/ 1024}KB (q$quality)');
        return encoded;
      }
    }

    // Step 2: Quality 70 still too large — reduce resolution instead
    // Clear text at lower resolution beats blurry text at higher resolution
    final resolutions = [1200, 800, 600];
    for (final maxDim in resolutions) {
      if (image.width <= maxDim && image.height <= maxDim) continue;

      final longer = image.width > image.height ? image.width : image.height;
      final ratio = maxDim / longer;
      final resized = img.copyResize(
        image,
        width: (image.width * ratio).round(),
        height: (image.height * ratio).round(),
        interpolation: img.Interpolation.cubic,
      );

      final encoded = img.encodeJpg(resized, quality: _minQuality);
      if (encoded.lengthInBytes <= _maxImageBytes) {
        debugPrint('CloudOcr: compressed to ${encoded.lengthInBytes ~/ 1024}KB (q$_minQuality, ${maxDim}px)');
        return encoded;
      }
    }

    // Fallback: lowest resolution, minimum quality
    final fallback = img.copyResize(image, width: 600, height: (600 * image.height / image.width).round());
    final encoded = img.encodeJpg(fallback, quality: _minQuality);
    debugPrint('CloudOcr: compressed to ${encoded.lengthInBytes ~/ 1024}KB (q$_minQuality, 600px, fallback)');
    return encoded;
  }

  /// Send compressed image to Qwen3-VL-Flash API.
  Future<CloudOcrResult> _sendToApi(List<int> imageBytes) async {
    final base64Image = base64Encode(imageBytes);

    final prompt = '''You are an exam answer extractor for Ethiopian teachers.

Look at this image of a student's exam paper.
Extract the answer for each question number.

Common Ethiopian format: the answer letter appears
BEFORE the question number like:
B 1. What is the capital?
A 2. What is 2+2?

Rules:
- For MCQ: extract single letter (A, B, C, D, or E)
- For multiple correct: extract all letters (e.g., "A,C")
- For True/False: extract T or F
- For short answer: extract the text after the question number
- Ignore student name, ID, and any non-answer text
- If an answer is unclear or unreadable, skip it

Return ONLY a JSON array. No other text.
Format: [{"q":1,"answer":"B","confidence":"high"},...]

If you detect zero answers, return an empty array: []''';

    final requestBody = jsonEncode({
      'model': _modelName,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:image/jpeg;base64,$base64Image',
              },
            },
          ],
        },
      ],
      'max_tokens': 1024,
      'temperature': 0.1,
    });

    try {
      final response = await http.post(
        Uri.parse(_apiEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: requestBody,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw CloudOcrException(
          'API error ${response.statusCode}: ${response.body}',
        );
      }

      return _parseResponse(response.body);
    } on TimeoutException {
      throw CloudOcrException('API request timed out');
    } on SocketException catch (e) {
      throw CloudOcrException('Network error: ${e.message}');
    } catch (e) {
      if (e is CloudOcrException) rethrow;
      throw CloudOcrException('API request failed: $e');
    }
  }

  /// Parse the API response into structured result.
  CloudOcrResult _parseResponse(String responseBody) {
    try {
      final Map<String, dynamic> json = jsonDecode(responseBody);
      final choices = json['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw CloudOcrException('Empty API response');
      }

      final content = choices[0]['message']?['content'] as String? ?? '';

      // Extract JSON array from response (may be wrapped in markdown)
      final jsonMatch = RegExp(r'\[.*\]', dotAll: true).firstMatch(content);
      if (jsonMatch == null) {
        // No JSON array found — return raw text
        return CloudOcrResult(
          rawText: content,
          answers: const [],
          confidence: 0.0,
        );
      }

      final answersJson = jsonDecode(jsonMatch.group(0)!) as List;
      final answers = answersJson.map((a) {
        return CloudOcrAnswer(
          questionNumber: a['q'] as int? ?? 0,
          answer: (a['answer'] as String? ?? '').toUpperCase(),
          confidence: _parseConfidence(a['confidence'] as String? ?? 'low'),
        );
      }).toList();

      // Calculate overall confidence
      double totalConfidence = 0;
      for (final a in answers) {
        totalConfidence += a.confidence;
      }
      final avgConfidence = answers.isNotEmpty ? totalConfidence / answers.length : 0.0;

      return CloudOcrResult(
        rawText: content,
        answers: answers,
        confidence: avgConfidence,
      );
    } catch (e) {
      if (e is CloudOcrException) rethrow;
      throw CloudOcrException('Failed to parse API response: $e');
    }
  }

  double _parseConfidence(String level) {
    switch (level.toLowerCase()) {
      case 'high':
        return 0.95;
      case 'medium':
        return 0.75;
      case 'low':
        return 0.4;
      default:
        return 0.5;
    }
  }
}

/// Result from cloud OCR processing.
class CloudOcrResult {
  final String rawText;
  final List<CloudOcrAnswer> answers;
  final double confidence;

  const CloudOcrResult({
    required this.rawText,
    required this.answers,
    required this.confidence,
  });

  bool get hasAnswers => answers.isNotEmpty;
}

/// A single answer detected by cloud OCR.
class CloudOcrAnswer {
  final int questionNumber;
  final String answer;
  final double confidence;

  const CloudOcrAnswer({
    required this.questionNumber,
    required this.answer,
    required this.confidence,
  });
}

/// Exception from cloud OCR operations.
class CloudOcrException implements Exception {
  final String message;
  const CloudOcrException(this.message);

  @override
  String toString() => 'CloudOcrException: $message';
}
