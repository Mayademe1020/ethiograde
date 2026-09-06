import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Smart OCR routing service.
///
/// Architecture:
/// 1. ML Kit on-device (fast, free, works for printed text)
/// 2. Detect if result looks like handwriting (low confidence, fragmented)
/// 3. If handwriting detected + internet available → Server proxy → Gemini
/// 4. If no internet → fall back to ML Kit result with review flag
///
/// The server proxy handles:
/// - API key security (key never leaves server)
/// - Rate limiting
/// - Cost monitoring
/// - Combined OCR + grading in one step
class SmartOcrService {
  static final SmartOcrService _instance = SmartOcrService._();
  factory SmartOcrService() => _instance;
  SmartOcrService._();

  static SmartOcrService get instance => _instance;

  late final TextRecognizer _mlKitRecognizer;
  bool _isInitialized = false;

  // Server proxy URL — set by the app at startup
  String? _serverUrl;
  bool _cloudEnabled = false;

  // API key for server auth — set from settings
  String? _apiKey;

  // Model selection — can be changed at runtime
  String _preferredModel = 'gemini'; // gemini, gemini-flash-lite, openai

  Future<void> initialize({String? serverUrl, String? apiKey}) async {
    if (_isInitialized) return;
    _mlKitRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    _serverUrl = serverUrl;
    _apiKey = apiKey;
    _cloudEnabled = serverUrl != null && serverUrl.isNotEmpty;
    _isInitialized = true;
    debugPrint('SmartOCR: initialized (Cloud: $_cloudEnabled, Auth: ${_apiKey != null})');
  }

  void setServerUrl(String? url) {
    _serverUrl = url;
    _cloudEnabled = url != null && url.isNotEmpty;
    debugPrint('SmartOCR: Cloud ${_cloudEnabled ? "enabled" : "disabled"}');
  }

