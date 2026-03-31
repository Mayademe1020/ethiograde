import 'package:uuid/uuid.dart';

class ScanResult {
  final String id;
  final String assessmentId;
  final String studentId;
  final String studentName;
  final String imagePath;
  final String? enhancedImagePath;
  final List<AnswerMatch> answers;
  final double totalScore;
  final double maxScore;
  final double percentage;
  final String grade;
  final ScanStatus status;
  final DateTime scannedAt;
  final String? voiceNotePath;
  final String? teacherComment;
  final double confidence; // Overall OCR confidence 0.0 - 1.0
  final int? imageHash; // dHash for duplicate scan detection
  final Map<String, dynamic> metadata;

  ScanResult({
    String? id,
    required this.assessmentId,
    required this.studentId,
    required this.studentName,
    required this.imagePath,
    this.enhancedImagePath,
    this.answers = const [],
    this.totalScore = 0,
    this.maxScore = 0,
    this.percentage = 0,
    this.grade = '',
    this.status = ScanStatus.pending,
    DateTime? scannedAt,
    this.voiceNotePath,
    this.teacherComment,
    this.confidence = 0,
    this.imageHash,
    this.metadata = const {},
  }) : id = id ?? const Uuid().v4(),
       scannedAt = scannedAt ?? DateTime.now();

  bool get needsReview => confidence < 0.7 ||
      answers.any((a) => a.confidence < 0.6);

  Map<String, dynamic> toMap() => {
    'id': id,
    'assessmentId': assessmentId,
    'studentId': studentId,
    'studentName': studentName,
    'imagePath': imagePath,
    'enhancedImagePath': enhancedImagePath,
    'answers': answers.map((a) => a.toMap()).toList(),
    'totalScore': totalScore,
    'maxScore': maxScore,
    'percentage': percentage,
    'grade': grade,
    'status': status.index,
    'scannedAt': scannedAt.toIso8601String(),
    'voiceNotePath': voiceNotePath,
    'teacherComment': teacherComment,
    'confidence': confidence,
    'imageHash': imageHash,
    'metadata': metadata,
  };

  factory ScanResult.fromMap(Map<String, dynamic> map) => ScanResult(
    id: map['id'],
    assessmentId: map['assessmentId'] ?? '',
    studentId: map['studentId'] ?? '',
    studentName: map['studentName'] ?? '',
    imagePath: map['imagePath'] ?? '',
    enhancedImagePath: map['enhancedImagePath'],
    answers: (map['answers'] as List? ?? [])
        .map((a) => AnswerMatch.fromMap(a))
        .toList(),
    totalScore: (map['totalScore'] ?? 0).toDouble(),
    maxScore: (map['maxScore'] ?? 0).toDouble(),
    percentage: (map['percentage'] ?? 0).toDouble(),
    grade: map['grade'] ?? '',
    status: ScanStatus.values[map['status'] ?? 0],
    scannedAt: DateTime.tryParse(map['scannedAt'] ?? '') ?? DateTime.now(),
    voiceNotePath: map['voiceNotePath'],
    teacherComment: map['teacherComment'],
    confidence: (map['confidence'] ?? 0).toDouble(),
    imageHash: map['imageHash'] as int?,
    metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
  );

  ScanResult copyWith({
    List<AnswerMatch>? answers,
    double? totalScore,
    double? percentage,
    String? grade,
    ScanStatus? status,
    String? voiceNotePath,
    String? teacherComment,
    int? imageHash,
  }) => ScanResult(
    id: id,
    assessmentId: assessmentId,
    studentId: studentId,
    studentName: studentName,
    imagePath: imagePath,
    enhancedImagePath: enhancedImagePath,
    answers: answers ?? this.answers,
    totalScore: totalScore ?? this.totalScore,
    maxScore: maxScore,
    percentage: percentage ?? this.percentage,
    grade: grade ?? this.grade,
    status: status ?? this.status,
    scannedAt: scannedAt,
    voiceNotePath: voiceNotePath ?? this.voiceNotePath,
    teacherComment: teacherComment ?? this.teacherComment,
    confidence: confidence,
    imageHash: imageHash ?? this.imageHash,
    metadata: metadata,
  );

