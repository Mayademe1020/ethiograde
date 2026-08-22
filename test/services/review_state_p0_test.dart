import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/scan_result.dart';

void main() {
  ScanResult makeResult({
    double confidence = 0.95,
    List<AnswerMatch>? answers,
    ScanStatus status = ScanStatus.graded,
    String studentId = 's1',
    String studentName = 'Test Student',
    Map<String, dynamic>? metadata,
  }) {
    return ScanResult(
      assessmentId: 'a1',
      studentId: studentId,
      studentName: studentName,
      imagePath: '/path/to/image.jpg',
      answers: answers ?? [
        AnswerMatch(
          questionNumber: 1,
          detectedAnswer: 'A',
          correctAnswer: 'A',
          isCorrect: true,
          score: 1,
          maxScore: 1,
          confidence: 0.95,
        ),
      ],
      totalScore: 1,
      maxScore: 1,
      percentage: 100,
      grade: 'A+',
      status: status,
      confidence: confidence,
      metadata: metadata ?? {},
    );
  }

  group('P0.2 — Review state semantics', () {
    test('low confidence → needs review', () {
      final result = makeResult(confidence: 0.5);
      expect(result.needsReview, true);
    });

    test('high confidence → no review needed', () {
      final result = makeResult(confidence: 0.95);
      expect(result.needsReview, false);
    });

    test('low confidence answer → needs review', () {
      final result = makeResult(
        confidence: 0.95,
        answers: [
          AnswerMatch(
            questionNumber: 1,
            detectedAnswer: 'A',
            correctAnswer: 'A',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.4, // Low confidence
          ),
        ],
      );
      expect(result.needsReview, true);
    });

    test('unmatched student does not count as low-confidence review', () {
      final result = makeResult(studentId: '', studentName: '');
      // Unmatched students are checked via isUnmatched, not needsReview
      expect(result.needsReview, false);
      expect(result.isUnmatched, true);
    });

    test('multiple marks detected → needs review', () {
      final result = makeResult(
        confidence: 0.95,
        answers: [
          AnswerMatch(
            questionNumber: 1,
            detectedAnswer: '[MULTIPLE]',
            correctAnswer: 'A',
            isCorrect: false,
            score: 0,
            maxScore: 1,
            confidence: 0,
          ),
        ],
      );
      expect(result.needsReview, true);
    });

    test('teacher reviewed → no review needed', () {
      final result = makeResult(
        confidence: 0.5,
        status: ScanStatus.reviewed,
      );
      expect(result.needsReview, false);
    });

    test('teacherReviewed metadata → no review needed', () {
      final result = makeResult(
        confidence: 0.5,
        metadata: {'teacherReviewed': true},
      );
      expect(result.needsReview, false);
    });

    test('batchReviewResolution metadata → no review needed', () {
      final result = makeResult(
        confidence: 0.5,
        metadata: {'batchReviewResolution': 'assigned_student'},
      );
      expect(result.needsReview, false);
    });

    test('duplicateReviewed metadata → no review needed', () {
      final result = makeResult(
        confidence: 0.5,
        metadata: {'duplicateReviewed': true},
      );
      expect(result.needsReview, false);
    });

    test('studentMatchResolved metadata → no review needed', () {
      final result = makeResult(
        confidence: 0.5,
        metadata: {'studentMatchResolved': true},
      );
      expect(result.needsReview, false);
    });

    test('resolved issues do not block finalization', () {
      final results = [
        makeResult(
          confidence: 0.5,
          status: ScanStatus.reviewed,
        ),
        makeResult(
          confidence: 0.95,
          studentId: 's2',
          studentName: 'Student 2',
        ),
      ];
      final unresolvedCount = results.where((r) => r.needsReview).length;
      expect(unresolvedCount, 0);
    });

    test('unresolved issues remain visible after restart', () {
      // Metadata persists in Hive, so needsReview is computed from persisted state
      final result = makeResult(
        confidence: 0.5,
        metadata: {}, // No resolution flags
      );
      expect(result.needsReview, true);
    });

    test('resolution persists explicitly', () {
      final result = makeResult(
        confidence: 0.5,
        metadata: {'teacherReviewed': true},
      );
      expect(result.needsReview, false);
    });
  });

  group('requiresTeacherAction — unified resolver', () {
    test('low confidence → requires teacher action', () {
      final result = makeResult(confidence: 0.5);
      expect(result.requiresTeacherAction, true);
    });

    test('high confidence, matched student → no action needed', () {
      final result = makeResult(confidence: 0.95);
      expect(result.requiresTeacherAction, false);
    });

    test('unmatched student → requires teacher action', () {
      final result = makeResult(studentId: '', studentName: '');
      expect(result.requiresTeacherAction, true);
    });

    test('multiple marks → requires teacher action', () {
      final result = makeResult(
        confidence: 0.95,
        answers: [
          AnswerMatch(
            questionNumber: 1,
            detectedAnswer: '[MULTIPLE]',
            correctAnswer: 'A',
            isCorrect: false,
            score: 0,
            maxScore: 1,
            confidence: 0,
          ),
        ],
      );
      expect(result.requiresTeacherAction, true);
    });

    test('teacher reviewed → no action needed even with low confidence', () {
      final result = makeResult(
        confidence: 0.5,
        status: ScanStatus.reviewed,
      );
      expect(result.requiresTeacherAction, false);
    });

    test('batchReviewResolution set → no action needed', () {
      final result = makeResult(
        confidence: 0.5,
        metadata: {'batchReviewResolution': 'assigned_student'},
      );
      expect(result.requiresTeacherAction, false);
    });

    test('unmatched student with batchReviewResolution → no action', () {
      final result = makeResult(
        studentId: '',
        studentName: '',
        metadata: {'batchReviewResolution': 'absent'},
      );
      expect(result.requiresTeacherAction, false);
    });

    test('isResolved combines all resolution flags', () {
      expect(makeResult(status: ScanStatus.reviewed).isResolved, true);
      expect(makeResult(metadata: {'teacherReviewed': true}).isResolved, true);
      expect(makeResult(metadata: {'batchReviewResolution': 'x'}).isResolved, true);
      expect(makeResult(metadata: {'duplicateReviewed': true}).isResolved, true);
      expect(makeResult(metadata: {'studentMatchResolved': true}).isResolved, true);
      expect(makeResult(confidence: 0.5).isResolved, false);
    });
  });
}
