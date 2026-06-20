import '../models/class_info.dart';
import '../models/student.dart';
import '../models/assessment.dart';
import '../models/scan_result.dart';
import 'class_provider.dart';
import 'student_provider.dart';
import 'assessment_provider.dart';
import 'hybrid_grading_service.dart';
import 'scoring_service.dart';

/// Seeds demo data on first launch so teachers see a populated dashboard.
///
/// Creates:
/// - 1 class ("Grade 5A Mathematics" / "በአምስተኛ ደረጃ ሒሳብ")
/// - 1 assessment with 10 MCQ math questions + answer key
///
/// All data is seeded via providers (which write to Hive), so it persists
/// and appears immediately on the dashboard.
class DemoDataService {
  /// Seed demo data. Safe to call multiple times — skips if class already exists.
  static Future<void> seed({
    required ClassProvider classProvider,
    required StudentProvider studentProvider,
    required AssessmentProvider assessmentProvider,
  }) async {
    // Always ensure the 20Q test exam exists
    if (!assessmentProvider.assessments.any((a) => a.id == 'test-20q-001')) {
      final randomAnswers = ['A', 'B', 'C', 'D', 'A', 'C', 'B', 'D', 'A', 'C',
                             'B', 'D', 'A', 'C', 'B', 'D', 'A', 'C', 'B', 'D'];
      final testQuestions = List.generate(20, (i) => Question(
        number: i + 1,
        type: QuestionType.mcq,
        text: 'Question ${i + 1}',
        points: 1,
        options: const ['A', 'B', 'C', 'D'],
        correctAnswer: randomAnswers[i],
      ));

      final testAssessment = Assessment(
        id: 'test-20q-001',
        title: '20Q Test',
        subject: 'Test',
        className: '',
        grade: 1,
        rubricType: 'moe_national',
        questions: testQuestions,
        totalPoints: 20,
        passingPoints: 10,
        status: AssessmentStatus.active,
        isQuickGrade: true,
        settings: {
          'examDayMode': 'gradePapers',
          'studentMode': 'noRoster',
          'answerKeyMode': 'manual',
          'requiresBatchReview': true,
          'shortAnswerPolicy': 'detect-and-review',
        },
        createdAt: DateTime.now(),
      );
      await assessmentProvider.addAssessment(testAssessment);
    }

    // Check if demo data already exists (idempotent)
    if (classProvider.classes.any((c) => c.id == 'demo-class-001')) {
      return;
    }

    // ── 1. Create demo class ────────────────────────────────────────
    final demoClass = ClassInfo(
      id: 'demo-class-001',
      name: 'Grade 5A',
      school: 'Demo School',
      grade: 5,
      section: 'A',
      subject: 'Mathematics',
      studentIds: [],
      ownerId: 'demo-teacher',
      createdAt: DateTime.now().subtract(const Duration(days: 7)));
    await classProvider.addClass(demoClass);

    // ── 2. Create 5 students ────────────────────────────────────────
    final students = [
      Student(
        id: 'demo-student-001',
        studentId: '001',
        firstName: 'Abel',
        lastName: 'Tesfaye',
        gender: 'M',
        classIds: [demoClass.id],
        grade: 5,
        section: 'A'),
      Student(
        id: 'demo-student-002',
        studentId: '002',
        firstName: 'Bethlehem',
        lastName: 'Assefa',
        gender: 'F',
        classIds: [demoClass.id],
        grade: 5,
        section: 'A'),
      Student(
        id: 'demo-student-003',
        studentId: '003',
        firstName: 'Dawit',
        lastName: 'Haile',
        gender: 'M',
        classIds: [demoClass.id],
        grade: 5,
        section: 'A'),
      Student(
        id: 'demo-student-004',
        studentId: '004',
        firstName: 'Helen',
        lastName: 'Kebede',
        gender: 'F',
        classIds: [demoClass.id],
        grade: 5,
        section: 'A'),
      Student(
        id: 'demo-student-005',
        studentId: '005',
        firstName: 'Yonas',
        lastName: 'Alemu',
        gender: 'M',
        classIds: [demoClass.id],
        grade: 5,
        section: 'A'),
    ];

    for (final student in students) {
      await studentProvider.addStudent(student);
    }

    // Link students to class
    await classProvider.addStudentsToClass(
      demoClass.id,
      students.map((s) => s.id).toList());

    // ── 3. Create demo assessment ───────────────────────────────────
    final questions = [
      Question(
        number: 1,
        type: QuestionType.mcq,
        text: 'What is 7 × 8?',
        points: 2,
        correctAnswer: 'C',
        topicTag: 'Multiplication'),
      Question(
        number: 2,
        type: QuestionType.mcq,
        text: 'What is 144 ÷ 12?',
        points: 2,
        correctAnswer: 'B',
        topicTag: 'Division'),
      Question(
        number: 3,
        type: QuestionType.mcq,
        text: 'What is 25 + 37?',
        points: 2,
        correctAnswer: 'A',
        topicTag: 'Addition'),
      Question(
        number: 4,
        type: QuestionType.mcq,
        text: 'What is 100 - 47?',
        points: 2,
        correctAnswer: 'D',
        topicTag: 'Subtraction'),
      Question(
        number: 5,
        type: QuestionType.trueFalse,
        text: 'A triangle has 4 sides.',
        points: 2,
        correctAnswer: 'False',
        topicTag: 'Geometry'),
      Question(
        number: 6,
        type: QuestionType.mcq,
        text: 'What is 9 × 9?',
        points: 2,
        correctAnswer: 'D',
        topicTag: 'Multiplication'),
      Question(
        number: 7,
        type: QuestionType.mcq,
        text: 'Round 76 to the nearest ten.',
        points: 2,
        correctAnswer: 'C',
        topicTag: 'Rounding'),
      Question(
        number: 8,
        type: QuestionType.trueFalse,
        text: '½ is greater than ¼.',
        points: 2,
        correctAnswer: 'True',
        topicTag: 'Fractions'),
      Question(
        number: 9,
        type: QuestionType.mcq,
        text: 'How many minutes are in 2 hours?',
        points: 2,
        correctAnswer: 'B',
        topicTag: 'Time'),
      Question(
        number: 10,
        type: QuestionType.mcq,
        text: 'What is 3² (3 squared)?',
        points: 2,
        correctAnswer: 'A',
        topicTag: 'Powers'),
    ];

    final assessment = Assessment(
      id: 'demo-assessment-001',
      title: 'Unit 1 Math Quiz',
      subject: 'Mathematics',
      className: demoClass.name,
      grade: 5,
      rubricType: 'moe_national',
      questions: questions,
      totalPoints: 20,
      passingPoints: 10,
      status: AssessmentStatus.active,
      createdAt: DateTime.now().subtract(const Duration(days: 2)));
    await assessmentProvider.addAssessment(assessment);

    // ── 4. Create 20Q Test exam ────────────────────────────────────
    final randomAnswers = ['A', 'B', 'C', 'D', 'A', 'C', 'B', 'D', 'A', 'C',
                           'B', 'D', 'A', 'C', 'B', 'D', 'A', 'C', 'B', 'D'];
    final testQuestions = List.generate(20, (i) => Question(
      number: i + 1,
      type: QuestionType.mcq,
      text: 'Question ${i + 1}',
      points: 1,
      options: const ['A', 'B', 'C', 'D'],
      correctAnswer: randomAnswers[i],
    ));

    final testAssessment = Assessment(
      id: 'test-20q-001',
      title: '20Q Test',
      subject: 'Test',
      className: '',
      grade: 1,
      rubricType: 'moe_national',
      questions: testQuestions,
      totalPoints: 20,
      passingPoints: 10,
      status: AssessmentStatus.active,
      isQuickGrade: true,
      settings: {
        'examDayMode': 'gradePapers',
        'studentMode': 'noRoster',
        'answerKeyMode': 'manual',
        'requiresBatchReview': true,
        'shortAnswerPolicy': 'detect-and-review',
      },
      createdAt: DateTime.now(),
    );
    await assessmentProvider.addAssessment(testAssessment);

    // ── 5. Seed demo scan results for "Unit 1 Math Quiz" ──────────
    final grading = HybridGradingService();
    final existingResults = await grading.loadScanResults('demo-assessment-001');
    if (existingResults.isEmpty) {
      final demoResults = _generateDemoResults(students, assessment);
      for (final result in demoResults) {
        await grading.saveScanResult(result);
      }
      // Mark assessment as completed
      await assessmentProvider.updateAssessmentStatus(
        'demo-assessment-001',
        AssessmentStatus.completed,
      );
    }
  }

