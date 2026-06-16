import 'package:flutter/foundation.dart';

/// Parses question-answer pairs from OCR-detected text.
///
/// Extracted from OcrService for testability. Handles:
/// - English MCQ: "1. A", "2-B", "3) C"
/// - True/False: "1. True", "2. F"
/// - Concatenated: "1A", "10B" (no delimiter, common in bubbled sheets)
/// - Short answers: "5. Addis Ababa", "6. 42 km" (multi-word text)
/// - Worksheet format: "1. What is the greeting? A" (question + answer same line)
/// - Matching pairs: "G D", "G,D", "1. G D" (letter sequences for column matching)
/// - Noisy OCR: extra spaces, mixed case, trailing punctuation
class AnswerParser {
  const AnswerParser();

  /// Parse question number and answer from a single OCR text line.
  /// Returns null if the line doesn't match any known format.
  (int, String)? parseQuestionAnswer(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    // ── Format 1: Answer BEFORE question number (Ethiopian format) ──
    // "B 1. What is..." → Q1, answer B
    // "AC 4. Name two..." → Q4, answer A,C
    // Pattern: 1-2 letters + space + digit + rest
    final format1 = RegExp(r'^([a-eA-E]{1,2})\s+(\d+)\s*[.\-):]?\s*(.+)$');
    final fmt1Match = format1.firstMatch(trimmed);
    if (fmt1Match != null) {
      final answerRaw = fmt1Match.group(1)!;
      final number = int.tryParse(fmt1Match.group(2)!);
      if (number != null && number > 0 && number <= 200) {
        // Normalize to uppercase, handle multi-letter (AC → A,C)
        final answer = _normalizeMcqAnswer(answerRaw);
        if (answer.isNotEmpty) return (number, answer);
      }
    }

    // Order matters: try most specific patterns first
    final patterns = <RegExp>[
      // "1. A" or "1-A" or "1) True" — standard format
      RegExp(r'^(\d+)\s*[.\-):]\s*(.+)$'),
      // "1A" or "10B" — concatenated, no delimiter (bubbled answer sheets)
      RegExp(r'^(\d+)([a-eA-E]|[tTfF]|true|false|True|False)$'),
      // "1 A" (number + space + very short answer — 1-2 chars only, last resort)
      RegExp(r'^(\d+)\s{1,2}(\S{1,2})$'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(trimmed);
      if (match == null) continue;

      final number = int.tryParse(match.group(1)!);
      if (number == null || number <= 0 || number > 200) continue;

      final rawAnswer = match.group(match.groupCount)!.trim();

      // ── Worksheet format: "1. What is the greeting? A" ──
      // The raw answer part may contain question text + answer.
      // Try to extract the actual answer from the end.
      final extracted = _extractAnswerFromText(rawAnswer);
      final answer = normalizeAnswer(extracted);
      if (answer.isEmpty) continue;

      return (number, answer);
    }

    return null;
  }

  /// Normalize MCQ answer letters to canonical form.
  /// "B" → "B", "b" → "B", "AC" → "A,C", "aC" → "A,C"
  static String _normalizeMcqAnswer(String raw) {
    final letters = raw.split('').where((c) => RegExp(r'[a-eA-E]').hasMatch(c)).toList();
    if (letters.isEmpty) return '';
    if (letters.length == 1) return letters.first.toUpperCase();
    // Multiple letters → comma-separated
    return letters.map((c) => c.toUpperCase()).join(',');
  }

  /// Extract the actual answer from text that may contain question content.
  ///
  /// Handles worksheet formats where OCR reads question text and answer
  /// on the same line: "What is the greeting? A" → "A"
  /// "Match the opposites. G D" → "G D"
  /// "The capital of Ethiopia is B" → "B"
  ///
  /// Strategy:
  /// 1. If the whole text IS a known answer (MCQ letter, T/F), return as-is
  /// 2. Try to find answer at the END of the text:
  ///    a. Last word(s) that are MCQ letters: "G D" → "G D"
  ///    b. Last word that is T/F: "... True" → "True"
  ///    c. Last single letter: "... B" → "B"
  /// 3. Return original text as fallback (let normalizeAnswer handle it)
  String _extractAnswerFromText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';

    final words = trimmed.split(RegExp(r'\s+'));
    if (words.isEmpty) return trimmed;

    // ── Pattern 1: Matching pairs — multiple single letters at end ──
    if (words.length >= 2) {
      final lastTwo = words.sublist(words.length - 2);
      final bothLetters = lastTwo.every(
        (w) => RegExp(r'^[a-zA-Z]$').hasMatch(w));
      if (bothLetters) {
        int letterStart = words.length - 2;
        while (letterStart > 0 &&
            RegExp(r'^[a-zA-Z]$').hasMatch(words[letterStart - 1])) {
          letterStart--;
        }
        return words.sublist(letterStart).join(' ');
      }
    }

    // ── Pattern 2: True/False at end ──
    final lastWord = words.last;
    final lastNorm = normalizeAnswer(lastWord);
    if (lastNorm == 'True' || lastNorm == 'False') {
      return lastWord;
    }

    // ── Pattern 3: Single MCQ letter at end ──
    if (RegExp(r'^[a-eA-E]$').hasMatch(lastWord)) {
      return lastWord;
    }

    // ── Pattern 3b: Amharic MCQ letter at end (ሀ/A, ለ/B, ሐ/C, መ/D, ሠ/E) ──
    const amharicMcq = {'ሀ': 'A', 'ለ': 'B', 'ሐ': 'C', 'መ': 'D', 'ሠ': 'E'};
    if (amharicMcq.containsKey(lastWord)) {
      return lastWord;
    }

    // Fallback: check if entire text is a known answer (MCQ, T/F, etc.)
    final normalized = normalizeAnswer(trimmed);
    if (normalized.isNotEmpty && normalized.length <= 20) return trimmed;

    return trimmed;
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
    if (lower == 'true' || lower == 't' || lower == 'yes' || lower == 'y') {
      return 'True';
    }
    if (lower == 'false' || lower == 'f' || lower == 'no' || lower == 'n') {
      return 'False';
    }

    // ── Amharic True/False words ──
    if (trimmed == 'እውነት' || trimmed == 'ት') return 'True';
    if (trimmed == 'ሐሰት') return 'False';

    // ── Amharic MCQ letters (ሀ=A, ለ=B, ሐ=C, መ=D, ሠ=E) ──
    const amharicMcq = {
      'ሀ': 'A', 'ለ': 'B', 'ሐ': 'C', 'መ': 'D', 'ሠ': 'E',
    };
    if (amharicMcq.containsKey(trimmed)) {
      return amharicMcq[trimmed]!;
    }

    // ── Matching pair sequences ──
    // "G D" or "G,D" or "G D E" — space/comma-separated single letters
    final matchingResult = _tryParseMatchingPair(stripped);
    if (matchingResult != null) return matchingResult;

    // ── MCQ letters ──
    if (RegExp(r'^[a-e]$').hasMatch(lower)) return lower.toUpperCase();

    // ── Fallback: return as-is if it looks like a plausible answer ──
    // Short alphanumeric (e.g., "AB" for multi-select, numbers for numeric answers)
    if (stripped.length <= 5 && RegExp(r'^[a-zA-Z0-9]+$').hasMatch(stripped)) {
      return stripped;
    }

    // ── Short answer: accept multi-word text (e.g., "Addis Ababa", "42 km") ──
    // Must contain at least 2 alphanumeric chars (including Amharic) to filter OCR noise
    if (stripped.length >= 2 &&
        stripped.length <= 80 &&
        RegExp(r'[a-zA-Z0-9\u1200-\u137F]').hasMatch(stripped)) {
      return stripped;
    }

    return '';
  }

