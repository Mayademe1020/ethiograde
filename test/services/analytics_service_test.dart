import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/services/analytics_service.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/models/class_info.dart';

void main() {
  const analytics = AnalyticsService();

  // ── Helper builders ──

  Assessment makeAssessment({
    String rubricType = 'moe_national',
    String className = 'Grade 5A',
    String subject = 'Math',
    List<Question>? questions,
  }) {
    return Assessment(
      title: 'Test',
      subject: subject,
      className: className,
      rubricType: rubricType,
      questions: questions ?? [],
    );
  }

  Question mcq(int number, {String? topicTag}) => Question(
        number: number,
        type: QuestionType.mcq,
        correctAnswer: 'A',
        points: 1.0,
        topicTag: topicTag,
      );

  AnswerMatch correctMatch(int q, {double score = 1, double maxScore = 1}) =>
      AnswerMatch(
        questionNumber: q,
        detectedAnswer: 'A',
        correctAnswer: 'A',
        isCorrect: true,
        score: score,
        maxScore: maxScore,
        confidence: 0.9,
      );

  AnswerMatch wrongMatch(int q, {double maxScore = 1}) => AnswerMatch(
        questionNumber: q,
        detectedAnswer: 'B',
        correctAnswer: 'A',
        isCorrect: false,
        score: 0,
        maxScore: maxScore,
        confidence: 0.8,
      );

  ScanResult makeResult({
    required String studentName,
    required double percentage,
    required String grade,
    required List<AnswerMatch> answers,
    double totalScore = 0,
    double maxScore = 10,
  }) {
    return ScanResult(
      assessmentId: 'a1',
      studentId: 's1',
      studentName: studentName,
      imagePath: '/fake',
      answers: answers,
      totalScore: totalScore,
      maxScore: maxScore,
      percentage: percentage,
      grade: grade,
    );
  }

  // ════════════════════════════════════════════════════════════════
  // computeAnalytics
  // ════════════════════════════════════════════════════════════════

  group('computeAnalytics', () {
    test('empty results → zero analytics', () {
      final assessment = makeAssessment();
      final result = analytics.computeAnalytics(
        assessment: assessment,
        results: [],
      );

      expect(result.classAverage, 0);
      expect(result.totalStudents, 0);
      expect(result.gradeDistribution, isEmpty);
      expect(result.questionAnalytics, isEmpty);
    });

    test('single student → average equals their score', () {
      final assessment = makeAssessment(questions: [mcq(1)]);
      final results = [
        makeResult(
          studentName: 'Abebe',
          percentage: 75,
          grade: 'B',
          totalScore: 7.5,
          maxScore: 10,
          answers: [correctMatch(1)],
        ),
      ];

      final result = analytics.computeAnalytics(
        assessment: assessment,
        results: results,
      );

      expect(result.totalStudents, 1);
      expect(result.classAverage, closeTo(75, 0.01));
      expect(result.highestScore, closeTo(75, 0.01));
      expect(result.lowestScore, closeTo(75, 0.01));
      expect(result.passedStudents, 1);
      expect(result.failedStudents, 0);
    });

    test('multiple students → correct averages and counts', () {
      final assessment = makeAssessment(questions: [mcq(1)]);
      final results = [
        makeResult(
            studentName: 'A',
            percentage: 90,
            grade: 'A',
            totalScore: 9,
            maxScore: 10,
            answers: [correctMatch(1)]),
        makeResult(
            studentName: 'B',
            percentage: 80,
            grade: 'B+',
            totalScore: 8,
            maxScore: 10,
            answers: [correctMatch(1)]),
        makeResult(
            studentName: 'C',
            percentage: 40,
            grade: 'F',
            totalScore: 4,
            maxScore: 10,
            answers: [wrongMatch(1)]),
      ];

      final result = analytics.computeAnalytics(
        assessment: assessment,
        results: results,
      );

      expect(result.totalStudents, 3);
      // (90 + 80 + 40) / 3 = 70
      expect(result.classAverage, closeTo(70.0, 0.01));
      expect(result.highestScore, 90);
      expect(result.lowestScore, 40);
      // Median of [40, 80, 90] = 80
      expect(result.medianScore, closeTo(80.0, 0.01));
      // Pass mark for MoE = 50, so 2 passed, 1 failed
      expect(result.passedStudents, 2);
      expect(result.failedStudents, 1);
      expect(result.passRate, closeTo(66.67, 0.1));
    });

    test('even number of students → median is average of middle two', () {
      final assessment = makeAssessment(questions: [mcq(1)]);
      final results = [
        makeResult(
            studentName: 'A',
            percentage: 60,
            grade: 'C',
            totalScore: 6,
            maxScore: 10,
            answers: [correctMatch(1)]),
        makeResult(
            studentName: 'B',
            percentage: 70,
            grade: 'B-',
            totalScore: 7,
            maxScore: 10,
            answers: [correctMatch(1)]),
        makeResult(
            studentName: 'C',
            percentage: 80,
            grade: 'B+',
            totalScore: 8,
            maxScore: 10,
            answers: [correctMatch(1)]),
        makeResult(
            studentName: 'D',
            percentage: 90,
            grade: 'A',
            totalScore: 9,
            maxScore: 10,
            answers: [correctMatch(1)]),
      ];

      final result = analytics.computeAnalytics(
        assessment: assessment,
        results: results,
      );

      // Median of [60, 70, 80, 90] = (70 + 80) / 2 = 75
      expect(result.medianScore, closeTo(75.0, 0.01));
    });

    test('grade distribution counts correctly', () {
      final assessment = makeAssessment(questions: [mcq(1)]);
      final results = [
        makeResult(
            studentName: 'A',
            percentage: 95,
            grade: 'A+',
            totalScore: 9.5,
            maxScore: 10,
            answers: [correctMatch(1)]),
        makeResult(
            studentName: 'B',
            percentage: 92,
            grade: 'A',
            totalScore: 9.2,
            maxScore: 10,
            answers: [correctMatch(1)]),
        makeResult(
            studentName: 'C',
            percentage: 92,
            grade: 'A',
            totalScore: 9.2,
            maxScore: 10,
            answers: [correctMatch(1)]),
        makeResult(
            studentName: 'D',
            percentage: 45,
            grade: 'F',
            totalScore: 4.5,
            maxScore: 10,
            answers: [wrongMatch(1)]),
      ];

      final result = analytics.computeAnalytics(
        assessment: assessment,
        results: results,
      );

      expect(result.gradeDistribution['A+'], 1);
      expect(result.gradeDistribution['A'], 2);
      expect(result.gradeDistribution['F'], 1);
    });

    test('pass mark varies by rubric type', () {
      final assessmentIntl =
          makeAssessment(rubricType: 'private_international', questions: [mcq(1)]);

      // 55% → fails on international (pass = 60), passes on MoE (pass = 50)
      final results = [
        makeResult(
            studentName: 'A',
            percentage: 55,
            grade: 'D',
            totalScore: 5.5,
            maxScore: 10,
            answers: [wrongMatch(1)]),
      ];

      final resultIntl = analytics.computeAnalytics(
        assessment: assessmentIntl,
        results: results,
      );
      expect(resultIntl.passedStudents, 0); // 55 < 60

      final assessmentMoE =
          makeAssessment(rubricType: 'moe_national', questions: [mcq(1)]);
      final resultMoE = analytics.computeAnalytics(
        assessment: assessmentMoE,
        results: results,
      );
      expect(resultMoE.passedStudents, 1); // 55 >= 50
    });

    test('question analytics: correct rate and distribution', () {
      final assessment = makeAssessment(questions: [mcq(1), mcq(2)]);
      final results = [
        // Student 1: Q1 correct, Q2 wrong
        makeResult(
            studentName: 'A',
            percentage: 50,
            grade: 'D',
            totalScore: 1,
            maxScore: 2,
            answers: [correctMatch(1), wrongMatch(2)]),
        // Student 2: Q1 wrong, Q2 correct
        makeResult(
            studentName: 'B',
            percentage: 50,
            grade: 'D',
            totalScore: 1,
            maxScore: 2,
            answers: [wrongMatch(1), correctMatch(2)]),
      ];

      final result = analytics.computeAnalytics(
        assessment: assessment,
        results: results,
      );

      expect(result.questionAnalytics.length, 2);

      final q1 = result.questionAnalytics
          .firstWhere((q) => q.questionNumber == 1);
      expect(q1.correctRate, closeTo(0.5, 0.01));
      expect(q1.totalAttempts, 2);
      expect(q1.correctAttempts, 1);

      final q2 = result.questionAnalytics
          .firstWhere((q) => q.questionNumber == 2);
      expect(q2.correctRate, closeTo(0.5, 0.01));
    });

    test('topic scores averaged correctly', () {
      final assessment = makeAssessment(
        questions: [mcq(1, topicTag: 'Algebra'), mcq(2, topicTag: 'Geometry')],
      );

      final results = [
        makeResult(
          studentName: 'A',
          percentage: 100,
          grade: 'A+',
          totalScore: 2,
          maxScore: 2,
          answers: [
            correctMatch(1, score: 1, maxScore: 1),
            correctMatch(2, score: 1, maxScore: 1),
          ],
        ),
        makeResult(
          studentName: 'B',
          percentage: 50,
          grade: 'D',
          totalScore: 1,
          maxScore: 2,
          answers: [
            correctMatch(1, score: 1, maxScore: 1),
            wrongMatch(2, maxScore: 1),
          ],
        ),
      ];

      final result = analytics.computeAnalytics(
        assessment: assessment,
        results: results,
      );

      // Algebra: 100% + 100% = avg 100%
      expect(result.topicScores['Algebra'], closeTo(100.0, 0.01));
      // Geometry: 100% + 0% = avg 50%
      expect(result.topicScores['Geometry'], closeTo(50.0, 0.01));
    });
  });

  // ════════════════════════════════════════════════════════════════
  // getDifficultQuestions
  // ════════════════════════════════════════════════════════════════

  group('getDifficultQuestions', () {
    test('filters questions below threshold', () {
      final questions = [
        const QuestionAnalytics(questionNumber: 1, correctRate: 0.2),
        const QuestionAnalytics(questionNumber: 2, correctRate: 0.8),
        const QuestionAnalytics(questionNumber: 3, correctRate: 0.35),
      ];

      final result = analytics.getDifficultQuestions(questions);

      expect(result.length, 2);
      expect(result[0].questionNumber, 1); // 0.2 < 0.35, sorted asc
      expect(result[1].questionNumber, 3);
    });

    test('custom threshold', () {
      final questions = [
        const QuestionAnalytics(questionNumber: 1, correctRate: 0.5),
        const QuestionAnalytics(questionNumber: 2, correctRate: 0.55),
      ];

      final result =
          analytics.getDifficultQuestions(questions, threshold: 0.5);

      expect(result.length, 1);
      expect(result[0].questionNumber, 1);
    });

    test('all above threshold → empty', () {
      final questions = [
        const QuestionAnalytics(questionNumber: 1, correctRate: 0.9),
        const QuestionAnalytics(questionNumber: 2, correctRate: 0.85),
      ];

      expect(analytics.getDifficultQuestions(questions), isEmpty);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // getEasyQuestions
  // ════════════════════════════════════════════════════════════════

  group('getEasyQuestions', () {
    test('filters questions above threshold', () {
      final questions = [
        const QuestionAnalytics(questionNumber: 1, correctRate: 0.95),
        const QuestionAnalytics(questionNumber: 2, correctRate: 0.5),
        const QuestionAnalytics(questionNumber: 3, correctRate: 0.9),
      ];

      final result = analytics.getEasyQuestions(questions);

      expect(result.length, 2);
      expect(result[0].questionNumber, 1); // 0.95 > 0.9, sorted desc
      expect(result[1].questionNumber, 3);
    });

    test('all below threshold → empty', () {
      final questions = [
        const QuestionAnalytics(questionNumber: 1, correctRate: 0.5),
      ];

      expect(analytics.getEasyQuestions(questions), isEmpty);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // getTopicHeatmap
  // ════════════════════════════════════════════════════════════════

  group('getTopicHeatmap', () {
    test('accumulates correct counts per topic per subject', () {
      final mathAssessment = makeAssessment(
        subject: 'Math',
        questions: [mcq(1, topicTag: 'Algebra')],
      );
      final scienceAssessment = makeAssessment(
        subject: 'Science',
        questions: [mcq(1, topicTag: 'Biology')],
      );

      final mathResults = [
        makeResult(
          studentName: 'A',
          percentage: 100,
          grade: 'A+',
          totalScore: 1,
          maxScore: 1,
          answers: [correctMatch(1)],
        ),
        makeResult(
          studentName: 'B',
          percentage: 0,
          grade: 'F',
          totalScore: 0,
          maxScore: 1,
          answers: [wrongMatch(1)],
        ),
      ];

      final scienceResults = [
        makeResult(
          studentName: 'A',
          percentage: 100,
          grade: 'A+',
          totalScore: 1,
          maxScore: 1,
          answers: [correctMatch(1)],
        ),
      ];

      final heatmap = analytics.getTopicHeatmap(
        assessments: [mathAssessment, scienceAssessment],
        allResults: [mathResults, scienceResults],
      );

      // Algebra under Math: 1 correct + 0 correct = 1
      expect(heatmap['Algebra']!['Math'], 1);
      // Biology under Science: 1 correct
      expect(heatmap['Biology']!['Science'], 1);
    });

    test('no topic tag → falls under General', () {
      final assessment = makeAssessment(
        subject: 'Math',
        questions: [Question(number: 1, type: QuestionType.mcq, correctAnswer: 'A', points: 1)],
      );
      final results = [
        makeResult(
          studentName: 'A',
          percentage: 100,
          grade: 'A+',
          totalScore: 1,
          maxScore: 1,
          answers: [correctMatch(1)],
        ),
      ];

      final heatmap = analytics.getTopicHeatmap(
        assessments: [assessment],
        allResults: [results],
      );

      expect(heatmap['General']!['Math'], 1);
    });

    test('empty assessments → empty heatmap', () {
      final heatmap = analytics.getTopicHeatmap(
        assessments: [],
        allResults: [],
      );

      expect(heatmap, isEmpty);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // QuestionAnalytics.isDifficult / isEasy
  // ════════════════════════════════════════════════════════════════

  group('QuestionAnalytics flags', () {
    test('isDifficult: correctRate < 0.4', () {
      expect(
          const QuestionAnalytics(questionNumber: 1, correctRate: 0.3)
              .isDifficult,
          isTrue);
      expect(
          const QuestionAnalytics(questionNumber: 1, correctRate: 0.4)
              .isDifficult,
          isFalse);
    });

    test('isEasy: correctRate > 0.85', () {
      expect(
          const QuestionAnalytics(questionNumber: 1, correctRate: 0.9).isEasy,
          isTrue);
      expect(
          const QuestionAnalytics(questionNumber: 1, correctRate: 0.85).isEasy,
          isFalse);
    });
  });
}
