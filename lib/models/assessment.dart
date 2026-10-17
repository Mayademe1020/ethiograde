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
  @HiveField(18)
  final int answerKeyRevision;
  @HiveField(19)
  final String answerKeyFingerprint;

  /// Canonical answer-key sections. `null` means a legacy assessment whose
  /// structure is derived from each [Question.type] via [effectiveSections].
  /// A non-empty list is an explicit, teacher-defined structure.
  @HiveField(20)
  final List<AnswerKeySection>? sections;

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
    this.answerKeyRevision = 0,
    this.answerKeyFingerprint = '',
    this.sections,
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
  int get multiAnswerCount =>
      questions.where((q) => q.type == QuestionType.multiAnswer).length;

  double get maxScore => questions.fold(0.0, (sum, q) => sum + q.points);

  /// Number of questions with a non-null, non-empty correct answer.
  int get answeredQuestionCount => questions
      .where(
        (q) => q.correctAnswer != null && q.correctAnswer.toString().isNotEmpty,
      )
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

  // ---------------------------------------------------------------------------
  // Answer-key structure (sections)
  // ---------------------------------------------------------------------------

  /// True when the assessment has an explicit, teacher-defined structure.
  bool get hasExplicitSections => sections != null && sections!.isNotEmpty;

  /// The structure to use for UI/navigation.
  ///
  /// Explicit structure is preferred. Legacy assessments (no stored sections)
  /// derive their structure from each [Question.type] so nothing is lost and
  /// the UI still shows organized sections.
  List<AnswerKeySection> get effectiveSections =>
      hasExplicitSections ? sections! : collapseSections(questions, const {});

  /// Validate the explicit structure against the question count.
  ///
  /// Returns a list of human-readable errors. An empty list means the
  /// structure is valid. Legacy assessments (no explicit sections) are always
  /// considered valid, since [effectiveSections] derives them.
  List<String> validateStructure() {
    final errors = <String>[];
    if (!hasExplicitSections) return errors;
    final secs = sections!;
    final total = questionCount;

    if (secs.any((s) => s.start < 1 || s.end > total || s.start > s.end)) {
      errors.add('A section is outside the $total-question exam.');
    }

    final sorted = [...secs]..sort((a, b) => a.start.compareTo(b.start));
    if (sorted.isNotEmpty && sorted.first.start != 1) {
      errors.add('Sections must start at question 1.');
    }
    if (sorted.isNotEmpty && sorted.last.end != total) {
      errors.add('Sections must cover up to question $total.');
    }
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].start <= sorted[i - 1].end) {
        errors.add(
          'Sections ${sorted[i - 1].label} and ${sorted[i].label} overlap.',
        );
      }
    }

    final covered = <int>{};
    for (final s in secs) {
      for (var n = s.start; n <= s.end; n++) {
        covered.add(n);
      }
    }
    final missing = <int>[];
    for (var n = 1; n <= total; n++) {
      if (!covered.contains(n)) missing.add(n);
    }
    if (missing.isNotEmpty) {
      final first = missing.first;
      final last = missing.last;
      errors.add(
        'Questions ${first == last ? '$first' : '$first–$last'} are not '
        'covered by any section.',
      );
    }
    return errors;
  }

  bool get isStructureValid => validateStructure().isEmpty;

  /// True when the explicit structure completely and unambiguously covers the
  /// exam (no overlaps/gaps/out-of-range). Used to gate progression.
  bool get canProceedToAnswers => !hasExplicitSections || isStructureValid;

  /// True if the structure covers every question (explicitly or derived).
  bool get isStructureComplete =>
      !hasExplicitSections ||
      (isStructureValid && sections!.fold(0, (s, e) => s + e.count) == questionCount);

  /// True for a uniform exam where every question shares one type.
  bool get isUniformStructure {
    final secs = effectiveSections;
    if (secs.isEmpty) return false;
    final type = secs.first.type;
    return secs.every((s) => s.type == type);
  }

  /// True if the explicit structure covers all questions with a single type.
  bool get isUniformExplicit =>
      hasExplicitSections &&
      sections!.length == 1 &&
      sections!.first.start == 1 &&
      sections!.first.end == questionCount;

  /// True when the explicit structure differs from what would be derived from
  /// the current [Question.type] values (i.e. the teacher changed structure).
  bool get structureDiffersFromQuestions {
    if (!hasExplicitSections) return false;
    final derived = collapseSections(questions, const {});
    if (derived.length != sections!.length) return true;
    for (var i = 0; i < derived.length; i++) {
      if (derived[i].start != sections![i].start ||
          derived[i].end != sections![i].end ||
          derived[i].type != sections![i].type) {
        return true;
      }
    }
    return false;
  }

  /// True if a coordinate map file has been generated for this assessment.
  bool get hasCoordinateMap =>
      coordinateMapPath != null && coordinateMapPath!.isNotEmpty;

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
      'answerKeyRevision': answerKeyRevision,
      'answerKeyFingerprint': answerKeyFingerprint,
      'sections': sections?.map((s) => s.toMap()).toList(),
    };

  factory Assessment.fromMap(Map<String, dynamic> map) => Assessment(
    id: map['id'],
    title: map['title'] ?? '',
    subject: map['subject'] ?? '',
    className: map['className'] ?? '',
    grade: map['grade'] ?? 1,
    rubricType: map['rubricType'] ?? 'moe_national',
    questions: (map['questions'] as List? ?? [])
        .map((q) => Question.fromMap(Map<String, dynamic>.from(q)))
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
    coordinateMapPath: map['coordinateMapPath'],
    answerKeyRevision: map['answerKeyRevision'] ?? 0,
    answerKeyFingerprint: map['answerKeyFingerprint'] ?? '',
    sections: (map['sections'] as List?)
        ?.map((s) => AnswerKeySection.fromMap(Map<String, dynamic>.from(s)))
        .toList(),
  );

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
    int? answerKeyRevision,
    String? answerKeyFingerprint,
    Map<String, dynamic>? settings,
    List<AnswerKeySection>? sections,
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
    coordinateMapPath: coordinateMapPath ?? this.coordinateMapPath,
    answerKeyRevision: answerKeyRevision ?? this.answerKeyRevision,
    answerKeyFingerprint: answerKeyFingerprint ?? this.answerKeyFingerprint,
    settings: settings ?? this.settings,
    sections: sections ?? this.sections,
  );
}

