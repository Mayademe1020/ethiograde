import '../models/assessment.dart';
import '../models/scan_result.dart';
import '../models/item_analysis.dart';

/// Computes item analysis statistics from scan results.
///
/// Provides per-question metrics (difficulty, discrimination, answer distribution)
/// and class-wide summary statistics. No persistence — all computed on-the-fly.
class ItemAnalysisService {
  const ItemAnalysisService();

  /// Compute per-question statistics for all questions in the assessment.
  List<QuestionStats> computeQuestionStats({
    required List<ScanResult> results,
    required Assessment assessment,
  }) {
    if (results.isEmpty || assessment.questions.isEmpty) return [];

    final gradedResults = results.where((r) => r.status == ScanStatus.graded || r.status == ScanStatus.reviewed).toList();
    if (gradedResults.isEmpty) return [];

    final totalStudents = gradedResults.length;
    final questionStats = <QuestionStats>[];

    for (final question in assessment.questions) {
      final qNumber = question.number;

      // Gather answers for this question across all students
      final answers = <String>[];
      int correctCount = 0;

      for (final result in gradedResults) {
        final match = result.answers.firstWhere(
          (a) => a.questionNumber == qNumber,
          orElse: () => AnswerMatch(
            questionNumber: qNumber,
            detectedAnswer: '',
            correctAnswer: '',
            isCorrect: false,
            score: 0,
            maxScore: question.points,
          ),
        );
        answers.add(match.detectedAnswer);
        if (match.isCorrect) correctCount++;
      }

      final difficulty = totalStudents > 0 ? correctCount / totalStudents : 0.0;

      // Answer distribution
      final distribution = <String, int>{};
      for (final answer in answers) {
        final key = answer.isEmpty ? '(unanswered)' : answer.toUpperCase();
        distribution[key] = (distribution[key] ?? 0) + 1;
      }

      // Most common wrong answer
      String? mostCommonWrong;
      final correctAnswer = question.correctAnswer?.toString().toUpperCase() ?? '';
      if (correctAnswer.isNotEmpty) {
        final wrongAnswers = distribution.entries
            .where((e) => e.key != correctAnswer && e.key != '(unanswered)')
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        if (wrongAnswers.isNotEmpty) {
          mostCommonWrong = wrongAnswers.first.key;
        }
      }

      // Discrimination index (top 27% vs bottom 27%)
      final discrimination = _computeDiscrimination(
        questionNumber: qNumber,
        results: gradedResults,
        totalStudents: totalStudents,
      );

      // Difficulty label
      String difficultyLabel;
      if (difficulty > 0.8) {
        difficultyLabel = 'Easy';
      } else if (difficulty >= 0.5) {
        difficultyLabel = 'Medium';
      } else {
        difficultyLabel = 'Hard';
      }

      questionStats.add(QuestionStats(
        questionNumber: qNumber,
        questionText: question.text,
        totalStudents: totalStudents,
        correctCount: correctCount,
        difficulty: difficulty,
        discrimination: discrimination,
        answerDistribution: distribution,
        mostCommonWrong: mostCommonWrong,
        difficultyLabel: difficultyLabel,
      ));
    }

    return questionStats;
  }

