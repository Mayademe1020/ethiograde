import '../models/student.dart';
import 'roster_parser.dart';

/// Result of trying to match a scanned name to a class list.
class MatchResult {
  final Student? matchedStudent;
  final String scannedName;
  final double confidence;
  final List<Student> similarStudents;
  final bool isAmbiguous; // Multiple close matches

  const MatchResult({
    this.matchedStudent,
    required this.scannedName,
    this.confidence = 0,
    this.similarStudents = const [],
    this.isAmbiguous = false,
  });

  bool get hasMatch => matchedStudent != null;
  bool get needsReview => !hasMatch || isAmbiguous;
}

/// Computes Levenshtein edit distance between two strings.
int _levenshtein(String a, String b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final matrix = List.generate(
    a.length + 1,
    (i) => List.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    matrix[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    matrix[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      matrix[i][j] = [
        matrix[i - 1][j] + 1,
        matrix[i][j - 1] + 1,
        matrix[i - 1][j - 1] + cost,
      ].reduce((a, b) => a < b ? a : b);
    }
  }
  return matrix[a.length][b.length];
}

/// Returns similarity score 0.0–1.0 between two strings (case-insensitive).
double _similarity(String a, String b) {
  final la = a.toLowerCase().trim();
  final lb = b.toLowerCase().trim();
  if (la.isEmpty && lb.isEmpty) return 1.0;
  if (la.isEmpty || lb.isEmpty) return 0.0;
  final maxLen = la.length > lb.length ? la.length : lb.length;
  return 1.0 - (_levenshtein(la, lb) / maxLen);
}

/// Matches OCR-scanned student names to a class list.
///
/// Combines name + student ID matching for disambiguation.
class StudentMatcher {
  /// Match a scanned name against a list of class students.
  ///
  /// Returns a [MatchResult] with the best match, similar candidates,
  /// and confidence score.
  static MatchResult matchName(
    String scannedName,
    List<Student> classStudents) {
    if (scannedName.trim().isEmpty || classStudents.isEmpty) {
      return MatchResult(scannedName: scannedName);
    }

    final normalized = scannedName.toLowerCase().trim();

    // ── 1. Try exact match ──────────────────
    final exactMatches = <Student>[];
    for (final s in classStudents) {
      if (normalized == s.fullName.toLowerCase().trim()) {
        exactMatches.add(s);
      }
    }

    if (exactMatches.length == 1) {
      return MatchResult(
        matchedStudent: exactMatches.first,
        scannedName: scannedName,
        confidence: 1.0);
    }

    if (exactMatches.length > 1) {
      return MatchResult(
        scannedName: scannedName,
        confidence: 1.0,
        similarStudents: exactMatches,
        isAmbiguous: true);
    }

    // ── 2. Try matching first name only ──────────────────
    final scannedFirst = scannedName.trim().split(RegExp(r'\s+')).first.toLowerCase();
    final firstNameMatches = <Student>[];
    for (final s in classStudents) {
      if (scannedFirst == s.firstName.toLowerCase()) {
        firstNameMatches.add(s);
      }
    }

    if (firstNameMatches.length == 1) {
      return MatchResult(
        matchedStudent: firstNameMatches.first,
        scannedName: scannedName,
        confidence: 0.85);
    }

    // ── 3. Try fuzzy match (similarity > 0.5) ─────────────────────
    final scored = <_ScoredStudent>[];
    for (final s in classStudents) {
      final score = _similarity(normalized, s.fullName);
      if (score > 0.5) {
        scored.add(_ScoredStudent(s, score));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    if (scored.isEmpty) {
      return MatchResult(scannedName: scannedName);
    }

    if (scored.first.score >= 0.7) {
      final isAmbiguous =
          scored.length > 1 &&
          scored[1].score >= 0.7 &&
          (scored.first.score - scored[1].score) < 0.1;

      return MatchResult(
        matchedStudent: isAmbiguous ? null : scored.first.student,
        scannedName: scannedName,
        confidence: scored.first.score,
        similarStudents: scored.take(3).map((s) => s.student).toList(),
        isAmbiguous: isAmbiguous);
    }

    return MatchResult(
      scannedName: scannedName,
      confidence: scored.first.score,
      similarStudents: scored.take(3).map((s) => s.student).toList());
  }

  /// Match by student ID (exact, faster than name matching).
  static MatchResult matchById(String studentId, List<Student> classStudents) {
    if (studentId.trim().isEmpty || classStudents.isEmpty) {
      return const MatchResult(scannedName: '');
    }

    final matches = classStudents
        .where((s) => s.studentId.trim() == studentId.trim())
        .toList();

    if (matches.length == 1) {
      return MatchResult(
        matchedStudent: matches.first,
        scannedName: studentId,
        confidence: 1.0);
    }

    return MatchResult(scannedName: studentId);
  }

  /// Parse OCR text and try to match to class list.
  ///
  /// Precedence:
  /// 1. Exact student ID match (highest trust)
  /// 2. Exact full-name match within class
  /// 3. Unique normalized-name match within class
  /// 4. Fuzzy-name match only when confident and unambiguous
  /// 5. Manual teacher assignment (returned as needsReview)
  static MatchResult matchFromOcr(
    String ocrText,
    List<Student> classStudents, {
    String? assessmentClassId,
  }) {
    const parser = RosterParser();
    final parsed = parser.parse(ocrText);

    if (parsed.isEmpty) {
      return const MatchResult(scannedName: '');
    }

    // ── Priority 1: Exact student ID match (highest trust) ──
    for (final p in parsed) {
      if (p.studentId.isNotEmpty) {
        final idResult = matchById(p.studentId, classStudents);
        if (idResult.hasMatch) {
          return idResult;
        }
      }
    }

    // ── Priority 2: Exact full-name match ──
    for (final p in parsed) {
      final fullName = '${p.firstName} ${p.lastName}'.trim();
      if (fullName.isEmpty) continue;

      final exactMatches = classStudents
          .where((s) => _normalizeName(fullName) == _normalizeName(s.fullName))
          .toList();

      if (exactMatches.length == 1) {
        return MatchResult(
          matchedStudent: exactMatches.first,
          scannedName: fullName,
          confidence: 1.0,
        );
      }

      if (exactMatches.length > 1) {
        // Duplicate exact names — ambiguous, needs teacher
        return MatchResult(
          scannedName: fullName,
          confidence: 1.0,
          similarStudents: exactMatches,
          isAmbiguous: true,
        );
      }
    }

    // ── Priority 3: Unique normalized-name match ──
    for (final p in parsed) {
      final fullName = '${p.firstName} ${p.lastName}'.trim();
      if (fullName.isEmpty) continue;

      final normalizedName = _normalizeName(fullName);
      final nameMatches = classStudents
          .where((s) => _normalizeName(s.fullName) == normalizedName)
          .toList();

      if (nameMatches.length == 1) {
        return MatchResult(
          matchedStudent: nameMatches.first,
          scannedName: fullName,
          confidence: 0.95,
        );
      }

      if (nameMatches.length > 1) {
        // Duplicate normalized names — ambiguous
        return MatchResult(
          scannedName: fullName,
          confidence: 0.95,
          similarStudents: nameMatches,
          isAmbiguous: true,
        );
      }
    }

    // ── Priority 4: First-name-only match (unique within class) ──
    for (final p in parsed) {
      final scannedFirst = p.firstName.toLowerCase().trim();
      if (scannedFirst.isEmpty) continue;

      final firstNameMatches = classStudents
          .where((s) => s.firstName.toLowerCase().trim() == scannedFirst)
          .toList();

      if (firstNameMatches.length == 1) {
        return MatchResult(
          matchedStudent: firstNameMatches.first,
          scannedName: '${p.firstName} ${p.lastName}'.trim(),
          confidence: 0.85,
        );
      }

      if (firstNameMatches.length > 1) {
        // Multiple students with same first name — ambiguous
        return MatchResult(
          scannedName: '${p.firstName} ${p.lastName}'.trim(),
          confidence: 0.85,
          similarStudents: firstNameMatches,
          isAmbiguous: true,
        );
      }
    }

    // ── Priority 5: Fuzzy match (confidence >= 0.7, unambiguous) ──
    for (final p in parsed) {
      final fullName = '${p.firstName} ${p.lastName}'.trim();
      if (fullName.isEmpty) continue;

      final result = matchName(fullName, classStudents);
      if (result.hasMatch && result.confidence >= 0.7 && !result.isAmbiguous) {
        return result;
      }
    }

    // ── No match found — needs teacher assignment ──
    final first = parsed.first;
    return MatchResult(
      scannedName: '${first.firstName} ${first.lastName}'.trim(),
    );
  }

  /// Normalize a name for comparison: lowercase, trim, collapse whitespace.
  static String _normalizeName(String name) {
    return name.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Expose similarity for external use (e.g., StudentNotFoundDialog).
  static double similarity(String a, String b) => _similarity(a, b);
}

class _ScoredStudent {
  final Student student;
  final double score;
  const _ScoredStudent(this.student, this.score);
}
