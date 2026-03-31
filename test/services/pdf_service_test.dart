import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/services/pdf_service.dart';
import 'package:ethiograde/models/student.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/models/class_info.dart';

void main() {
  late PdfService pdfService;
  late Student testStudent;
  late Student testStudentAm;
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

    testStudentAm = Student(
      id: 's2',
      firstName: 'Chaltu',
      lastName: 'Dida',
      firstNameAmharic: 'ቻልቱ',
      lastNameAmharic: 'ዲዳ',
      className: 'Grade 9',
      section: 'B',
      studentId: '902',
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
        Question(number: 4, type: QuestionType.mcq, correctAnswer: 'C'),
        Question(number: 5, type: QuestionType.trueFalse, correctAnswer: 'False'),
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
        AnswerMatch(
          questionNumber: 4,
          detectedAnswer: 'C',
          correctAnswer: 'C',
          isCorrect: true,
          score: 1,
          maxScore: 1,
          confidence: 0.92,
        ),
        AnswerMatch(
          questionNumber: 5,
          detectedAnswer: 'False',
          correctAnswer: 'False',
          isCorrect: true,
          score: 1,
          maxScore: 1,
          confidence: 0.88,
        ),
      ],
      totalScore: 4,
      maxScore: 5,
      percentage: 80.0,
      grade: 'A',
      confidence: 0.90,
    );
  });

  // ──── Student Report ────

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
      expect(size, greaterThan(1000));
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
        student: testStudentAm,
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
        teacherComment: 'Good work overall — keep improving on Q3',
      );

      final file = await pdfService.generateStudentReport(
        student: testStudent,
        assessment: testAssessment,
        result: resultWithComment,
      );

      expect(await file.exists(), isTrue);
      expect(await file.length(), greaterThan(1000));
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

    test('handles long student name without crash', () async {
      final longNameStudent = Student(
        id: 's3',
        firstName: 'Abdulkadir Mohammed Hassan Al-Rashid',
        lastName: 'Ibrahim Abubakar Yusuf',
        className: 'Grade 12',
      );

      final file = await pdfService.generateStudentReport(
        student: longNameStudent,
        assessment: testAssessment,
        result: testResult,
      );

      expect(await file.exists(), isTrue);
    });

    test('handles 100% score (all correct)', () async {
      final allCorrect = ScanResult(
        assessmentId: 'a1',
        studentId: 's1',
        studentName: 'Abebe Kebede',
        imagePath: '/tmp/test.jpg',
        answers: List.generate(5, (i) => AnswerMatch(
          questionNumber: i + 1,
          detectedAnswer: 'A',
          correctAnswer: 'A',
          isCorrect: true,
          score: 1,
          maxScore: 1,
          confidence: 0.95,
        )),
        totalScore: 5,
        maxScore: 5,
        percentage: 100.0,
        grade: 'A+',
        confidence: 0.95,
      );

      final file = await pdfService.generateStudentReport(
        student: testStudent,
        assessment: testAssessment,
        result: allCorrect,
      );

      expect(await file.exists(), isTrue);
      expect(await file.length(), greaterThan(1000));
    });

    test('handles 0% score (all wrong)', () async {
      final allWrong = ScanResult(
        assessmentId: 'a1',
        studentId: 's1',
        studentName: 'Abebe Kebede',
        imagePath: '/tmp/test.jpg',
        answers: List.generate(5, (i) => AnswerMatch(
          questionNumber: i + 1,
          detectedAnswer: 'A',
          correctAnswer: 'B',
          isCorrect: false,
          score: 0,
          maxScore: 1,
          confidence: 0.4,
        )),
        totalScore: 0,
        maxScore: 5,
        percentage: 0.0,
        grade: 'F',
        confidence: 0.4,
      );

      final file = await pdfService.generateStudentReport(
        student: testStudent,
        assessment: testAssessment,
        result: allWrong,
      );

      expect(await file.exists(), isTrue);
    });

    test('handles private_international rubric type', () async {
      final file = await pdfService.generateStudentReport(
        student: testStudent,
        assessment: testAssessment,
        result: testResult,
        rubricType: 'private_international',
      );

      expect(await file.exists(), isTrue);
    });

    test('handles university rubric type', () async {
      final file = await pdfService.generateStudentReport(
        student: testStudent,
        assessment: testAssessment,
        result: testResult,
        rubricType: 'university',
      );

      expect(await file.exists(), isTrue);
    });

    test('handles student with empty Amharic name', () async {
      final noAmharic = Student(
        id: 's4',
        firstName: 'John',
        lastName: 'Smith',
        className: 'Grade 10',
      );

      final file = await pdfService.generateStudentReport(
        student: noAmharic,
        assessment: testAssessment,
        result: testResult,
      );

      expect(await file.exists(), isTrue);
    });
  });

  // ──── Class Report ────

  group('PdfService — class report', () {
    test('generates non-empty PDF for class report', () async {
      final analytics = ClassAnalytics(
        classId: 'c1',
        assessmentId: 'a1',
        classAverage: 72.5,
        highestScore: 98.0,
        lowestScore: 35.0,
        passRate: 80.0,
        totalStudents: 25,
        passedStudents: 20,
        failedStudents: 5,
        gradeDistribution: {'A': 5, 'B': 10, 'C': 5, 'D': 3, 'F': 2},
        questionAnalytics: [
          const QuestionAnalytics(questionNumber: 1, correctRate: 0.9),
          const QuestionAnalytics(questionNumber: 2, correctRate: 0.3),
        ],
      );

      final file = await pdfService.generateClassReport(
        assessment: testAssessment,
        results: [testResult],
        analytics: analytics,
        schoolName: 'Test School',
        className: 'Grade 10A',
      );

      expect(await file.exists(), isTrue);
      final size = await file.length();
      expect(size, greaterThan(1000));
    });

    test('Amharic class report generates valid PDF', () async {
      final analytics = ClassAnalytics(
        classId: 'c1',
        assessmentId: 'a1',
        classAverage: 65.0,
        highestScore: 90.0,
        lowestScore: 30.0,
        passRate: 70.0,
        totalStudents: 20,
        passedStudents: 14,
        failedStudents: 6,
        gradeDistribution: {'A': 3, 'B': 7, 'C': 4, 'D': 3, 'F': 3},
      );

      final file = await pdfService.generateClassReport(
        assessment: testAssessment,
        results: [testResult],
        analytics: analytics,
        schoolName: 'የሙከራ ት/ቤት',
        className: '10ሀ',
        isAmharic: true,
      );

      expect(await file.exists(), isTrue);
      expect(await file.length(), greaterThan(1000));
    });

    test('handles empty results list', () async {
      final analytics = ClassAnalytics(
        classId: 'c1',
        assessmentId: 'a1',
      );

      final file = await pdfService.generateClassReport(
        assessment: testAssessment,
        results: [],
        analytics: analytics,
        schoolName: 'Test School',
        className: 'Grade 10A',
      );

      expect(await file.exists(), isTrue);
    });

    test('handles multiple students in class report', () async {
      final analytics = ClassAnalytics(
        classId: 'c1',
        assessmentId: 'a1',
        classAverage: 68.0,
        highestScore: 95.0,
        lowestScore: 25.0,
        passRate: 75.0,
        totalStudents: 3,
        passedStudents: 2,
        failedStudents: 1,
        gradeDistribution: {'A': 1, 'B': 1, 'C': 0, 'D': 0, 'F': 1},
      );

      final results = List.generate(3, (i) => ScanResult(
        assessmentId: 'a1',
        studentId: 's$i',
        studentName: 'Student ${i + 1}',
        imagePath: '/tmp/test$i.jpg',
        totalScore: (4 - i).toDouble(),
        maxScore: 5,
        percentage: (80.0 - i * 20),
        grade: ['A', 'B', 'D'][i],
        confidence: 0.9,
      ));

      final file = await pdfService.generateClassReport(
        assessment: testAssessment,
        results: results,
        analytics: analytics,
        schoolName: 'Test School',
        className: 'Grade 10A',
      );

      expect(await file.exists(), isTrue);
      expect(await file.length(), greaterThan(1000));
    });

    test('handles topic scores in analytics', () async {
      final analytics = ClassAnalytics(
        classId: 'c1',
        assessmentId: 'a1',
        classAverage: 70.0,
        highestScore: 90.0,
        lowestScore: 40.0,
        passRate: 80.0,
        totalStudents: 10,
        passedStudents: 8,
        failedStudents: 2,
        topicScores: {
          'Algebra': 75.0,
          'Geometry': 60.0,
          'Statistics': 85.0,
        },
        questionAnalytics: [
          const QuestionAnalytics(
            questionNumber: 1,
            correctRate: 0.4,
            topicTag: 'Algebra',
          ),
        ],
      );

      final file = await pdfService.generateClassReport(
        assessment: testAssessment,
        results: [testResult],
        analytics: analytics,
        schoolName: 'Test School',
        className: 'Grade 10A',
      );

      expect(await file.exists(), isTrue);
    });
  });

  // ──── Answer Sheet Template ────

  group('PdfService — answer sheet template', () {
    test('generates answer sheet for single student', () async {
      final file = await pdfService.generateAnswerSheetTemplate(
        assessment: testAssessment,
        students: [testStudent],
        schoolName: 'Test School',
      );

      expect(await file.exists(), isTrue);
      expect(file.path, endsWith('.pdf'));
      expect(await file.length(), greaterThan(1000));
    });

    test('generates one page per student', () async {
      final students = List.generate(3, (i) => Student(
        id: 's$i',
        firstName: 'Student',
        lastName: '${i + 1}',
        className: 'Grade 10',
        studentId: '${1000 + i}',
      ));

      final file = await pdfService.generateAnswerSheetTemplate(
        assessment: testAssessment,
        students: students,
        schoolName: 'Test School',
      );

      expect(await file.exists(), isTrue);
      // 3 students = 3 pages, should be significantly larger
      expect(await file.length(), greaterThan(2000));
    });

    test('handles empty student list', () async {
      final file = await pdfService.generateAnswerSheetTemplate(
        assessment: testAssessment,
        students: [],
        schoolName: 'Test School',
      );

      // Empty student list = 0 pages but file still created
      expect(await file.exists(), isTrue);
    });

    test('handles prefillNames = false', () async {
      final file = await pdfService.generateAnswerSheetTemplate(
        assessment: testAssessment,
        students: [testStudent],
        schoolName: 'Test School',
        prefillNames: false,
      );

      expect(await file.exists(), isTrue);
    });

    test('handles assessment with short-answer questions', () async {
      final mixedAssessment = Assessment(
        id: 'a2',
        title: 'Mixed Test',
        subject: 'Science',
        questions: [
          Question(number: 1, type: QuestionType.mcq, correctAnswer: 'A'),
          Question(number: 2, type: QuestionType.trueFalse, correctAnswer: 'True'),
          Question(number: 3, type: QuestionType.shortAnswer, correctAnswer: 'Photosynthesis'),
          Question(number: 4, type: QuestionType.essay, correctAnswer: ''),
        ],
      );

      final file = await pdfService.generateAnswerSheetTemplate(
        assessment: mixedAssessment,
        students: [testStudent],
        schoolName: 'Test School',
      );

      expect(await file.exists(), isTrue);
    });
  });

  // ──── Edge Cases ────

  group('PdfService — edge cases', () {
    test('handles assessment with only true/false questions', () async {
      final tfAssessment = Assessment(
        id: 'a3',
        title: 'True/False Quiz',
        subject: 'History',
        questions: List.generate(10, (i) => Question(
          number: i + 1,
          type: QuestionType.trueFalse,
          correctAnswer: i % 2 == 0 ? 'True' : 'False',
        )),
      );

      final file = await pdfService.generateStudentReport(
        student: testStudent,
        assessment: tfAssessment,
        result: testResult,
      );

      expect(await file.exists(), isTrue);
    });

    test('handles very long assessment title', () async {
      final longTitleAssessment = Assessment(
        id: 'a4',
        title: 'የአስተማሪ ሙከራ የተለያዩ የትምህርት ዓውድ ስርዓተ ትምህርት ለአሥራ ሁለተኛ ደረጃ ተማሪዎች',
        subject: 'Amharic',
        questions: testAssessment.questions,
      );

      final file = await pdfService.generateStudentReport(
        student: testStudent,
        assessment: longTitleAssessment,
        result: testResult,
        isAmharic: true,
      );

      expect(await file.exists(), isTrue);
    });

    test('generates multiple reports without collision', () async {
      final files = <File>[];
      for (int i = 0; i < 3; i++) {
        final result = ScanResult(
          assessmentId: 'a1',
          studentId: 's$i',
          studentName: 'Student $i',
          imagePath: '/tmp/test$i.jpg',
          totalScore: (i + 1).toDouble(),
          maxScore: 5,
          percentage: (i + 1) * 20.0,
          confidence: 0.9,
        );
        final file = await pdfService.generateStudentReport(
          student: testStudent,
          assessment: testAssessment,
          result: result,
        );
        files.add(file);
      }

      // All files should exist and be unique
      for (final file in files) {
        expect(await file.exists(), isTrue);
      }
      final paths = files.map((f) => f.path).toSet();
      expect(paths.length, 3);
    });

    test('getPdfBytes returns non-empty bytes', () async {
      final file = await pdfService.generateStudentReport(
        student: testStudent,
        assessment: testAssessment,
        result: testResult,
      );

      final bytes = await pdfService.getPdfBytes(file);
      expect(bytes.length, greaterThan(1000));
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
