import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

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

  /// Maximum image file size in bytes after compression (800KB).
  /// Higher quality = better handwritten text recognition.
  static const int _maxImageBytes = 800 * 1024;

  /// Maximum image dimension for compression.
  static const int _maxDimension = 3000;

  /// Minimum JPEG quality — below this, handwritten text becomes unreadable.
  static const int _minQuality = 75;

  /// API endpoint — set via [configure].
  String _apiEndpoint = '';
  String _apiKey = '';
  String _modelName = 'gpt-4o';
  bool _configured = false;

  /// Fallback: Gemini config loaded from .env at runtime.
  String? _geminiKey;
  bool _fallbackAttempted = false;

  bool get isConfigured => _configured;

  /// Auto-configure from SettingsProvider (called before each scan).
  ///
  /// In debug builds, falls back to a hardcoded key so the app works
  /// out of the box for testing. Remove before production release.
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

    // Debug-only fallback — reads key from settings or .env
    // No hardcoded keys allowed in source code
    return false;
  }

  /// Configure the API credentials.
  void configure({required String apiEndpoint, required String apiKey}) {
    _apiEndpoint = apiEndpoint;
    _apiKey = apiKey;
    _configured = true;
    debugPrint(
      'CloudOcr: configured with endpoint ${_apiEndpoint.substring(0, (_apiEndpoint.length - 10).clamp(0, _apiEndpoint.length))}...',
    );
  }

  /// Process a paper image and return recognized text regions.
  ///
  /// 1. Compresses image for API transmission
  /// 2. Sends to cloud vision API with answer sheet prompt
  /// 3. Returns structured text response
  ///
  /// [questionCount] — number of items on the answer sheet (for prompt).
  /// Throws [CloudOcrException] on failure.
  Future<CloudOcrResult> processImage(String imagePath, {int? questionCount}) async {
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
    final response = await _sendToApi(compressedBytes, questionCount: questionCount);

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
        debugPrint(
          'CloudOcr: compressed to ${encoded.lengthInBytes ~/ 1024}KB (q$quality)',
        );
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
        debugPrint(
          'CloudOcr: compressed to ${encoded.lengthInBytes ~/ 1024}KB (q$_minQuality, ${maxDim}px)',
        );
        return encoded;
      }
    }

    // Fallback: lowest resolution, minimum quality
    final fallback = img.copyResize(
      image,
      width: 600,
      height: (600 * image.height / image.width).round(),
    );
    final encoded = img.encodeJpg(fallback, quality: _minQuality);
    debugPrint(
      'CloudOcr: compressed to ${encoded.lengthInBytes ~/ 1024}KB (q$_minQuality, 600px, fallback)',
    );
    return encoded;
  }

  /// Send compressed image to cloud vision API.
  ///
  /// Primary: GitHub Models (GPT-4o). Fallback: Gemini if quota exhausted.
  Future<CloudOcrResult> _sendToApi(List<int> imageBytes, {int? questionCount}) async {
    final base64Image = base64Encode(imageBytes);

    // Try primary endpoint first
    try {
      return await _sendRequest(base64Image, _apiEndpoint, _apiKey, _modelName, questionCount: questionCount);
    } on CloudOcrException catch (e) {
      final msg = e.message.toLowerCase();
      final isQuotaError =
          msg.contains('quota') ||
          msg.contains('rate limit') ||
          msg.contains('429') ||
          msg.contains('insufficient_quota');

      if (isQuotaError && !_fallbackAttempted) {
        debugPrint(
          'CloudOcr: primary endpoint quota exceeded, trying Gemini fallback',
        );
        return await _tryGeminiFallback(base64Image, questionCount: questionCount);
      }
      rethrow;
    }
  }

  /// Attempt Gemini fallback using key from .env.
  Future<CloudOcrResult> _tryGeminiFallback(String base64Image, {int? questionCount}) async {
    _fallbackAttempted = true;
    _geminiKey ??= await _loadGeminiKey();
    if (_geminiKey == null || _geminiKey!.isEmpty) {
      throw CloudOcrException(
        'Primary endpoint quota exceeded and no Gemini key in .env',
      );
    }

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$_geminiKey',
    );

    final prompt = _buildPrompt(questionCount: questionCount);
    final requestBody = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {'mime_type': 'image/jpeg', 'data': base64Image},
            },
          ],
        },
      ],
    });

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: requestBody,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw CloudOcrException(
          'Gemini fallback error ${response.statusCode}: ${response.body}',
        );
      }

      final json = jsonDecode(response.body);
      final text = json['candidates']?[0]?['content']?['parts']?[0]?['text'];
      if (text == null) {
        throw CloudOcrException('Gemini fallback: no text in response');
      }

      return _parseTextResponse(text);
    } catch (e) {
      if (e is CloudOcrException) rethrow;
      throw CloudOcrException('Gemini fallback failed: $e');
    }
  }

  Future<String?> _loadGeminiKey() async {
    try {
      final envFile = File('.env');
      if (!await envFile.exists()) return null;
      final content = await envFile.readAsString();
      return content
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.startsWith('GEMINI_API_KEY='))
          .map((l) => l.substring('GEMINI_API_KEY='.length))
          .firstOrNull;
    } catch (_) {
      return null;
    }
  }

  /// Send a single request to an OpenAI-compatible endpoint.
  Future<CloudOcrResult> _sendRequest(
    String base64Image,
    String endpoint,
    String apiKey,
    String model, {
    int? questionCount,
  }) async {
    final prompt = _buildPrompt(questionCount: questionCount);

    // Debug: save the compressed image sent to API
    if (kDebugMode) {
      await _saveDebugImage(base64Image);
    }

    final requestBody = jsonEncode({
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
            },
          ],
        },
      ],
      'max_tokens': 1024,
      'temperature': 0.1,
    });

    try {
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: requestBody,
          )
          .timeout(const Duration(seconds: 30));

      // Debug: log raw response
      if (kDebugMode) {
        debugPrint('CloudOcr: === RAW API RESPONSE ===');
        debugPrint('CloudOcr: status=${response.statusCode}');
        debugPrint('CloudOcr: body=${response.body}');
        debugPrint('CloudOcr: === END RESPONSE ===');
        await _saveDebugResponse(response.body);
      }

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

  /// Save the compressed image sent to Cloud OCR for debugging.
  Future<void> _saveDebugImage(String base64Image) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final debugDir = Directory('${dir.path}/cloud_ocr_debug');
      if (!await debugDir.exists()) {
        await debugDir.create(recursive: true);
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${debugDir.path}/ocr_input_$timestamp.jpg');
      await file.writeAsBytes(base64Decode(base64Image));
      debugPrint('CloudOcr: DEBUG image saved to ${file.path}');
    } catch (e) {
      debugPrint('CloudOcr: Failed to save debug image: $e');
    }
  }

  /// Save the raw API response for debugging.
  Future<void> _saveDebugResponse(String responseBody) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final debugDir = Directory('${dir.path}/cloud_ocr_debug');
      if (!await debugDir.exists()) {
        await debugDir.create(recursive: true);
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${debugDir.path}/ocr_response_$timestamp.txt');
      await file.writeAsString(responseBody);
      debugPrint('CloudOcr: DEBUG response saved to ${file.path}');
    } catch (e) {
      debugPrint('CloudOcr: Failed to save debug response: $e');
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
      final avgConfidence = answers.isNotEmpty
          ? totalConfidence / answers.length
          : 0.0;

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

  String _buildPrompt({int? questionCount}) {
    final qCountHint = questionCount != null
        ? ' The sheet should have $questionCount numbered items.'
        : '';

    return '''You are reading a student's answer sheet from an exam.$qCountHint

The sheet has numbered items (1, 2, 3...). Next to each number, the student wrote their answer by hand.

FOR EACH NUMBERED ITEM:
1. Find the number (1, 2, 3...)
2. Read exactly what the student wrote next to it
3. Return the answer as-is — do not correct spelling or guess

ANSWER TYPES YOU WILL SEE:
- Single letters: A, B, C, D, E (multiple choice)
- Words or phrases: "Addis Ababa", "photosynthesis", "42 km"
- True/False: T, F, True, False, Yes, No
- Numbers: 3, 14, 2.5
- Amharic text: እውነት, ሐሰት, ሀ, ለ, ሐ, መ, ሠ

RULES:
- Read EXACTLY what is written — do not guess, interpret, or correct
- If a number has no handwritten answer, return BLANK
- If handwriting is completely illegible, return UNREADABLE
- Do not confuse printed section headers, instructions, or page numbers with answers
- Ignore all printed text — only read handwritten content

Return JSON array: [{"q":1,"answer":"B","confidence":"high"}, {"q":2,"answer":"BLANK","confidence":"high"}]
Confidence: "high" if clearly readable, "medium" if somewhat unclear, "low" if barely readable''';
  }

  /// Parse raw text response (from Gemini fallback) into structured result.
  CloudOcrResult _parseTextResponse(String text) {
    final jsonMatch = RegExp(r'\[.*\]', dotAll: true).firstMatch(text);
    if (jsonMatch == null) {
      return CloudOcrResult(rawText: text, answers: const [], confidence: 0.0);
    }

    final answersJson = jsonDecode(jsonMatch.group(0)!) as List;
    final answers = answersJson.map((a) {
      return CloudOcrAnswer(
        questionNumber: a['q'] as int? ?? 0,
        answer: (a['answer'] as String? ?? '').toUpperCase(),
        confidence: _parseConfidence(a['confidence'] as String? ?? 'low'),
      );
    }).toList();

    double totalConfidence = 0;
    for (final a in answers) {
      totalConfidence += a.confidence;
    }
    final avgConfidence = answers.isNotEmpty
        ? totalConfidence / answers.length
        : 0.0;

    return CloudOcrResult(
      rawText: text,
      answers: answers,
      confidence: avgConfidence,
    );
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
