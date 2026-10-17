/// Data models for item analysis — per-question statistics and class summary.
///
/// Computed from ScanResult answers, no persistence needed.
/// Used by ItemAnalysisService to generate analytics for teachers.
class QuestionStats {
  final int questionNumber;
  final String questionText;
  final int totalStudents;
  final int correctCount;
  final double difficulty; // 0.0 - 1.0 (% correct)
  final double discrimination; // -1.0 to 1.0
  final Map<String, int> answerDistribution; // {'A': 5, 'B': 12, ...}
  final String? mostCommonWrong;
  final String difficultyLabel; // 'Easy', 'Medium', 'Hard'

  const QuestionStats({
    required this.questionNumber,
    this.questionText = '',
    required this.totalStudents,
    required this.correctCount,
    required this.difficulty,
    required this.discrimination,
    required this.answerDistribution,
    this.mostCommonWrong,
    required this.difficultyLabel,
  });

  double get incorrectRate => totalStudents > 0 ? 1.0 - difficulty : 0.0;

  int get unansweredCount => answerDistribution['(unanswered)'] ?? 0;

  bool get isLowDiscrimination => discrimination < 0.3;
}

/// Answer option breakdown for a single question.
class AnswerBreakdown {
  final String option;
  final int count;
  final double percentage;
  final bool isCorrectOption;

  const AnswerBreakdown({
    required this.option,
    required this.count,
    required this.percentage,
    required this.isCorrectOption,
  });
}

/// Class-wide summary of all question statistics.
class ClassAnalysisSummary {
  final int totalStudents;
  final int totalQuestions;
  final double averageScore;
  final double medianScore;
  final double passRate;
  final List<QuestionStats> questions;
  final int easyCount;
  final int mediumCount;
  final int hardCount;
  final int lowDiscriminationCount;

  const ClassAnalysisSummary({
    required this.totalStudents,
    required this.totalQuestions,
    required this.averageScore,
    required this.medianScore,
    required this.passRate,
    required this.questions,
    required this.easyCount,
    required this.mediumCount,
    required this.hardCount,
    required this.lowDiscriminationCount,
  });

  static const ClassAnalysisSummary empty = ClassAnalysisSummary(
    totalStudents: 0,
    totalQuestions: 0,
    averageScore: 0,
    medianScore: 0,
    passRate: 0,
    questions: [],
    easyCount: 0,
    mediumCount: 0,
    hardCount: 0,
    lowDiscriminationCount: 0,
  );

  List<QuestionStats> get hardQuestions =>
      questions.where((q) => q.difficultyLabel == 'Hard').toList();

  List<QuestionStats> get lowDiscriminationQuestions =>
      questions.where((q) => q.isLowDiscrimination).toList();
}
