import '../models/assessment.dart';

/// Code string understood by the bulk-apply logic for a given question type.
String sectionTypeCode(QuestionType type) => switch (type) {
      QuestionType.mcq => 'MCQ',
      QuestionType.trueFalse => 'T/F',
      QuestionType.multiAnswer => 'MULTI',
      QuestionType.shortAnswer => 'SHORT',
      QuestionType.essay => 'SHORT',
      QuestionType.matching => 'MATCH',
    };

/// Section-aware parse: answers are mapped in order to the section's question
/// range and typed with the section's KNOWN type. No type inference happens,
/// so an MCQ section never silently reinterprets input as short-answer etc.
List<Map<String, dynamic>>? parseSectionBulkPaste(
  String raw,
  AnswerKeySection section,
) {
  if (raw.trim().isEmpty) return null;
  final parts = raw
      .split(RegExp(r'[,\s]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;

  final typeCode = sectionTypeCode(section.type);
  final results = <Map<String, dynamic>>[];
  for (var i = 0; i < parts.length; i++) {
    final qNum = section.start + i;
    if (qNum > section.end) break;
    results.add({
      'num': qNum,
      'answer': parts[i],
      'type': typeCode,
    });
  }
  return results.isEmpty ? null : results;
}

/// Global "Paste All" parse. Infers a per-answer type from its content so a
/// mixed-structure exam can be pasted in one go. Ambiguous tokens fall back to
/// SHORT (the preview always shows the inferred type, so nothing is applied
/// silently — the teacher reviews before tapping Apply).
List<Map<String, dynamic>>? parseBulkPaste(String raw, int expectedCount) {
  if (raw.trim().isEmpty) return null;
  final parts = raw
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;

  final results = <Map<String, dynamic>>[];
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    final qNum = i + 1;

    if (part == '—' || part == '-' || part.isEmpty) {
      continue;
    }

    // Quoted text → short answer
    if (part.startsWith('"') && part.endsWith('"')) {
      results.add({
        'num': qNum,
        'answer': part.substring(1, part.length - 1),
        'type': 'SHORT',
      });
      continue;
    }
    if (part.startsWith('"')) {
      results.add({
        'num': qNum,
        'answer': part.replaceAll('"', ''),
        'type': 'SHORT',
      });
      continue;
    }

    // Number+letter pairs → matching (e.g., "1C,2A,3D")
    if (RegExp(r'^\d+[A-E]').hasMatch(part)) {
      results.add({'num': qNum, 'answer': part, 'type': 'MATCH'});
      continue;
    }

    // Letters with + → multi-answer (e.g., "A+C")
    if (part.contains('+') &&
        RegExp(r'^[A-Ea-e]+(\+[A-Ea-e]+)+$').hasMatch(part)) {
      results.add({
        'num': qNum,
        'answer': part.toUpperCase(),
        'type': 'MULTI',
      });
      continue;
    }

    // T or F → true/false
    final upper = part.toUpperCase();
    if (upper == 'T' ||
        upper == 'TRUE' ||
        upper == 'F' ||
        upper == 'FALSE') {
      final tfVal = upper.startsWith('T') ? 'True' : 'False';
      results.add({'num': qNum, 'answer': tfVal, 'type': 'T/F'});
      continue;
    }

    // Single letter A-E → MCQ
    if (RegExp(r'^[A-Ea-e]$').hasMatch(part)) {
      results.add({'num': qNum, 'answer': upper, 'type': 'MCQ'});
      continue;
    }

    // Anything else → short answer
    results.add({'num': qNum, 'answer': part, 'type': 'SHORT'});
  }

  return results.isEmpty ? null : results;
}
