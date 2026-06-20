import '../models/assessment.dart';
import '../models/grading_scale.dart';
import '../models/scan_result.dart';
import '../models/weighted_grade.dart';

/// Pure-Dart scoring engine. No Flutter, no platform plugins.
/// Extracted from OcrService for independent testability.
///
/// Handles:
/// - Answer matching by question type (MCQ, T/F, short answer)
/// - Grading scale lookup (MoE national, private international, university, or custom)
/// - Confidence calculation
/// - Answer deduplication
class ScoringService {
  const ScoringService();

  /// Runtime registry for custom grading scales.
  /// Call [registerCustomScales] from UI code before scoring.
  static final Map<String, GradingScale> _customScales = {};

  /// Register custom scales so [calculateGrade] can find them by rubricKey.
  static void registerCustomScales(List<GradingScale> scales) {
    _customScales.clear();
    for (final s in scales) {
      _customScales[s.rubricKey] = s;
    }
  }

  // ── Grading Scales ──

  static const Map<String, Map<String, List<int>>> gradingScales = {
    'moe_national': {
      'A+': [95, 100],
      'A': [90, 94],
      'A-': [85, 89],
      'B+': [80, 84],
      'B': [75, 79],
      'B-': [70, 74],
      'C+': [65, 69],
      'C': [60, 64],
      'C-': [55, 59],
      'D': [50, 54],
      'F': [0, 49],
    },
    'private_international': {
      'A*': [90, 100],
      'A': [80, 89],
      'B': [70, 79],
      'C': [60, 69],
      'D': [50, 59],
      'F': [0, 49],
    },
    'university': {
      'A': [90, 100],
      'A-': [85, 89],
      'B+': [80, 84],
      'B': [75, 79],
      'B-': [70, 74],
      'C+': [65, 69],
      'C': [60, 64],
      'C-': [55, 59],
      'D': [50, 54],
      'F': [0, 49],
    },
  };

  /// Map a percentage score to a letter grade under the given rubric.
  ///
  /// Checks custom scales first (registered via [registerCustomScales]),
  /// then falls back to built-in scales.
  String calculateGrade(double percentage, String rubricType) {
    // Check custom scale registry
    if (rubricType.startsWith('custom:')) {
      final custom = _customScales[rubricType];
      if (custom != null) return custom.gradeFor(percentage);
      // Fall back to moe_national if custom scale not found
      return _builtinGrade(percentage, 'moe_national');
    }
    return _builtinGrade(percentage, rubricType);
  }

  String _builtinGrade(double percentage, String rubricType) {
    final scale = gradingScales[rubricType] ?? gradingScales['moe_national']!;
    for (final entry in scale.entries) {
      final range = entry.value;
      if (percentage >= range[0] && percentage <= range[1]) {
        return entry.key;
      }
    }
    return 'F';
  }

