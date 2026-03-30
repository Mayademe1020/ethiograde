/// Parses question-answer pairs from OCR-detected text.
///
/// Extracted from OcrService for testability. Handles:
/// - English MCQ: "1. A", "2-B", "3) C"
/// - Amharic MCQ: "1. ሀ", "2. ለ"
/// - True/False: "1. True", "2. እውነት", "3. F"
/// - Concatenated: "1A", "2B" (no delimiter, common in bubbled sheets)
/// - Noisy OCR: extra spaces, mixed case, trailing punctuation
class AnswerParser {
  const AnswerParser();

  /// Parse question number and answer from a single OCR text line.
  /// Returns null if the line doesn't match any known format.
  (int, String)? parseQuestionAnswer(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    // Order matters: try most specific patterns first
    final patterns = <RegExp>[
      // "1. A" or "1-A" or "1) እውነት" or "1: True"
      RegExp(r'^(\d+)\s*[.\-):]\s*(.+)$'),
      // "1A" or "10B" — concatenated, no delimiter (bubbled answer sheets)
      // Handles MCQ letters, T/F, Amharic letters, and true/false case-insensitive
      RegExp(r'^(\d+)([a-eA-Eሀ-ሠ]|[tTfF]|true|false|True|False|እውነት|ሐሰት)$'),
      // "1 A" (number + space + very short answer — 1-2 chars only, last resort)
      RegExp(r'^(\d+)\s{1,2}(\S{1,2})$'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(trimmed);
      if (match == null) continue;

      final number = int.tryParse(match.group(1)!);
      if (number == null || number <= 0 || number > 200) continue;

      final rawAnswer = match.group(match.groupCount)!.trim();
      final answer = normalizeAnswer(rawAnswer);
      if (answer.isEmpty) continue;

      return (number, answer);
    }

    return null;
  }

  /// Normalize raw OCR answer text to canonical form.
  /// Returns empty string if the input is unrecognizable noise.
  String normalizeAnswer(String raw) {
    if (raw.isEmpty) return '';

    final trimmed = raw.trim();

    // Strip trailing punctuation that OCR often adds: "A." "B," "C;"
    final stripped = trimmed.replaceAll(RegExp(r'[.,;:!?]+$'), '');
    if (stripped.isEmpty && trimmed.isNotEmpty) {
      // Was only punctuation — treat as noise
      return '';
    }

    final lower = stripped.toLowerCase();

    // ── True/False variants ──

    // English
    if (lower == 'true' || lower == 't' || lower == 'yes' || lower == 'y') {
      return 'True';
    }
    if (lower == 'false' || lower == 'f' || lower == 'no' || lower == 'n') {
      return 'False';
    }

    // Amharic
    if (lower.contains('እውነት') || lower == 'ት') return 'True';
    if (lower.contains('ሐሰት') || lower == 'ሐ') return 'False';

    // ── MCQ letters ──

    // English single letter (case-insensitive)
    if (RegExp(r'^[a-e]$').hasMatch(lower)) return lower.toUpperCase();

    // Amharic letters mapped to MCQ options
    const amharicLetters = {
      'ሀ': 'A',
      'ለ': 'B',
      'ሐ': 'C',
      'መ': 'D',
      'ሠ': 'E',
    };
    if (amharicLetters.containsKey(stripped)) return amharicLetters[stripped]!;

    // ── Fallback: return as-is if it looks like a plausible answer ──
    // Short alphanumeric (e.g., "AB" for multi-select, numbers for numeric answers)
    if (stripped.length <= 5 && RegExp(r'^[a-zA-Z0-9ሀ-፱]+$').hasMatch(stripped)) {
      return stripped;
    }

    return '';
  }

  /// Parse multiple text regions into detected answers.
  List<ParsedAnswer> parseAnswers(List<TextRegionInput> regions) {
    final answers = <ParsedAnswer>[];

    for (final region in regions) {
      final parsed = parseQuestionAnswer(region.text);
      if (parsed != null) {
        answers.add(ParsedAnswer(
          questionNumber: parsed.$1,
          answer: parsed.$2,
          confidence: region.confidence,
          rawText: region.text,
        ));
      }
    }

    return answers;
  }
}

/// Input from OCR — a detected text line with position and confidence.
class TextRegionInput {
  final String text;
  final double confidence;
  final double x;
  final double y;

  const TextRegionInput({
    required this.text,
    required this.confidence,
    this.x = 0,
    this.y = 0,
  });
}

/// A parsed question-answer pair.
class ParsedAnswer {
  final int questionNumber;
  final String answer;
  final double confidence;
  final String rawText;

  const ParsedAnswer({
    required this.questionNumber,
    required this.answer,
    required this.confidence,
    required this.rawText,
  });
}