  /// Compute discrimination index for a single question.
  ///
  /// Uses the top 27% vs bottom 27% method:
  /// - Sort students by total score
  /// - Compare correct rate in top group vs bottom group
  /// - Range: -1.0 (inverted) to 1.0 (perfect discrimination)
  double _computeDiscrimination({
    required int questionNumber,
    required List<ScanResult> results,
    required int totalStudents,
  }) {
    if (totalStudents < 4) return 0.0; // Need at least 4 students

    // Sort results by total score (descending)
    final sorted = List<ScanResult>.from(results)
      ..sort((a, b) => b.totalScore.compareTo(a.totalScore));

    final groupSize = (totalStudents * 0.27).ceil().clamp(2, totalStudents ~/ 2);
    final topGroup = sorted.sublist(0, groupSize);
    final bottomGroup = sorted.sublist(totalStudents - groupSize);

    // Count correct in each group
    int topCorrect = 0;
    int bottomCorrect = 0;

    for (final result in topGroup) {
      final match = result.answers.firstWhere(
        (a) => a.questionNumber == questionNumber,
        orElse: () => AnswerMatch(
          questionNumber: questionNumber,
          detectedAnswer: '',
          correctAnswer: '',
          isCorrect: false,
          score: 0,
          maxScore: 1,
        ),
      );
      if (match.isCorrect) topCorrect++;
    }

    for (final result in bottomGroup) {
      final match = result.answers.firstWhere(
        (a) => a.questionNumber == questionNumber,
        orElse: () => AnswerMatch(
          questionNumber: questionNumber,
          detectedAnswer: '',
          correctAnswer: '',
          isCorrect: false,
          score: 0,
          maxScore: 1,
        ),
      );
      if (match.isCorrect) bottomCorrect++;
    }

    final topRate = topCorrect / groupSize;
    final bottomRate = bottomCorrect / groupSize;

    return topRate - bottomRate;
  }

  /// Compute class-wide summary statistics.
  ClassAnalysisSummary computeSummary({
    required List<ScanResult> results,
    required Assessment assessment,
  }) {
    final gradedResults = results.where((r) =>
        r.status == ScanStatus.graded || r.status == ScanStatus.reviewed).toList();

    if (gradedResults.isEmpty) return ClassAnalysisSummary.empty;

    final percentages = gradedResults.map((r) => r.percentage).toList()..sort();
    final average = percentages.reduce((a, b) => a + b) / percentages.length;
    final median = _median(percentages);
    final passCount = gradedResults.where((r) => r.percentage >= 50).length;
    final passRate = passCount / gradedResults.length * 100;

    final questionStats = computeQuestionStats(
      results: gradedResults,
      assessment: assessment,
    );

    final easyCount = questionStats.where((q) => q.difficultyLabel == 'Easy').length;
    final mediumCount = questionStats.where((q) => q.difficultyLabel == 'Medium').length;
    final hardCount = questionStats.where((q) => q.difficultyLabel == 'Hard').length;
    final lowDiscCount = questionStats.where((q) => q.isLowDiscrimination).length;

    return ClassAnalysisSummary(
      totalStudents: gradedResults.length,
      totalQuestions: assessment.questions.length,
      averageScore: average,
      medianScore: median,
      passRate: passRate,
      questions: questionStats,
      easyCount: easyCount,
      mediumCount: mediumCount,
      hardCount: hardCount,
      lowDiscriminationCount: lowDiscCount,
    );
  }

  /// Get answer breakdown for a specific question (for detail view).
  List<AnswerBreakdown> getAnswerBreakdown({
    required int questionNumber,
    required List<ScanResult> results,
    required String correctAnswer,
  }) {
    final distribution = <String, int>{};
    int total = 0;

    for (final result in results) {
      final match = result.answers.firstWhere(
        (a) => a.questionNumber == questionNumber,
        orElse: () => AnswerMatch(
          questionNumber: questionNumber,
          detectedAnswer: '',
          correctAnswer: '',
          isCorrect: false,
          score: 0,
          maxScore: 1,
        ),
      );
      final answer = match.detectedAnswer.isEmpty ? '(unanswered)' : match.detectedAnswer.toUpperCase();
      distribution[answer] = (distribution[answer] ?? 0) + 1;
      total++;
    }

    return distribution.entries.map((e) {
      final pct = total > 0 ? e.value / total * 100 : 0.0;
      return AnswerBreakdown(
        option: e.key,
        count: e.value,
        percentage: pct,
        isCorrectOption: e.key == correctAnswer.toUpperCase(),
      );
    }).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  double _median(List<double> sorted) {
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }
}