  /// Set the API key for server authentication.
  void setApiKey(String? key) {
    _apiKey = key;
    debugPrint('SmartOCR: API key ${key != null ? "set" : "cleared"}');
  }

  Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    if (_apiKey != null) 'X-Api-Key': _apiKey!,
  };

  /// Set preferred model (gemini, gemini-flash-lite, openai).
  /// Falls back to other models if preferred is unavailable.
  void setPreferredModel(String model) {
    _preferredModel = model;
    debugPrint('SmartOCR: Preferred model set to $model');
  }

  /// Get current preferred model.
  String get preferredModel => _preferredModel;

  /// Get available models from server config.
  Future<List<ModelInfo>> getAvailableModels() async {
    if (_serverUrl == null) return [];

    try {
      final response = await http.get(
        Uri.parse('$_serverUrl/getModels'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = data['result']['models'] as List? ?? [];
        return models.map((m) => ModelInfo.fromJson(m)).toList();
      }
    } catch (e) {
      debugPrint('SmartOCR: Failed to get models ($e)');
    }

    return [
      const ModelInfo(name: 'gemini', displayName: 'Gemini 2.0 Flash', isAvailable: true),
      const ModelInfo(name: 'gemini-flash-lite', displayName: 'Gemini 2.0 Flash Lite', isAvailable: true),
    ];
  }

  /// Main OCR entry point.
  ///
  /// Returns recognized text with confidence and source info.
  Future<SmartOcrResult> recognizeText(String imagePath) async {
    await initialize();

    // Step 1: Run ML Kit on-device (always available)
    final mlKitResult = await _runMlKit(imagePath);

    // Step 2: Analyze quality — is this likely handwriting?
    final isHandwriting = _detectHandwriting(mlKitResult);

    // Step 3: If handwriting detected and cloud available, try server proxy
    if (isHandwriting && _cloudEnabled && _serverUrl != null) {
      try {
        final cloudResult = await _callServerProxy(imagePath);
        if (cloudResult != null && cloudResult.confidence > mlKitResult.confidence) {
          debugPrint('SmartOCR: Cloud used (${cloudResult.confidence.toStringAsFixed(2)} vs ML Kit ${mlKitResult.confidence.toStringAsFixed(2)})');
          return cloudResult.copyWith(source: OcrSource.cloud);
        }
      } catch (e) {
        debugPrint('SmartOCR: Cloud failed ($e), using ML Kit');
      }
    }

    // Step 4: Return ML Kit result (with handwriting flag if detected)
    return mlKitResult.copyWith(
      isHandwriting: isHandwriting,
      needsReview: isHandwriting && mlKitResult.confidence < 0.6,
    );
  }

  /// Grade an exam paper — sends image + answer key to server.
  ///
  /// This is the primary entry point for exam grading.
  /// Returns graded results directly from Gemini via server proxy.
  Future<GradingResult?> gradeExam({
    required String imagePath,
    required Map<String, dynamic> answerKey,
    String? assessmentTitle,
    String? mimeType,
    String? preferredModel,
  }) async {
    if (!_cloudEnabled || _serverUrl == null) {
      debugPrint('SmartOCR: Cloud not enabled, cannot grade');
      return null;
    }

    if (_apiKey == null) {
      debugPrint('SmartOCR: No API key configured');
      return null;
    }

    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse('$_serverUrl/gradeExam'),
        headers: _authHeaders,
        body: jsonEncode({
          'data': {
            'imageBase64': base64Image,
            'answerKey': answerKey,
            'assessmentTitle': assessmentTitle,
            'mimeType': mimeType ?? 'image/jpeg',
            'preferredModel': preferredModel ?? _preferredModel,
          },
        }),
      ).timeout(const Duration(seconds: 120));

      if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('SmartOCR: Auth failed — check API key');
        return null;
      }

      if (response.statusCode != 200) {
        debugPrint('SmartOCR: Server error ${response.statusCode}: ${response.body}');
        return null;
      }

      final json = jsonDecode(response.body);
      final result = json['result'];

      if (result == null) {
        debugPrint('SmartOCR: Server returned null result');
        return null;
      }

      debugPrint('SmartOCR: Graded with ${result['provider']} — Score: ${result['overallScore']}/${result['maxScore']}');
      return GradingResult.fromJson(result);
    } catch (e) {
      debugPrint('SmartOCR: Grading error ($e)');
      return null;
    }
  }

  /// Fetch cost summary from server.
  Future<CostSummary?> getCosts() async {
    if (_serverUrl == null || _apiKey == null) return null;

    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/getCosts'),
        headers: _authHeaders,
        body: jsonEncode({'data': {}}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body);
      final result = json['result'];
      if (result == null) return null;

      return CostSummary.fromJson(result);
    } catch (e) {
      debugPrint('SmartOCR: getCosts error ($e)');
      return null;
    }
  }

  /// Run ML Kit text recognition.
  Future<SmartOcrResult> _runMlKit(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognized = await _mlKitRecognizer.processImage(inputImage);

      final texts = <OcrTextBlock>[];
      double totalConfidence = 0;
      int blockCount = 0;

      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          final text = line.text.trim();
          if (text.isEmpty) continue;

          double lineConfidence = 0.8;
          if (line.elements.isNotEmpty) {
            final confs = line.elements.map((e) => e.confidence ?? 0.8).toList();
            lineConfidence = confs.reduce((a, b) => a + b) / confs.length;
          }

          final points = line.cornerPoints;
          double x = 0, y = 0, width = 0, height = 0;
          if (points.isNotEmpty) {
            final xs = points.map((p) => p.x.toDouble());
            final ys = points.map((p) => p.y.toDouble());
            x = xs.reduce(math.min);
            y = ys.reduce(math.min);
            width = xs.reduce(math.max) - x;
            height = ys.reduce(math.max) - y;
          }

          texts.add(OcrTextBlock(
            text: text,
            confidence: lineConfidence.clamp(0.0, 1.0),
            x: x, y: y, width: width, height: height,
          ));
          totalConfidence += lineConfidence;
          blockCount++;
        }
      }

      final avgConfidence = blockCount > 0 ? totalConfidence / blockCount : 0.0;

      return SmartOcrResult(
        text: texts.map((t) => t.text).join('\n'),
        blocks: texts,
        confidence: avgConfidence.clamp(0.0, 1.0),
        source: OcrSource.mlKit,
      );
    } catch (e) {
      debugPrint('SmartOCR: ML Kit failed ($e)');
      return SmartOcrResult.empty();
    }
  }

  /// Detect if the OCR result looks like handwriting.
  bool _detectHandwriting(SmartOcrResult result) {
    if (result.blocks.isEmpty) return false;

    int score = 0;

    // Signal 1: Low confidence
    if (result.confidence < 0.6) {
      score += 2;
    } else if (result.confidence < 0.75) {
      score += 1;
    }

    // Signal 2: Many short lines
    final shortLines = result.blocks.where((b) => b.text.length < 5).length;
    if (shortLines > result.blocks.length * 0.4) {
      score += 2;
    }

    // Signal 3: Inconsistent line heights
    if (result.blocks.length > 2) {
      final heights = result.blocks.map((b) => b.height).toList();
      final avgHeight = heights.reduce((a, b) => a + b) / heights.length;
      final variance = heights.map((h) => (h - avgHeight) * (h - avgHeight)).reduce((a, b) => a + b) / heights.length;
      final cv = math.sqrt(variance) / avgHeight;
      if (cv > 0.3) score += 1;
    }

    // Signal 4: Mixed case patterns
    final allText = result.text.toLowerCase();
    if (allText.contains(RegExp(r'[a-z][A-Z][a-z]'))) score += 1;

    return score >= 3;
  }

  /// Call server proxy for cloud OCR/grading.
  Future<SmartOcrResult?> _callServerProxy(String imagePath) async {
    if (_serverUrl == null || _apiKey == null) return null;

    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse('$_serverUrl/gradeExam'),
        headers: _authHeaders,
        body: jsonEncode({
          'data': {
            'imageBase64': base64Image,
            'answerKey': {}, // OCR only, no grading
            'mimeType': 'image/jpeg',
          },
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body);
      final result = json['result'];
      if (result == null) return null;

      // Convert grading result to OCR result
      final results = result['results'] as List? ?? [];
      final text = results.map((r) => r['detectedAnswer'] ?? '').join('\n');
      final confidence = (result['confidence'] as num?)?.toDouble() ?? 0.5;

      return SmartOcrResult(
        text: text,
        blocks: [OcrTextBlock(
          text: text,
          confidence: confidence,
          x: 0, y: 0, width: 0, height: 0,
        )],
        confidence: confidence,
        source: OcrSource.cloud,
      );
    } catch (e) {
      debugPrint('SmartOCR: Server proxy error ($e)');
      return null;
    }
  }

  void dispose() {
    if (_isInitialized) {
      _mlKitRecognizer.close();
      _isInitialized = false;
    }
  }
}

