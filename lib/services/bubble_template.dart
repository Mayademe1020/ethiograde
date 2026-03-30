/// Template defining where bubbles are located on a paper image.
///
/// Templates map the physical layout of a bubble sheet to question numbers
/// and answer options. The app generates bubble sheets via PDF service;
/// these templates describe where to look when reading them back.
///
/// Grid layout:
/// ```
///   Col 0  Col 1  Col 2  Col 3  Col 4
///   [ A ]  [ B ]  [ C ]  [ D ]  [ E ]   ← Q1 (row 0)
///   [ A ]  [ B ]  [ C ]  [ D ]  [ E ]   ← Q2 (row 1)
///   ...
/// ```
///
/// All coordinates are in the enhanced image's pixel space (after EXIF
/// correction + downscale to 1600px max dimension).
class BubbleTemplate {
  final String name;
  final int questionCount;
  final List<String> options;

  /// Starting position of the first bubble (center of circle).
  final double startX;
  final double startY;

  /// Horizontal distance between option bubbles in the same row.
  final double columnSpacing;

  /// Vertical distance between question rows.
  final double rowSpacing;

  /// Expected radius of each bubble in pixels (sampling region).
  final double bubbleRadius;

  /// Normalized fill threshold: 0.0–1.0.
  /// If the dark pixel ratio in the sampling region exceeds this,
  /// the bubble is considered "filled".
  final double fillThreshold;

  const BubbleTemplate({
    required this.name,
    required this.questionCount,
    this.options = const ['A', 'B', 'C', 'D', 'E'],
    required this.startX,
    required this.startY,
    required this.columnSpacing,
    required this.rowSpacing,
    this.bubbleRadius = 8.0,
    this.fillThreshold = 0.45,
  });

  /// Get the expected center position of a specific bubble.
  /// [questionIndex] is 0-based (question 1 = index 0).
  /// [optionIndex] is 0-based (option A = index 0).
  (double x, double y) bubbleCenter(int questionIndex, int optionIndex) {
    return (
      startX + optionIndex * columnSpacing,
      startY + questionIndex * rowSpacing,
    );
  }

  /// Number of options per question.
  int get optionCount => options.length;

  Map<String, dynamic> toMap() => {
    'name': name,
    'questionCount': questionCount,
    'options': options,
    'startX': startX,
    'startY': startY,
    'columnSpacing': columnSpacing,
    'rowSpacing': rowSpacing,
    'bubbleRadius': bubbleRadius,
    'fillThreshold': fillThreshold,
  };

  factory BubbleTemplate.fromMap(Map<String, dynamic> map) => BubbleTemplate(
    name: map['name'] ?? 'custom',
    questionCount: map['questionCount'] ?? 20,
    options: List<String>.from(map['options'] ?? ['A', 'B', 'C', 'D', 'E']),
    startX: (map['startX'] ?? 0).toDouble(),
    startY: (map['startY'] ?? 0).toDouble(),
    columnSpacing: (map['columnSpacing'] ?? 0).toDouble(),
    rowSpacing: (map['rowSpacing'] ?? 0).toDouble(),
    bubbleRadius: (map['bubbleRadius'] ?? 8.0).toDouble(),
    fillThreshold: (map['fillThreshold'] ?? 0.45).toDouble(),
  );

  @override
  String toString() => 'BubbleTemplate($name, $questionCount Q × $optionCount opts)';
}

/// Pre-built templates matching common Ethiopian exam formats.
///
/// These match the output of the app's PDF service bubble sheet generator.
/// Coordinates assume a 1600px-wide enhanced image (the app's standard
/// processing pipeline downscales to this size).
class StandardTemplates {
  StandardTemplates._();

  /// 20 questions, 5 options (A–E), single column.
  /// Standard Ethiopian MoE format for most subjects.
  static const BubbleTemplate moe20x5 = BubbleTemplate(
    name: 'MoE 20×5',
    questionCount: 20,
    options: ['A', 'B', 'C', 'D', 'E'],
    startX: 280,
    startY: 290,
    columnSpacing: 110,
    rowSpacing: 30,
    bubbleRadius: 8,
    fillThreshold: 0.45,
  );

  /// 30 questions, 5 options (A–E), single column.
  /// Extended format for comprehensive exams.
  static const BubbleTemplate moe30x5 = BubbleTemplate(
    name: 'MoE 30×5',
    questionCount: 30,
    options: ['A', 'B', 'C', 'D', 'E'],
    startX: 280,
    startY: 260,
    columnSpacing: 110,
    rowSpacing: 27,
    bubbleRadius: 7,
    fillThreshold: 0.45,
  );

  /// 10 True/False questions.
  static const BubbleTemplate tf10 = BubbleTemplate(
    name: 'True/False 10',
    questionCount: 10,
    options: ['True', 'False'],
    startX: 350,
    startY: 290,
    columnSpacing: 200,
    rowSpacing: 30,
    bubbleRadius: 8,
    fillThreshold: 0.45,
  );

  /// 20 True/False questions.
  static const BubbleTemplate tf20 = BubbleTemplate(
    name: 'True/False 20',
    questionCount: 20,
    options: ['True', 'False'],
    startX: 350,
    startY: 270,
    columnSpacing: 200,
    rowSpacing: 27,
    bubbleRadius: 7,
    fillThreshold: 0.45,
  );

  /// 50 questions, 4 options (A–D). Common for university entrance exams.
  static const BubbleTemplate uni50x4 = BubbleTemplate(
    name: 'University 50×4',
    questionCount: 50,
    options: ['A', 'B', 'C', 'D'],
    startX: 300,
    startY: 220,
    columnSpacing: 130,
    rowSpacing: 22,
    bubbleRadius: 6,
    fillThreshold: 0.45,
  );

  /// Get a template by name (case-insensitive).
  static BubbleTemplate? byName(String name) {
    final lower = name.toLowerCase();
    for (final t in all) {
      if (t.name.toLowerCase() == lower) return t;
    }
    return null;
  }

  /// Match a template to an assessment's question count and type.
  static BubbleTemplate matchAssessment({
    required int questionCount,
    required bool isTrueFalse,
  }) {
    if (isTrueFalse) {
      if (questionCount <= 10) return tf10;
      return tf20;
    }

    if (questionCount <= 20) return moe20x5;
    if (questionCount <= 30) return moe30x5;
    return uni50x4;
  }

  /// All available standard templates.
  static List<BubbleTemplate> get all => [moe20x5, moe30x5, tf10, tf20, uni50x4];
}
