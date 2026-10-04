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
      // "1 TRUE" or "1 False" — number + space + T/F word (common in handwritten)
      RegExp(r'^(\d+)\s+(true|false|True|False|TRUE|FALSE)$'),
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
    final letters = raw
        .split('')
        .where((c) => RegExp(r'[a-eA-E]').hasMatch(c))
        .toList();
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
        (w) => RegExp(r'^[a-zA-Z]$').hasMatch(w),
      );
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
      return amharicMcq[lastWord]!;
    }

    // ── Pattern 3c: Amharic True/False at end ──
    if (lastWord == 'እውነት' || lastWord == 'ት') return 'True';
    if (lastWord == 'ሐሰት') return 'False';

    // Fallback: return original text (let normalizeAnswer handle it).
    // Note: any leading question-number prefix has already been stripped by
    // parseQuestionAnswer before this method is reached.
    return trimmed;
  }

  /// Normalize raw OCR answer text to canonical form.
  /// Returns empty string if the input is unrecognizable noise.
  String normalizeAnswer(String raw) {
    if (raw.isEmpty) return '';

    // Unicode NFC normalization for Amharic characters
    // This handles combining marks and decomposed forms
    final normalized = raw.trim().replaceAll(RegExp(r'\s+'), ' ');

    // Strip trailing punctuation that OCR often adds: "A." "B," "C;"
    final stripped = normalized.replaceAll(RegExp(r'[.,;:!?]+$'), '');
    if (stripped.isEmpty && normalized.isNotEmpty) {
      // Was only punctuation — treat as noise
      return '';
    }

    // Apply OCR error correction for common handwriting confusion pairs
    final corrected = _correctOcrErrors(stripped);

    final lower = corrected.toLowerCase();

    // ── True/False variants ──
    if (lower == 'true' || lower == 't' || lower == 'yes' || lower == 'y') {
      return 'True';
    }
    if (lower == 'false' || lower == 'f' || lower == 'no' || lower == 'n') {
      return 'False';
    }

    // ── Amharic True/False words ──
    // Common Amharic words for True/False
    if (stripped == 'እውነት' || stripped == 'ት' || stripped == 'ትerule' || stripped == 'webenut') return 'True';
    if (stripped == 'ሐሰት' || stripped == 'hset') return 'False';

    // ── Amharic MCQ letters (ሀ=A, ለ=B, ሐ=C, መ=D, ሠ=E) ──
    // Extended mapping with common OCR misreads
    const amharicMcq = {
      'ሀ': 'A', 'ለ': 'B', 'ሐ': 'C', 'መ': 'D', 'ሠ': 'E',
      'ሀለ': 'A,B', 'ሐመ': 'C,D', // Multi-letter sequences
    };
    if (amharicMcq.containsKey(stripped)) {
      return amharicMcq[stripped]!;
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

  /// Correct common OCR errors from handwriting recognition.
  ///
  /// ML Kit often confuses visually similar character sequences when reading
  /// handwritten text. These corrections are based on common confusion pairs
  /// observed in handwriting OCR.
  ///
  /// Applied ONLY to short answers (not MCQ letters which are single chars).
  /// Does NOT apply to True/False words or single-letter answers.
  ///
  /// Only applies corrections when BOTH the original and corrected words
  /// lack common vowels — this avoids destroying real words like "runner".
  static String _correctOcrErrors(String text) {
    if (text.length <= 2) return text; // Don't correct single letters/numbers

    // Don't correct True/False words — they're handled by normalizeAnswer
    final lower = text.toLowerCase();
    if (lower == 'true' || lower == 'false' || lower == 'yes' || lower == 'no') {
      return text;
    }

    // Don't apply letter-pair corrections to real words.
    // The fuzzy matching in ScoringService already handles these cases.
    // These corrections are only useful for very garbled text where no
    // real word is formed — e.g., "rnner" → "mner" (still garbled but
    // closer to what the student wrote). In practice, the risk of
    // destroying real words ("runner" → "munner") outweighs the benefit.

    return text;
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
    final tokens = text
        .split(RegExp(r'[\s,]+'))
        .where((t) => t.isNotEmpty)
        .toList();

    if (tokens.length < 2) return null;

    // All tokens must be single letters
    final allSingleLetters = tokens.every(
      (t) => RegExp(r'^[a-zA-Z]$').hasMatch(t),
    );
    if (!allSingleLetters) return null;

    // At least one letter beyond E (F-Z) → likely matching, not MCQ
    final hasNonMcq = tokens.any((t) => RegExp(r'^[f-zF-Z]$').hasMatch(t));
    final isMatchingPattern = hasNonMcq;

    if (!isMatchingPattern) return null;

    // Normalize to uppercase, join with dashes
    final normalized = tokens.map((t) => t.toUpperCase()).join('-');
    return 'MATCH:$normalized';
  }

  /// Check if a string contains Amharic (Ge'ez) characters.
  /// Unicode range for Ge'ez: U+1200 to U+137F
  static bool containsAmharic(String text) {
    return RegExp(r'[\u1200-\u137F]').hasMatch(text);
  }

  /// Normalize Amharic text for comparison.
  /// Handles common OCR misreads and Unicode normalization.
  static String normalizeAmharic(String text) {
    return text
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^\u1200-\u137Fa-zA-Z0-9\s]'), '');
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
            rawText: region.text,
          ),
        );
      }
    }

    return answers;
  }

  /// Parse answers with context from the assessment's question types.
  ///
  /// Uses the assessment's question types to:
  /// 1. Filter out clearly wrong answer formats (e.g., text answer for MCQ question)
  /// 2. Adjust confidence based on format match
  /// 3. Accept alternative formats (e.g., "Yes"/"No" for True/False questions)
  ///
  /// Takes pre-parsed answers to avoid double-parsing.
  List<ParsedAnswer> parseAnswersWithContext(
    List<ParsedAnswer> rawAnswers, {
    required Map<int, String> questionTypes, // questionNumber → questionType
  }) {
    final filtered = <ParsedAnswer>[];

    for (final answer in rawAnswers) {
      final qType = questionTypes[answer.questionNumber];
      if (qType == null) {
        // No context for this question — keep as-is
        filtered.add(answer);
        continue;
      }

      // Check if answer format matches expected question type
      final isFormatMatch = _isAnswerFormatCompatible(answer.answer, qType);
      if (isFormatMatch) {
        // Format matches — boost confidence slightly
        filtered.add(ParsedAnswer(
          questionNumber: answer.questionNumber,
          answer: answer.answer,
          confidence: (answer.confidence + 0.1).clamp(0.0, 1.0),
          rawText: answer.rawText,
        ));
      } else {
        // Format doesn't match — keep but with reduced confidence
        // (might be OCR error, but don't discard entirely)
        filtered.add(ParsedAnswer(
          questionNumber: answer.questionNumber,
          answer: answer.answer,
          confidence: (answer.confidence * 0.7).clamp(0.0, 1.0),
          rawText: answer.rawText,
        ));
      }
    }

    return filtered;
  }

  /// Check if an answer format is compatible with the expected question type.
  bool _isAnswerFormatCompatible(String answer, String questionType) {
    final lower = answer.toLowerCase();

    switch (questionType) {
      case 'mcq':
        // MCQ should be a single letter A-E, or multi-letter like "A,C" or "A,B,C"
        return RegExp(r'^[a-eA-E](,[a-eA-E])*$').hasMatch(answer) ||
               RegExp(r'^[a-eA-E]$').hasMatch(lower);

      case 'trueFalse':
        // True/False should be T/F, True/False, Yes/No
        return lower == 'true' || lower == 'false' ||
               lower == 't' || lower == 'f' ||
               lower == 'yes' || lower == 'no' ||
               lower == 'y' || lower == 'n' ||
               answer == 'እውነት' || answer == 'ሐሰት';

      case 'shortAnswer':
        // Short answer: any text 1-80 chars, numbers, or formulas
        return answer.isNotEmpty && answer.length <= 80;

      case 'matching':
        // Matching: letter sequences like "A,B" or "G D"
        return RegExp(r'^[a-gA-G](,[a-gA-G])*$').hasMatch(answer) ||
               RegExp(r'^[a-gA-G](\s[a-gA-G])+$').hasMatch(answer);

      default:
        return true; // Unknown type — accept anything
    }
  }

  /// Get the dominant question type from an assessment's questions.
  /// Returns null if no questions or mixed types.
  static String? getDominantQuestionType(List<dynamic> questions) {
    if (questions.isEmpty) return null;

    final typeCounts = <String, int>{};
    for (final q in questions) {
      final type = q.type.toString().split('.').last;
      typeCounts[type] = (typeCounts[type] ?? 0) + 1;
    }

    if (typeCounts.isEmpty) return null;

    // Return the most common type if it's > 50% of questions
    final sorted = typeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final dominant = sorted.first;
    if (dominant.value > questions.length * 0.5) {
      return dominant.key;
    }

    return null; // Mixed types — no dominant type
  }

  /// Parse answers from all OCR text regions with spatial awareness.
  ///
  /// Three passes, in strict priority order:
  ///
  /// 1. **Standard (authoritative)** — same-line formats like
  ///    "16. Addis Ababa". Never overridden by spatial passes.
  /// 2. **Horizontal spatial** — a bare question number with the answer on
  ///    the same visual line but detected as a separate region.
  /// 3. **Vertical spatial** — a bare question number with the handwritten
  ///    answer on a following line (students rarely repeat numbers inside
  ///    answer boxes). Conservative guards:
  ///    - anchor must be ONLY a question number ("16", "16.")
  ///    - candidate strictly below within [maxGapBelow], horizontally near
  ///      the anchor column (within [_maxDxForBelowAssociation])
  ///    - candidate must normalize to a plausible answer and must NOT be a
  ///      numbered line belonging to another question
  ///    - nearest candidate wins; consumed candidates are never reused
  ///
  /// [regions] — all OCR text lines with positions and confidence.
  /// [maxGap] — max vertical pixel gap to consider lines "on the same line".
  ///   Default 20px works for enhanced 2000px images.
  /// [maxGapBelow] — max vertical pixel gap between a bare question number
  ///   and its answer below. Default 90px (~13mm on an A4 photo scaled to
  ///   2000px). Associations made here carry `spatialAssociation: true`.
  ///
  /// Returns parsed answers with question numbers inferred from position.
  List<ParsedAnswer> parseAnswersWithPosition(
    List<TextRegionInput> regions, {
    double maxGap = 20.0,
    double maxGapBelow = 90.0,
  }) {
    // First pass: try standard parsing on each line
    final standardAnswers = parseAnswers(regions);
    final answeredQs = standardAnswers.map((a) => a.questionNumber).toSet();

    // Sort regions by Y position (top to bottom); keep indexes so both
    // spatial passes share consumption tracking without double-claiming.
    final sortedRegions = List<TextRegionInput>.from(regions)
      ..sort((a, b) => a.y.compareTo(b.y));

    final consumed = <int>{};
    for (int i = 0; i < sortedRegions.length; i++) {
      if (parseQuestionAnswer(sortedRegions[i].text) != null) {
        consumed.add(i);
      }
    }

    // Second pass: group regions into horizontal lines (same Y within
    // maxGap) and attach answers sitting next to a bare question number.
    final lines = <List<int>>[];
    for (int i = 0; i < sortedRegions.length; i++) {
      if (lines.isEmpty) {
        lines.add([i]);
        continue;
      }
      final lastLine = lines.last;
      if ((sortedRegions[i].y - sortedRegions[lastLine.first].y).abs() <=
          maxGap) {
        lastLine.add(i);
      } else {
        lines.add([i]);
      }
    }

    final spatialAnswers = <ParsedAnswer>[];

    for (final line in lines) {
      if (line.length < 2) continue;

      // Sort left to right
      final byX = List<int>.from(line)
        ..sort((a, b) => sortedRegions[a].x.compareTo(sortedRegions[b].x));

      // Check if first element is a question number
      final firstText = sortedRegions[byX.first].text.trim();
      final qMatch = RegExp(r'^(\d+)\s*[.\-):]?$').firstMatch(firstText);
      if (qMatch == null) continue;

      final qNum = int.tryParse(qMatch.group(1)!);
      if (qNum == null || qNum <= 0 || qNum > 200) continue;
      if (answeredQs.contains(qNum)) continue;

      // Try each remaining element on this line as the answer
      for (int j = 1; j < byX.length; j++) {
        final idx = byX[j];
        if (consumed.contains(idx)) continue;
        final answerText = sortedRegions[idx].text.trim();
        final normalized = normalizeAnswer(answerText);
        if (normalized.isNotEmpty) {
          spatialAnswers.add(
            ParsedAnswer(
              questionNumber: qNum,
              answer: normalized,
              confidence: sortedRegions[idx].confidence,
              rawText:
                  '${sortedRegions[byX.first].text} ${sortedRegions[idx].text}',
              spatialAssociation: true,
            ),
          );
          answeredQs.add(qNum);
          consumed.add(idx);
          break;
        }
      }
    }

    // Third pass: vertical association — bare number with the answer on a
    // following line. See doc comment for the guard rails.
    final verticalAnswers = _associateAnswersBelow(
      sortedRegions: sortedRegions,
      consumed: consumed,
      answeredQs: answeredQs,
      maxGapBelow: maxGapBelow,
    );

    return [...standardAnswers, ...spatialAnswers, ...verticalAnswers];
  }

  /// Maximum horizontal distance between a bare question-number anchor and
  /// a candidate answer below it, in pixels of the enhanced image.
  /// ~48mm at A4/2000px scale — wide enough for indented handwriting,
  /// narrow enough to resist grabbing the neighbouring column.
  static const double _maxDxForBelowAssociation = 320.0;

  /// Vertical (below-the-number) association pass. See
  /// [parseAnswersWithPosition] for the guard rails.
  ///
  /// Non-numeric candidates are preferred over pure-digit ones so a column
  /// of question numbers ("16 / 17 / 18") does not chain-attach as fake
  /// numeric answers; a genuine numeric answer ("42") still attaches when
  /// no text candidate exists. Equal-distance ties are refused entirely.
  List<ParsedAnswer> _associateAnswersBelow({
    required List<TextRegionInput> sortedRegions,
    required Set<int> consumed,
    required Set<int> answeredQs,
    required double maxGapBelow,
  }) {
    final verticalAnswers = <ParsedAnswer>[];

    ({int idx, double dy})? findBest(
      int anchorIdx,
      String anchorText, {
      required bool allowPureNumeric,
    }) {
      int? best;
      double bestDy = 0;
      for (int j = 0; j < sortedRegions.length; j++) {
        if (j == anchorIdx || consumed.contains(j)) continue;
        final cand = sortedRegions[j];
        final dy = cand.y - sortedRegions[anchorIdx].y;
        if (dy <= 0 || dy > maxGapBelow) continue;
        final dx = (cand.x - sortedRegions[anchorIdx].x).abs();
        if (dx > _maxDxForBelowAssociation) continue;

        final trimmed = cand.text.trim();

        // A numbered line below belongs to its own question — never steal it.
        if (parseQuestionAnswer(trimmed) != null) continue;

        // Noise guard: must normalize to a plausible answer.
        final normalized = normalizeAnswer(trimmed);
        if (normalized.isEmpty) continue;

        // Prefer words/phrases over bare digits when both exist.
        if (!allowPureNumeric && RegExp(r'^\d+$').hasMatch(normalized)) {
          continue;
        }

        if (best == null || dy < bestDy) {
          best = j;
          bestDy = dy;
        } else if (dy == bestDy) {
          // Two candidates equally near — refuse to guess.
          return null;
        }
      }
      return best == null ? null : (idx: best, dy: bestDy);
    }

    for (int i = 0; i < sortedRegions.length; i++) {
      if (consumed.contains(i)) continue;

      // Anchor must be ONLY a bare question number ("16", "16.", "16)").
      final anchorText = sortedRegions[i].text.trim();
      final m = RegExp(r'^(\d{1,3})\s*[.\-):]?$').firstMatch(anchorText);
      if (m == null) continue;
      final qNum = int.tryParse(m.group(1)!);
      if (qNum == null || qNum <= 0 || qNum > 200) continue;
      if (answeredQs.contains(qNum)) continue;

      final pick =
          findBest(i, anchorText, allowPureNumeric: false) ??
          findBest(i, anchorText, allowPureNumeric: true);
      if (pick == null) continue;

      final chosen = sortedRegions[pick.idx];
      verticalAnswers.add(
        ParsedAnswer(
          questionNumber: qNum,
          answer: normalizeAnswer(chosen.text.trim()),
          confidence: chosen.confidence,
          rawText: '$anchorText ${chosen.text}',
          spatialAssociation: true,
        ),
      );
      answeredQs.add(qNum);
      consumed.add(pick.idx);
    }

    return verticalAnswers;
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

  /// True when the question number was associated positionally rather than
  /// read from the same OCR line as the answer. Spatial associations are
  /// inherently less certain and are flagged so the grading pipeline can
  /// route them through teacher review.
  final bool spatialAssociation;

  const ParsedAnswer({
    required this.questionNumber,
    required this.answer,
    required this.confidence,
    required this.rawText,
    this.spatialAssociation = false,
  });
}
