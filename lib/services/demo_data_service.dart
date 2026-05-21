import '../models/class_info.dart';
import '../models/student.dart';
import '../models/assessment.dart';
import 'class_provider.dart';
import 'student_provider.dart';
import 'assessment_provider.dart';

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
  }
}
