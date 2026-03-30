import '../models/assessment.dart';
import '../models/scan_result.dart';
import 'answer_parser.dart';

/// Pure-Dart scoring engine. No Flutter, no platform plugins.
/// Extracted from OcrService for independent testability.
///
/// Handles:
/// - Answer matching by question type (MCQ, T/F, short answer)
/// - Grading scale lookup (MoE national, private international, university)
/// - Confidence calculation
/// - Answer deduplication
class ScoringService {
  const ScoringService();

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
  String calculateGrade(double percentage, String rubricType) {
    final scale = gradingScales[rubricType] ?? gradingScales['moe_national']!;
    for (final entry in scale.entries) {
      final range = entry.value;
      if (percentage >= range[0] && percentage <= range[1]) {
        return entry.key;
      }
    }
    return 'F';
  }

  /// Check if a detected answer matches the correct answer for a question type.
  bool checkAnswer({
    required dynamic detected,
    required dynamic correct,
    required QuestionType type,
  }) {
    if (detected == null || correct == null) return false;

    if (type == QuestionType.mcq || type == QuestionType.trueFalse) {
      return detected.toString().toUpperCase() ==
          correct.toString().toUpperCase();
    }

    if (type == QuestionType.shortAnswer) {
      if (correct is List) {
        return correct.any(
          (c) => c.toString().toLowerCase() == detected.toString().toLowerCase(),
        );
      }
      return detected.toString().toLowerCase() ==
          correct.toString().toLowerCase();
    }

    return false;
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
        matches.add(AnswerMatch(
          questionNumber: question.number,
          detectedAnswer: '[MISSING]',
          correctAnswer: question.correctAnswer?.toString() ?? '',
          isCorrect: false,
          score: 0,
          maxScore: question.points,
          confidence: 0,
        ));
        continue;
      }

      final isCorrect = checkAnswer(
        detected: detectedAnswer.answer,
        correct: question.correctAnswer,
        type: question.type,
      );

      matches.add(AnswerMatch(
        questionNumber: question.number,
        detectedAnswer: detectedAnswer.answer,
        correctAnswer: question.correctAnswer?.toString() ?? '',
        isCorrect: isCorrect,
        score: isCorrect ? question.points : 0,
        maxScore: question.points,
        confidence: detectedAnswer.confidence,
        ocrRawText: detectedAnswer.rawText,
      ));
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
  double calculatePercentage({required double totalScore, required double maxScore}) {
    if (maxScore <= 0) return 0;
    return (totalScore / maxScore) * 100;
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
      map[qNum] = pair.substring(colonIndex + 1);
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
          duplicates.add(AnswerDuplicate(
            scanIndexA: i,
            scanIndexB: j,
            matchRatio: ratio,
          ));
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
