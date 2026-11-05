/// Parses raw OCR text from a printed answer key sheet into structured answers.
///
/// Handles common Ethiopian exam answer key formats:
/// - "1. B", "1) B", "1: B", "Q1 B", "1 B"
/// - Answer letters: A–E, T/F, True/False
class AnswerKeyOcrParser {
  const AnswerKeyOcrParser();

  /// Parse OCR text into a list of detected answers.
  ///
  /// Returns answers sorted by question number. Each answer includes
  /// a confidence level: "high", "medium", or "low".
  List<OcrParsedAnswer> parse(String ocrText, {int? expectedCount}) {
    final answers = <OcrParsedAnswer>[];
    final seen = <int>{};

    // Match patterns like: "1. B", "1) B", "1: B", "Q1 B", "1 B", "1-B"
    final pattern = RegExp(
      r'(?:Q|q)?\s*(\d{1,3})\s*[.:)\]-]\s*([A-Ea-eTtFf]{1,5}(?:\s+(?:true|false|TRUE|FALSE))?)',
      multiLine: true,
    );

    for (final match in pattern.allMatches(ocrText)) {
      final number = int.tryParse(match.group(1) ?? '');
      if (number == null || number < 1 || number > 200) continue;
      if (seen.contains(number)) continue;
      seen.add(number);

      final rawAnswer = match.group(2)?.trim() ?? '';
      final normalized = _normalizeAnswer(rawAnswer);
      if (normalized.isEmpty) continue;

      final confidence = _assessConfidence(rawAnswer, match.group(0) ?? '');
      answers.add(OcrParsedAnswer(
        questionNumber: number,
        answer: normalized,
        rawText: rawAnswer,
        confidence: confidence,
      ));
    }

    // Also try a simpler pattern: just a number followed by a letter on the same line
    // Handles cases where the separator is a space or tab
    final simplePattern = RegExp(
      r'(?:^|\s)(\d{1,3})\s+([A-Ea-eTtFf])\b',
      multiLine: true,
    );

    for (final match in simplePattern.allMatches(ocrText)) {
      final number = int.tryParse(match.group(1) ?? '');
      if (number == null || number < 1 || number > 200) continue;
      if (seen.contains(number)) continue;
      seen.add(number);

      final rawAnswer = match.group(2)?.trim() ?? '';
      final normalized = _normalizeAnswer(rawAnswer);
      if (normalized.isEmpty) continue;

      answers.add(OcrParsedAnswer(
        questionNumber: number,
        answer: normalized,
        rawText: rawAnswer,
        confidence: 'medium',
      ));
    }

    answers.sort((a, b) => a.questionNumber.compareTo(b.questionNumber));
    return answers;
  }

  /// Normalize a raw answer string to a standard format.
  String _normalizeAnswer(String raw) {
    final trimmed = raw.trim().toUpperCase();
    if (trimmed.isEmpty) return '';

    // Single letter A-E
    if (RegExp(r'^[A-E]$').hasMatch(trimmed)) return trimmed;

    // T/F
    if (trimmed == 'T' || trimmed == 'TRUE' || trimmed == 'toBeTruthy') return 'True';
    if (trimmed == 'F' || trimmed == 'FALSE' || trimmed == 'isFalse') return 'False';
    if (trimmed == 'T') return 'True';
    if (trimmed == 'F') return 'False';

    // Multi-answer like "A+C" or "A, C"
    if (trimmed.contains('+') || trimmed.contains(',')) {
      final parts = trimmed.split(RegExp(r'[,+]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      final normalized = parts.where((p) => RegExp(r'^[A-E]$').hasMatch(p)).toList();
      if (normalized.isNotEmpty) return normalized.join(',');
    }

    // If it's a single letter after stripping whitespace
    if (trimmed.length <= 2 && RegExp(r'^[A-E]$').hasMatch(trimmed)) return trimmed;

    return trimmed.length <= 5 ? trimmed : '';
  }

  /// Assess confidence based on the raw OCR text quality.
  String _assessConfidence(String rawAnswer, String fullMatch) {
    final clean = rawAnswer.trim();

    // High confidence: clean single letter, clear separator
    if (RegExp(r'^[A-E]$').hasMatch(clean) &&
        RegExp(r'[.:)\-]').hasMatch(fullMatch)) {
      return 'high';
    }

    // High confidence for T/F
    if (['T', 'F', 'TRUE', 'FALSE'].contains(clean.toUpperCase())) {
      return 'high';
    }

    // Medium confidence: letter present but format is unusual
    if (RegExp(r'[A-Ea-eTtFf]').hasMatch(clean)) return 'medium';

    // Low confidence: unrecognized format
    return 'low';
  }
}

/// A single parsed answer from OCR output.
class OcrParsedAnswer {
  final int questionNumber;
  final String answer;
  final String rawText;
  final String confidence;

  const OcrParsedAnswer({
    required this.questionNumber,
    required this.answer,
    required this.rawText,
    required this.confidence,
  });

  bool get isHighConfidence => confidence == 'high';
  bool get isLowConfidence => confidence == 'low';
}