/// Source of OCR result.
enum OcrSource { mlKit, cloud }

/// A block of recognized text with position.
class OcrTextBlock {
  final String text;
  final double confidence;
  final double x, y, width, height;

  const OcrTextBlock({
    required this.text,
    required this.confidence,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

/// Result from smart OCR routing.
class SmartOcrResult {
  final String text;
  final List<OcrTextBlock> blocks;
  final double confidence;
  final OcrSource source;
  final bool isHandwriting;
  final bool needsReview;

  const SmartOcrResult({
    required this.text,
    required this.blocks,
    required this.confidence,
    required this.source,
    this.isHandwriting = false,
    this.needsReview = false,
  });

  factory SmartOcrResult.empty() => const SmartOcrResult(
    text: '', blocks: [], confidence: 0, source: OcrSource.mlKit,
  );

  SmartOcrResult copyWith({
    String? text,
    List<OcrTextBlock>? blocks,
    double? confidence,
    OcrSource? source,
    bool? isHandwriting,
    bool? needsReview,
  }) {
    return SmartOcrResult(
      text: text ?? this.text,
      blocks: blocks ?? this.blocks,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
      isHandwriting: isHandwriting ?? this.isHandwriting,
      needsReview: needsReview ?? this.needsReview,
    );
  }

  bool get isEmpty => text.isEmpty;
  bool get isNotEmpty => text.isNotEmpty;
}

/// Model information from server.
class ModelInfo {
  final String name;
  final String displayName;
  final bool isAvailable;
  final double? costPer1k;
  final int? latencyMs;

  const ModelInfo({
    required this.name,
    required this.displayName,
    required this.isAvailable,
    this.costPer1k,
    this.latencyMs,
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      name: json['name'] ?? '',
      displayName: json['displayName'] ?? '',
      isAvailable: json['isAvailable'] ?? false,
      costPer1k: (json['costPer1k'] as num?)?.toDouble(),
      latencyMs: json['latencyMs'],
    );
  }
}

/// Grading result from server proxy.
class GradingResult {
  final List<QuestionResult> results;
  final double overallScore;
  final double maxScore;
  final double confidence;
  final String? studentName;
  final String? notes;

  const GradingResult({
    required this.results,
    required this.overallScore,
    required this.maxScore,
    required this.confidence,
    this.studentName,
    this.notes,
  });

  factory GradingResult.fromJson(Map<String, dynamic> json) {
    return GradingResult(
      results: (json['results'] as List? ?? [])
          .map((r) => QuestionResult.fromJson(r))
          .toList(),
      overallScore: (json['overallScore'] as num?)?.toDouble() ?? 0,
      maxScore: (json['maxScore'] as num?)?.toDouble() ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      studentName: json['studentName'],
      notes: json['notes'],
    );
  }

  double get percentage => maxScore > 0 ? (overallScore / maxScore * 100) : 0;
}

/// Result for a single question.
class QuestionResult {
  final int questionNumber;
  final String detectedAnswer;
  final String correctAnswer;
  final bool isCorrect;
  final double score;
  final double maxScore;
  final double confidence;
  final String? notes;

  const QuestionResult({
    required this.questionNumber,
    required this.detectedAnswer,
    required this.correctAnswer,
    required this.isCorrect,
    required this.score,
    required this.maxScore,
    required this.confidence,
    this.notes,
  });

  factory QuestionResult.fromJson(Map<String, dynamic> json) {
    return QuestionResult(
      questionNumber: json['questionNumber'] ?? 0,
      detectedAnswer: json['detectedAnswer'] ?? '',
      correctAnswer: json['correctAnswer'] ?? '',
      isCorrect: json['isCorrect'] ?? false,
      score: (json['score'] as num?)?.toDouble() ?? 0,
      maxScore: (json['maxScore'] as num?)?.toDouble() ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      notes: json['notes'],
    );
  }
}

/// Cost summary from server.
class CostSummary {
  final int totalRequests;
  final double totalCost;
  final double monthlyBudget;
  final String period;
  final Map<String, CostByProvider> byProvider;

  const CostSummary({
    required this.totalRequests,
    required this.totalCost,
    required this.monthlyBudget,
    required this.period,
    required this.byProvider,
  });

  factory CostSummary.fromJson(Map<String, dynamic> json) {
    final byProvider = <String, CostByProvider>{};
    final raw = json['byProvider'] as Map? ?? {};
    for (final entry in raw.entries) {
      byProvider[entry.key] = CostByProvider.fromJson(entry.value);
    }

    return CostSummary(
      totalRequests: json['totalRequests'] ?? 0,
      totalCost: (json['totalCost'] as num?)?.toDouble() ?? 0,
      monthlyBudget: (json['monthlyBudget'] as num?)?.toDouble() ?? 10.0,
      period: json['period'] ?? 'all-time',
      byProvider: byProvider,
    );
  }

  double get budgetUsedPercent =>
      monthlyBudget > 0 ? (totalCost / monthlyBudget * 100).clamp(0, 100) : 0;

  bool get isOverBudget => totalCost > monthlyBudget;
}

/// Cost breakdown per provider.
class CostByProvider {
  final int requests;
  final double cost;

  const CostByProvider({required this.requests, required this.cost});

  factory CostByProvider.fromJson(Map<String, dynamic> json) {
    return CostByProvider(
      requests: json['requests'] ?? 0,
      cost: (json['cost'] as num?)?.toDouble() ?? 0,
    );
  }
}
