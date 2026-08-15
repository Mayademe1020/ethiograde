import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'scan_result.g.dart';

@HiveType(typeId: 7)
class ScanResult {
  static const Object _copySentinel = Object();

  @HiveField(0)
  final String id;
  @HiveField(1)
  final String assessmentId;
  @HiveField(2)
  final String studentId;
  @HiveField(3)
  final String studentName;
  @HiveField(4)
  final String imagePath;
  @HiveField(5)
  final String? enhancedImagePath;
  @HiveField(6)
  final List<AnswerMatch> answers;
  @HiveField(7)
  final double totalScore;
  @HiveField(8)
  final double maxScore;
  @HiveField(9)
  final double percentage;
  @HiveField(10)
  final String grade;
  @HiveField(11)
  final ScanStatus status;
  @HiveField(12)
  final DateTime scannedAt;
  @HiveField(13)
  final String? voiceNotePath;
  @HiveField(14)
  final String? teacherComment;
  @HiveField(15)
  final double confidence; // Overall OCR confidence 0.0 - 1.0
  @HiveField(16)
  final int? imageHash; // dHash for duplicate scan detection
  @HiveField(17)
  final bool isManualEntry; // true when scores entered by hand, not scanned
  @HiveField(18)
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
    this.isManualEntry = false,
    this.metadata = const {},
  }) : id = id ?? const Uuid().v4(),
       scannedAt = scannedAt ?? DateTime.now();

  /// Whether this result has been resolved by the teacher.
  ///
  /// A result is resolved when any of these conditions hold:
  /// - status is ScanStatus.reviewed
  /// - metadata['teacherReviewed'] is true
  /// - metadata['batchReviewResolution'] is non-null
  /// - metadata['duplicateReviewed'] is true
  /// - metadata['studentMatchResolved'] is true
  bool get isResolved {
    if (status == ScanStatus.reviewed) return true;
    if (metadata['teacherReviewed'] == true) return true;
    if (metadata['batchReviewResolution'] != null) return true;
    if (metadata['duplicateReviewed'] == true) return true;
    if (metadata['studentMatchResolved'] == true) return true;
    return false;
  }

  /// Whether this result still requires teacher action.
  ///
  /// Returns true only for UNRESOLVED issues. Resolved items are excluded.
  /// This is the canonical resolver — use this instead of checking
  /// needsReview and isUnmatched separately.
  ///
  /// Combines:
  /// - Low-confidence answers (needsReview)
  /// - Unmatched student identity (isUnmatched)
  bool get requiresTeacherAction {
    if (isResolved) return false;

    // Unresolved low-confidence overall
    if (confidence < 0.7) return true;

    // Unresolved low-confidence on individual answers
    if (answers.any((a) => a.confidence < 0.6)) return true;

    // Multiple-mark responses detected (confidence 0 from OMR)
    if (answers.any((a) => a.detectedAnswer == '[MULTIPLE]')) return true;

    // Unresolved unmatched student
    if (studentId.isEmpty || studentName.trim().isEmpty) return true;

    return false;
  }

  /// Whether this result still requires teacher review (low-confidence only).
  ///
  /// Returns true only for UNRESOLVED low-confidence issues.
  /// Unmatched students and other issues are checked separately.
  /// Prefer [requiresTeacherAction] for unified checking.
  bool get needsReview {
    if (isResolved) return false;

    // Unresolved low-confidence overall
    if (confidence < 0.7) return true;

    // Unresolved low-confidence on individual answers
    if (answers.any((a) => a.confidence < 0.6)) return true;

    // Multiple-mark responses detected (confidence 0 from OMR)
    if (answers.any((a) => a.detectedAnswer == '[MULTIPLE]')) return true;

    return false;
  }

  /// Whether this result has an unmatched student.
  bool get isUnmatched => studentId.isEmpty || studentName.trim().isEmpty;

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
    'isManualEntry': isManualEntry,
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
    isManualEntry: map['isManualEntry'] ?? false,
    metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
  );

  ScanResult copyWith({
    String? studentId,
    String? studentName,
    String? imagePath,
    Object? enhancedImagePath = _copySentinel,
    List<AnswerMatch>? answers,
    double? totalScore,
    double? maxScore,
    double? percentage,
    String? grade,
    ScanStatus? status,
    String? voiceNotePath,
    String? teacherComment,
    double? confidence,
    int? imageHash,
    bool? isManualEntry,
    Map<String, dynamic>? metadata,
  }) => ScanResult(
    id: id,
    assessmentId: assessmentId,
    studentId: studentId ?? this.studentId,
    studentName: studentName ?? this.studentName,
    imagePath: imagePath ?? this.imagePath,
    enhancedImagePath: identical(enhancedImagePath, _copySentinel)
        ? this.enhancedImagePath
        : enhancedImagePath as String?,
    answers: answers ?? this.answers,
    totalScore: totalScore ?? this.totalScore,
    maxScore: maxScore ?? this.maxScore,
    percentage: percentage ?? this.percentage,
    grade: grade ?? this.grade,
    status: status ?? this.status,
    scannedAt: scannedAt,
    voiceNotePath: voiceNotePath ?? this.voiceNotePath,
    teacherComment: teacherComment ?? this.teacherComment,
    confidence: confidence ?? this.confidence,
    imageHash: imageHash ?? this.imageHash,
    isManualEntry: isManualEntry ?? this.isManualEntry,
    metadata: metadata ?? this.metadata,
  );
}

@HiveType(typeId: 10)
enum ScanStatus {
  @HiveField(0)
  pending,
  @HiveField(1)
  processing,
  @HiveField(2)
  graded,
  @HiveField(3)
  reviewed,
  @HiveField(4)
  needsRescan,
}

@HiveType(typeId: 8)
class AnswerMatch {
  @HiveField(0)
  final int questionNumber;
  @HiveField(1)
  final String detectedAnswer;
  @HiveField(2)
  final String correctAnswer;
  @HiveField(3)
  final bool isCorrect;
  @HiveField(4)
  final double score;
  @HiveField(5)
  final double maxScore;
  @HiveField(6)
  final double confidence;
  @HiveField(7)
  final String? ocrRawText;
  @HiveField(8)
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

@HiveType(typeId: 9)
class BoundingBox {
  @HiveField(0)
  final double left;
  @HiveField(1)
  final double top;
  @HiveField(2)
  final double right;
  @HiveField(3)
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
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };

  factory BoundingBox.fromMap(Map<String, dynamic> map) => BoundingBox(
    left: (map['left'] ?? 0).toDouble(),
    top: (map['top'] ?? 0).toDouble(),
    right: (map['right'] ?? 0).toDouble(),
    bottom: (map['bottom'] ?? 0).toDouble(),
  );
}
