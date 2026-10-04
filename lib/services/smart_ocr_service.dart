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

  /// Normalised result of a proxy call.
  ///
  /// The proxy is a Google Apps Script web app, which cannot set HTTP status
  /// codes — every reply arrives as 200. Success is therefore carried in the
  /// `{ok, result, error}` envelope, not the status line.
  ProxyResponse? _lastError;

  /// True when the last failure was an auth rejection — the UI uses this to
  /// tell the teacher their API key is wrong rather than showing a timeout.
  bool get hadAuthFailure => _lastError?.code == 401 || _lastError?.code == 403;

  String? get lastErrorMessage => _lastError?.error;

  Uri _endpoint(String action) {
    final base = _serverUrl!.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base?action=$action');
  }

  /// POST to the proxy and unwrap the `{ok, result}` envelope.
  ///
  /// The shared secret travels in the body because Apps Script web apps
  /// cannot read inbound HTTP headers. The `X-Api-Key` header is still sent so
  /// header-aware backends keep working.
  Future<Map<String, dynamic>?> _postProxy(
    String action,
    Map<String, dynamic> data,
  ) async {
    if (_serverUrl == null || _serverUrl!.isEmpty) return null;
    if (_apiKey == null || _apiKey!.isEmpty) {
      _lastError = const ProxyResponse('App API key not set', 401);
      return null;
    }

    try {
      final response = await http
          .post(
            _endpoint(action),
            headers: _authHeaders,
            body: jsonEncode({
              'action': action,
              'apiKey': _apiKey,
              'data': data,
            }),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode != 200) {
        _lastError =
            ProxyResponse('Server error ${response.statusCode}', response.statusCode);
        debugPrint('SmartOCR: $action HTTP ${response.statusCode}');
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        _lastError = const ProxyResponse('Malformed server response', 502);
        return null;
      }

      if (decoded['ok'] != true) {
        _lastError = ProxyResponse(
          (decoded['error'] ?? 'Unknown server error').toString(),
          _asInt(decoded['code']) ?? 500,
        );
        debugPrint('SmartOCR: $action failed — ${_lastError!.error}');
        return null;
      }

      _lastError = null;
      final result = decoded['result'];
      return result is Map ? result.cast<String, dynamic>() : <String, dynamic>{};
    } catch (e) {
      _lastError = ProxyResponse(e.toString(), 0);
      debugPrint('SmartOCR: $action error ($e)');
      return null;
    }
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  /// Set preferred model (gemini, gemini-flash-lite, openai).
  /// Falls back to other models if preferred is unavailable.
  void setPreferredModel(String model) {
    _preferredModel = model;
    debugPrint('SmartOCR: Preferred model set to $model');
  }

  /// Get current preferred model.
  String get preferredModel => _preferredModel;

  /// Get available models from the proxy.
  Future<List<ModelInfo>> getAvailableModels() async {
    final result = await _postProxy('getModels', const {});
    final raw = result?['models'];
    if (raw is! List) return _fallbackModels;
    return raw
        .whereType<Map>()
        .map((m) => ModelInfo.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  static const List<ModelInfo> _fallbackModels = [
    ModelInfo(name: 'gemini', displayName: 'Gemini 2.0 Flash', isAvailable: true),
    ModelInfo(
      name: 'gemini-flash-lite',
      displayName: 'Gemini 2.0 Flash Lite',
      isAvailable: true,
    ),
    ModelInfo(
      name: 'gemini-2.5-flash',
      displayName: 'Gemini 2.5 Flash',
      isAvailable: true,
    ),
  ];

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

  /// Grade an exam paper — sends the image plus the answer key to the proxy.
  ///
  /// This is the primary entry point for cloud grading. Gemini reads the
  /// handwriting and grades it against the key in a single pass, which is far
  /// more accurate than on-device OCR. Returns null on any failure so the
  /// caller can fall back to the local ML Kit pipeline.
  Future<GradingResult?> gradeExam({
    required String imagePath,
    required Map<String, dynamic> answerKey,
    String? assessmentTitle,
    String? mimeType,
    String? preferredModel,
  }) async {
    if (!_cloudEnabled || _serverUrl == null) {
      debugPrint('SmartOCR: cloud disabled, cannot grade');
      return null;
    }

    try {
      final bytes = await File(imagePath).readAsBytes();
      final result = await _postProxy('gradeExam', {
        'imageBase64': base64Encode(bytes),
        'answerKey': answerKey,
        'assessmentTitle': assessmentTitle,
        'mimeType': mimeType ?? _guessMimeType(imagePath),
        'preferredModel': preferredModel ?? _preferredModel,
      });

      if (result == null) return null;

      final conf = (result['confidence'] as num?)?.toDouble() ?? 0;
      debugPrint(
        'SmartOCR: graded by ${result['provider']} — '
        '${result['overallScore']}/${result['maxScore']} '
        '(${conf.toStringAsFixed(2)} conf)',
      );
      return GradingResult.fromJson(result);
    } catch (e) {
      debugPrint('SmartOCR: gradeExam error ($e)');
      return null;
    }
  }

  static String _guessMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// Fetch cost summary from the proxy.
  Future<CostSummary?> getCosts() async {
    final result = await _postProxy('getCosts', const {});
    if (result == null) return null;
    return CostSummary.fromJson(result);
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
      if (avgHeight > 0) {
        final variance = heights
                .map((h) => (h - avgHeight) * (h - avgHeight))
                .reduce((a, b) => a + b) /
            heights.length;
        final cv = math.sqrt(variance) / avgHeight;
        if (cv > 0.3) score += 1;
      }
    }

    // Signal 4: Mixed case patterns
    final allText = result.text.toLowerCase();
    if (allText.contains(RegExp(r'[a-z][A-Z][a-z]'))) score += 1;

    return score >= 3;
  }

  /// Ask the cloud to transcribe a paper without grading it.
  ///
  /// Used by [recognizeText] when ML Kit output looks like handwriting and no
  /// answer key is available at that call site. The reply is reshaped into one
  /// [OcrTextBlock] per question — each block already carries its own
  /// `"<n>. <answer>"` label and a synthetic vertical position, so
  /// `AnswerParser.parseAnswersWithPosition` can consume it directly. The
  /// previous implementation collapsed every answer into one flat block,
  /// which destroyed the per-question structure the parser depends on.
  Future<SmartOcrResult?> _callServerProxy(String imagePath) async {
    if (_serverUrl == null || _serverUrl!.isEmpty) return null;
    if (_apiKey == null || _apiKey!.isEmpty) return null;

    try {
      final bytes = await File(imagePath).readAsBytes();
      final result = await _postProxy('gradeExam', {
        'imageBase64': base64Encode(bytes),
        'answerKey': const <String, dynamic>{},
        'ocrOnly': true,
        'mimeType': _guessMimeType(imagePath),
        'preferredModel': _preferredModel,
      });

      if (result == null) return null;

      final raw = result['results'];
      final rows = raw is List
          ? raw.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList()
          : const <Map<String, dynamic>>[];

      return buildCloudOcrResult(rows);
    } catch (e) {
      debugPrint('SmartOCR: cloud transcribe error ($e)');
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

/// A failed proxy call, carrying the HTTP-equivalent status the envelope
/// reported so callers can distinguish auth problems from transport problems.
class ProxyResponse {
  final String error;
  final int code;

  const ProxyResponse(this.error, this.code);

  bool get isAuthFailure => code == 401 || code == 403;

  bool get isRateLimit => code == 429;
}

/// Vertical spacing used when laying cloud answers out as synthetic blocks.
/// Matches a typical 30px line height so the column reads top-to-bottom.
const double kCloudBlockLineHeight = 30.0;

/// Reshape a cloud OCR reply into a [SmartOcrResult] the local pipeline can
/// consume.
///
/// Every row becomes its own block labelled `"<n>. <answer>"` at a synthetic
/// y-position derived from the question number. That self-labelling matters:
/// [AnswerParser.parseAnswersWithPosition] can then match each block on its
/// own line without needing spatial association, so a paper with gaps or
/// out-of-order questions still parses correctly.
///
/// Returns null when nothing usable came back, which tells the caller to keep
/// the local ML Kit reading instead.
SmartOcrResult? buildCloudOcrResult(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) return null;

  final blocks = <OcrTextBlock>[];
  final seen = <int>{};

  for (final row in rows) {
    final number = _asIntOrNull(row['questionNumber']);
    if (number == null || number <= 0 || seen.contains(number)) continue;

    final answer = (row['detectedAnswer'] ?? '').toString().trim();
    if (answer.isEmpty) continue;

    seen.add(number);
    blocks.add(OcrTextBlock(
      text: '$number. $answer',
      confidence:
          (row['confidence'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.5,
      x: 0,
      y: number * kCloudBlockLineHeight,
      width: 400,
      height: kCloudBlockLineHeight,
    ));
  }

  if (blocks.isEmpty) return null;

  blocks.sort((a, b) => a.y.compareTo(b.y));

  final total = blocks.fold<double>(0, (sum, b) => sum + b.confidence);
  final avgConfidence = total / blocks.length;

  return SmartOcrResult(
    text: blocks.map((b) => b.text).join('\n'),
    blocks: blocks,
    confidence: avgConfidence,
    source: OcrSource.cloud,
    isHandwriting: true,
    // Anything the model was unsure about goes to teacher review rather than
    // being silently accepted as a reading.
    needsReview: blocks.any((b) => b.confidence < 0.5),
  );
}

int? _asIntOrNull(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
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
      name: (json['name'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      isAvailable: json['isAvailable'] == true,
      costPer1k: json['costPer1k'] == null ? null : _asDouble(json['costPer1k']),
      latencyMs: _asIntOrNull(json['latencyMs']),
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
    final raw = json['results'];
    return GradingResult(
      results: raw is List
          ? raw
              .whereType<Map>()
              .map((r) => QuestionResult.fromJson(r.cast<String, dynamic>()))
              .toList()
          : const <QuestionResult>[],
      overallScore: _asDouble(json['overallScore']),
      maxScore: _asDouble(json['maxScore']),
      confidence: _asDouble(json['confidence']),
      studentName: json['studentName']?.toString(),
      notes: json['notes']?.toString(),
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
      // Gemini sometimes emits question numbers as strings ("4"), and score
      // fields as numeric strings, so coerce rather than trusting the type.
      questionNumber: _asIntOrNull(json['questionNumber']) ?? 0,
      detectedAnswer: (json['detectedAnswer'] ?? '').toString(),
      correctAnswer: (json['correctAnswer'] ?? '').toString(),
      isCorrect: json['isCorrect'] == true,
      score: _asDouble(json['score']),
      maxScore: _asDouble(json['maxScore']),
      confidence: _asDouble(json['confidence']),
      notes: json['notes']?.toString(),
    );
  }
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
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
    final raw = json['byProvider'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.value is Map) {
          byProvider[entry.key.toString()] =
              CostByProvider.fromJson((entry.value as Map).cast<String, dynamic>());
        }
      }
    }

    return CostSummary(
      totalRequests: _asIntOrNull(json['totalRequests']) ?? 0,
      totalCost: _asDouble(json['totalCost']),
      monthlyBudget: _asDouble(json['monthlyBudget']) == 0
          ? 10.0
          : _asDouble(json['monthlyBudget']),
      period: (json['period'] ?? 'all-time').toString(),
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
      requests: _asIntOrNull(json['requests']) ?? 0,
      cost: _asDouble(json['cost']),
    );
  }
}
