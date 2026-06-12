import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/assessment.dart';
import '../../models/scan_result.dart';
import '../../models/student.dart';
import '../../models/coordinate_map.dart';
import '../../services/hybrid_grading_service.dart';
import '../../services/coordinate_map_omr_service.dart';
import '../../services/answer_sheet_generator.dart';
import '../../services/scoring_service.dart';
import '../../services/assessment_provider.dart';
import '../../services/class_provider.dart';
import '../../services/student_provider.dart';
import '../../services/draft_service.dart';
import '../../services/weighted_grade_provider.dart';
import '../../services/paper_image_intake_service.dart';
import '../../widgets/student_not_found_dialog.dart';
import 'master_key_confirmation_sheet.dart';

/// Callbacks for batch processor to communicate state changes back to the UI.
class BatchProcessorCallbacks {
  final void Function(int processed, int total) onProgress;
  final void Function(List<ScanResult> results) onResultsChanged;
  final void Function(List<AnswerDuplicate> duplicates) onDuplicatesChanged;
  final void Function(bool processing) onProcessingChanged;
  final void Function(bool ready, String? error) onMasterKeyStateChanged;
  final Future<Student?> Function(String scannedName, String classId)?
      onStudentNotFound;

  const BatchProcessorCallbacks({
    required this.onProgress,
    required this.onResultsChanged,
    required this.onDuplicatesChanged,
    required this.onProcessingChanged,
    required this.onMasterKeyStateChanged,
    this.onStudentNotFound,
  });
}

/// Encapsulates batch scanning logic (coordinate-map OMR and hybrid grading).
///
/// Separated from the UI widget to keep BatchScanScreen focused on layout.
class BatchProcessor {
  final BatchProcessorCallbacks callbacks;

  const BatchProcessor({required this.callbacks});

  /// Process a batch of images — routes to coordinate-map OMR or hybrid grading.
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

    if (assessment.hasCoordinateMap) {
      await _processBatchCoordinateMap(
        context: context,
        images: images,
        assessment: assessment,
        classId: classId,
        isNoRosterMode: isNoRosterMode,
        temporaryImageSource: temporaryImageSource,
        existingResults: existingResults,
        startCount: startCount,
      );
    } else {
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
  }

  /// Process master answer sheet scan.
  Future<void> processMasterKey({
    required BuildContext context,
    required String imagePath,
    required Assessment assessment,
  }) async {
    callbacks.onProgress(0, 1);
    callbacks.onMasterKeyStateChanged(false, null);

    if (!assessment.hasCoordinateMap) {
      callbacks.onMasterKeyStateChanged(
        false,
        'Generate an EthioGrade answer sheet before scanning a master key.',
      );
      return;
    }

    String resolvedPath = await AnswerSheetGenerator.resolveCoordinateMapPath(
      assessment.coordinateMapPath!,
    );
    var mapFile = File(resolvedPath);

    if (!await mapFile.exists()) {
      final regenerated = await AnswerSheetGenerator.regenerateCoordinateMap(
        assessment,
      );
      if (regenerated != null && await regenerated.exists()) {
        mapFile = regenerated;
      } else {
        callbacks.onMasterKeyStateChanged(
          false,
          'The answer sheet map is missing. Generate the PDF again, then rescan the master key.',
        );
        return;
      }
    }

    final mapJson = jsonDecode(await mapFile.readAsString());
    final layout = mapJson['layout'] ?? 'fullA4';
    final mapsToTry = layout == 'halfSheet' && mapJson['halfSheets'] is List
        ? (mapJson['halfSheets'] as List)
              .map((m) => CoordinateMap.fromMap(m))
              .toList()
        : [CoordinateMap.fromMap(mapJson)];

    final omrService = CoordinateMapOmrService();
    CoordinateMapOmrResult? bestResult;
    for (final coordMap in mapsToTry) {
      final result = await omrService.scan(
        imagePath: imagePath,
        coordinateMap: coordMap,
        assessment: assessment,
      );
      if (bestResult == null ||
          result.anchorsDetected > bestResult.anchorsDetected) {
        bestResult = result;
      }
    }

    callbacks.onProgress(1, 1);

    if (bestResult == null || !bestResult.isAnswerKey) {
      callbacks.onMasterKeyStateChanged(
        false,
        'I could not detect the master checkbox. Check the answer-key box on the sheet, then rescan.',
      );
      return;
    }

    final confirmedKey = await showMasterKeyConfirmation(
      context: context,
      assessment: assessment,
      omrResult: bestResult,
    );

    if (confirmedKey == null || confirmedKey.isEmpty) {
      callbacks.onMasterKeyStateChanged(false, 'Master answer key was not saved.');
      return;
    }

    await _saveAnswerKeyToAssessment(context, assessment, confirmedKey);
    callbacks.onMasterKeyStateChanged(true, null);
  }

