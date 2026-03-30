/// Parses question-answer pairs from OCR-detected text.
///
/// Extracted from OcrService for testability. Handles:
/// - English MCQ: "1. A", "2-B", "3) C"
/// - Amharic MCQ: "1. ሀ", "2. ለ"
/// - Amharic numerals: "፩. A", "፪፫. B" (Ge'ez question numbers)
/// - True/False: "1. True", "2. እውነት", "3. F"
/// - Concatenated: "1A", "2B" (no delimiter, common in bubbled sheets)
/// - Noisy OCR: extra spaces, mixed case, trailing punctuation
class AnswerParser {
  const AnswerParser();

  /// Ge'ez/Amharic numeral to integer map.
  /// ፩=1, ፪=2, ፫=3, ፬=4, ፭=5, ፮=6, ፯=7, ፰=8, ፱=9
  static const _amharicDigits = {
    '፩': 1, '፪': 2, '፫': 3, '፬': 4,
    '፭': 5, '፮': 6, '፯': 7, '፰': 8, '፱': 9,
  };

  /// Pattern matching Amharic Ge'ez digits (፩ through ፱).
  static final _amharicDigitPattern = RegExp(r'[፩፪፫፬፭፮፯፰፱]+');

  /// Convert an Amharic numeral string to an integer.
  /// "፩" → 1, "፪፫" → 23, "፱፱" → 99
  /// Returns null if the string is empty or contains non-digit characters.
  static int? _amharicToInt(String s) {
    if (s.isEmpty) return null;
    int result = 0;
    for (int i = 0; i < s.length; i++) {
      final digit = _amharicDigits[s[i]];
      if (digit == null) return null;
      result = result * 10 + digit;
    }
    return result > 0 ? result : null;
  }

  /// Replace all Amharic numeral sequences in [text] with Latin digits.
  /// "፩. A" → "1. A", "፪፫. B" → "23. B"
  static String _amharicToLatinNumerals(String text) {
    return text.replaceAllMapped(_amharicDigitPattern, (match) {
      final amharicNum = match.group(0)!;
      final intVal = _amharicToInt(amharicNum);
      return intVal?.toString() ?? amharicNum;
    });
  }

  /// Parse question number and answer from a single OCR text line.
  /// Returns null if the line doesn't match any known format.
  (int, String)? parseQuestionAnswer(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    // Pre-process: convert Amharic numerals to Latin before pattern matching.
    // This lets existing regex patterns handle ፩፪፫ etc. transparently.
    final normalized = _amharicToLatinNumerals(trimmed);

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
      // Try Latin-normalized text first (handles Amharic numerals),
      // then fall back to original (preserves Amharic answer letters).
      var match = pattern.firstMatch(normalized);
      final usedNormalized = match != null;
      match ??= pattern.firstMatch(trimmed);
      if (match == null) continue;

      final number = int.tryParse(match.group(1)!);
      if (number == null || number <= 0 || number > 200) continue;

      // Use original text for answer extraction (preserves Amharic letters)
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