  /// Try to parse a string as a matching pair sequence.
  ///
  /// Returns canonical form like "MATCH:A-B-C" if it's a sequence of
  /// single letters separated by spaces or commas.
  /// Examples: "G D" → "MATCH:G-D", "G,D,E" → "MATCH:G-D-E"
  ///
  /// Requirements:
  /// - 2+ tokens, each a single letter (A-Z)
  /// - Separated by spaces or commas
  /// - At least one non-MCQ letter present (F-Z) to distinguish from
  ///   multi-select MCQ ("A B" could be either — but matching uses
  ///   letters beyond E which MCQ never does)
  ///
  /// Returns null if not a matching pair.
  String? _tryParseMatchingPair(String text) {
    // Split by spaces or commas
    final tokens =
        text.split(RegExp(r'[\s,]+')).where((t) => t.isNotEmpty).toList();

    if (tokens.length < 2) return null;

    // All tokens must be single letters
    final allSingleLetters = tokens.every(
      (t) => RegExp(r'^[a-zA-Z]$').hasMatch(t));
    if (!allSingleLetters) return null;

    // At least one letter beyond E (F-Z) → likely matching, not MCQ
    final hasNonMcq = tokens.any(
      (t) => RegExp(r'^[f-zF-Z]$').hasMatch(t));
    final uniqueTokens = tokens.toSet();
    final isMatchingPattern = hasNonMcq;

    if (!isMatchingPattern) return null;

    // Normalize to uppercase, join with dashes
    final normalized = tokens.map((t) => t.toUpperCase()).join('-');
    return 'MATCH:$normalized';
  }

