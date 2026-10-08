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
  ///
  /// Binary comparator: true = match, false = no match. It deliberately
  /// knows NOTHING about review policy — callers that need three-way
  /// semantics (CORRECT / INCORRECT / NEEDS REVIEW) must combine it with
  /// [isFuzzyOnlyMatch]. See the Phase 1.1 policy in HybridGradingService:
  /// a fuzzy-only short-answer match must not silently award CORRECT.
  bool checkAnswer({
    required dynamic detected,
    required dynamic correct,
    required QuestionType type,
  }) {
    if (detected == null || correct == null) return false;

    final detectedStr = detected.toString().trim();

    // Handle BLANK and UNREADABLE — always wrong
    if (detectedStr.toUpperCase() == 'BLANK' ||
        detectedStr.toUpperCase() == 'UNREADABLE') {
      return false;
    }

    if (type == QuestionType.mcq || type == QuestionType.trueFalse) {
      final detectedNorm = _normalizeWhitespace(detectedStr).toUpperCase();
      final correctStr = correct.toString();

      // T/F aliases: T=True, F=False
      final expandedDetected = _expandTfAlias(detectedNorm);
      final expandedCorrect = _expandTfAlias(
        _normalizeWhitespace(correctStr).toUpperCase(),
      );

      // Support multiple correct answers: "A,C" or List ["A", "C"]
      if (correct is List) {
        return correct.any((c) {
          final cExpanded = _expandTfAlias(
            _normalizeWhitespace(c.toString()).toUpperCase(),
          );
          return cExpanded == expandedDetected;
        });
      }

      // Support comma-separated answers: "A,C" matches "A" or "C" or "A,C"
      if (correctStr.contains(',')) {
        final correctOptions = correctStr
            .split(',')
            .map((s) => _expandTfAlias(s.trim().toUpperCase()))
            .toList();
        return correctOptions.contains(expandedDetected);
      }

      return expandedDetected == expandedCorrect;
    }

    if (type == QuestionType.matching) {
      return _checkMatchingAnswer(detectedStr, correct.toString());
    }

    if (type == QuestionType.multiAnswer) {
      // Multi-answer: correct is "A,C" — student must select ALL correct letters
      final detectedNorm = detectedStr.toUpperCase().replaceAll(
        RegExp(r'\s+'),
        '',
      );
      final correctStr = correct.toString();
      final correctLetters = correctStr
          .split(',')
          .map((s) => s.trim().toUpperCase())
          .toSet();
      // Student answer could be "A,C" or "AC" or individual detected letters
      final studentLetters = detectedNorm
          .split(RegExp(r'[,+]+'))
          .map((s) => s.trim().toUpperCase())
          .where((s) => s.isNotEmpty)
          .toSet();
      return correctLetters.isNotEmpty &&
          studentLetters.containsAll(correctLetters);
    }

    if (type == QuestionType.shortAnswer) {
      // Enhanced normalization: lowercase, trim, convert number words, normalize units
      final detectedNorm = _normalizeForComparison(detectedStr);
      if (correct is List) {
        // Normalize all correct answers
        final normalizedCorrects = correct.map((c) => _normalizeForComparison(c.toString())).toList();

        // Exact match first
        final exactMatch = normalizedCorrects.any((c) => c == detectedNorm);
        if (exactMatch) return true;

        // Spell-check: correct single-character OCR errors
        final spellCorrected = _spellCorrect(detectedNorm, correct.map((c) => c.toString()).toList());
        if (normalizedCorrects.contains(spellCorrected)) return true;

        // Semantic match (synonyms)
        final semanticMatch = normalizedCorrects.any((c) => _semanticMatch(detectedNorm, c));
        if (semanticMatch) return true;

        // Stem match: "jumping" = "jump", "walked" = "walk"
        final stemMatch = normalizedCorrects.any((c) =>
          detectedNorm.split(RegExp(r'\s+')).length == 1 &&
          c.split(RegExp(r'\s+')).length == 1 &&
          _stemMatch(detectedNorm, c));
        if (stemMatch) return true;

        // Fuzzy match for each option
        return normalizedCorrects.any((c) => _fuzzyMatch(detectedNorm, c));
      }
      final correctNorm = _normalizeForComparison(correct.toString());
      // Exact match first
      if (detectedNorm == correctNorm) return true;

      // Spell-check
      final spellCorrected = _spellCorrect(detectedNorm, [correct.toString()]);
      if (_normalizeWhitespace(spellCorrected) == _normalizeWhitespace(correctNorm)) return true;

      // Semantic match
      if (_semanticMatch(detectedNorm, correctNorm)) return true;

      // Stem match: "jumping" = "jump", "walked" = "walk"
      if (detectedNorm.split(RegExp(r'\s+')).length == 1 &&
          correctNorm.split(RegExp(r'\s+')).length == 1) {
        if (_stemMatch(detectedNorm, correctNorm)) return true;
      }

      // Fuzzy match with Levenshtein distance tolerance
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
  /// Also supports word-level matching for multi-word answers.
  static bool _fuzzyMatch(String a, String b, {int tolerance = 2}) {
    if (a == b) return true;
    if (a.isEmpty || b.isEmpty) return false;

    // ── Word-level matching for multi-word answers ──
    // If both answers have multiple words, check if they share enough words
    final aWords = a.split(RegExp(r'\s+'));
    final bWords = b.split(RegExp(r'\s+'));
    if (aWords.length > 1 && bWords.length > 1) {
      // Count matching words (case-insensitive)
      int matchCount = 0;
      for (final aw in aWords) {
        for (final bw in bWords) {
          if (aw.toLowerCase() == bw.toLowerCase()) {
            matchCount++;
            break;
          }
        }
      }
      // If ≥50% of words match, consider it a match
      final maxWords = aWords.length > bWords.length ? aWords.length : bWords.length;
      if (matchCount >= (maxWords * 0.5).ceil()) return true;
    }

    // ── Character-level Levenshtein matching ──
    // Increased tolerance: 2 for short answers, 3 for longer answers
    final dynamicTolerance = a.length <= 5 ? tolerance : tolerance + 1;
    if ((a.length - b.length).abs() > dynamicTolerance) return false;
    return _levenshteinDistance(a, b) <= dynamicTolerance;
  }

  /// Whether [detected] and [correct] match ONLY via fuzzy tolerance —
  /// i.e. they differ after normalization but sit within Levenshtein
  /// distance [tolerance].
  ///
  /// Phase 1.1 policy (Option B): for short-answer questions, a fuzzy-only
  /// match is a recognition-uncertainty signal, not proof of correctness.
  /// The grading pipeline routes such answers to teacher review instead of
  /// silently awarding CORRECT. Exact normalized matches and clearly
  /// different answers never enter this path.
  ///
  /// Pure function; does not mutate or change [checkAnswer] semantics.
  static bool isFuzzyOnlyMatch(
    String detected,
    String correct, {
    int tolerance = 2,
  }) {
    final d = _normalizeForComparison(detected);
    final c = _normalizeForComparison(correct);
    if (d == c) return false; // exact — CORRECT, no review needed
    if (d.isEmpty || c.isEmpty) return false;

    // ── Word-level check ──
    //
    // The escape hatch exists for answers that are genuinely right but merely
    // gained or lost a word ("Addis Ababa Ethiopia" vs "Addis Ababa"). It must
    // require EVERY word of the shorter answer to be present. An earlier
    // version compared against the longer count with a 50% threshold, so
    // "Addis Abena" vs "Addis Ababa" escaped on the strength of "addis" alone
    // and a real two-character typo was auto-marked CORRECT.
    final dWords = d.split(RegExp(r'\s+'));
    final cWords = c.split(RegExp(r'\s+'));
    if (dWords.length > 1 && cWords.length > 1) {
      int matchCount = 0;
      for (final dw in dWords) {
        for (final cw in cWords) {
          if (dw.toLowerCase() == cw.toLowerCase()) {
            matchCount++;
            break;
          }
        }
      }
      final shorterWords =
          dWords.length < cWords.length ? dWords.length : cWords.length;
      if (matchCount >= shorterWords) return false;
    }

    // ── Semantic check ──
    if (_semanticMatch(d, c)) return false; // Synonyms — not fuzzy-only

    // ── Character-level Levenshtein check ──
    final dynamicTolerance = d.length <= 5 ? tolerance : tolerance + 1;
    if ((d.length - c.length).abs() > dynamicTolerance) return false;
    return _levenshteinDistance(d, c) <= dynamicTolerance;
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
          prev[j] + 1, // deletion
          curr[j - 1] + 1, // insertion
          prev[j - 1] + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
      final temp = prev;
      prev = curr;
      curr = temp;
    }
    return prev[bLen];
  }

  // ── Number Word Recognition ──

  /// Convert number words to digits: "forty two" → "42"
  /// Returns the original text if it can't be fully converted.
  static String _wordsToNumber(String text) {
    const numberWords = {
      'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4,
      'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9,
      'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13,
      'fourteen': 14, 'fifteen': 15, 'sixteen': 16, 'seventeen': 17,
      'eighteen': 18, 'nineteen': 19, 'twenty': 20, 'thirty': 30,
      'forty': 40, 'fifty': 50, 'sixty': 60, 'seventy': 70,
      'eighty': 80, 'ninety': 90, 'hundred': 100, 'thousand': 1000,
    };

    final words = text.toLowerCase().split(RegExp(r'\s+'));
    int total = 0;
    int current = 0;
    bool hasNumberWord = false;
    bool hasNonNumberWord = false;

    for (final word in words) {
      if (numberWords.containsKey(word)) {
        hasNumberWord = true;
        final val = numberWords[word]!;
        if (val == 100 || val == 1000) {
          current = current == 0 ? val : current * val;
        } else {
          current += val;
        }
      } else if (word == 'and' && hasNumberWord) {
        continue; // Skip "and" in "one hundred and twenty"
      } else {
        // Non-number word — track it but don't bail
        hasNonNumberWord = true;
      }
    }

    if (!hasNumberWord) return text;

    total += current;

    // If there were non-number words (like units), reconstruct with the number
    if (hasNonNumberWord) {
      // Replace number words with digits, keep other words
      final result = <String>[];
      int numAccum = 0;
      bool inNumber = false;
      for (final word in words) {
        if (numberWords.containsKey(word) || word == 'and') {
          inNumber = true;
          if (word != 'and') {
            final val = numberWords[word]!;
            if (val == 100 || val == 1000) {
              numAccum = numAccum == 0 ? val : numAccum * val;
            } else {
              numAccum += val;
            }
          }
        } else {
          if (inNumber && numAccum > 0) {
            result.add(numAccum.toString());
            numAccum = 0;
            inNumber = false;
          }
          result.add(word);
        }
      }
      if (inNumber && numAccum > 0) {
        result.add(numAccum.toString());
      }
      return result.join(' ');
    }

    return total.toString();
  }

  /// Normalize answer for comparison: lowercase, trim, collapse whitespace,
  /// convert number words to digits, normalize units.
  static String _normalizeForComparison(String text) {
    var result = _normalizeWhitespace(text);

    // Convert number words to digits
    result = _wordsToNumber(result);

    // Normalize units: "42 km" = "42km"
    result = result.replaceAll(RegExp(r'(\d)\s+(km|cm|mm|kg|g|mg|l|ml|°c|°f|m|s)'), r'$1$2');

    return result;
  }

  // ── Spell-Check for Short Answers ──

  /// Correct single-character OCR errors using the answer key.
  /// If detected is within Levenshtein distance 1 of a valid answer,
  /// return the canonical answer.
  static String _spellCorrect(String detected, List<String> validAnswers) {
    final normalized = _normalizeWhitespace(detected);
    for (final answer in validAnswers) {
      final normalizedAnswer = _normalizeWhitespace(answer);
      if (_levenshteinDistance(normalized.toLowerCase(), normalizedAnswer.toLowerCase()) <= 1) {
        return normalizedAnswer; // Return the canonical answer
      }
    }
    return detected;
  }

  // ── Semantic Similarity (Synonyms) ──

  /// Common English synonyms for short answer matching.
  static const Map<String, List<String>> _synonyms = {
    'big': ['large', 'huge', 'enormous', 'vast'],
    'small': ['tiny', 'little', 'minute', 'petite'],
    'fast': ['quick', 'rapid', 'swift', 'speedy'],
    'slow': ['sluggish', 'lethargic', 'gradual'],
    'happy': ['glad', 'joyful', 'pleased', 'delighted'],
    'sad': ['unhappy', 'sorrowful', 'gloomy'],
    'hot': ['warm', 'heated', 'boiling'],
    'cold': ['cool', 'chilly', 'freezing'],
    'good': ['excellent', 'fine', 'great', 'wonderful'],
    'bad': ['poor', 'terrible', 'awful'],
    'important': ['significant', 'crucial', 'vital', 'essential'],
    'different': ['distinct', 'diverse', 'various'],
    'same': ['identical', 'similar', 'equivalent'],
    'begin': ['start', 'commence', 'initiate'],
    'end': ['finish', 'conclude', 'terminate'],
    'help': ['assist', 'support', 'aid'],
    'make': ['create', 'produce', 'construct'],
    'give': ['provide', 'supply', 'deliver'],
    'take': ['grab', 'seize', 'capture'],
    'go': ['move', 'travel', 'proceed'],
    'come': ['arrive', 'approach', 'reach'],
  };

  /// Check if two words are synonyms.
  static bool _areSynonyms(String a, String b) {
    final la = a.toLowerCase();
    final lb = b.toLowerCase();
    if (la == lb) return true;

    for (final entry in _synonyms.entries) {
      final key = entry.key;
      final values = entry.value;
      if (key == la && values.contains(lb)) return true;
      if (key == lb && values.contains(la)) return true;
      if (values.contains(la) && values.contains(lb)) return true;
    }
    return false;
  }

  /// Semantic match: check if answers are synonyms.
  static bool _semanticMatch(String a, String b) {
    final aWords = a.toLowerCase().split(RegExp(r'\s+'));
    final bWords = b.toLowerCase().split(RegExp(r'\s+'));

    if (aWords.length == 1 && bWords.length == 1) {
      return _areSynonyms(aWords[0], bWords[0]);
    }

    // Multi-word: check if any word in A is a synonym of any word in B
    int matchCount = 0;
    for (final aw in aWords) {
      for (final bw in bWords) {
        if (_areSynonyms(aw, bw)) {
          matchCount++;
          break;
        }
      }
    }

    // Require EVERY word of the shorter answer to be covered. Using the longer
    // count with a 50% threshold let a single shared word certify the whole
    // answer: "Addis Abena" vs "Addis Ababa" counted "addis" (identical, so a
    // synonym of itself) as half a match and was treated as equivalent, hiding
    // a real two-character typo.
    final shorterWords =
        aWords.length < bWords.length ? aWords.length : bWords.length;
    return matchCount >= shorterWords;
  }

  // ── Light Stemming for Verb Forms ──

  /// Strip common English verb suffixes to get the base form.
  /// Handles: -ing, -ed, -s, -es, -ies, -ly, -ment, -tion, -ness
  static String _lightStem(String word) {
    if (word.length <= 3) return word; // Don't stem short words

    var result = word.toLowerCase();

    // -ing: running → run, making → make, jumping → jump
    if (result.endsWith('ing') && result.length > 5) {
      result = result.substring(0, result.length - 3);
      // Double consonant: running → run (remove extra consonant)
      if (result.length >= 2 && result[result.length - 1] == result[result.length - 2]) {
        result = result.substring(0, result.length - 1);
      }
      // Only add 'e' for CVC stems where the vowel would be lost:
      // "mak" → "make", "hop" → "hope", but NOT "run" or "jump"
      if (result.length >= 3 && _needsFinalE(result)) {
        result += 'e';
      }
      return result;
    }

    // -ed: jumped → jump, played → play, cared → care
    if (result.endsWith('ed') && result.length > 4) {
      result = result.substring(0, result.length - 2);
      // Double consonant: stopped → stop (remove extra consonant)
      if (result.length >= 2 && result[result.length - 1] == result[result.length - 2]) {
        result = result.substring(0, result.length - 1);
      }
      // Only add 'e' for CVC stems where the vowel would be lost
      if (result.length >= 3 && _needsFinalE(result)) {
        result += 'e';
      }
      return result;
    }

    // -s/-es: jumps → jump, watches → watch, boxes → box
    if (result.endsWith('ies') && result.length > 4) {
      return '${result.substring(0, result.length - 3)}y';
    }
    if (result.endsWith('es') && result.length > 4) {
      result = result.substring(0, result.length - 2);
      // Only keep 'e' if stem needs it for pronunciation
      if (result.endsWith('s') || result.endsWith('x') || result.endsWith('z') ||
          result.endsWith('h') || result.endsWith('c')) {
        return result; // "boxes" → "box" (no extra e)
      }
      return result;
    }
    if (result.endsWith('s') && result.length > 3 && !result.endsWith('ss')) {
      return result.substring(0, result.length - 1);
    }

    // -ly: quickly → quick
    if (result.endsWith('ly') && result.length > 4) {
      return result.substring(0, result.length - 2);
    }

    // -ment: movement → move
    if (result.endsWith('ment') && result.length > 6) {
      result = result.substring(0, result.length - 4);
      if (result.length >= 3 && _needsFinalE(result)) result += 'e';
      return result;
    }

    // -tion: creation → create
    if (result.endsWith('tion') && result.length > 6) {
      result = result.substring(0, result.length - 4);
      if (result.length >= 3 && _needsFinalE(result)) result += 'e';
      return result;
    }

    // -ness: happiness → happy
    if (result.endsWith('ness') && result.length > 6) {
      return result.substring(0, result.length - 4);
    }

    return result;
  }

  /// Check if a stem needs a final 'e' for pronunciation.
  /// Returns true for CVC (consonant-vowel-consonant) patterns like
  /// "mak" → "make", "hop" → "hope", but NOT for "run", "jump", "play".
  static bool _needsFinalE(String stem) {
    if (stem.length < 3) return false;
    final last = stem[stem.length - 1];
    final secondLast = stem[stem.length - 2];
    final thirdLast = stem[stem.length - 3];

    // Must end in a consonant
    if ('aeiou'.contains(last)) return false;
    // Second-to-last must be a vowel (CVC pattern)
    if (!'aeiou'.contains(secondLast)) return false;
    // Third-to-last must be a consonant (CVC, not CCVC like "jump")
    if ('aeiou'.contains(thirdLast)) return false;
    // Don't add 'e' to very short stems
    if (stem.length <= 3) return false;

    return true;
  }

  /// Check if two words have the same stem.
  static bool _stemMatch(String a, String b) {
    return _lightStem(a) == _lightStem(b);
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
    final parts = working
        .split(RegExp(r'[-\s,]+'))
        .where((p) => p.isNotEmpty)
        .toList();

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
            confidence: 0,
          ),
        );
        continue;
      }

      final isCorrect = checkAnswer(
        detected: detectedAnswer.answer,
        correct: question.correctAnswer,
        type: question.type,
      );

      matches.add(
        AnswerMatch(
          questionNumber: question.number,
          detectedAnswer: detectedAnswer.answer,
          correctAnswer: question.correctAnswer?.toString() ?? '',
          isCorrect: isCorrect,
          score: isCorrect ? question.points : 0,
          maxScore: question.points,
          confidence: detectedAnswer.confidence,
          ocrRawText: detectedAnswer.rawText,
        ),
      );
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
    final unassigned = questions
        .where((q) => !questionToComponent.containsKey(q.number))
        .toList();

    if (unassigned.isNotEmpty) {
      final totalWeight = scale.components.fold(0.0, (s, c) => s + c.weight);
      int assignedCount = 0;
      for (int c = 0; c < scale.components.length; c++) {
        final proportion = totalWeight > 0
            ? scale.components[c].weight / totalWeight
            : 1.0 / scale.components.length;
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
            AnswerDuplicate(scanIndexA: i, scanIndexB: j, matchRatio: ratio),
          );
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
  final bool needsReview;
  final String source;

  const DetectedAnswer({
    required this.questionNumber,
    required this.answer,
    required this.confidence,
    required this.rawText,
    this.needsReview = false,
    this.source = 'unknown',
  });

  DetectedAnswer copyWith({
    int? questionNumber,
    String? answer,
    double? confidence,
    String? rawText,
    bool? needsReview,
    String? source,
  }) {
    return DetectedAnswer(
      questionNumber: questionNumber ?? this.questionNumber,
      answer: answer ?? this.answer,
      confidence: confidence ?? this.confidence,
      rawText: rawText ?? this.rawText,
      needsReview: needsReview ?? this.needsReview,
      source: source ?? this.source,
    );
  }
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