  /// Process batch using coordinate-map OMR (Phase 4 pipeline).
  Future<void> _processBatchCoordinateMap({
    required BuildContext context,
    required List<String> images,
    required Assessment assessment,
    required String? classId,
    required bool isNoRosterMode,
    required String? temporaryImageSource,
    required List<ScanResult> existingResults,
    required int startCount,
  }) async {
    String resolvedPath = await AnswerSheetGenerator.resolveCoordinateMapPath(
      assessment.coordinateMapPath!,
    );
    var mapFile = File(resolvedPath);

    if (!await mapFile.exists()) {
      final regenerated = await AnswerSheetGenerator.regenerateCoordinateMap(
        assessment,
      );
      if (regenerated != null && await regenerated.exists()) {
        mapFile = regenerated;
      } else {
        await _processBatchHybrid(
          context: context,
          images: images,
          assessment: assessment,
          classId: classId,
          isNoRosterMode: isNoRosterMode,
          temporaryImageSource: temporaryImageSource,
          existingResults: existingResults,
        );
        return;
      }
    }

    final mapJson = jsonDecode(await mapFile.readAsString());
    final layout = mapJson['layout'] ?? 'fullA4';

    List<CoordinateMap> mapsToTry;
    if (layout == 'halfSheet' && mapJson['halfSheets'] is List) {
      mapsToTry = (mapJson['halfSheets'] as List)
          .map((m) => CoordinateMap.fromMap(m))
          .toList();
    } else {
      mapsToTry = [CoordinateMap.fromMap(mapJson)];
    }

    final omrService = CoordinateMapOmrService();
    final results = <ScanResult>[];
    Map<int, String>? savedAnswerKey;
    int answerKeySheetsScanned = 0;

    for (int i = 0; i < images.length; i++) {
      CoordinateMapOmrResult? bestResult;

      for (final coordMap in mapsToTry) {
        final result = await omrService.scan(
          imagePath: images[i],
          coordinateMap: coordMap,
          assessment: assessment,
        );

        if (bestResult == null ||
            result.anchorsDetected > bestResult.anchorsDetected) {
          bestResult = result;
        }
      }

      if (bestResult == null) continue;

      if (bestResult.isAnswerKey) {
        answerKeySheetsScanned++;
        final confirmedKey = await showMasterKeyConfirmation(
          context: context,
          assessment: assessment,
          omrResult: bestResult,
        );
        if (confirmedKey != null && confirmedKey.isNotEmpty) {
          savedAnswerKey = confirmedKey;
          await _saveAnswerKeyToAssessment(context, assessment, confirmedKey);

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "Master answer key saved (${confirmedKey.length})",
                ),
                backgroundColor: const Color(0xFF2E7D32),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
        callbacks.onProgress(startCount + i + 1, startCount + images.length);
        continue;
      }

      final scanResult = _omrResultToScanResult(
        omrResult: bestResult,
        assessment: assessment,
        imagePath: images[i],
        studentIndex: startCount + i + 1 - answerKeySheetsScanned,
        answerKey: savedAnswerKey,
        isNoRosterMode: isNoRosterMode,
        temporaryImageSource: temporaryImageSource,
      );

      results.add(scanResult);
      callbacks.onProgress(startCount + i + 1, startCount + images.length);
    }

    final allResults = List<ScanResult>.from(existingResults)..addAll(results);
    callbacks.onResultsChanged(allResults);
    callbacks.onProcessingChanged(false);

    if (allResults.length >= 2) {
      final duplicates = HybridGradingService().detectBatchDuplicates(allResults);
      callbacks.onDuplicatesChanged(duplicates);
    }

    if (allResults.isNotEmpty) {
      DraftService().saveDraft(
        assessmentId: assessment.id,
        completedResults: allResults.map((r) => r.toMap()).toList(),
        currentStudentIndex: startCount + images.length,
        metadata: {'classId': classId ?? ''},
      );
    }
  }

