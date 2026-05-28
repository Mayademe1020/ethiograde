import '../models/student.dart';

/// Parsed result from a single line of OCR text.
class ParsedStudent {
  final String studentId; // Roll number from prefix
  final String firstName;
  final String lastName; // Combined father + grandfather name
  final String gender; // 'M', 'F', or '' (unknown)
  final String rawLine; // Original OCR text for debugging
  final double confidence; // 0.0-1.0 based on parsing quality

  const ParsedStudent({
    this.studentId = '',
    required this.firstName,
    this.lastName = '',
    this.gender = '',
    this.rawLine = '',
    this.confidence = 1.0,
  });

  bool get isEmpty => firstName.trim().isEmpty;

  Student toStudent({String classId = ''}) => Student(
    studentId: studentId,
    firstName: firstName,
    lastName: lastName,
    gender: gender,
    classIds: classId.isNotEmpty ? [classId] : []);
}

/// Parses raw OCR text into a list of student names.
///
/// Handles these formats:
/// - Numbered: "1. አበበ ከበደ" or "1) Abebe Kebede"
/// - Table: "001 አበበ ከበደ ወንድ" (ID + name + gender)
/// - Simple: "አበበ ከበደ ተስፋዬ" (name only, 2-3 words)
/// - Attendance: "አበበ ✓" or "Abebe P/A"
///
/// Ethiopian naming convention: FirstName FatherName [GrandfatherName]
/// We accept 2 or 3 word names. If 3 words: first=FirstName,
/// last=FatherName+GrandfatherName. If 2 words: first=first, last=second.
class RosterParser {
  const RosterParser();

  /// Parse a block of OCR text into a list of students.
  List<ParsedStudent> parse(String ocrText) {
    final lines = ocrText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && l.length > 1)
        .toList();

    final results = <ParsedStudent>[];
    int autoIndex = 1;

    for (final line in lines) {
      final parsed = _parseLine(line, fallbackIndex: autoIndex);
      if (parsed != null && !parsed.isEmpty) {
        results.add(parsed);
        autoIndex++;
      }
    }

