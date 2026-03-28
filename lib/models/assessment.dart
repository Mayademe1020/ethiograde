import 'package:uuid/uuid.dart';

class Assessment {
  final String id;
  final String title;
  final String titleAmharic;
  final String subject;
  final String className;
  final int grade;
  final String rubricType; // moe_national, private_international, university
  final List<Question> questions;
  final DateTime createdAt;
  final DateTime? completedAt;
  final int totalPoints;
  final int passingPoints;
  final AssessmentStatus status;
  final String? voiceInstructions;
  final Map<String, dynamic> settings;

  Assessment({
    String? id,
    required this.title,
    this.titleAmharic = '',
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
    this.settings = const {},
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  int get questionCount => questions.length;
  int get mcqCount => questions.where((q) => q.type == QuestionType.mcq).length;
  int get trueFalseCount => questions.where((q) => q.type == QuestionType.trueFalse).length;
  int get shortAnswerCount => questions.where((q) => q.type == QuestionType.shortAnswer).length;
  int get essayCount => questions.where((q) => q.type == QuestionType.essay).length;

  double get maxScore => questions.fold(0.0, (sum, q) => sum + q.points);

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'titleAmharic': titleAmharic,
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
    'settings': settings,
  };

  factory Assessment.fromMap(Map<String, dynamic> map) => Assessment(
    id: map['id'],
    title: map['title'] ?? '',
    titleAmharic: map['titleAmharic'] ?? '',
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
    settings: Map<String, dynamic>.from(map['settings'] ?? {}),
  );

  Assessment copyWith({
    String? title,
    String? titleAmharic,
    String? subject,
    String? className,
    int? grade,
    String? rubricType,
    List<Question>? questions,
    AssessmentStatus? status,
  }) => Assessment(
    id: id,
    title: title ?? this.title,
    titleAmharic: titleAmharic ?? this.titleAmharic,
    subject: subject ?? this.subject,
    className: className ?? this.className,
    grade: grade ?? this.grade,
    rubricType: rubricType ?? this.rubricType,
    questions: questions ?? this.questions,
    createdAt: createdAt,
    status: status ?? this.status,
  );
}

enum AssessmentStatus { draft, active, grading, completed }

class Question {
  final String id;
  final int number;
  final QuestionType type;
  final String text;
  final String textAmharic;
  final double points;
  final List<String> options; // For MCQ: ['A', 'B', 'C', 'D', 'E']
  final dynamic correctAnswer; // String for MCQ/TF, List<String> for short answer
  final String? explanation;
  final String? topicTag;
  final List<String>? keywords; // For short answer matching
  final EssayRubric? essayRubric;

  Question({
    String? id,
    required this.number,
    required this.type,
    this.text = '',
    this.textAmharic = '',
    this.points = 1.0,
    this.options = const ['A', 'B', 'C', 'D', 'E'],
    this.correctAnswer,
    this.explanation,
    this.topicTag,
    this.keywords,
    this.essayRubric,
  }) : id = id ?? const Uuid().v4();

  bool get isObjective => type == QuestionType.mcq || type == QuestionType.trueFalse;
  bool get isSubjective => type == QuestionType.shortAnswer || type == QuestionType.essay;

  Map<String, dynamic> toMap() => {
    'id': id,
    'number': number,
    'type': type.index,
    'text': text,
    'textAmharic': textAmharic,
    'points': points,
    'options': options,
    'correctAnswer': correctAnswer,
    'explanation': explanation,
    'topicTag': topicTag,
    'keywords': keywords,
    'essayRubric': essayRubric?.toMap(),
  };

  factory Question.fromMap(Map<String, dynamic> map) => Question(
    id: map['id'],
    number: map['number'] ?? 0,
    type: QuestionType.values[map['type'] ?? 0],
    text: map['text'] ?? '',
    textAmharic: map['textAmharic'] ?? '',
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
        : null,
  );
}

enum QuestionType { mcq, trueFalse, shortAnswer, essay }

class EssayRubric {
  final double contentWeight;    // 0.0 - 1.0
  final double structureWeight;
  final double grammarWeight;
  final double analysisWeight;
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
      map['criteriaDescriptions'] ?? {},
    ),
  );
}