@HiveType(typeId: 5)
enum AssessmentStatus {
  @HiveField(0)
  draft,
  @HiveField(1)
  active,
  @HiveField(2)
  grading,
  @HiveField(3)
  completed,
}

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
  final dynamic correctAnswer; // String for MCQ/TF, List<String> for short answer
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
      type == QuestionType.mcq ||
      type == QuestionType.trueFalse ||
      type == QuestionType.matching ||
      type == QuestionType.multiAnswer;
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
          ? EssayRubric.fromMap(Map<String, dynamic>.from(map['essayRubric']))
          : null,
    );
  }

  static const _sentinel = Object();

  Question copyWith({
    String? id,
    int? number,
    QuestionType? type,
    String? text,
    double? points,
    List<String>? options,
    dynamic correctAnswer = _sentinel,
    dynamic explanation = _sentinel,
    dynamic topicTag = _sentinel,
    dynamic keywords = _sentinel,
    dynamic essayRubric = _sentinel,
  }) => Question(
    id: id ?? this.id,
    number: number ?? this.number,
    type: type ?? this.type,
    text: text ?? this.text,
    points: points ?? this.points,
    options: options ?? this.options,
    correctAnswer: correctAnswer == _sentinel
        ? this.correctAnswer
        : correctAnswer,
    explanation: explanation == _sentinel ? this.explanation : explanation,
    topicTag: topicTag == _sentinel ? this.topicTag : topicTag,
    keywords: keywords == _sentinel ? this.keywords : keywords,
    essayRubric: essayRubric == _sentinel ? this.essayRubric : essayRubric,
  );
}

@HiveType(typeId: 6)
enum QuestionType {
  @HiveField(0)
  mcq,
  @HiveField(1)
  trueFalse,
  @HiveField(2)
  shortAnswer,
  @HiveField(3)
  essay,
  @HiveField(4)
  matching,
  @HiveField(5)
  multiAnswer,
}

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
      map['criteriaDescriptions'] ?? {},
    ),
  );
}

/// Canonical answer-key structure for an assessment.
///
/// A section owns only its [start]/[end] question range and the
/// [QuestionType] for that range. Per-question scoring ([Question.points])
/// remains the sole source of truth for scoring and is intentionally NOT
/// stored here (see Phase 1 scope).
///
/// Persistence semantics:
///  * `sections == null`  -> legacy assessment; [Assessment.effectiveSections]
///    derives the structure from each [Question.type] so nothing is lost.
///  * non-empty list     -> explicit, teacher-defined structure. Once saved,
///    [Question.type] values are kept in sync with these sections so there is
///    a single source of truth for grading and the answer-key fingerprint.
@HiveType(typeId: 11)
class AnswerKeySection {
  @HiveField(0)
  final int start; // 1-based inclusive
  @HiveField(1)
  final int end; // 1-based inclusive
  @HiveField(2)
  final QuestionType type;

  const AnswerKeySection({
    required this.start,
    required this.end,
    required this.type,
  });

  int get count => end - start + 1;

  bool covers(int questionNumber) =>
      questionNumber >= start && questionNumber <= end;

