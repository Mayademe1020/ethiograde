import '../models/assessment.dart';

/// Configuration for answer sheet PDF generation.
///
/// All settings the teacher controls from the setup screen before
/// generating the answer sheet PDF + coordinate map.
class AnswerSheetConfig {
  final String assessmentId;
  final String schoolName;
  final String examName;
  final String subject;
  final int questionsPerPage; // 0 = auto
  final bool prefillStudentNames;
  final List<StudentNameEntry> students; // only if prefill is true
  final List<QuestionTypeRange> typeRanges; // auto-detected from assessment

  const AnswerSheetConfig({
    required this.assessmentId,
    this.schoolName = '',
    this.examName = '',
    this.subject = '',
    this.questionsPerPage = 0,
    this.prefillStudentNames = false,
    this.students = const [],
    this.typeRanges = const [],
  });

  /// Auto-detect type ranges from an assessment's questions.
  static List<QuestionTypeRange> detectRanges(Assessment assessment) {
    if (assessment.questions.isEmpty) return [];

    final ranges = <QuestionTypeRange>[];
    int rangeStart = 0;
    bool currentIsMcq = assessment.questions[0].type == QuestionType.mcq ||
        assessment.questions[0].type == QuestionType.matching;

    for (int i = 1; i <= assessment.questions.length; i++) {
      final isLast = i == assessment.questions.length;
      final isMcq = isLast ||
          assessment.questions[i].type == QuestionType.mcq ||
          assessment.questions[i].type == QuestionType.matching;

      if (isLast || isMcq != currentIsMcq) {
        ranges.add(QuestionTypeRange(
          start: rangeStart + 1,
          end: isLast ? i : i,
          isMcq: currentIsMcq));
        if (!isLast) {
          rangeStart = i;
          currentIsMcq = isMcq;
        }
      }
    }

    return ranges;
  }

  int get totalQuestions =>
      typeRanges.fold(0, (sum, r) => sum + (r.end - r.start + 1));

  int get mcqCount => typeRanges
      .where((r) => r.isMcq)
      .fold(0, (sum, r) => sum + (r.end - r.start + 1));

  int get tfCount => typeRanges
      .where((r) => !r.isMcq)
      .fold(0, (sum, r) => sum + (r.end - r.start + 1));

  AnswerSheetConfig copyWith({
    String? schoolName,
    String? examName,
    String? subject,
    int? questionsPerPage,
    bool? prefillStudentNames,
    List<StudentNameEntry>? students,
    List<QuestionTypeRange>? typeRanges,
  }) =>
      AnswerSheetConfig(
        assessmentId: assessmentId,
        schoolName: schoolName ?? this.schoolName,
        examName: examName ?? this.examName,
        subject: subject ?? this.subject,
        questionsPerPage: questionsPerPage ?? this.questionsPerPage,
        prefillStudentNames: prefillStudentNames ?? this.prefillStudentNames,
        students: students ?? this.students,
        typeRanges: typeRanges ?? this.typeRanges);
}

/// A range of questions with a specific type.
class QuestionTypeRange {
  final int start; // 1-based
  final int end; // 1-based, inclusive
  final bool isMcq; // true = MCQ, false = T/F

  const QuestionTypeRange({
    required this.start,
    required this.end,
    required this.isMcq,
  });

  int get count => end - start + 1;

  String get label => start == end ? 'Q$start' : 'Q$start–$end';
}

/// A student entry for pre-filled name sheets.
class StudentNameEntry {
  final String id;
  final String name;
  final String studentId;

  const StudentNameEntry({
    required this.id,
    required this.name,
    required this.studentId,
  });
}
