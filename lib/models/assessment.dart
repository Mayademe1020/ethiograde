import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'assessment.g.dart';

@HiveType(typeId: 2)
class Assessment {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String title;
  @HiveField(3)
  final String subject;
  @HiveField(4)
  final String className;
  @HiveField(5)
  final int grade;
  @HiveField(6)
  final String rubricType; // moe_national, private_international, university
  @HiveField(7)
  final List<Question> questions;
  @HiveField(8)
  final DateTime createdAt;
  @HiveField(9)
  final DateTime? completedAt;
  @HiveField(10)
  final int totalPoints;
  @HiveField(11)
  final int passingPoints;
  @HiveField(12)
  final AssessmentStatus status;
  @HiveField(13)
  final String? voiceInstructions;
  @HiveField(14)
  final bool isQuickGrade; // true for Quick Grade auto-created assessments
  @HiveField(15)
  final Map<String, dynamic> settings;
  @HiveField(16)
  final String? weightedScaleId;
  @HiveField(17)
  final String? coordinateMapPath; // Path to .coordmap.json from Phase 1

  Assessment({
    String? id,
    required this.title,
    required this.subject,
    this.className = '',
    this.grade = 1,
    this.rubricType = 'moe_national',
    this.questions = const [],
    DateTime? createdAt,
    this.completedAt,
    this.totalPoints = 0,
    this.passingPoints = 0,
    this.status = AssessmentStatus.draft,
    this.voiceInstructions,
    this.isQuickGrade = false,
    this.settings = const {},
    this.weightedScaleId,
    this.coordinateMapPath,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  int get questionCount => questions.length;
  int get mcqCount => questions.where((q) => q.type == QuestionType.mcq).length;
  int get trueFalseCount =>
      questions.where((q) => q.type == QuestionType.trueFalse).length;
  int get shortAnswerCount =>
      questions.where((q) => q.type == QuestionType.shortAnswer).length;
  int get essayCount =>
      questions.where((q) => q.type == QuestionType.essay).length;

  double get maxScore => questions.fold(0.0, (sum, q) => sum + q.points);

  /// Number of questions with a non-null, non-empty correct answer.
  int get answeredQuestionCount => questions
      .where((q) => q.correctAnswer != null && q.correctAnswer.toString().isNotEmpty)
      .length;

  /// 0.0–1.0 ratio of answered questions.
  double get answerKeyCompleteness =>
      questions.isEmpty ? 0.0 : answeredQuestionCount / questions.length;

  /// True if every question has a correct answer set.
  bool get isAnswerKeyComplete =>
      questions.isNotEmpty && answeredQuestionCount == questions.length;

  /// Human-readable "12/40 answers set".
  String get answerKeyStatus =>
      '$answeredQuestionCount/${questions.length} answers set';

  /// True if a coordinate map file has been generated for this assessment.
  bool get hasCoordinateMap => coordinateMapPath != null && coordinateMapPath!.isNotEmpty;

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'subject': subject,
    'className': className,
    'grade': grade,
    'rubricType': rubricType,
    'questions': questions.map((q) => q.toMap()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'totalPoints': totalPoints,
    'passingPoints': passingPoints,
    'status': status.index,
    'voiceInstructions': voiceInstructions,
    'isQuickGrade': isQuickGrade,
    'settings': settings,
    'weightedScaleId': weightedScaleId,
    'coordinateMapPath': coordinateMapPath,
  };

  factory Assessment.fromMap(Map<String, dynamic> map) => Assessment(
    id: map['id'],
    title: map['title'] ?? '',
    subject: map['subject'] ?? '',
    className: map['className'] ?? '',
    grade: map['grade'] ?? 1,
    rubricType: map['rubricType'] ?? 'moe_national',
    questions: (map['questions'] as List? ?? [])
        .map((q) => Question.fromMap(q))
        .toList(),
    createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
    completedAt: map['completedAt'] != null
        ? DateTime.tryParse(map['completedAt'])
        : null,
    totalPoints: map['totalPoints'] ?? 0,
    passingPoints: map['passingPoints'] ?? 0,
    status: AssessmentStatus.values[map['status'] ?? 0],
    voiceInstructions: map['voiceInstructions'],
    isQuickGrade: map['isQuickGrade'] ?? false,
    settings: Map<String, dynamic>.from(map['settings'] ?? {}),
    weightedScaleId: map['weightedScaleId'],
    coordinateMapPath: map['coordinateMapPath']);

  Assessment copyWith({
    String? title,
    String? subject,
    String? className,
    int? grade,
    String? rubricType,
    List<Question>? questions,
    AssessmentStatus? status,
    String? weightedScaleId,
    String? coordinateMapPath,
  }) => Assessment(
    id: id,
    title: title ?? this.title,
    subject: subject ?? this.subject,
    className: className ?? this.className,
    grade: grade ?? this.grade,
    rubricType: rubricType ?? this.rubricType,
    questions: questions ?? this.questions,
    createdAt: createdAt,
    status: status ?? this.status,
    weightedScaleId: weightedScaleId ?? this.weightedScaleId,
    coordinateMapPath: coordinateMapPath ?? this.coordinateMapPath);
}

@HiveType(typeId: 5)
enum AssessmentStatus { @HiveField(0) draft, @HiveField(1) active, @HiveField(2) grading, @HiveField(3) completed }

@HiveType(typeId: 3)
class Question {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final int number;
  @HiveField(2)
  final QuestionType type;
  @HiveField(3)
  final String text;
  @HiveField(5)
  final double points;
  @HiveField(6)
  final List<String> options; // For MCQ: ['A', 'B', 'C', 'D', 'E']
  @HiveField(7)
  final dynamic
  correctAnswer; // String for MCQ/TF, List<String> for short answer
  @HiveField(8)
  final String? explanation;
  @HiveField(9)
  final String? topicTag;
  @HiveField(10)
  final List<String>? keywords; // For short answer matching
  @HiveField(11)
  final EssayRubric? essayRubric;

  Question({
    String? id,
    required this.number,
    required this.type,
    this.text = '',
    this.points = 1.0,
    this.options = const ['A', 'B', 'C', 'D', 'E'],
    this.correctAnswer,
    this.explanation,
    this.topicTag,
    this.keywords,
    this.essayRubric,
  }) : id = id ?? const Uuid().v4();

  bool get isObjective =>
      type == QuestionType.mcq || type == QuestionType.trueFalse || type == QuestionType.matching;
  bool get isSubjective =>
      type == QuestionType.shortAnswer || type == QuestionType.essay;

  Map<String, dynamic> toMap() => {
    'id': id,
    'number': number,
    'type': type.index,
    'text': text,
    'points': points,
    'options': options,
    'correctAnswer': correctAnswer,
    'explanation': explanation,
    'topicTag': topicTag,
    'keywords': keywords,
    'essayRubric': essayRubric?.toMap(),
  };

  factory Question.fromMap(Map<String, dynamic> map) {
    return Question(
      id: map['id'],
      number: map['number'] ?? 0,
      type: QuestionType.values[map['type'] ?? 0],
      text: map['text'] ?? '',
      points: (map['points'] ?? 1).toDouble(),
      options: List<String>.from(map['options'] ?? ['A', 'B', 'C', 'D', 'E']),
      correctAnswer: map['correctAnswer'],
      explanation: map['explanation'],
      topicTag: map['topicTag'],
      keywords: map['keywords'] != null
          ? List<String>.from(map['keywords'])
          : null,
      essayRubric: map['essayRubric'] != null
          ? EssayRubric.fromMap(map['essayRubric'])
          : null);
  }

  Question copyWith({
    String? id,
    int? number,
    QuestionType? type,
    String? text,
    double? points,
    List<String>? options,
    dynamic correctAnswer,
    String? explanation,
    String? topicTag,
    List<String>? keywords,
    EssayRubric? essayRubric,
  }) => Question(
    id: id ?? this.id,
    number: number ?? this.number,
    type: type ?? this.type,
    text: text ?? this.text,
    points: points ?? this.points,
    options: options ?? this.options,
    correctAnswer: correctAnswer ?? this.correctAnswer,
    explanation: explanation ?? this.explanation,
    topicTag: topicTag ?? this.topicTag,
    keywords: keywords ?? this.keywords,
    essayRubric: essayRubric ?? this.essayRubric,
  );
}

@HiveType(typeId: 6)
enum QuestionType { @HiveField(0) mcq, @HiveField(1) trueFalse, @HiveField(2) shortAnswer, @HiveField(3) essay, @HiveField(4) matching }

@HiveType(typeId: 4)
class EssayRubric {
  @HiveField(0)
  final double contentWeight; // 0.0 - 1.0
  @HiveField(1)
  final double structureWeight;
  @HiveField(2)
  final double grammarWeight;
  @HiveField(3)
  final double analysisWeight;
  @HiveField(4)
  final Map<String, String> criteriaDescriptions;

  const EssayRubric({
    this.contentWeight = 0.35,
    this.structureWeight = 0.20,
    this.grammarWeight = 0.20,
    this.analysisWeight = 0.25,
    this.criteriaDescriptions = const {},
  });

  Map<String, dynamic> toMap() => {
    'contentWeight': contentWeight,
    'structureWeight': structureWeight,
    'grammarWeight': grammarWeight,
    'analysisWeight': analysisWeight,
    'criteriaDescriptions': criteriaDescriptions,
  };

  factory EssayRubric.fromMap(Map<String, dynamic> map) => EssayRubric(
    contentWeight: (map['contentWeight'] ?? 0.35).toDouble(),
    structureWeight: (map['structureWeight'] ?? 0.20).toDouble(),
    grammarWeight: (map['grammarWeight'] ?? 0.20).toDouble(),
    analysisWeight: (map['analysisWeight'] ?? 0.25).toDouble(),
    criteriaDescriptions: Map<String, String>.from(
      map['criteriaDescriptions'] ?? {}));
}
