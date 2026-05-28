/// Coordinate map for an OMR answer sheet.
///
/// Maps every bubble position to millimeter coordinates on an A4 page.
/// Generated alongside the PDF, consumed by the OMR scanning pipeline.
///
/// Units: millimeters from top-left of page (0,0).
class CoordinateMap {
  final String assessmentId;
  final String version;
  final PageDimensions page;
  final List<AnchorPoint> anchors;
  final List<QuestionBubble> questions;
  final Map<String, dynamic> metadata;

  const CoordinateMap({
    required this.assessmentId,
    this.version = '1.0',
    required this.page,
    required this.anchors,
    required this.questions,
    this.metadata = const {},
  });

  /// Find a bubble by question number and option letter.
  BubblePosition? findBubble(int questionNumber, String option) {
    try {
      final q = questions.firstWhere((q) => q.number == questionNumber);
      return q.bubbles.firstWhere(
        (b) => b.option.toUpperCase() == option.toUpperCase());
    } catch (_) {
      return null;
    }
  }

  /// All anchor positions as flat list.
  List<BubblePosition> get anchorPositions =>
      anchors.map((a) => a.position).toList();

  Map<String, dynamic> toMap() => {
    'assessmentId': assessmentId,
    'version': version,
    'page': page.toMap(),
    'anchors': anchors.map((a) => a.toMap()).toList(),
    'questions': questions.map((q) => q.toMap()).toList(),
    'metadata': metadata,
  };

  factory CoordinateMap.fromMap(Map<String, dynamic> map) => CoordinateMap(
    assessmentId: map['assessmentId'] ?? '',
    version: map['version'] ?? '1.0',
    page: PageDimensions.fromMap(map['page'] ?? {}),
    anchors: (map['anchors'] as List? ?? [])
        .map((a) => AnchorPoint.fromMap(a))
        .toList(),
    questions: (map['questions'] as List? ?? [])
        .map((q) => QuestionBubble.fromMap(q))
        .toList(),
    metadata: Map<String, dynamic>.from(map['metadata'] ?? {}));
}

/// A4 page dimensions in millimeters.
class PageDimensions {
  final double widthMm;
  final double heightMm;

  const PageDimensions({this.widthMm = 210.0, this.heightMm = 297.0});

  Map<String, dynamic> toMap() => {'widthMm': widthMm, 'heightMm': heightMm};

  factory PageDimensions.fromMap(Map<String, dynamic> map) => PageDimensions(
    widthMm: (map['widthMm'] ?? 210.0).toDouble(),
    heightMm: (map['heightMm'] ?? 297.0).toDouble());
}

/// Corner anchor point for perspective correction during scanning.
class AnchorPoint {
  final String corner; // 'topLeft', 'topRight', 'bottomLeft', 'bottomRight'
  final BubblePosition position;

  const AnchorPoint({required this.corner, required this.position});

  Map<String, dynamic> toMap() => {
    'corner': corner,
    'xMm': position.xMm,
    'yMm': position.yMm,
    'sizeMm': position.widthMm,
  };

  factory AnchorPoint.fromMap(Map<String, dynamic> map) => AnchorPoint(
    corner: map['corner'] ?? '',
    position: BubblePosition(
      xMm: (map['xMm'] ?? 0).toDouble(),
      yMm: (map['yMm'] ?? 0).toDouble(),
      widthMm: (map['sizeMm'] ?? 8.0).toDouble(),
      heightMm: (map['sizeMm'] ?? 8.0).toDouble(),
      option: ''));
}

/// A single question row with its bubble positions.
class QuestionBubble {
  final int number;
  final SheetQuestionType type;
  final List<BubblePosition> bubbles;
  final String column; // 'left' or 'right'

  const QuestionBubble({
    required this.number,
    required this.type,
    required this.bubbles,
    this.column = 'left',
  });

  Map<String, dynamic> toMap() => {
    'number': number,
    'type': type.name,
    'column': column,
    'bubbles': bubbles.map((b) => b.toMap()).toList(),
  };

  factory QuestionBubble.fromMap(Map<String, dynamic> map) => QuestionBubble(
    number: map['number'] ?? 0,
    type: SheetQuestionType.values.firstWhere(
      (t) => t.name == (map['type'] ?? 'mcq'),
      orElse: () => SheetQuestionType.mcq),
    bubbles: (map['bubbles'] as List? ?? [])
        .map((b) => BubblePosition.fromMap(b))
        .toList(),
    column: map['column'] ?? 'left');
}

/// Position of a single bubble or anchor in mm on the A4 page.
class BubblePosition {
  final double xMm; // Center X in mm from left edge
  final double yMm; // Center Y in mm from top edge
  final double widthMm;
  final double heightMm;
  final String option; // 'A', 'B', 'C', 'D', 'T', 'F', or '' for anchors

  const BubblePosition({
    required this.xMm,
    required this.yMm,
    this.widthMm = 4.0,
    this.heightMm = 4.0,
    required this.option,
  });

  Map<String, dynamic> toMap() => {
    'xMm': xMm,
    'yMm': yMm,
    'widthMm': widthMm,
    'heightMm': heightMm,
    'option': option,
  };

  factory BubblePosition.fromMap(Map<String, dynamic> map) => BubblePosition(
    xMm: (map['xMm'] ?? 0).toDouble(),
    yMm: (map['yMm'] ?? 0).toDouble(),
    widthMm: (map['widthMm'] ?? 4.0).toDouble(),
    heightMm: (map['heightMm'] ?? 4.0).toDouble(),
    option: map['option'] ?? '');
}

enum SheetQuestionType { mcq, trueFalse }
