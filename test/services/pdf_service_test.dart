import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/services/pdf_service.dart';
import 'package:ethiograde/models/student.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';

void main() {
  late PdfService pdfService;
  late Student testStudent;
  late Assessment testAssessment;
  late ScanResult testResult;

  setUp(() {
    pdfService = PdfService();

    testStudent = Student(
      id: 's1',
      firstName: 'Abebe',
      lastName: 'Kebede',
      firstNameAmharic: 'አበበ',
      lastNameAmharic: 'ከበደ',
      className: 'Grade 10',
      section: 'A',
      studentId: '1001',
    );

    testAssessment = Assessment(
      id: 'a1',
      title: 'Math Final',
      subject: 'Mathematics',
      rubricType: 'moe_national',
      questions: [
        Question(number: 1, type: QuestionType.mcq, correctAnswer: 'A'),
        Question(number: 2, type: QuestionType.mcq, correctAnswer: 'B'),
        Question(number: 3, type: QuestionType.trueFalse, correctAnswer: 'True'),
      ],
    );

    testResult = ScanResult(
      assessmentId: 'a1',
      studentId: 's1',
      studentName: 'Abebe Kebede',
      imagePath: '/tmp/test.jpg',
      answers: [
        AnswerMatch(
          questionNumber: 1,
          detectedAnswer: 'A',
          correctAnswer: 'A',
          isCorrect: true,
          score: 1,
          maxScore: 1,
          confidence: 0.95,
        ),
        AnswerMatch(
          questionNumber: 2,
          detectedAnswer: 'B',
          correctAnswer: 'B',
          isCorrect: true,
          score: 1,
          maxScore: 1,
          confidence: 0.90,
        ),
        AnswerMatch(
          questionNumber: 3,
          detectedAnswer: 'False',
          correctAnswer: 'True',
          isCorrect: false,
          score: 0,
          maxScore: 1,
          confidence: 0.85,
        ),
      ],
      totalScore: 2,
      maxScore: 3,
      percentage: 66.67,
      grade: 'C+',
      confidence: 0.90,
    );
  });

  group('PdfService — student report', () {
    test('generates non-empty PDF file', () async {
      final file = await pdfService.generateStudentReport(
        student: testStudent,
        assessment: testAssessment,
        result: testResult,
        schoolName: 'Test School',
        teacherName: 'Teacher Name',
      );

      expect(await file.exists(), isTrue);
      final size = await file.length();
      expect(size, greaterThan(1000)); // Real PDF is > 1KB
    });

    test('generated file has .pdf extension', () async {
      final file = await pdfService.generateStudentReport(
        student: testStudent,
        assessment: testAssessment,
        result: testResult,
      );

      expect(file.path, endsWith('.pdf'));
    });

    test('Amharic mode generates valid PDF', () async {
      final file = await pdfService.generateStudentReport(
        student: testStudent,
        assessment: testAssessment,
        result: testResult,
        isAmharic: true,
      );

      expect(await file.exists(), isTrue);
      final size = await file.length();
      expect(size, greaterThan(1000));
    });

    test('handles student with teacher comment', () async {
      final resultWithComment = testResult.copyWith(
        teacherComment: 'Good work overall',
      );

      final file = await pdfService.generateStudentReport(
        student: testStudent,
        assessment: testAssessment,
        result: resultWithComment,
      );

      expect(await file.exists(), isTrue);
    });

    test('handles empty school name', () async {
      final file = await pdfService.generateStudentReport(
        student: testStudent,
        assessment: testAssessment,
        result: testResult,
        schoolName: '',
      );

      expect(await file.exists(), isTrue);
    });
  });

  group('PdfService — class report', () {
    test('generates non-empty PDF for class report', () async {
      final file = await pdfService.generateClassReport(
        assessment: testAssessment,
        results: [testResult],
        schoolName: 'Test School',
        className: 'Grade 10A',
      );

      expect(await file.exists(), isTrue);
      final size = await file.length();
      expect(size, greaterThan(1000));
    });

    test('handles empty results list', () async {
      final file = await pdfService.generateClassReport(
        assessment: testAssessment,
        results: [],
        schoolName: 'Test School',
        className: 'Grade 10A',
      );

      expect(await file.exists(), isTrue);
    });
  });

  // Cleanup temp PDFs
  tearDown(() async {
    final tempDir = Directory.systemTemp;
    await for (final file in tempDir.list()) {
      if (file.path.contains('ethiograde') && file.path.endsWith('.pdf')) {
        try { await file.delete(); } catch (_) {}
      }
    }
  });
}
