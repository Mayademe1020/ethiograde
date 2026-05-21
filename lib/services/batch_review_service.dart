import '../models/assessment.dart';
import '../models/scan_result.dart';
import '../models/student.dart';
import 'scoring_service.dart';

class BatchReviewSummary {
  const BatchReviewSummary({
    required this.scannedPapers,
    required this.lowConfidencePapers,
    required this.possibleDuplicates,
    required this.missingStudents,
    required this.unassignedPapers,
  });

  final int scannedPapers;
  final int lowConfidencePapers;
  final int possibleDuplicates;
  final List<Student> missingStudents;
  final int unassignedPapers;

  bool get hasBlockingReview =>
      lowConfidencePapers > 0 ||
      possibleDuplicates > 0 ||
      missingStudents.isNotEmpty ||
      unassignedPapers > 0;
}

class BatchReviewService {
  const BatchReviewService();

  BatchReviewSummary summarize({
    required List<ScanResult> results,
    required List<Student> roster,
    required int duplicateCount,
    required bool noRoster,
  }) {
    final scannedStudentIds = results
        .map((result) => result.studentId)
        .where((id) => id.isNotEmpty)
        .toSet();

    final missingStudents = noRoster
        ? <Student>[]
        : roster
              .where((student) => !scannedStudentIds.contains(student.id))
              .toList(growable: false);

    return BatchReviewSummary(
      scannedPapers: results.length,
      lowConfidencePapers: results.where((result) => result.needsReview).length,
      possibleDuplicates: duplicateCount,
      missingStudents: missingStudents,
      unassignedPapers: results
          .where(
            (result) =>
                result.studentId.isEmpty || result.studentName.trim().isEmpty,
          )
          .length,
    );
  }

  ScanResult assignStudent(ScanResult result, Student student) {
    return result.copyWith(
      studentId: student.id,
      studentName: student.fullName,
      metadata: {
        ...result.metadata,
        'batchReviewResolution': 'assigned_student',
        'batchReviewResolvedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  ScanResult markAbsent({
    required Assessment assessment,
    required Student student,
  }) {
    return _placeholderResult(
      assessment: assessment,
      student: student,
      status: ScanStatus.reviewed,
      resolution: 'absent',
      comment: 'Marked absent in batch review',
    );
  }

  ScanResult leaveUngraded({
    required Assessment assessment,
    required Student student,
  }) {
    return _placeholderResult(
      assessment: assessment,
      student: student,
      status: ScanStatus.pending,
      resolution: 'left_ungraded',
      comment: 'Left ungraded in batch review',
    );
  }

  ScanResult needsManualEntry({
    required Assessment assessment,
    required Student student,
  }) {
    return _placeholderResult(
      assessment: assessment,
      student: student,
      status: ScanStatus.needsRescan,
      resolution: 'manual_entry_needed',
      comment: 'Teacher chose manual entry from batch review',
    );
  }

  List<ScanResult> removeAt(List<ScanResult> results, int index) {
    if (index < 0 || index >= results.length) return List.of(results);
    return [
      for (var i = 0; i < results.length; i++)
        if (i != index) results[i],
    ];
  }

  List<ScanResult> appendIfMissingStudent(
    List<ScanResult> results,
    ScanResult resolution,
  ) {
    final exists = results.any(
      (result) =>
          result.studentId == resolution.studentId &&
          result.metadata['batchReviewResolution'] ==
              resolution.metadata['batchReviewResolution'],
    );
    return exists ? List.of(results) : [...results, resolution];
  }

  ScanResult markDuplicateReviewed(ScanResult result) {
    return result.copyWith(
      metadata: {
        ...result.metadata,
        'duplicateReviewed': true,
        'duplicateReviewedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  ScanResult _placeholderResult({
    required Assessment assessment,
    required Student student,
    required ScanStatus status,
    required String resolution,
    required String comment,
  }) {
    final maxScore = assessment.questions.fold<double>(
      0,
      (total, question) => total + question.points,
    );

    return ScanResult(
      assessmentId: assessment.id,
      studentId: student.id,
      studentName: student.fullName,
      imagePath: '',
      answers: assessment.questions
          .map(
            (question) => AnswerMatch(
              questionNumber: question.number,
              detectedAnswer: '[MISSING]',
              correctAnswer: question.correctAnswer?.toString() ?? '',
              isCorrect: false,
              score: 0,
              maxScore: question.points,
              confidence: 1,
              ocrRawText: comment,
            ),
          )
          .toList(growable: false),
      totalScore: 0,
      maxScore: maxScore,
      percentage: const ScoringService().calculatePercentage(
        totalScore: 0,
        maxScore: maxScore,
      ),
      grade: '',
      status: status,
      confidence: 1,
      isManualEntry: resolution == 'manual_entry_needed',
      metadata: {
        'batchReviewResolution': resolution,
        'batchReviewResolvedAt': DateTime.now().toIso8601String(),
      },
    );
  }
}
