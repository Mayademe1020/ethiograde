import 'package:flutter/material.dart';
import '../../config/theme.dart';

class ExamSection {
  final String name;
  final int startQ;
  final int endQ;
  final String type;

  const ExamSection({
    required this.name,
    required this.startQ,
    required this.endQ,
    required this.type,
  });

  factory ExamSection.fromMap(Map<String, dynamic> map) {
    return ExamSection(
      name: map['name'] ?? 'A',
      startQ: map['startQ'] ?? 1,
      endQ: map['endQ'] ?? 1,
      type: map['type'] ?? 'mcq',
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'startQ': startQ,
    'endQ': endQ,
    'type': type,
  };

  int get questionCount => endQ - startQ + 1;
}

class SectionHeader extends StatelessWidget {
  final ExamSection section;
  final int answeredCount;
  final VoidCallback? onTap;
  final VoidCallback? onBulk;

  const SectionHeader({
    super.key,
    required this.section,
    required this.answeredCount,
    this.onTap,
    this.onBulk,
  });

  @override
  Widget build(BuildContext context) {
    final color = typeColor(section.type);
    final label = typeLabel(section.type);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(color: color.withValues(alpha: 0.2), width: 3),
            top: BorderSide(color: color.withValues(alpha: 0.2)),
            right: BorderSide(color: color.withValues(alpha: 0.2)),
            bottom: BorderSide(color: color.withValues(alpha: 0.2)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              'Section ${section.name}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                label,
                style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: color),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Q${section.startQ}-${section.endQ}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: context.lightText,
              ),
            ),
            const Spacer(),
            if (onBulk != null)
              GestureDetector(
                onTap: onBulk,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    Icons.content_paste,
                    size: 16,
                    color: context.primaryGreen,
                  ),
                ),
              ),
            Text(
              '$answeredCount/${section.questionCount}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: answeredCount >= section.questionCount
                    ? context.primaryGreen
                    : context.lightText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color typeColor(String type) {
    return switch (type) {
      'mcq' => const Color(0xFF7EB8DA),
      'trueFalse' => const Color(0xFFF0C674),
      'shortAnswer' => const Color(0xFFE8B07A),
      'essay' => const Color(0xFFC5A3E8),
      'matching' => const Color(0xFFE8A0B8),
      'multiAnswer' => const Color(0xFFC5A3E8),
      _ => const Color(0xFF7EB8DA),
    };
  }

  static String typeLabel(String type) {
    return switch (type) {
      'mcq' => 'MCQ',
      'trueFalse' => 'T/F',
      'shortAnswer' => 'SHORT',
      'essay' => 'ESSAY',
      'matching' => 'MATCH',
      'multiAnswer' => 'MULTI',
      _ => 'MCQ',
    };
  }
}

/// Resolves overlaps and gaps in a manually-edited section list by producing a
/// clean, contiguous partition of [total] questions.
///
/// Earlier sections keep their intended size and type; each later section starts
/// immediately after the previous one (so a first section kept at 1–12 makes the
/// next start at 13), and the final section extends to cover the rest of the
/// exam. This is the system-level "smart fix" offered to the teacher when a
/// manual edit would otherwise leave the structure invalid.
List<ExamSection> autoFixSections(List<ExamSection> sections, int total) {
  if (sections.isEmpty) {
    return [ExamSection(name: 'A', startQ: 1, endQ: total, type: 'mcq')];
  }
  final sorted = [...sections]..sort((a, b) => a.startQ.compareTo(b.startQ));
  const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  final result = <ExamSection>[];
  var cursor = 1;
  for (var i = 0; i < sorted.length; i++) {
    final s = sorted[i];
    final start = i == 0 ? 1 : cursor;
    int end;
    if (i == sorted.length - 1) {
      end = total;
    } else {
      end = s.endQ;
      if (end < start) end = start;
      if (end > total) end = total;
    }
    result.add(
      ExamSection(
        name: i < letters.length ? letters[i] : s.name,
        startQ: start,
        endQ: end,
        type: s.type,
      ),
    );
    cursor = end + 1;
  }
  return result;
}

/// Human-readable summary of a section list, e.g.
/// "A (MCQ): Questions 1–12\nB (T/F): Questions 13–20".
String describeSections(List<ExamSection> sections) {
  return sections.map((s) {
    final type = SectionHeader.typeLabel(s.type);
    return '${s.name} ($type): Questions ${s.startQ}–${s.endQ}';
  }).join('\n');
}