  /// Parse multiple text regions into detected answers.
  List<ParsedAnswer> parseAnswers(List<TextRegionInput> regions) {
    final answers = <ParsedAnswer>[];

    for (final region in regions) {
      final parsed = parseQuestionAnswer(region.text);
      // DEBUG: Show what parser receives and what it extracts
      if (parsed != null) {
        debugPrint('PARSER: "${region.text}" → Q${parsed.$1} = ${parsed.$2}');
      } else {
        debugPrint('PARSER: "${region.text}" → NO MATCH');
      }
      if (parsed != null) {
        answers.add(
          ParsedAnswer(
            questionNumber: parsed.$1,
            answer: parsed.$2,
            confidence: region.confidence,
            rawText: region.text));
      }
    }

    return answers;
  }

  /// Parse answers from all OCR text regions with spatial awareness.
  ///
  /// Uses Y-position to group nearby lines — answers on worksheets are
  /// often on the same line or slightly below their question text.
  ///
  /// [regions] — all OCR text lines with positions and confidence.
  /// [maxGap] — max vertical pixel gap to consider lines "on the same line".
  ///   Default 20px works for enhanced 1600px images.
  ///
  /// Returns parsed answers with question numbers inferred from position.
  List<ParsedAnswer> parseAnswersWithPosition(
    List<TextRegionInput> regions, {
    double maxGap = 20.0,
  }) {
    // First pass: try standard parsing on each line
    final standardAnswers = parseAnswers(regions);
    final answeredQs = standardAnswers.map((a) => a.questionNumber).toSet();

    // Second pass: for lines that didn't parse, check if they're answers
    // sitting next to a question number (spatial grouping)
    final spatialAnswers = <ParsedAnswer>[];

    // Sort regions by Y position (top to bottom)
    final sortedRegions = List<TextRegionInput>.from(regions)
      ..sort((a, b) => a.y.compareTo(b.y));

    // Group regions into horizontal lines (same Y within maxGap)
    final lines = <List<TextRegionInput>>[];
    for (final region in sortedRegions) {
      if (lines.isEmpty) {
        lines.add([region]);
        continue;
      }
      final lastLine = lines.last;
      if ((region.y - lastLine.first.y).abs() <= maxGap) {
        lastLine.add(region);
      } else {
        lines.add([region]);
      }
    }

    // For each horizontal line, check if it has a question number + answer
    for (final line in lines) {
      if (line.length < 2) continue;

      // Sort left to right
      line.sort((a, b) => a.x.compareTo(b.x));

      // Check if first element is a question number
      final firstText = line.first.text.trim();
      final qMatch = RegExp(r'^(\d+)\s*[.\-):]?$').firstMatch(firstText);
      if (qMatch == null) continue;

      final qNum = int.tryParse(qMatch.group(1)!);
      if (qNum == null || qNum <= 0 || qNum > 200) continue;
      if (answeredQs.contains(qNum)) continue;

      // Try each remaining element on this line as the answer
      for (int i = 1; i < line.length; i++) {
        final answerText = line[i].text.trim();
        final normalized = normalizeAnswer(answerText);
        if (normalized.isNotEmpty) {
          spatialAnswers.add(
            ParsedAnswer(
              questionNumber: qNum,
              answer: normalized,
              confidence: line[i].confidence,
              rawText: '${line.first.text} ${line[i].text}'));
          answeredQs.add(qNum);
          break;
        }
      }
    }

    return [...standardAnswers, ...spatialAnswers];
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
