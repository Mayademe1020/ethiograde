class ClassInfo {
  final String id;
  final String name;
  final String nameAmharic;
  final int grade;
  final String section;
  final String subject;
  final String schoolYear;
  final List<String> studentIds;
  final DateTime createdAt;

  ClassInfo({
    required this.id,
    required this.name,
    this.nameAmharic = '',
    this.grade = 1,
    this.section = '',
    this.subject = '',
    this.schoolYear = '2016 E.C.',
    this.studentIds = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  int get studentCount => studentIds.length;

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'nameAmharic': nameAmharic,
    'grade': grade, 'section': section, 'subject': subject,
    'schoolYear': schoolYear, 'studentIds': studentIds,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ClassInfo.fromMap(Map<String, dynamic> map) => ClassInfo(
    id: map['id'] ?? '',
    name: map['name'] ?? '',
    nameAmharic: map['nameAmharic'] ?? '',
    grade: map['grade'] ?? 1,
    section: map['section'] ?? '',
    subject: map['subject'] ?? '',
    schoolYear: map['schoolYear'] ?? '2016 E.C.',
    studentIds: List<String>.from(map['studentIds'] ?? []),
    createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
  );
}

class ClassAnalytics {
  final String classId;
  final String assessmentId;
  final double classAverage;
  final double highestScore;
  final double lowestScore;
  final double medianScore;
  final double passRate;
  final int totalStudents;
  final int passedStudents;
  final int failedStudents;
  final Map<String, int> gradeDistribution; // {'A': 5, 'B': 12, ...}
  final List<QuestionAnalytics> questionAnalytics;
  final Map<String, double> topicScores; // topic_tag -> avg_score

  const ClassAnalytics({
    required this.classId,
    required this.assessmentId,
    this.classAverage = 0,
    this.highestScore = 0,
    this.lowestScore = 0,
    this.medianScore = 0,
    this.passRate = 0,
    this.totalStudents = 0,
    this.passedStudents = 0,
    this.failedStudents = 0,
    this.gradeDistribution = const {},
    this.questionAnalytics = const [],
    this.topicScores = const {},
  });

  Map<String, dynamic> toMap() => {
    'classId': classId,
    'assessmentId': assessmentId,
    'classAverage': classAverage,
    'highestScore': highestScore,
    'lowestScore': lowestScore,
    'medianScore': medianScore,
    'passRate': passRate,
    'totalStudents': totalStudents,
    'passedStudents': passedStudents,
    'failedStudents': failedStudents,
    'gradeDistribution': gradeDistribution,
    'questionAnalytics': questionAnalytics.map((q) => q.toMap()).toList(),
    'topicScores': topicScores,
  };

  factory ClassAnalytics.fromMap(Map<String, dynamic> map) => ClassAnalytics(
    classId: map['classId'] ?? '',
    assessmentId: map['assessmentId'] ?? '',
    classAverage: (map['classAverage'] ?? 0).toDouble(),
    highestScore: (map['highestScore'] ?? 0).toDouble(),
    lowestScore: (map['lowestScore'] ?? 0).toDouble(),
    medianScore: (map['medianScore'] ?? 0).toDouble(),
    passRate: (map['passRate'] ?? 0).toDouble(),
    totalStudents: map['totalStudents'] ?? 0,
    passedStudents: map['passedStudents'] ?? 0,
    failedStudents: map['failedStudents'] ?? 0,
    gradeDistribution: Map<String, int>.from(map['gradeDistribution'] ?? {}),
    questionAnalytics: (map['questionAnalytics'] as List? ?? [])
        .map((q) => QuestionAnalytics.fromMap(q))
        .toList(),
    topicScores: Map<String, double>.from(map['topicScores'] ?? {}),
  );
}

class QuestionAnalytics {
  final int questionNumber;
  final double correctRate; // 0.0 - 1.0
  final int totalAttempts;
  final int correctAttempts;
  final Map<String, int> answerDistribution; // {'A': 15, 'B': 8, ...}
  final String? topicTag;

  const QuestionAnalytics({
    required this.questionNumber,
    this.correctRate = 0,
    this.totalAttempts = 0,
    this.correctAttempts = 0,
    this.answerDistribution = const {},
    this.topicTag,
  });

  bool get isDifficult => correctRate < 0.4;
  bool get isEasy => correctRate > 0.85;

  Map<String, dynamic> toMap() => {
    'questionNumber': questionNumber,
    'correctRate': correctRate,
    'totalAttempts': totalAttempts,
    'correctAttempts': correctAttempts,
    'answerDistribution': answerDistribution,
    'topicTag': topicTag,
  };

  factory QuestionAnalytics.fromMap(Map<String, dynamic> map) =>
      QuestionAnalytics(
        questionNumber: map['questionNumber'] ?? 0,
        correctRate: (map['correctRate'] ?? 0).toDouble(),
        totalAttempts: map['totalAttempts'] ?? 0,
        correctAttempts: map['correctAttempts'] ?? 0,
        answerDistribution:
            Map<String, int>.from(map['answerDistribution'] ?? {}),
        topicTag: map['topicTag'],
      );
}
