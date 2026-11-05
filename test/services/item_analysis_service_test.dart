import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/services/item_analysis_service.dart';

void main() {
  const service = ItemAnalysisService();

  Assessment makeAssessment({List<Question>? questions}) => Assessment(
    title: 'Biology',
    subject: 'Biology',
    questions:
        questions ??
        [
          Question(
            number: 1,
            type: QuestionType.mcq,
            points: 1,
            correctAnswer: 'A',
            text: 'Capital?',
          ),
          Question(
            number: 2,
            type: QuestionType.mcq,
            points: 1,
            correctAnswer: 'B',
            text: 'Largest?',
          ),
        ],
  );

  ScanResult makeResult({
    required String id,
    required double percentage,
    required double totalScore,
    required List<AnswerMatch> answers,
    ScanStatus status = ScanStatus.graded,
  }) {
    return ScanResult(
      id: id,
      assessmentId: 'a1',
      studentId: id,
      studentName: 'Student $id',
      imagePath: '/path/$id.jpg',
      answers: answers,
      totalScore: totalScore,
      maxScore: 2,
      percentage: percentage,
      grade: '',
      status: status,
      confidence: 1,
    );
  }

  AnswerMatch answer(
    int q,
    String detected,
    String correct, {
    bool isCorrect = true,
  }) {
    return AnswerMatch(
      questionNumber: q,
      detectedAnswer: detected,
      correctAnswer: correct,
      isCorrect: isCorrect,
      score: isCorrect ? 1 : 0,
      maxScore: 1,
      confidence: 1,
    );
  }

  group('computeSummary', () {
    test('empty results returns empty summary', () {
      final summary = service.computeSummary(
        results: [],
        assessment: makeAssessment(),
      );
      expect(summary.totalStudents, 0);
      expect(summary.questions, isEmpty);
    });

    test('only pending results yields empty summary', () {
      final summary = service.computeSummary(
        results: [
          makeResult(
            id: 's1',
            percentage: 50,
            totalScore: 1,
            answers: [],
            status: ScanStatus.pending,
          ),
        ],
        assessment: makeAssessment(),
      );
      expect(summary.totalStudents, 0);
    });

    test('computes average, median, and pass rate', () {
      final assessment = makeAssessment();
      final results = [
        makeResult(
          id: 's1',
          percentage: 100,
          totalScore: 2,
          answers: [answer(1, 'A', 'A'), answer(2, 'B', 'B')],
        ),
        makeResult(
          id: 's2',
          percentage: 50,
          totalScore: 1,
          answers: [answer(1, 'A', 'A'), answer(2, 'C', 'B', isCorrect: false)],
        ),
        makeResult(
          id: 's3',
          percentage: 0,
          totalScore: 0,
          answers: [
            answer(1, 'C', 'A', isCorrect: false),
            answer(2, 'C', 'B', isCorrect: false),
          ],
        ),
      ];

      final summary = service.computeSummary(
        results: results,
        assessment: assessment,
      );

      expect(summary.totalStudents, 3);
      expect(summary.totalQuestions, 2);
      expect(summary.averageScore, closeTo(50.0, 0.001));
      expect(summary.medianScore, 50.0);
      expect(summary.passRate, closeTo(66.666, 0.01));
    });

    test('classifies question difficulty by correct rate', () {
      final assessment = makeAssessment();
      // Q1: 2/3 correct → medium (0.66). Q2: 1/3 correct → hard (0.33)
      final results = [
        makeResult(
          id: 's1',
          percentage: 100,
          totalScore: 2,
          answers: [answer(1, 'A', 'A'), answer(2, 'B', 'B')],
        ),
        makeResult(
          id: 's2',
          percentage: 50,
          totalScore: 1,
          answers: [answer(1, 'A', 'A'), answer(2, 'C', 'B', isCorrect: false)],
        ),
        makeResult(
          id: 's3',
          percentage: 0,
          totalScore: 0,
          answers: [
            answer(1, 'C', 'A', isCorrect: false),
            answer(2, 'C', 'B', isCorrect: false),
          ],
        ),
      ];

      final summary = service.computeSummary(
        results: results,
        assessment: assessment,
      );

      expect(summary.easyCount, 0);
      expect(summary.mediumCount, 1);
      expect(summary.hardCount, 1);

      final q1 = summary.questions.firstWhere((q) => q.questionNumber == 1);
      final q2 = summary.questions.firstWhere((q) => q.questionNumber == 2);
      expect(q1.difficultyLabel, 'Medium');
      expect(q2.difficultyLabel, 'Hard');
    });
  });

  group('computeQuestionStats', () {
    test('returns stats for each question', () {
      final assessment = makeAssessment();
      final results = [
        makeResult(
          id: 's1',
          percentage: 100,
          totalScore: 2,
          answers: [answer(1, 'A', 'A'), answer(2, 'B', 'B')],
        ),
        makeResult(
          id: 's2',
          percentage: 0,
          totalScore: 0,
          answers: [
            answer(1, 'B', 'A', isCorrect: false),
            answer(2, 'C', 'B', isCorrect: false),
          ],
        ),
      ];

      final stats = service.computeQuestionStats(
        results: results,
        assessment: assessment,
      );

      expect(stats, hasLength(2));
      final q1 = stats.firstWhere((q) => q.questionNumber == 1);
      expect(q1.correctCount, 1);
      expect(q1.totalStudents, 2);
      expect(q1.difficulty, 0.5);
      expect(q1.answerDistribution['A'], 1);
      expect(q1.answerDistribution['B'], 1);
      expect(q1.mostCommonWrong, 'B');
    });

    test('unanswered answers are grouped separately', () {
      final assessment = makeAssessment();
      final results = [
        makeResult(
          id: 's1',
          percentage: 100,
          totalScore: 2,
          answers: [answer(1, 'A', 'A'), answer(2, 'B', 'B')],
        ),
        makeResult(
          id: 's2',
          percentage: 50,
          totalScore: 1,
          answers: [answer(1, '', 'A', isCorrect: false), answer(2, 'B', 'B')],
        ),
      ];

      final stats = service.computeQuestionStats(
        results: results,
        assessment: assessment,
      );

      final q1 = stats.firstWhere((q) => q.questionNumber == 1);
      expect(q1.unansweredCount, 1);
      expect(q1.answerDistribution['(unanswered)'], 1);
    });
  });

  group('discrimination index', () {
    test('returns 0 for fewer than 4 students', () {
      final assessment = makeAssessment();
      final results = [
        makeResult(
          id: 's1',
          percentage: 100,
          totalScore: 2,
          answers: [answer(1, 'A', 'A'), answer(2, 'B', 'B')],
        ),
        makeResult(
          id: 's2',
          percentage: 0,
          totalScore: 0,
          answers: [
            answer(1, 'C', 'A', isCorrect: false),
            answer(2, 'C', 'B', isCorrect: false),
          ],
        ),
      ];

      final stats = service.computeQuestionStats(
        results: results,
        assessment: assessment,
      );
      expect(stats.first.discrimination, 0.0);
    });

    test('positive discrimination when top students get it right', () {
      final assessment = makeAssessment();
      // 8 students. Q1: all top scorers correct, bottom scorers wrong
      final results = <ScanResult>[
        for (var i = 0; i < 8; i++)
          makeResult(
            id: 's$i',
            percentage: i >= 4 ? 100.0 : 0.0,
            totalScore: i >= 4 ? 2.0 : 0.0,
            answers: [
              answer(1, i >= 4 ? 'A' : 'C', 'A', isCorrect: i >= 4),
              answer(2, 'B', 'B'),
            ],
          ),
      ];

      final stats = service.computeQuestionStats(
        results: results,
        assessment: assessment,
      );

      final q1 = stats.firstWhere((q) => q.questionNumber == 1);
      expect(q1.discrimination, greaterThan(0.5));
    });
  });

  group('getAnswerBreakdown', () {
    test('sorts by count descending and flags correct option', () {
      final results = [
        makeResult(
          id: 's1',
          percentage: 100,
          totalScore: 2,
          answers: [answer(1, 'A', 'A')],
        ),
        makeResult(
          id: 's2',
          percentage: 0,
          totalScore: 0,
          answers: [answer(1, 'B', 'A', isCorrect: false)],
        ),
        makeResult(
          id: 's3',
          percentage: 0,
          totalScore: 0,
          answers: [answer(1, 'B', 'A', isCorrect: false)],
        ),
        makeResult(
          id: 's4',
          percentage: 0,
          totalScore: 0,
          answers: [answer(1, 'C', 'A', isCorrect: false)],
        ),
      ];

      final breakdown = service.getAnswerBreakdown(
        questionNumber: 1,
        results: results,
        correctAnswer: 'A',
      );

      expect(breakdown, hasLength(3));
      // B (2) sorts before A (1) and C (1)
      expect(breakdown.first.option, 'B');
      expect(breakdown.first.count, 2);
      final a = breakdown.firstWhere((b) => b.option == 'A');
      expect(a.isCorrectOption, isTrue);
      expect(a.percentage, 25.0);
    });
  });
}
