import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/assessment.dart';
import '../models/scan_result.dart';
import 'ocr_service.dart';
import 'scoring_service.dart';
import 'validation_service.dart';

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
///   and now auto-persists every graded result to the encrypted Hive box.
///
/// Future: when OMR (bubble detection) is added, this service will run
/// both OCR and OMR in parallel and merge results — hence "Hybrid".
class HybridGradingService {
  static final HybridGradingService _instance = HybridGradingService._();
  factory HybridGradingService() => _instance;
  HybridGradingService._();

  final OcrService _ocr = OcrService();
  final ScoringService _scoring = const ScoringService();
  static const ValidationService _validator = ValidationService();
  bool _isInitialized = false;

  /// ScanResults that failed to save — retried on next successful save.
  final List<ScanResult> _pendingSaves = [];

  static const String _scanResultsBoxName = 'scan_results';

  /// Initialize underlying services. Safe to call multiple times.
  Future<void> initialize() async {
    if (_isInitialized) return;
    await _ocr.initialize();
    _isInitialized = true;
  }

  // ── Grading ───────────────────────────────────────────────────────

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
  /// 7. Auto-save to encrypted Hive box (with retry)
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

      // Auto-save with retry — never let persistence break the grading flow
      await _saveWithRetry(result);

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

  // ── Persistence ───────────────────────────────────────────────────

  /// Persist a ScanResult to the encrypted lazy box.
  /// On failure: retry once after 500ms, then queue for later.
  Future<void> _saveWithRetry(ScanResult result) async {
    // Validate before writing
    final validation = _validator.validateScanResult(result);
    if (!validation.isValid) {
      debugPrint('HybridGrading: scan result validation failed: ${validation.errors}');
      // Still save — validation is advisory, not blocking
    }

    try {
      final box = Hive.lazyBox(_scanResultsBoxName);
      await box.put(result.id, result.toMap());
      debugPrint('HybridGrading: saved scan result ${result.id}');

      // Opportunistically flush pending saves
      await flushPendingSaves();
    } catch (e) {
      debugPrint('HybridGrading: save failed (${e.runtimeType}), retrying in 500ms…');
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        final box = Hive.lazyBox(_scanResultsBoxName);
        await box.put(result.id, result.toMap());
        debugPrint('HybridGrading: retry succeeded for ${result.id}');
        await flushPendingSaves();
      } catch (e2) {
        debugPrint('HybridGrading: retry failed (${e2.runtimeType}), queuing for later');
        _pendingSaves.add(result);
      }
    }
  }

  /// Retry all items in the pending-saves queue.
  /// Removes entries on success; keeps them on failure.
  Future<void> flushPendingSaves() async {
    if (_pendingSaves.isEmpty) return;

    final box = Hive.lazyBox(_scanResultsBoxName);
    final succeeded = <ScanResult>[];

    for (final result in _pendingSaves) {
      try {
        await box.put(result.id, result.toMap());
        succeeded.add(result);
      } catch (e) {
        debugPrint('HybridGrading: flush failed for ${result.id} (${e.runtimeType})');
      }
    }

    _pendingSaves.removeWhere(succeeded.contains);
    if (succeeded.isNotEmpty) {
      debugPrint('HybridGrading: flushed ${succeeded.length} pending saves');
    }
  }

  // ── Queries ───────────────────────────────────────────────────────

  /// Load all scan results for a specific assessment.
  /// Sorts by score descending (best first).
  Future<List<ScanResult>> loadScanResults(String assessmentId) async {
    try {
      final box = Hive.lazyBox(_scanResultsBoxName);
      final results = <ScanResult>[];

      for (final key in box.keys) {
        final data = await box.get(key);
        if (data == null) continue;
        final map = Map<String, dynamic>.from(data as Map);
        if (map['assessmentId'] == assessmentId) {
          results.add(ScanResult.fromMap(map));
        }
      }

      results.sort((a, b) => b.totalScore.compareTo(a.totalScore));
      return results;
    } catch (e) {
      debugPrint('HybridGrading: loadScanResults failed (${e.runtimeType})');
      return [];
    }
  }

  /// Single lookup by ID. Returns `null` when not found.
  Future<ScanResult?> getScanResultById(String id) async {
    try {
      final box = Hive.lazyBox(_scanResultsBoxName);
      final data = await box.get(id);
      if (data == null) return null;
      return ScanResult.fromMap(Map<String, dynamic>.from(data as Map));
    } catch (e) {
      debugPrint('HybridGrading: getScanResultById failed (${e.runtimeType})');
      return null;
    }
  }

  /// Remove a scan result from the box.
  Future<bool> deleteScanResult(String id) async {
    try {
      final box = Hive.lazyBox(_scanResultsBoxName);
      await box.delete(id);
      return true;
    } catch (e) {
      debugPrint('HybridGrading: deleteScanResult failed (${e.runtimeType})');
      return false;
    }
  }

  /// Load all results for a single student across all assessments.
  /// Sorts by date descending (most recent first).
  Future<List<ScanResult>> getResultsForStudent(String studentId) async {
    try {
      final box = Hive.lazyBox(_scanResultsBoxName);
      final results = <ScanResult>[];

      for (final key in box.keys) {
        final data = await box.get(key);
        if (data == null) continue;
        final map = Map<String, dynamic>.from(data as Map);
        if (map['studentId'] == studentId) {
          results.add(ScanResult.fromMap(map));
        }
      }

      results.sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
      return results;
    } catch (e) {
      debugPrint('HybridGrading: getResultsForStudent failed (${e.runtimeType})');
      return [];
    }
  }

  /// Count of items waiting to be saved.
  int get pendingSaveCount => _pendingSaves.length;

  // ── Helpers ───────────────────────────────────────────────────────

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
