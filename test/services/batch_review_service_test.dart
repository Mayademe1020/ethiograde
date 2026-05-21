import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/models/student.dart';
import 'package:ethiograde/services/batch_review_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = BatchReviewService();

  Assessment assessment() => Assessment(
    id: 'exam-1',
    title: 'Biology',
    subject: 'Biology',
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
        points: 2,
        correctAnswer: 'B',
      ),
    ],
  );

  Student student(String id, String name) {
    final parts = name.split(' ');
    return Student(
      id: id,
      studentId: id,
      firstName: parts.first,
      lastName: parts.length > 1 ? parts.sublist(1).join(' ') : '',
      classIds: const ['class-1'],
    );
  }

  ScanResult result({
    required String studentId,
    required String studentName,
    double confidence = 1,
  }) {
    return ScanResult(
      assessmentId: 'exam-1',
      studentId: studentId,
      studentName: studentName,
      imagePath: 'paper.jpg',
      confidence: confidence,
      answers: [
        AnswerMatch(
          questionNumber: 1,
          detectedAnswer: 'A',
          correctAnswer: 'A',
          isCorrect: true,
          score: 1,
          maxScore: 1,
          confidence: confidence,
        ),
      ],
    );
  }

  test('summarize finds missing students, low confidence, and unassigned', () {
    final roster = [
      student('s1', 'Abebe Kebede'),
      student('s2', 'Mimi Bekele'),
    ];

    final summary = service.summarize(
      results: [
        result(studentId: 's1', studentName: 'Abebe Kebede', confidence: 0.5),
        result(studentId: '', studentName: 'Paper 2'),
      ],
      roster: roster,
      duplicateCount: 1,
      noRoster: false,
    );

    expect(summary.scannedPapers, 2);
    expect(summary.lowConfidencePapers, 1);
    expect(summary.possibleDuplicates, 1);
    expect(summary.missingStudents.single.id, 's2');
    expect(summary.unassignedPapers, 1);
  });

  test('markAbsent creates an explicit reviewed zero row', () {
    final abebe = student('s1', 'Abebe Kebede');

    final absent = service.markAbsent(assessment: assessment(), student: abebe);

    expect(absent.studentId, 's1');
    expect(absent.status, ScanStatus.reviewed);
    expect(absent.maxScore, 3);
    expect(absent.metadata['batchReviewResolution'], 'absent');
    expect(absent.answers, hasLength(2));
  });

  test('removeAt returns a new list without mutating the original', () {
    final original = [
      result(studentId: 's1', studentName: 'Abebe Kebede'),
      result(studentId: 's2', studentName: 'Mimi Bekele'),
    ];

    final updated = service.removeAt(original, 0);

    expect(original, hasLength(2));
    expect(updated, hasLength(1));
    expect(updated.single.studentId, 's2');
  });
}
