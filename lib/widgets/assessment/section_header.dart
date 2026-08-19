import 'package:flutter/material.dart';
import '../../config/theme.dart';

class ExamSection {
  final String name;
  final int startQ;
  final int endQ;
  final String type;
  final double points;

  const ExamSection({
    required this.name,
    required this.startQ,
    required this.endQ,
    required this.type,
    required this.points,
  });

  factory ExamSection.fromMap(Map<String, dynamic> map) {
    return ExamSection(
      name: map['name'] ?? 'A',
      startQ: map['startQ'] ?? 1,
      endQ: map['endQ'] ?? 1,
      type: map['type'] ?? 'mcq',
      points: (map['points'] ?? 1).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'startQ': startQ,
    'endQ': endQ,
    'type': type,
    'points': points,
  };

  int get questionCount => endQ - startQ + 1;
}

class SectionHeader extends StatelessWidget {
  final ExamSection section;
  final int answeredCount;
  final VoidCallback? onTap;

  const SectionHeader({
    super.key,
    required this.section,
    required this.answeredCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = typeColor(section.type);
    final label = _typeLabel(section.type);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(color: color, width: 3),
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
            const SizedBox(width: 4),
            Text(
              '${section.points.toInt()}pt',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: context.lightText,
              ),
            ),
            const Spacer(),
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

  static String _typeLabel(String type) {
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