  String get label => start == end ? 'Q$start' : 'Q$start–$end';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnswerKeySection &&
          start == other.start &&
          end == other.end &&
          type == other.type;

  @override
  int get hashCode => start.hashCode ^ end.hashCode ^ type.hashCode;

  @override
  String toString() => 'AnswerKeySection($label, ${type.name})';

  AnswerKeySection copyWith({int? start, int? end, QuestionType? type}) =>
      AnswerKeySection(
        start: start ?? this.start,
        end: end ?? this.end,
        type: type ?? this.type,
      );

  Map<String, dynamic> toMap() => {
        'start': start,
        'end': end,
        'type': type.name,
      };

  factory AnswerKeySection.fromMap(Map<String, dynamic> map) => AnswerKeySection(
        start: map['start'] as int,
        end: map['end'] as int,
        type: questionTypeFromString(map['type'] as String? ?? 'mcq'),
      );
}

/// Result of applying a set of [AnswerKeySection]s to a question list.
class ApplySectionsResult {
  final List<Question> questions;
  final List<int> incompatibleQuestionNumbers;

  const ApplySectionsResult(this.questions, this.incompatibleQuestionNumbers);
}

QuestionType questionTypeFromString(String value) {
  for (final t in QuestionType.values) {
    if (t.name == value) return t;
  }
  return QuestionType.mcq;
}

List<String>? _optionsForType(QuestionType type, List<String>? current) {
  if (type == QuestionType.trueFalse) return const ['True', 'False'];
  if (type == QuestionType.multiAnswer) return const ['A', 'B', 'C', 'D', 'E'];
  return current;
}

/// True when [oldAnswer] can stay attached to a question whose type changes
/// from [oldType] to [newType] without losing meaning.
bool _isAnswerCompatible(
  dynamic oldAnswer,
  QuestionType oldType,
  QuestionType newType,
) {
  if (oldAnswer == null) return true;
  final s = oldAnswer.toString().trim();
  if (s.isEmpty) return true;

  bool letterBased(QuestionType t) =>
      t == QuestionType.mcq || t == QuestionType.multiAnswer;
  bool textBased(QuestionType t) =>
      t == QuestionType.shortAnswer || t == QuestionType.essay;

  if (letterBased(oldType) && letterBased(newType)) return true;
  if (textBased(oldType) && textBased(newType)) return true;
  if (oldType == QuestionType.trueFalse && newType == QuestionType.trueFalse) {
    return true;
  }
  if (oldType == QuestionType.matching && newType == QuestionType.matching) {
    return true;
  }
  return false;
}

/// Collapse a question list (optionally with per-question [overrides]) into
/// contiguous same-type [AnswerKeySection]s.
List<AnswerKeySection> collapseSections(
  List<Question> questions,
  Map<int, QuestionType> overrides,
) {
  if (questions.isEmpty) return [];
  final types = questions.map((q) => overrides[q.number] ?? q.type).toList();
  final result = <AnswerKeySection>[];
  var start = questions.first.number;
  var prev = types.first;
  for (var i = 1; i < types.length; i++) {
    if (types[i] != prev) {
      result.add(AnswerKeySection(
        start: start,
        end: questions[i - 1].number,
        type: prev,
      ));
      start = questions[i].number;
      prev = types[i];
    }
  }
  result.add(AnswerKeySection(
    start: start,
    end: questions.last.number,
    type: prev,
  ));
  return result;
}

/// Apply [sections] to [questions], syncing each question's type.
///
/// Compatible type changes keep the existing answer. Incompatible changes
/// (e.g. MCQ "A" -> Short Answer) are left untouched and reported in
/// [ApplySectionsResult.incompatibleQuestionNumbers] unless
/// [clearIncompatible] is true, in which case those answers are cleared.
ApplySectionsResult applySectionsToQuestions(
  List<Question> questions,
  List<AnswerKeySection> sections, {
  bool clearIncompatible = false,
}) {
  final updated = <Question>[];
  final incompatible = <int>[];
  for (final q in questions) {
    AnswerKeySection? section;
    for (final s in sections) {
      if (s.covers(q.number)) {
        section = s;
        break;
      }
    }
    if (section == null) {
      updated.add(q);
      continue;
    }
    if (q.type == section.type) {
      updated.add(q);
      continue;
    }
    final compatible = _isAnswerCompatible(q.correctAnswer, q.type, section.type);
    if (compatible) {
      updated.add(q.copyWith(
        type: section.type,
        options: _optionsForType(section.type, q.options),
      ));
    } else if (clearIncompatible) {
      updated.add(q.copyWith(
        type: section.type,
        options: _optionsForType(section.type, q.options),
        correctAnswer: '',
      ));
    } else {
      updated.add(q);
      incompatible.add(q.number);
    }
  }
  return ApplySectionsResult(updated, incompatible);
}