  /// Check if answer detection is aligned with the expected key length.
  ///
  /// Returns alignment details: how many answers were detected vs expected,
  /// how many are [MISSING], and whether the mismatch is significant enough
  /// to warn the teacher.
  ///
  /// [expectedObjectiveCount] — number of MCQ + True/False questions in the
  /// assessment's answer key. Pass 0 for subjective-only assessments.
  AlignmentCheck checkAlignment(int expectedObjectiveCount) {
    if (expectedObjectiveCount <= 0 || answers.isEmpty) {
      return AlignmentCheck(
        detectedObjective: 0,
        expectedObjective: expectedObjectiveCount,
        missingCount: 0,
        needsWarning: false,
      );
    }

    final detectedObjective = answers
        .where((a) => a.detectedAnswer != '[MISSING]')
        .length;
    final missingCount = answers
        .where((a) => a.detectedAnswer == '[MISSING]')
        .length;

    // Warn if more than 20% of objective answers are missing
    // (e.g., paper misaligned, wrong template, partial scan)
    final missingRatio = missingCount / expectedObjectiveCount;
    final needsWarning = missingRatio > 0.2;

    return AlignmentCheck(
      detectedObjective: detectedObjective,
      expectedObjective: expectedObjectiveCount,
      missingCount: missingCount,
      needsWarning: needsWarning,
    );
  }
}

/// Result of checking answer key alignment after scanning.
class AlignmentCheck {
  final int detectedObjective;
  final int expectedObjective;
  final int missingCount;
  final bool needsWarning;

  const AlignmentCheck({
    required this.detectedObjective,
    required this.expectedObjective,
    required this.missingCount,
    required this.needsWarning,
  });

  /// Ratio of missing answers (0.0 = none missing, 1.0 = all missing).
  double get missingRatio =>
      expectedObjective > 0 ? missingCount / expectedObjective : 0.0;
}

enum ScanStatus { pending, processing, graded, reviewed, needsRescan }

class AnswerMatch {
  final int questionNumber;
  final String detectedAnswer;
  final String correctAnswer;
  final bool isCorrect;
  final double score;
  final double maxScore;
  final double confidence;
  final String? ocrRawText;
  final BoundingBox? boundingBox;

  AnswerMatch({
    required this.questionNumber,
    required this.detectedAnswer,
    required this.correctAnswer,
    required this.isCorrect,
    required this.score,
    required this.maxScore,
    this.confidence = 0,
    this.ocrRawText,
    this.boundingBox,
  });

  Map<String, dynamic> toMap() => {
    'questionNumber': questionNumber,
    'detectedAnswer': detectedAnswer,
    'correctAnswer': correctAnswer,
    'isCorrect': isCorrect,
    'score': score,
    'maxScore': maxScore,
    'confidence': confidence,
    'ocrRawText': ocrRawText,
    'boundingBox': boundingBox?.toMap(),
  };

  factory AnswerMatch.fromMap(Map<String, dynamic> map) => AnswerMatch(
    questionNumber: map['questionNumber'] ?? 0,
    detectedAnswer: map['detectedAnswer'] ?? '',
    correctAnswer: map['correctAnswer'] ?? '',
    isCorrect: map['isCorrect'] ?? false,
    score: (map['score'] ?? 0).toDouble(),
    maxScore: (map['maxScore'] ?? 1).toDouble(),
    confidence: (map['confidence'] ?? 0).toDouble(),
    ocrRawText: map['ocrRawText'],
    boundingBox: map['boundingBox'] != null
        ? BoundingBox.fromMap(map['boundingBox'])
        : null,
  );
}

class BoundingBox {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const BoundingBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get width => right - left;
  double get height => bottom - top;

  Map<String, dynamic> toMap() => {
    'left': left, 'top': top, 'right': right, 'bottom': bottom,
  };

  factory BoundingBox.fromMap(Map<String, dynamic> map) => BoundingBox(
    left: (map['left'] ?? 0).toDouble(),
    top: (map['top'] ?? 0).toDouble(),
    right: (map['right'] ?? 0).toDouble(),
    bottom: (map['bottom'] ?? 0).toDouble(),
  );
}