  /// Process batch using legacy hybrid grading (OCR + pixel-based OMR).
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
      onProgress: (processed, total) {
        callbacks.onProgress(processed, total);
      },
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

  /// Save scanned answer key to assessment model.
  Future<void> _saveAnswerKeyToAssessment(
    BuildContext context,
    Assessment assessment,
    Map<int, String> key,
  ) async {
    final updatedQuestions = assessment.questions.map((q) {
      final scannedAnswer = key[q.number];
      if (scannedAnswer != null && scannedAnswer.isNotEmpty) {
        return q.copyWith(correctAnswer: scannedAnswer);
      }
      return q;
    }).toList();

    final updated = assessment.copyWith(questions: updatedQuestions);
    await context.read<AssessmentProvider>().updateAssessment(updated);
  }

  /// Convert CoordinateMapOmrResult to ScanResult.
  ScanResult _omrResultToScanResult({
    required CoordinateMapOmrResult omrResult,
    required Assessment assessment,
    required String imagePath,
    required int studentIndex,
    required bool isNoRosterMode,
    Map<int, String>? answerKey,
    String? temporaryImageSource,
  }) {
    final answers = omrResult.answers.map((a) {
      final q = assessment.questions.firstWhere(
        (q) => q.number == a.questionNumber,
        orElse: () =>
            Question(number: a.questionNumber, type: QuestionType.mcq),
      );

      final correctAnswer =
          answerKey != null && answerKey.containsKey(a.questionNumber)
          ? answerKey[a.questionNumber]!
          : (a.correctAnswer).toString();

      final detected = a.detectedAnswer.toUpperCase();
      final correct = correctAnswer.toUpperCase();
      final isCorrect = detected.isNotEmpty && detected == correct;

      return AnswerMatch(
        questionNumber: a.questionNumber,
        detectedAnswer: a.detectedAnswer,
        correctAnswer: correctAnswer,
        isCorrect: isCorrect,
        score: isCorrect ? q.points : 0,
        maxScore: q.points,
        confidence: a.confidence,
        ocrRawText: '[OMR] fill=${(a.fillRatio * 100).toStringAsFixed(0)}%',
      );
    }).toList();

    final totalScore = answers.fold(0.0, (s, a) => s + a.score);
    final maxScore = answers.fold(0.0, (s, a) => s + a.maxScore);
    final percentage = maxScore > 0 ? (totalScore / maxScore) * 100 : 0.0;
    final avgConf = omrResult.averageConfidence;

    final result = ScanResult(
      assessmentId: assessment.id,
      studentId: isNoRosterMode ? '' : 'scan-$studentIndex',
      studentName: isNoRosterMode ? 'Paper $studentIndex' : 'Student $studentIndex',
      imagePath: imagePath,
      answers: answers,
      totalScore: totalScore,
      maxScore: maxScore,
      percentage: percentage,
      grade: ScoringService().calculateGrade(percentage, assessment.rubricType),
      status: avgConf < 0.6 ? ScanStatus.needsRescan : ScanStatus.graded,
      confidence: avgConf,
      metadata: {
        'source': 'coordinate_map_omr',
        'anchorsDetected': omrResult.anchorsDetected,
        'missingAnswers': omrResult.missingAnswers,
        'lowConfidenceAnswers': omrResult.lowConfidenceAnswers,
      },
    );

    if (temporaryImageSource == null) return result;
    return result.copyWith(
      metadata: {
        ...result.metadata,
        'imageSource': temporaryImageSource,
        'paperImageRetention': PaperImageIntakeService.temporaryRetention,
      },
    );
  }
}