  /// Normalize whitespace and case for OCR comparison.
  /// Trims leading/trailing spaces, collapses internal runs to single space, lowercases.
  static String _normalizeWhitespace(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Check if a detected answer matches the correct answer for a question type.
  bool checkAnswer({
    required dynamic detected,
    required dynamic correct,
    required QuestionType type,
  }) {
    if (detected == null || correct == null) return false;

    final detectedStr = detected.toString().trim();

    // Handle BLANK and UNREADABLE — always wrong
    if (detectedStr.toUpperCase() == 'BLANK' || detectedStr.toUpperCase() == 'UNREADABLE') {
      return false;
    }

    if (type == QuestionType.mcq || type == QuestionType.trueFalse) {
      final detectedNorm = _normalizeWhitespace(detectedStr).toUpperCase();
      final correctStr = correct.toString();

      // T/F aliases: T=True, F=False
      final expandedDetected = _expandTfAlias(detectedNorm);
      final expandedCorrect = _expandTfAlias(_normalizeWhitespace(correctStr).toUpperCase());

      // Support multiple correct answers: "A,C" or List ["A", "C"]
      if (correct is List) {
        return correct.any((c) {
          final cExpanded = _expandTfAlias(_normalizeWhitespace(c.toString()).toUpperCase());
          return cExpanded == expandedDetected;
        });
      }

      // Support comma-separated answers: "A,C" matches "A" or "C" or "A,C"
      if (correctStr.contains(',')) {
        final correctOptions = correctStr.split(',').map((s) =>
            _expandTfAlias(s.trim().toUpperCase())).toList();
        return correctOptions.contains(expandedDetected);
      }

      return expandedDetected == expandedCorrect;
    }

    if (type == QuestionType.matching) {
      return _checkMatchingAnswer(detectedStr, correct.toString());
    }

    if (type == QuestionType.shortAnswer) {
      // Normalize whitespace: OCR often inserts extra spaces
      final detectedNorm = _normalizeWhitespace(detectedStr);
      if (correct is List) {
        // Exact match first
        final exactMatch = correct.any(
          (c) => _normalizeWhitespace(c.toString()) == detectedNorm);
        if (exactMatch) return true;
        // Fuzzy match for each option
        return correct.any(
          (c) => _fuzzyMatch(detectedNorm, _normalizeWhitespace(c.toString())));
      }
      final correctNorm = _normalizeWhitespace(correct.toString());
      // Exact match first
      if (detectedNorm == correctNorm) return true;
      // Fuzzy match with Levenshtein distance ≤ 2
      return _fuzzyMatch(detectedNorm, correctNorm);
    }

    return false;
  }

  /// Expand T/F aliases: T → TRUE, F → FALSE.
  static String _expandTfAlias(String normalized) {
    if (normalized == 'T') return 'TRUE';
    if (normalized == 'F') return 'FALSE';
    return normalized;
  }

  /// Fuzzy match with Levenshtein distance tolerance.
  /// Returns true if the distance is ≤ [tolerance] (default 2).
  static bool _fuzzyMatch(String a, String b, {int tolerance = 2}) {
    if (a == b) return true;
    if (a.isEmpty || b.isEmpty) return false;
    // Only fuzzy match if lengths are within tolerance
    if ((a.length - b.length).abs() > tolerance) return false;
    return _levenshteinDistance(a, b) <= tolerance;
  }

  /// Compute Levenshtein edit distance between two strings.
  static int _levenshteinDistance(String a, String b) {
    final aLen = a.length;
    final bLen = b.length;
    if (aLen == 0) return bLen;
    if (bLen == 0) return aLen;

    // Use single-row DP for memory efficiency
    var prev = List<int>.generate(bLen + 1, (i) => i);
    var curr = List<int>.filled(bLen + 1, 0);

    for (int i = 1; i <= aLen; i++) {
      curr[0] = i;
      for (int j = 1; j <= bLen; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [
          prev[j] + 1,      // deletion
          curr[j - 1] + 1,  // insertion
          prev[j - 1] + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
      final temp = prev;
      prev = curr;
      curr = temp;
    }
    return prev[bLen];
  }

  /// Check if a matching answer matches the correct sequence.
  ///
  /// Matching answers use format "MATCH:A-B-C" where each letter represents
  /// the column B match for the corresponding question in column A.
  ///
  /// Scoring modes:
  /// - Exact match (default): all letters must match in order
  /// - Partial credit: each correct position earns proportional points
  ///
  /// Also handles raw letter sequences like "G D" or "G-D" by normalizing
  /// them to "MATCH:G-D" format before comparison.
  bool _checkMatchingAnswer(String detected, String correct) {
    final detLetters = _extractMatchingLetters(detected);
    final corLetters = _extractMatchingLetters(correct);

    if (detLetters.isEmpty || corLetters.isEmpty) return false;

    // Exact match: all letters in same order
    if (detLetters.length != corLetters.length) return false;

    for (int i = 0; i < detLetters.length; i++) {
      if (detLetters[i] != corLetters[i]) return false;
    }
    return true;
  }

  /// Extract individual letters from a matching answer string.
  ///
  /// Handles formats:
  /// - "MATCH:G-D-E" → ['G', 'D', 'E']
  /// - "G D" → ['G', 'D']
  /// - "G,D,E" → ['G', 'D', 'E']
  /// - "GDE" → ['G', 'D', 'E']
  List<String> _extractMatchingLetters(String answer) {
    final trimmed = answer.trim();

    // Strip "MATCH:" prefix if present
    String working = trimmed;
    if (working.toUpperCase().startsWith('MATCH:')) {
      working = working.substring(6);
    }

    // Split by dash, space, or comma
    final parts = working.split(RegExp(r'[-\s,]+')).where((p) => p.isNotEmpty).toList();

    // Each part should be a single letter
    final letters = <String>[];
    for (final part in parts) {
      if (part.length == 1 && RegExp(r'^[a-zA-Z]$').hasMatch(part)) {
        letters.add(part.toUpperCase());
      } else if (RegExp(r'^[a-zA-Z]+$').hasMatch(part)) {
        // Multiple letters concatenated: "GDE" → ['G', 'D', 'E']
        for (int i = 0; i < part.length; i++) {
          letters.add(part[i].toUpperCase());
        }
      }
    }

    return letters;
  }

  /// Calculate partial credit for a matching answer.
  ///
  /// Each correct position earns [pointsPerMatch] points.
  /// Returns 0 if formats are incompatible.
  double scoreMatchingPartial({
    required String detected,
    required String correct,
    required double totalPoints,
  }) {
    final detLetters = _extractMatchingLetters(detected);
    final corLetters = _extractMatchingLetters(correct);

    if (corLetters.isEmpty) return 0;
    if (detLetters.isEmpty) return 0;

    final maxCompare = detLetters.length < corLetters.length
        ? detLetters.length
        : corLetters.length;

    int correctCount = 0;
    for (int i = 0; i < maxCompare; i++) {
      if (detLetters[i] == corLetters[i]) correctCount++;
    }

    final pointsPerMatch = totalPoints / corLetters.length;
    return correctCount * pointsPerMatch;
  }

  /// Score detected answers against an assessment's answer key.
  List<AnswerMatch> scoreAnswers({
    required List<DetectedAnswer> detected,
    required Assessment assessment,
  }) {
    final matches = <AnswerMatch>[];

    for (final question in assessment.questions) {
      final detectedAnswer = detected
          .where((d) => d.questionNumber == question.number)
          .firstOrNull;

      if (detectedAnswer == null) {
        matches.add(
          AnswerMatch(
            questionNumber: question.number,
            detectedAnswer: '[MISSING]',
            correctAnswer: question.correctAnswer?.toString() ?? '',
            isCorrect: false,
            score: 0,
            maxScore: question.points,
            confidence: 0));
        continue;
      }

      final isCorrect = checkAnswer(
        detected: detectedAnswer.answer,
        correct: question.correctAnswer,
        type: question.type);

      matches.add(
        AnswerMatch(
          questionNumber: question.number,
          detectedAnswer: detectedAnswer.answer,
          correctAnswer: question.correctAnswer?.toString() ?? '',
          isCorrect: isCorrect,
          score: isCorrect ? question.points : 0,
          maxScore: question.points,
          confidence: detectedAnswer.confidence,
          ocrRawText: detectedAnswer.rawText));
    }

    return matches;
  }

  /// Remove duplicate answers for the same question number.
  /// Keeps the one with highest confidence.
  List<DetectedAnswer> deduplicateAnswers(List<DetectedAnswer> answers) {
    final Map<int, DetectedAnswer> best = {};
    for (final answer in answers) {
      final existing = best[answer.questionNumber];
      if (existing == null || answer.confidence > existing.confidence) {
        best[answer.questionNumber] = answer;
      }
    }
    return best.values.toList()
      ..sort((a, b) => a.questionNumber.compareTo(b.questionNumber));
  }

  /// Average confidence across all scored answers. Returns 0 if empty.
  double calculateConfidence(List<AnswerMatch> answers) {
    if (answers.isEmpty) return 0;
    return answers.fold(0.0, (sum, a) => sum + a.confidence) / answers.length;
  }

  /// Calculate total score from scored answers.
  double calculateTotalScore(List<AnswerMatch> answers) {
    return answers.fold(0.0, (sum, a) => sum + a.score);
  }

  /// Calculate percentage from total and max score.
  double calculatePercentage({
    required double totalScore,
    required double maxScore,
  }) {
    if (maxScore <= 0) return 0;
    return (totalScore / maxScore) * 100;
  }

  // ── Weighted Per-Paper Scoring ────────────────────────────────────

  /// Compute weighted percentage for a single paper's scored answers.
  ///
  /// Distributes questions to components:
  /// 1. By topic tag match (component name ↔ question topicTag)
  /// 2. Remaining questions distributed proportionally by component weight
  ///
  /// Returns null if no questions could be assigned.
  double? computeWeightedPercentage({
    required List<AnswerMatch> scoredAnswers,
    required List<Question> questions,
    required WeightedGradeScale scale,
  }) {
    if (scoredAnswers.isEmpty || scale.components.isEmpty) return null;

    // Build question number → AnswerMatch lookup
    final answerByQ = <int, AnswerMatch>{};
    for (final a in scoredAnswers) {
      answerByQ[a.questionNumber] = a;
    }

    // Build question → component index mapping
    final questionToComponent = <int, int>{};

    // Pass 1: topic tag matching
    for (final q in questions) {
      if (q.topicTag != null && q.topicTag!.isNotEmpty) {
        for (int c = 0; c < scale.components.length; c++) {
          final compName = scale.components[c].name.toLowerCase();
          final tag = q.topicTag!.toLowerCase();
          if (compName.contains(tag) || tag.contains(compName)) {
            questionToComponent[q.number] = c;
            break;
          }
        }
      }
    }

    // Pass 2: distribute remaining proportionally by weight
    final unassigned =
        questions.where((q) => !questionToComponent.containsKey(q.number)).toList();

    if (unassigned.isNotEmpty) {
      final totalWeight = scale.components.fold(0.0, (s, c) => s + c.weight);
      int assignedCount = 0;
      for (int c = 0; c < scale.components.length; c++) {
        final proportion =
            totalWeight > 0 ? scale.components[c].weight / totalWeight : 1.0 / scale.components.length;
        final count = (unassigned.length * proportion).round();
        final start = assignedCount;
        final end = (assignedCount + count).clamp(0, unassigned.length);
        for (int j = start; j < end; j++) {
          questionToComponent[unassigned[j].number] = c;
        }
        assignedCount = end;
      }
      // Remainder → last component
      for (int j = assignedCount; j < unassigned.length; j++) {
        questionToComponent[unassigned[j].number] = scale.components.length - 1;
      }
    }

    // Compute per-component scores
    final componentScores = <int, double>{};
    final componentMaxScores = <int, double>{};

    for (final entry in questionToComponent.entries) {
      final answer = answerByQ[entry.key];
      if (answer == null) continue;
      final c = entry.value;
      componentScores[c] = (componentScores[c] ?? 0) + answer.score;
      componentMaxScores[c] = (componentMaxScores[c] ?? 0) + answer.maxScore;
    }

    // Weighted sum
    double weightedSum = 0;
    double totalActiveWeight = 0;
    for (int c = 0; c < scale.components.length; c++) {
      final max = componentMaxScores[c] ?? 0;
      if (max <= 0) continue;
      final pct = ((componentScores[c] ?? 0) / max) * 100;
      weightedSum += pct * scale.components[c].weight;
      totalActiveWeight += scale.components[c].weight;
    }

    if (totalActiveWeight <= 0) return null;
    return weightedSum / totalActiveWeight;
  }

  // ── Answer-Pattern Duplicate Detection ──

  /// Generate a normalized fingerprint from scored answers.
  ///
  /// Returns a string like "1:A|2:B|3:TRUE|4:C" — sorted by question number,
  /// answers uppercased for comparison stability.
  /// Two scans of the same paper produce identical fingerprints regardless of
  /// image noise, lighting, or crop differences.
  String generateAnswerFingerprint(List<AnswerMatch> answers) {
    if (answers.isEmpty) return '';
    final sorted = List<AnswerMatch>.from(answers)
      ..sort((a, b) => a.questionNumber.compareTo(b.questionNumber));
    return sorted
        .where((a) => a.detectedAnswer != '[MISSING]')
        .map((a) => '${a.questionNumber}:${a.detectedAnswer.toUpperCase()}')
        .join('|');
  }

  /// Compare two fingerprints and return the match ratio (0.0–1.0).
  ///
  /// Compares question-by-question: counts matching answers for questions
  /// present in both. Questions missing from either side are ignored in
  /// the denominator (avoids penalizing partial scans).
  double compareFingerprints(String fp1, String fp2) {
    if (fp1.isEmpty || fp2.isEmpty) return 0.0;
    if (fp1 == fp2) return 1.0;

    final map1 = _parseFingerprint(fp1);
    final map2 = _parseFingerprint(fp2);

    // Only compare questions present in both
    final commonKeys = map1.keys.toSet().intersection(map2.keys.toSet());
    if (commonKeys.isEmpty) return 0.0;

    int matches = 0;
    for (final key in commonKeys) {
      if (map1[key] == map2[key]) matches++;
    }

    return matches / commonKeys.length;
  }

  /// Parse "1:A|2:B|3:TRUE" into {1: "A", 2: "B", 3: "TRUE"}.
  Map<int, String> _parseFingerprint(String fp) {
    final map = <int, String>{};
    for (final pair in fp.split('|')) {
      final colonIndex = pair.indexOf(':');
      if (colonIndex < 0) continue;
      final qNum = int.tryParse(pair.substring(0, colonIndex));
      if (qNum == null) continue;
      map[qNum] = pair.substring(colonIndex + 1).toUpperCase();
    }
    return map;
  }

  /// Detect answer-pattern duplicates across a batch of scan results.
  ///
  /// Compares every pair of results. Returns a list of [AnswerDuplicate]
  /// entries for pairs whose answer patterns match ≥ [threshold] (default 0.9).
  ///
  /// This catches what dHash can't: different photos of different students
  /// with identical answers (e.g., copied papers), and same-paper re-scans
  /// where the image hash was inconclusive.
  List<AnswerDuplicate> detectAnswerDuplicates(
    List<List<AnswerMatch>> allAnswers, {
    double threshold = 0.9,
  }) {
    final fingerprints = allAnswers.map(generateAnswerFingerprint).toList();
    final duplicates = <AnswerDuplicate>[];

    for (int i = 0; i < fingerprints.length; i++) {
      if (fingerprints[i].isEmpty) continue;
      for (int j = i + 1; j < fingerprints.length; j++) {
        if (fingerprints[j].isEmpty) continue;
        final ratio = compareFingerprints(fingerprints[i], fingerprints[j]);
        if (ratio >= threshold) {
          duplicates.add(
            AnswerDuplicate(scanIndexA: i, scanIndexB: j, matchRatio: ratio));
        }
      }
    }

    return duplicates;
  }
}

/// A detected question-answer pair from OCR.
/// (Re-declared here to avoid importing ocr_service.dart and pulling in ML Kit.)
class DetectedAnswer {
  final int questionNumber;
  final String answer;
  final double confidence;
  final String rawText;

  const DetectedAnswer({
    required this.questionNumber,
    required this.answer,
    required this.confidence,
    required this.rawText,
  });
}

/// Represents a pair of scans whose answer patterns match above threshold.
class AnswerDuplicate {
  /// Index in the batch results list.
  final int scanIndexA;
  final int scanIndexB;

  /// Ratio of matching answers (0.0–1.0). 1.0 = identical.
  final double matchRatio;

  const AnswerDuplicate({
    required this.scanIndexA,
    required this.scanIndexB,
    required this.matchRatio,
  });

  /// Percentage match for display (e.g., 97.5).
  double get matchPercent => matchRatio * 100;
}
