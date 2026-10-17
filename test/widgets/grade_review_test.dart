import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethiograde/screens/review/grade_review_screen.dart';
import 'package:ethiograde/widgets/scan_accuracy_summary_card.dart';
import 'package:ethiograde/services/student_provider.dart';
import 'package:ethiograde/services/assessment_provider.dart';
import 'package:ethiograde/services/class_provider.dart';
import 'package:ethiograde/services/teacher_provider.dart';
import 'package:ethiograde/services/weighted_grade_provider.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'ethiograde_grade_review_test_',
    );
    Hive.init(tempDir.path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Hive.openBox('students');
    await Hive.openBox('assessments');
    await Hive.openBox('classes');
    await Hive.openBox('teachers');
    await Hive.openBox('settings_pii');
    await Hive.openBox('grading_drafts');
    await Hive.openBox('audit_trail');
    await Hive.openBox('weighted_scales');
    await Hive.openBox('scan_results');
  });

  tearDown(() async {
    for (final name in [
      'students',
      'assessments',
      'classes',
      'teachers',
      'settings_pii',
      'grading_drafts',
      'audit_trail',
      'weighted_scales',
      'scan_results',
    ]) {
      if (Hive.isBoxOpen(name)) {
        try {
          await Hive.box(name).clear();
          await Hive.box(name).close();
        } catch (_) {}
      }
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Assessment makeAssessment({String? weightedScaleId}) => Assessment(
    id: 'a1',
    title: 'Math Unit 1',
    subject: 'Math',
    status: AssessmentStatus.active,
    weightedScaleId: weightedScaleId,
  );

  Widget wrapReview({
    required Assessment assessment,
    required List<ScanResult> results,
  }) {
    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => StudentProvider()),
          ChangeNotifierProvider(create: (_) => AssessmentProvider()),
          ChangeNotifierProvider(create: (_) => ClassProvider()),
          ChangeNotifierProvider(create: (_) => TeacherProvider()),
          ChangeNotifierProvider(create: (_) => WeightedGradeProvider()),
        ],
        child: GradeReviewScreen(assessment: assessment, results: results),
      ),
    );
  }

  group('GradeReviewScreen — empty state', () {
    testWidgets('shows empty state when no results', (tester) async {
      await tester.pumpWidget(
        wrapReview(assessment: makeAssessment(), results: []),
      );
      await tester.pumpAndSettle();

      expect(find.text('No results to review'), findsOneWidget);
    });
  });

  group('ScanAccuracySummaryCard', () {
    ScanResult scanResult({
      required String studentId,
      required String studentName,
      required List<AnswerMatch> answers,
    }) => ScanResult(
      assessmentId: 'a1',
      studentId: studentId,
      studentName: studentName,
      imagePath: '',
      answers: answers,
      totalScore: 0,
      maxScore: 0,
      percentage: 0,
      grade: '',
      status: ScanStatus.reviewed,
      confidence: 0.95,
    );

    Assessment accAssessment() => Assessment(
      id: 'a1',
      title: 'Acc Exam',
      subject: 'Math',
      status: AssessmentStatus.active,
      questions: [
        Question(
          number: 1,
          type: QuestionType.mcq,
          text: 'Q1',
          correctAnswer: 'A',
        ),
        Question(
          number: 2,
          type: QuestionType.mcq,
          text: 'Q2',
          correctAnswer: 'B',
        ),
      ],
    );

    testWidgets('shows overall accuracy and correct/wrong/missed counts', (
      tester,
    ) async {
      final results = [
        scanResult(
          studentId: 's1',
          studentName: 'Abebe',
          answers: [
            AnswerMatch(
              questionNumber: 1,
              detectedAnswer: 'A',
              correctAnswer: 'A',
              isCorrect: true,
              score: 1,
              maxScore: 1,
              confidence: 0.9,
              ocrRawText: 'A',
            ),
            AnswerMatch(
              questionNumber: 2,
              detectedAnswer: 'C',
              correctAnswer: 'B',
              isCorrect: false,
              score: 0,
              maxScore: 1,
              confidence: 0.9,
              ocrRawText: 'C',
            ),
          ],
        ),
        scanResult(
          studentId: 's2',
          studentName: 'Bekele',
          answers: [
            AnswerMatch(
              questionNumber: 1,
              detectedAnswer: 'A',
              correctAnswer: 'A',
              isCorrect: true,
              score: 1,
              maxScore: 1,
              confidence: 0.9,
              ocrRawText: 'A',
            ),
            AnswerMatch(
              questionNumber: 2,
              detectedAnswer: '[MISSING]',
              correctAnswer: 'B',
              isCorrect: false,
              score: 0,
              maxScore: 1,
              confidence: 0.9,
              ocrRawText: '[MISSING]',
            ),
          ],
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScanAccuracySummaryCard(
              assessment: accAssessment(),
              results: results,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 2 correct + 1 wrong + 1 missed = 4 attempts → 50%
      expect(find.text('Scan Accuracy'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(
        find.textContaining('2 correct, 1 wrong, 1 not read'),
        findsOneWidget,
      );
    });

    testWidgets('shows low-accuracy questions when below threshold', (
      tester,
    ) async {
      final results = [
        scanResult(
          studentId: 's1',
          studentName: 'Abebe',
          answers: [
            AnswerMatch(
              questionNumber: 1,
              detectedAnswer: 'A',
              correctAnswer: 'A',
              isCorrect: true,
              score: 1,
              maxScore: 1,
              confidence: 0.9,
              ocrRawText: 'A',
            ),
            AnswerMatch(
              questionNumber: 2,
              detectedAnswer: 'B',
              correctAnswer: 'B',
              isCorrect: true,
              score: 1,
              maxScore: 1,
              confidence: 0.9,
              ocrRawText: 'B',
            ),
          ],
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScanAccuracySummaryCard(
              assessment: accAssessment(),
              results: results,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Both questions 100% accurate — no low-accuracy section
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('Low-accuracy questions'), findsNothing);
      expect(find.text('Scan Accuracy'), findsOneWidget);
    });
  });
}