    return _deduplicate(results);
  }

  /// Parse a single line. Returns null if the line is garbage.
  ParsedStudent? _parseLine(String line, {required int fallbackIndex}) {
    // Skip pure noise lines
    if (_isNoise(line)) return null;

    var remaining = line;

    // ── 1. Try to extract roll number prefix ──────────────────────
    String rollNumber = '';
    final rollMatch = _rollNumberRegex.firstMatch(remaining);
    if (rollMatch != null) {
      // Regex has 3 capture groups — find the one that matched
      rollNumber =
          rollMatch.group(1) ?? rollMatch.group(2) ?? rollMatch.group(3) ?? '';
      remaining = remaining.substring(rollMatch.end).trim();
    }

    // ── 2. Try to extract trailing gender ─────────────────────────
    String gender = '';
    final genderResult = _extractGender(remaining);
    if (genderResult.gender.isNotEmpty) {
      gender = genderResult.gender;
      remaining = genderResult.remaining;
    }

    // ── 3. Try to extract attendance marks (✓, ✗, P, A, ተገኝ, ጠፋ) ──
    // Remove attendance marks from the end
    remaining = _stripAttendance(remaining);

    // ── 4. Extract name words ─────────────────────────────────────
    final nameWords = _extractNameWords(remaining);
    if (nameWords.isEmpty) return null;

    // ── 5. Split into first + last ────────────────────────────────
    String firstName;
    String lastName;
    if (nameWords.length >= 3) {
      firstName = nameWords[0];
      lastName = nameWords.sublist(1).join(' ');
    } else if (nameWords.length == 2) {
      firstName = nameWords[0];
      lastName = nameWords[1];
    } else {
      firstName = nameWords[0];
      lastName = '';
    }

    // ── 6. Confidence ─────────────────────────────────────────────
    double confidence = 1.0;
    if (rollNumber.isEmpty) confidence -= 0.1;
    if (gender.isEmpty) confidence -= 0.1;
    if (nameWords.length < 2) confidence -= 0.3;

    return ParsedStudent(
      studentId: rollNumber.isEmpty
          ? fallbackIndex.toString().padLeft(3, '0')
          : rollNumber,
      firstName: firstName,
      lastName: lastName,
      gender: gender,
      rawLine: line,
      confidence: confidence.clamp(0.0, 1.0));
  }

  // ── Roll number patterns ──────────────────────────────────────────
  // Matches: "1. ", "1) ", "001 ", "No.1 ", "ተ.ቁ 1 "
  static final _rollNumberRegex = RegExp(
    r'^(?:'
    r'(?:ተ\.?ቁ|No\.?|#)\s*(\d+)\s*[,.\-)\]]*\s*' // "ተ.ቁ 1" or "No.1"
    r'|(\d{1,4})\s*[.)\-]\s+' // "1. " or "1) " or "001- "
    r'|(\d{1,4})\s{1,}' // "001 " (number followed by space = column format)
    r')',
    unicode: true);

  // ── Gender detection ───────────────────────────────────────────────

  static const _maleWords = {
    'ወንድ',
    'ወ',
    'M',
    'm',
    'Male',
    'male',
    'MALE',
    'm.',
    ' đứ',
    'זכר',
  };

  static const _femaleWords = {
    'ሴት',
    'ሴ',
    'F',
    'f',
    'Female',
    'female',
    'FEMALE',
    'f.',
    'נקבה',
  };

  _GenderResult _extractGender(String text) {
    final words = text.split(RegExp(r'\s+'));
    final reversed = words.reversed.toList();

    // Check last 2 words for gender markers
    for (int i = 0; i < reversed.length && i < 2; i++) {
      final word = reversed[i].replaceAll(RegExp(r'[,;.\-)]+$'), '');
      if (_maleWords.contains(word)) {
        final remaining = words.take(words.length - 1 - i).join(' ').trim();
        return _GenderResult('M', remaining);
      }
      if (_femaleWords.contains(word)) {
        final remaining = words.take(words.length - 1 - i).join(' ').trim();
        return _GenderResult('F', remaining);
      }
    }
    return _GenderResult('', text);
  }

  // ── Attendance marks ───────────────────────────────────────────────

  static final _attendanceRegex = RegExp(
    r'\s*(?:✓|✗|✔|✘|[PApa]|ተገኝ|ጠፋ|ነበር|አልነበር|出席|缺席)\s*$',
    unicode: true);

  String _stripAttendance(String text) {
    return text.replaceAll(_attendanceRegex, '').trim();
  }

  // ── Name word extraction ───────────────────────────────────────────

  /// Extract words that look like name components.
  /// Filters out: numbers, single chars, common non-name tokens.
  List<String> _extractNameWords(String text) {
    final words = text.split(RegExp(r'\s+'));
    return words.where((w) {
      final clean = w.replaceAll(RegExp(r'[,;.\-()]+$'), '');
      if (clean.length < 2) return false;
      if (RegExp(r'^\d+$').hasMatch(clean)) return false;
      // Skip common OCR noise
      if (clean == 'ወንድ' || clean == 'ሴት') return false;
      return true;
    }).toList();
  }

  // ── Noise detection ────────────────────────────────────────────────

  static final _noisePatterns = [
    RegExp(r'^[-=—_]{3,}$'), // separator lines
    RegExp(r'^\d+\s*[-=]\s*$'), // "1 -" alone
    RegExp(
      r'^(ክፍል|Grade|Class|Section|ስም|Name|ተ\.ቁ|ID)[:/\s]*$',
      unicode: true),
    RegExp(r'^[^\w\u1200-\u137F]+$'), // no word chars or Ethiopic chars
  ];

  bool _isNoise(String line) {
    if (line.length < 2) return true;
    for (final pattern in _noisePatterns) {
      if (pattern.hasMatch(line)) return true;
    }
    return false;
  }

  // ── Deduplication ──────────────────────────────────────────────────

  List<ParsedStudent> _deduplicate(List<ParsedStudent> students) {
    final seen = <String>{};
    final result = <ParsedStudent>[];

    for (final s in students) {
      // Always use name as dedup key — fallback IDs are auto-generated
      // and meaningless for dedup. OCR-extracted IDs are part of the name
      // context anyway (same name + same ID = duplicate).
      final key = '${s.firstName.toLowerCase()}_${s.lastName.toLowerCase()}';
      if (!seen.contains(key)) {
        seen.add(key);
        result.add(s);
      }
    }
    return result;
  }
}

class _GenderResult {
  final String gender;
  final String remaining;
  const _GenderResult(this.gender, this.remaining);
}