  static List<ScanResult> _generateDemoResults(
    List<Student> students,
    Assessment assessment,
  ) {
    final maxScore = assessment.maxScore;
    final scoring = const ScoringService();

    final results = <ScanResult>[];
    // Vary scores: 60%, 80%, 45%, 90%, 70%
    final scoreRatios = [0.60, 0.80, 0.45, 0.90, 0.70];

    for (int i = 0; i < students.length && i < scoreRatios.length; i++) {
      final student = students[i];
      final ratio = scoreRatios[i];
      final answers = <AnswerMatch>[];

      for (int q = 0; q < assessment.questions.length; q++) {
        final question = assessment.questions[q];
        final isCorrect = (q / assessment.questions.length) < ratio;
        final detectedAnswer = isCorrect
            ? (question.correctAnswer?.toString() ?? 'A')
            : _wrongAnswer(question.correctAnswer?.toString() ?? 'A');

        answers.add(AnswerMatch(
          questionNumber: question.number,
          detectedAnswer: detectedAnswer,
          correctAnswer: question.correctAnswer?.toString() ?? '',
          isCorrect: isCorrect,
          score: isCorrect ? question.points : 0,
          maxScore: question.points,
          confidence: 0.95,
        ));
      }

      final totalScore = scoring.calculateTotalScore(answers);
      final percentage = scoring.calculatePercentage(
        totalScore: totalScore,
        maxScore: maxScore,
      );
      final grade = scoring.calculateGrade(
        percentage,
        assessment.rubricType,
      );

      results.add(ScanResult(
        assessmentId: assessment.id,
        studentId: student.id,
        studentName: student.fullName,
        imagePath: '',
        answers: answers,
        totalScore: totalScore,
        maxScore: maxScore,
        percentage: percentage,
        grade: grade,
        status: ScanStatus.reviewed,
        confidence: 0.95,
        isManualEntry: true,
        metadata: {'entryMethod': 'demo_seed'},
      ));
    }

    return results;
  }

  static String _wrongAnswer(String correct) {
    const options = ['A', 'B', 'C', 'D'];
    final others = options.where((o) => o != correct).toList();
    return others.isNotEmpty ? others.first : 'A';
  }
}
