import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/assessment.dart';
import '../models/scan_result.dart';
import 'ocr_service.dart';
import 'scoring_service.dart';

/// High-level grading service that orchestrates the full scan→score pipeline.
///
/// This is the service that screens should call — not OcrService directly.
/// It provides a stable API while we iterate on the underlying OCR and
/// (future) OMR implementations.
///
/// Design rationale:
/// - OcrService handles low-level image processing and text extraction
/// - ScoringService handles answer matching and grade calculation
/// - HybridGradingService orchestrates both and adds business logic
///   (error handling, retry logic, batch processing, progress reporting)
///
/// Future: when OMR (bubble detection) is added, this service will run
/// both OCR and OMR in parallel and merge results — hence "Hybrid".
class HybridGradingService {
  static final HybridGradingService _instance = HybridGradingService._();
  factory HybridGradingService() => _instance;
  HybridGradingService._();

  final OcrService _ocr = OcrService();
  final ScoringService _scoring = const ScoringService();
  bool _isInitialized = false;

  /// Initialize underlying services. Safe to call multiple times.
  Future<void> initialize() async {
    if (_isInitialized) return;
    await _ocr.initialize();
    _isInitialized = true;
  }

  /// Grade a single paper image against an assessment.
  ///
  /// This is the primary entry point for single-paper grading.
  /// Handles the full pipeline:
  /// 1. Enhance image (downscale, grayscale, contrast)
  /// 2. Extract text via ML Kit (offline, on-device)
  /// 3. Parse question-answer pairs
  /// 4. Deduplicate duplicate detections
  /// 5. Score against assessment answer key
  /// 6. Calculate grade and confidence
  ///
  /// Returns a ScanResult with status set to graded or needsRescan.
  /// Never throws — returns a failed ScanResult on error so the UI
  /// can show the teacher what went wrong and let them retry.
  Future<ScanResult> gradePaper({
    required String imagePath,
    required Assessment assessment,
    required String studentId,
    required String studentName,
  }) async {
    await initialize();

    // Verify image file exists before processing
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      debugPrint('HybridGrading: image not found: $imagePath');
      return _failedResult(
        assessmentId: assessment.id,
        studentId: studentId,
        studentName: studentName,
        imagePath: imagePath,
        reason: 'Image file not found',
      );
    }

    try {
      final result = await _ocr.processScannedPaper(
        imagePath: imagePath,
        assessment: assessment,
        studentId: studentId,
        studentName: studentName,
      );

      debugPrint(
        'HybridGrading: ${result.studentName} → '
        '${result.totalScore}/${result.maxScore} '
        '(${result.grade}, ${(result.confidence * 100).toStringAsFixed(0)}% conf)',
      );

      return result;
    } catch (e, stackTrace) {
      debugPrint('HybridGrading: grading failed for $studentName (${e.runtimeType})');
      debugPrint('Stack: $stackTrace');
      return _failedResult(
        assessmentId: assessment.id,
        studentId: studentId,
        studentName: studentName,
        imagePath: imagePath,
        reason: 'Processing error: ${e.runtimeType}',
      );
    }
  }

  /// Grade a batch of paper images.
  ///
  /// Processes each image sequentially (safe for 2GB devices — no parallel
  /// memory pressure). Reports progress via [onProgress].
  ///
  /// [imagePaths] — list of image file paths to process
  /// [assessment] — the assessment with answer key
  /// [studentNames] — optional list of student names (same length as images).
  ///   If null, auto-generates "Student 1", "Student 2", etc.
  /// [onProgress] — called after each image with (processed, total)
  ///
  /// Returns all results, including failed ones (check status field).
  Future<List<ScanResult>> gradeBatch({
    required List<String> imagePaths,
    required Assessment assessment,
    List<String>? studentNames,
    void Function(int processed, int total)? onProgress,
  }) async {
    await initialize();

    final results = <ScanResult>[];

    for (int i = 0; i < imagePaths.length; i++) {
      final name = (studentNames != null && i < studentNames.length)
          ? studentNames[i]
          : 'Student ${i + 1}';

      final result = await gradePaper(
        imagePath: imagePaths[i],
        assessment: assessment,
        studentId: 'student_${i + 1}',
        studentName: name,
      );

      results.add(result);
      onProgress?.call(i + 1, imagePaths.length);
    }

    debugPrint(
      'HybridGrading: batch complete — '
      '${results.where((r) => r.status == ScanStatus.graded).length} graded, '
      '${results.where((r) => r.status == ScanStatus.needsRescan).length} need rescan',
    );

    return results;
  }

  /// Re-grade a single paper (e.g., after teacher manually adjusts image).
  /// Same as [gradePaper] but logs differently for debugging.
  Future<ScanResult> regradePaper({
    required String imagePath,
    required Assessment assessment,
    required String studentId,
    required String studentName,
  }) async {
    debugPrint('HybridGrading: re-grading $studentName');
    return gradePaper(
      imagePath: imagePath,
      assessment: assessment,
      studentId: studentId,
      studentName: studentName,
    );
  }

  /// Create a failed ScanResult when processing cannot complete.
  ScanResult _failedResult({
    required String assessmentId,
    required String studentId,
    required String studentName,
    required String imagePath,
    required String reason,
  }) {
    return ScanResult(
      assessmentId: assessmentId,
      studentId: studentId,
      studentName: studentName,
      imagePath: imagePath,
      status: ScanStatus.needsRescan,
      confidence: 0,
      metadata: {'error': reason},
    );
  }

  /// Release resources. Call when app is shutting down.
  void dispose() {
    _ocr.dispose();
    _isInitialized = false;
  }
}
