import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/assessment.dart';
import '../models/scan_result.dart';
import 'ocr_service.dart';
import 'omr_service.dart';
import 'bubble_template.dart';
import 'scoring_service.dart';
import 'validation_service.dart';
import 'answer_parser.dart';

/// High-level grading service that orchestrates the full scan→score pipeline.
///
/// This is the service that screens should call — not OcrService directly.
///
/// Architecture:
/// - OcrService: image enhancement + ML Kit text extraction
/// - OmrService: template-based bubble detection (pixel sampling)
/// - ScoringService: answer matching + grade calculation
/// - HybridGradingService: orchestrates all three, merges OCR+OMR results,
///   adds business logic (error handling, retry, batch, persistence)
///
/// Hybrid merge strategy:
/// - MCQ / TrueFalse → OMR wins (bubbles are the source of truth)
/// - Short answer → OCR wins (OMR can't read free text)
/// - Both detect → keep OMR for objective, OCR for subjective
/// - Neither detects → mark MISSING
/// - OMR confidence < 0.5 → fall back to OCR even for MCQ
class HybridGradingService {
  static final HybridGradingService _instance = HybridGradingService._();
  factory HybridGradingService() => _instance;
  HybridGradingService._();

  final OcrService _ocr = OcrService();
  final OmrService _omr = OmrService();
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
  /// Runs both OCR and OMR on the enhanced image, merges results,
  /// scores against the answer key, and auto-persists.
  ///
  /// Returns a ScanResult with status set to graded or needsRescan.
  /// Never throws — returns a failed ScanResult on error so the UI
  /// can show the teacher what went wrong and let them retry.
  Future<ScanResult> gradePaper({
    required String imagePath,
    required Assessment assessment,
    required String studentId,
    required String studentName,
    BubbleTemplate? template,
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
      // ── Step 1: Enhance image (once) ──
      // Both OCR and OMR work on the same enhanced image
      final enhancedPath = await _ocr.enhanceImage(imagePath);

      // ── Step 2: Run OCR and OMR ──
      // No parallelism — sequential is safe for 2GB devices
      final extractionResult = await _ocr.extractTextRegions(enhancedPath);

      final ocrAnswers = _parseOcrAnswers(extractionResult.regions, assessment);
      final omrAnswers = await _omr.detectAndParse(
        enhancedImagePath: enhancedPath,
        assessment: assessment,
        template: template,
      );

      // ── Step 3: Merge OCR + OMR results ──
      final mergedAnswers = _mergeAnswers(
        ocrAnswers: ocrAnswers,
        omrAnswers: omrAnswers,
        assessment: assessment,
      );

      // ── Step 4: Deduplicate (same Q# detected twice) ──
      final deduplicated = _scoring.deduplicateAnswers(mergedAnswers);

      // ── Step 5: Score against answer key ──
      final scoredAnswers = _scoring.scoreAnswers(
        detected: deduplicated,
        assessment: assessment,
      );

      // ── Step 6: Calculate totals ──
      final totalScore = _scoring.calculateTotalScore(scoredAnswers);
      final maxScore = assessment.maxScore;
      final percentage = _scoring.calculatePercentage(
        totalScore: totalScore,
        maxScore: maxScore,
      );
      final overallConfidence = _scoring.calculateConfidence(scoredAnswers);

      // ── Step 7: Build metadata ──
      final metadata = <String, dynamic>{
        'textLinesDetected': extractionResult.regions.length,
        'ocrAnswersDetected': ocrAnswers.length,
        'omrAnswersDetected': omrAnswers.length,
        'questionsMerged': mergedAnswers.length,
        'questionsDeduplicated': deduplicated.length,
        'duplicatesRemoved': mergedAnswers.length - deduplicated.length,
        'skewAngle': extractionResult.skewAngle,
        'skewWarning': extractionResult.skewAngle.abs() > 8.0,
        'omrConfidence': omrAnswers.isEmpty
            ? 0.0
            : omrAnswers.fold(0.0, (s, a) => s + a.confidence) / omrAnswers.length,
        'detectedMethod': omrAnswers.isNotEmpty ? 'hybrid' : 'ocr-only',
      };

      final result = ScanResult(
        assessmentId: assessment.id,
        studentId: studentId,
        studentName: studentName,
        imagePath: imagePath,
        enhancedImagePath: enhancedPath,
        answers: scoredAnswers,
        totalScore: totalScore,
        maxScore: maxScore,
        percentage: percentage,
        grade: _scoring.calculateGrade(percentage.toDouble(), assessment.rubricType),
        status: overallConfidence < 0.6 ? ScanStatus.needsRescan : ScanStatus.graded,
        confidence: overallConfidence,
        metadata: metadata,
      );

      debugPrint(
        'HybridGrading: ${result.studentName} → '
        '${result.totalScore}/${result.maxScore} '
        '(${result.grade}, ${(result.confidence * 100).toStringAsFixed(0)}% conf, '
        '${metadata['detectedMethod']})',
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
  /// [template] — optional OMR template override; auto-selected if null
  /// [onProgress] — called after each image with (processed, total)
  ///
  /// Returns all results, including failed ones (check status field).
  Future<List<ScanResult>> gradeBatch({
    required List<String> imagePaths,
    required Assessment assessment,
    List<String>? studentNames,
    BubbleTemplate? template,
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
        template: template,
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
  Future<ScanResult> regradePaper({
    required String imagePath,
    required Assessment assessment,
    required String studentId,
    required String studentName,
    BubbleTemplate? template,
  }) async {
    debugPrint('HybridGrading: re-grading $studentName');
    return gradePaper(
      imagePath: imagePath,
      assessment: assessment,
      studentId: studentId,
      studentName: studentName,
      template: template,
    );
  }

  // ── Answer Merging ────────────────────────────────────────────────

  /// Merge OCR and OMR results using the hybrid strategy.
  ///
  /// For each question in the assessment:
  /// - MCQ / TrueFalse → prefer OMR (bubbles are source of truth)
  ///   - Fall back to OCR if OMR confidence < 0.5
  /// - ShortAnswer → always use OCR (OMR can't read free text)
  /// - Essay → always use OCR
  ///
  /// If both have the answer with similar confidence, OMR wins for objective.
  List<DetectedAnswer> _mergeAnswers({
    required List<DetectedAnswer> ocrAnswers,
    required List<DetectedAnswer> omrAnswers,
    required Assessment assessment,
  }) {
    final merged = <DetectedAnswer>[];

    // Index by question number for fast lookup
    final ocrByQ = <int, DetectedAnswer>{};
    for (final a in ocrAnswers) {
      ocrByQ[a.questionNumber] = a;
    }

    final omrByQ = <int, DetectedAnswer>{};
    for (final a in omrAnswers) {
      omrByQ[a.questionNumber] = a;
    }

    for (final question in assessment.questions) {
      final ocr = ocrByQ[question.number];
      final omr = omrByQ[question.number];

      final isObjective = question.type == QuestionType.mcq ||
          question.type == QuestionType.trueFalse;

      if (isObjective) {
        // Objective questions: OMR preferred
        if (omr != null && omr.confidence >= 0.5) {
          merged.add(omr);
        } else if (ocr != null) {
          // OMR absent or low-confidence — use OCR
          merged.add(ocr);
        } else if (omr != null) {
          // OMR below 0.5 but nothing else — still use it
          merged.add(omr);
        }
        // else: neither detected → skip (will show as MISSING in scoring)
      } else {
        // Subjective questions: OCR always
        if (ocr != null) {
          merged.add(ocr);
        }
      }
    }

    return merged;
  }

  /// Parse OCR text regions into DetectedAnswers.
  List<DetectedAnswer> _parseOcrAnswers(
    List<TextRegion> regions,
    Assessment assessment,
  ) {
    final parser = const AnswerParser();
    final inputs = regions
        .map((r) => TextRegionInput(
              text: r.text,
              confidence: r.confidence,
              x: r.x,
              y: r.y,
            ))
        .toList();

    return parser
        .parseAnswers(inputs)
        .map((p) => DetectedAnswer(
              questionNumber: p.questionNumber,
              answer: p.answer,
              confidence: p.confidence,
              rawText: p.rawText,
            ))
        .toList();
  }

  // ── Persistence ───────────────────────────────────────────────────

  /// Public save method for external callers (e.g., review screen overrides).
  /// Persists an updated ScanResult to Hive with retry logic.
  /// Call after teacher overrides scores, edits comments, or adds voice notes.
  Future<bool> saveScanResult(ScanResult result) async {
    try {
      await _saveWithRetry(result);
      return true;
    } catch (e) {
      debugPrint('HybridGrading: saveScanResult failed (${e.runtimeType})');
      return false;
    }
  }

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

  // ── Batch Duplicate Detection ─────────────────────────────────────

  /// Detect answer-pattern duplicates across graded batch results.
  ///
  /// Call after [gradeBatch] completes. Compares answer fingerprints
  /// (sorted Q#:Answer pairs) between all results. Returns entries for
  /// pairs that match ≥ 90% of their answers.
  ///
  /// This catches what dHash can't: different photos of different students
  /// who gave the same answers, and same-paper re-scans where image hashing
  /// was inconclusive due to MCQ format similarity.
  ///
  /// Returns empty list if no duplicates found.
  List<AnswerDuplicate> detectBatchDuplicates(List<ScanResult> results) {
    if (results.length < 2) return [];
    final allAnswers = results.map((r) => r.answers).toList();
    return _scoring.detectAnswerDuplicates(allAnswers);
  }

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
