import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/assessment.dart';
import '../../models/scan_result.dart';
import '../../models/student.dart';
import '../../services/hybrid_grading_service.dart';
import '../../services/scoring_service.dart';
import '../../services/class_provider.dart';
import '../../services/student_provider.dart';
import '../../services/draft_service.dart';
import '../../services/weighted_grade_provider.dart';
import '../../services/paper_image_intake_service.dart';

/// Callbacks for batch processor to communicate state changes back to the UI.
class BatchProcessorCallbacks {
  final void Function(int processed, int total) onProgress;
  final void Function(List<ScanResult> results) onResultsChanged;
  final void Function(List<AnswerDuplicate> duplicates) onDuplicatesChanged;
  final void Function(bool processing) onProcessingChanged;
  final void Function(bool ready, String? error) onMasterKeyStateChanged;
  final void Function(String title, String detail)? onCaptureFeedbackChanged;
  final Future<Student?> Function(String scannedName, String classId)?
      onStudentNotFound;

  const BatchProcessorCallbacks({
    required this.onProgress,
    required this.onResultsChanged,
    required this.onDuplicatesChanged,
    required this.onProcessingChanged,
    required this.onMasterKeyStateChanged,
    this.onCaptureFeedbackChanged,
    this.onStudentNotFound,
  });
}

/// Encapsulates batch scanning logic (coordinate-map OMR and hybrid grading).
///
/// Separated from the UI widget to keep BatchScanScreen focused on layout.
class BatchProcessor {
  final BatchProcessorCallbacks callbacks;

  const BatchProcessor({required this.callbacks});

  /// Process a batch of images — uses OCR-only hybrid grading.
  /// Coordinate-map OMR path is disabled for answer sheet scanning.
  Future<void> processBatch({
    required BuildContext context,
    required List<String> images,
    required Assessment assessment,
    required String? classId,
    required bool isNoRosterMode,
    required String? temporaryImageSource,
    required List<ScanResult> existingResults,
    required int startCount,
  }) async {
    callbacks.onProcessingChanged(true);

    // Always use hybrid grading (OCR only) — skip coordinate-map OMR
    await _processBatchHybrid(
      context: context,
      images: images,
      assessment: assessment,
      classId: classId,
      isNoRosterMode: isNoRosterMode,
      temporaryImageSource: temporaryImageSource,
      existingResults: existingResults,
    );
  }

  /// Process master answer sheet scan.
  /// Disabled for answer sheet scanning mode — teacher enters answers manually.
  Future<void> processMasterKey({
    required BuildContext context,
    required String imagePath,
    required Assessment assessment,
  }) async {
    callbacks.onProgress(0, 1);
    callbacks.onMasterKeyStateChanged(
      false,
      'Enter the answer key manually when creating the exam.',
    );
    return;
  }

  /// Process batch using hybrid grading (OCR only).
  Future<void> _processBatchHybrid({
    required BuildContext context,
    required List<String> images,
    required Assessment assessment,
    required String? classId,
    required bool isNoRosterMode,
    required String? temporaryImageSource,
    required List<ScanResult> existingResults,
  }) async {
    final grading = HybridGradingService();

    List<Student>? classStudents;
    if (classId != null) {
      final classProv = context.read<ClassProvider>();
      final studentProv = context.read<StudentProvider>();
      final cls = classProv.getClassById(classId);
      if (cls != null) {
        classStudents = cls.studentIds
            .map(studentProv.getStudentById)
            .whereType<Student>()
            .toList();
      }
    }

    final weightedScale = assessment.weightedScaleId != null
        ? context.read<WeightedGradeProvider>().getForExam(assessment.id)
        : null;

    final results = await grading.gradeBatch(
      imagePaths: images,
      assessment: assessment,
      classId: classId,
      classStudents: classStudents,
      onStudentNotFound: callbacks.onStudentNotFound,
      weightedScale: weightedScale,
      onProgress: callbacks.onProgress,
    );

    final taggedResults = results.map((r) {
      if (temporaryImageSource == null) return r;
      return r.copyWith(
        metadata: {
          ...r.metadata,
          'imageSource': temporaryImageSource,
          'paperImageRetention': PaperImageIntakeService.temporaryRetention,
        },
      );
    }).toList();

    final allResults = List<ScanResult>.from(existingResults)..addAll(taggedResults);
    callbacks.onResultsChanged(allResults);
    callbacks.onProcessingChanged(false);

    if (allResults.length >= 2) {
      final duplicates = grading.detectBatchDuplicates(allResults);
      callbacks.onDuplicatesChanged(duplicates);
    }

    if (allResults.isNotEmpty) {
      DraftService().saveDraft(
        assessmentId: assessment.id,
        completedResults: allResults.map((r) => r.toMap()).toList(),
        currentStudentIndex: existingResults.length + taggedResults.length,
        metadata: {'classId': classId ?? ''},
      );
    }
  }
}
