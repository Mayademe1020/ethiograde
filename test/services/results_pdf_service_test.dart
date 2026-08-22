import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/services/results_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return Directory.systemTemp.path;
          }
          return null;
        });
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Assessment makeAssessment() => Assessment(
    title: 'Biology Final',
    subject: 'Biology',
    className: '10A',
    questions: [
      Question(
        number: 1,
        type: QuestionType.mcq,
        points: 1,
        correctAnswer: 'A',
      ),
      Question(
        number: 2,
        type: QuestionType.mcq,
        points: 1,
        correctAnswer: 'B',
      ),
    ],
  );

  ScanResult makeResult({
    required String name,
    required double score,
    required double max,
    required double pct,
    required String grade,
    required List<AnswerMatch> answers,
  }) {
    return ScanResult(
      id: name,
      assessmentId: 'a1',
      studentId: name,
      studentName: name,
      imagePath: '/path/$name.jpg',
      answers: answers,
      totalScore: score,
      maxScore: max,
      percentage: pct,
      grade: grade,
      status: ScanStatus.graded,
      confidence: 0.9,
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

  test('generates a valid PDF report file', () async {
    final results = [
      makeResult(
        name: 'Abebe',
        score: 2,
        max: 2,
        pct: 100,
        grade: 'A+',
        answers: [answer(1, 'A', 'A'), answer(2, 'B', 'B')],
      ),
      makeResult(
        name: 'Bekele',
        score: 1,
        max: 2,
        pct: 50,
        grade: 'C',
        answers: [answer(1, 'A', 'A'), answer(2, 'C', 'B', isCorrect: false)],
      ),
      makeResult(
        name: 'Chala',
        score: 0,
        max: 2,
        pct: 0,
        grade: 'F',
        answers: [
          answer(1, 'C', 'A', isCorrect: false),
          answer(2, 'C', 'B', isCorrect: false),
        ],
      ),
    ];

    final file = await ResultsPdfService().generateResultsReport(
      assessment: makeAssessment(),
      results: results,
      schoolName: 'Test School',
      teacherName: 'Mr. Tesfaye',
    );

    expect(await file.exists(), isTrue);
    final bytes = await file.readAsBytes();
    expect(bytes.length, greaterThan(1000));
    // PDF magic header
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

    await file.delete();
  });

  test('generates a PDF with empty results without crashing', () async {
    final file = await ResultsPdfService().generateResultsReport(
      assessment: makeAssessment(),
      results: const [],
    );

    expect(await file.exists(), isTrue);
    final bytes = await file.readAsBytes();
    expect(bytes.length, greaterThan(500));

    await file.delete();
  });
}
