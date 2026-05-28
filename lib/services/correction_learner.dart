import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// A pattern of teacher corrections: "for question X, teacher changes A→B."
///
/// Stored per-question globally (not per-assessment) so the app learns
/// which answers the OCR consistently misreads across all exams.
class CorrectionPattern {
  /// Composite key: "Q{number}:{originalAnswer}" (e.g. "Q5:C")
  final String key;
  final int questionNumber;
  final String originalAnswer;
  final String correctedAnswer;
  final int count;
  final DateTime lastCorrected;

  const CorrectionPattern({
    required this.key,
    required this.questionNumber,
    required this.originalAnswer,
    required this.correctedAnswer,
    required this.count,
    required this.lastCorrected,
  });

  Map<String, dynamic> toMap() => {
    'key': key,
    'questionNumber': questionNumber,
    'originalAnswer': originalAnswer,
    'correctedAnswer': correctedAnswer,
    'count': count,
    'lastCorrected': lastCorrected.toIso8601String(),
  };

  factory CorrectionPattern.fromMap(Map<String, dynamic> map) {
    return CorrectionPattern(
      key: map['key'] as String,
      questionNumber: map['questionNumber'] as int,
      originalAnswer: map['originalAnswer'] as String,
      correctedAnswer: map['correctedAnswer'] as String,
      count: map['count'] as int,
      lastCorrected: DateTime.parse(map['lastCorrected'] as String));
  }
}

/// Learns from teacher corrections to suggest fixes for OCR mistakes.
///
/// When a teacher changes an answer (e.g., OCR says "C", teacher corrects to "D"),
/// this service records the pattern. If the same correction happens ≥2 times,
/// the app can suggest it proactively.
///
/// All data stays on-device. No network calls.
class CorrectionLearner {
  static final CorrectionLearner _instance = CorrectionLearner._();
  factory CorrectionLearner() => _instance;
  CorrectionLearner._();

  static const String _boxName = 'correction_patterns';

  bool _initialized = false;

  /// Initialize the correction patterns box.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await Hive.openBox(_boxName);
      _initialized = true;
      debugPrint('CorrectionLearner: initialized (${_box.length} patterns)');
    } catch (e) {
      debugPrint('CorrectionLearner: init failed — $e');
      // Try to recover by deleting corrupt box
      try {
        await Hive.deleteBoxFromDisk(_boxName);
        await Hive.openBox(_boxName);
        _initialized = true;
      } catch (e2) {
        debugPrint('CorrectionLearner: recovery failed — $e2');
      }
    }
  }

  Box get _box => Hive.box(_boxName);

  /// Record a teacher correction.
  ///
  /// [questionNumber] — which question was corrected
  /// [originalAnswer] — what OCR detected (e.g., "C")
  /// [correctedAnswer] — what the teacher changed it to (e.g., "D")
  Future<void> recordCorrection({
    required int questionNumber,
    required String originalAnswer,
    required String correctedAnswer,
  }) async {
    await initialize();

    // Don't record if there was no actual change
    if (originalAnswer.toUpperCase() == correctedAnswer.toUpperCase()) return;

    final key = 'Q$questionNumber:${originalAnswer.toUpperCase()}';
    final existing = _box.get(key);

    if (existing != null) {
      final pattern = CorrectionPattern.fromMap(
        Map<String, dynamic>.from(existing as Map));
      // Only update if same correction direction
      if (pattern.correctedAnswer.toUpperCase() ==
          correctedAnswer.toUpperCase()) {
        await _box.put(key, {
          ...pattern.toMap(),
          'count': pattern.count + 1,
          'lastCorrected': DateTime.now().toIso8601String(),
        });
      } else {
        // Different correction direction — replace (teacher changed their mind)
        await _box.put(
          key,
          CorrectionPattern(
            key: key,
            questionNumber: questionNumber,
            originalAnswer: originalAnswer.toUpperCase(),
            correctedAnswer: correctedAnswer.toUpperCase(),
            count: 1,
            lastCorrected: DateTime.now()).toMap());
      }
    } else {
      await _box.put(
        key,
        CorrectionPattern(
          key: key,
          questionNumber: questionNumber,
          originalAnswer: originalAnswer.toUpperCase(),
          correctedAnswer: correctedAnswer.toUpperCase(),
          count: 1,
          lastCorrected: DateTime.now()).toMap());
    }

    debugPrint(
      'CorrectionLearner: recorded Q$questionNumber '
      '$originalAnswer→$correctedAnswer');
  }

  /// Get a suggestion for a detected answer based on learned patterns.
  ///
  /// Returns the corrected answer if the same correction has been made ≥[minCount] times.
  /// Returns null if no strong pattern exists.
  String? getSuggestion({
    required int questionNumber,
    required String detectedAnswer,
    int minCount = 2,
  }) {
    if (!_initialized) return null;

    final key = 'Q$questionNumber:${detectedAnswer.toUpperCase()}';
    final existing = _box.get(key);

    if (existing == null) return null;

    final pattern = CorrectionPattern.fromMap(
      Map<String, dynamic>.from(existing as Map));

    if (pattern.count >= minCount) {
      return pattern.correctedAnswer;
    }

    return null;
  }

  /// Get all patterns that have occurred ≥[minCount] times.
  /// Useful for showing teachers what the app has learned.
  List<CorrectionPattern> getStrongPatterns({int minCount = 2}) {
    if (!_initialized) return [];

    final patterns = <CorrectionPattern>[];
    for (final key in _box.keys) {
      final data = _box.get(key);
      if (data == null) continue;
      final pattern = CorrectionPattern.fromMap(
        Map<String, dynamic>.from(data as Map));
      if (pattern.count >= minCount) {
        patterns.add(pattern);
      }
    }

    patterns.sort((a, b) => b.count.compareTo(a.count));
    return patterns;
  }

  /// Get all patterns for a specific question number.
  List<CorrectionPattern> getPatternsForQuestion(int questionNumber) {
    if (!_initialized) return [];

    final patterns = <CorrectionPattern>[];
    final prefix = 'Q$questionNumber:';

    for (final key in _box.keys) {
      if (!key.toString().startsWith(prefix)) continue;
      final data = _box.get(key);
      if (data == null) continue;
      patterns.add(
        CorrectionPattern.fromMap(Map<String, dynamic>.from(data as Map)));
    }

    return patterns;
  }

  /// Total number of learned patterns.
  int get patternCount => _initialized ? _box.length : 0;

  /// Clear all learned patterns. Teacher can reset if corrections are wrong.
  Future<void> clearAll() async {
    await initialize();
    await _box.clear();
    debugPrint('CorrectionLearner: all patterns cleared');
  }

  /// Remove a single pattern.
  Future<void> removePattern(String key) async {
    await initialize();
    await _box.delete(key);
  }
}
