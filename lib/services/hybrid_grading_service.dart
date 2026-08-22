import 'dart:io';
import '../models/assessment.dart';
import '../models/scan_result.dart';
import '../models/student.dart';
import '../models/weighted_grade.dart';
import 'app_log.dart';
import 'error_handler.dart';
import 'hive_box_mixin.dart';
import '../config/integrity_metadata_keys.dart';
import 'ocr_service.dart';
import 'omr_service.dart';
import 'omr_calibration_service.dart';
import 'bubble_template.dart';
import 'scoring_service.dart';
import 'validation_service.dart';
import 'answer_parser.dart';
import 'student_matcher.dart';
import 'backup_service.dart';

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
class HybridGradingService with HiveBoxMixin {
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
    String? studentId,
    String? studentName,
    BubbleTemplate? template,
    // Class-aware matching (optional)
    String? classId,
    List<Student>? classStudents,
    Future<Student?> Function(String scannedName, String classId)?
    onStudentNotFound,
    // Weighted scoring (optional)
    WeightedGradeScale? weightedScale,
  }) async {
    await initialize();

    // Verify image file exists before processing
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      AppLog.warn(this, 'gradePaper', 'image not found: $imagePath');
      return _failedResult(
        assessmentId: assessment.id,
        studentId: studentId ?? '',
        studentName: studentName ?? 'Unknown',
        imagePath: imagePath,
        reason: 'Image file not found',
      );
    }

    // Declare before try so catch block can reference them
    String resolvedId = studentId ?? '';
    String resolvedName = studentName ?? 'Student';

    try {
      // Check if this image was already graded by cloud OCR
      final existingResults = await loadScanResults(assessment.id);
      final alreadyGraded = existingResults.where(
        (r) =>
            r.imagePath == imagePath &&
            r.metadata['detectedMethod'] == 'cloud-ocr',
      );
      if (alreadyGraded.isNotEmpty) {
        AppLog.info(
          this,
          'gradePaper',
          'skipping — already graded by cloud OCR',
        );
        return alreadyGraded.first;
      }

      // ── Step 1: Enhance image (once) ──
      // Both OCR and OMR work on the same enhanced image
      final enhancedPath = await _ocr.enhanceImage(imagePath);

      // ── Step 2: Determine grading mode ──
      // Auto-detect based on question types to avoid wasted processing
      final hasTextQuestions =
          assessment.shortAnswerCount > 0 ||
          assessment.essayCount > 0 ||
          assessment.multiAnswerCount > 0;
      final hasBubbleQuestions =
          assessment.mcqCount > 0 || assessment.trueFalseCount > 0;

      final gradingMode = hasTextQuestions && hasBubbleQuestions
          ? 'hybrid'
          : hasTextQuestions
          ? 'ocr-only'
          : 'omr-only';

      AppLog.info(this, 'gradePaper', 'grading mode: $gradingMode');

      // ── Step 3: Run OCR (skipped for pure-OMR exams) ──
      ({List<TextRegion> regions, double skewAngle})? extractionResult;
      if (gradingMode != 'omr-only') {
        extractionResult = await _ocr.extractTextRegions(enhancedPath);
        AppLog.info(
          this,
          'gradePaper',
          'OCR returned ${extractionResult.regions.length} text regions',
        );
      }

      // ── Step 3.5: Class-aware student matching ──

      if (classId != null &&
          classStudents != null &&
          classStudents.isNotEmpty &&
          extractionResult != null) {
        final ocrText = extractionResult.regions.map((r) => r.text).join('\n');
        final match = StudentMatcher.matchFromOcr(ocrText, classStudents);

        if (match.hasMatch && !match.isAmbiguous) {
          resolvedId = match.matchedStudent!.id;
          resolvedName = match.matchedStudent!.fullName;
          AppLog.info(
            this,
            'gradePaper',
            'matched "$resolvedName" (${(match.confidence * 100).toStringAsFixed(0)}%)',
          );
        } else if (onStudentNotFound != null) {
          // Ask the UI to resolve — teacher can add or select
          final scannedName = match.scannedName.isNotEmpty
              ? match.scannedName
              : 'Unknown Student';
          final added = await onStudentNotFound(scannedName, classId);
          if (added != null) {
            resolvedId = added.id;
            resolvedName = added.fullName;
          } else {
            // Teacher skipped — use scanned name as-is
            resolvedName = scannedName;
          }
        } else {
          // No callback — use scanned name or fallback
          resolvedName = match.scannedName.isNotEmpty
              ? match.scannedName
              : resolvedName;
        }
      }

      final ocrAnswers = extractionResult != null
          ? _parseOcrAnswers(extractionResult.regions, assessment)
          : <DetectedAnswer>[];

      // ── Step 3.75: Run OMR (skipped for pure-OCR exams) ──
      List<DetectedAnswer> omrAnswers = [];
      bool omrRan = false;
      String? omrTemplateName;

      if (gradingMode != 'ocr-only') {
        try {
          // Try calibrated template first, then fall back to provided/default
          final effectiveTemplate =
              template ?? await _loadCalibratedTemplate(assessment.id);

          final omrResult = await _omr.detectAndParse(
            enhancedImagePath: enhancedPath,
            assessment: assessment,
            template: effectiveTemplate,
          );
          omrAnswers = omrResult;
          omrRan = true;
          omrTemplateName = effectiveTemplate?.name ?? 'auto';
          AppLog.info(
            this,
            'gradePaper',
            'OMR detected ${omrAnswers.length} answers (template: $omrTemplateName)',
          );
        } catch (e, st) {
          AppLog.warn(
            this,
            'gradePaper',
            'OMR failed, falling back to OCR: $e',
          );
          AppErrorHandler.catchError(this, 'gradePaper/OMR', e, st);
        }
      }

      // ── Step 2.875: Merge OMR + OCR ──
      // Strategy:
      // - MCQ / TrueFalse → OMR wins if confidence >= 0.5, else OCR
      // - Short answer / Essay / MultiAnswer → OCR wins
      final mergedAnswers = _mergeOmrOcr(
        ocrAnswers: ocrAnswers,
        omrAnswers: omrAnswers,
        assessment: assessment,
      );
      AppLog.info(
        this,
        'gradePaper',
        'merged ${mergedAnswers.length} answers (OMR ran: $omrRan)',
      );

      // ── Step 4: Deduplicate (same Q# detected twice) ──
      final deduplicated = _scoring.deduplicateAnswers(mergedAnswers);

      // ── Step 5: Score against answer key ──
      final scoredAnswers = _scoring.scoreAnswers(
        detected: deduplicated,
        assessment: assessment,
      );

      // ── Step 6: Calculate totals ──
      double totalScore = _scoring.calculateTotalScore(scoredAnswers);
      final double maxScore = assessment.maxScore;
      double percentage = _scoring.calculatePercentage(
        totalScore: totalScore,
        maxScore: maxScore,
      );
      final overallConfidence = _scoring.calculateConfidence(scoredAnswers);

      // ── Step 6b: Build metadata (before weighted scoring reads it) ──
      final metadata = <String, dynamic>{
        'textLinesDetected': extractionResult?.regions.length ?? 0,
        'ocrAnswersDetected': ocrAnswers.length,
        'omrAnswersDetected': omrAnswers.length,
        'questionsDetected': mergedAnswers.length,
        'skewAngle': extractionResult?.skewAngle ?? 0.0,
        'skewWarning': (extractionResult?.skewAngle.abs() ?? 0.0) > 8.0,
        'detectedMethod': gradingMode,
        if (omrRan) 'omrTemplate': omrTemplateName,
        IntegrityMetadataKeys.scoredWithKeyFingerprint:
            assessment.answerKeyFingerprint,
        IntegrityMetadataKeys.scoredWithKeyRevision:
            assessment.answerKeyRevision,
      };

      // ── Step 7: Apply weighted scoring if scale is provided ──
      String rubricType = assessment.rubricType;
      if (weightedScale != null && weightedScale.components.isNotEmpty) {
        final weightedPct = _scoring.computeWeightedPercentage(
          scoredAnswers: scoredAnswers,
          questions: assessment.questions,
          scale: weightedScale,
        );
        if (weightedPct != null) {
          percentage = weightedPct;
          totalScore = (weightedPct / 100) * maxScore;
          rubricType = weightedScale.rubricType;
          metadata['weightedScoring'] = true;
          metadata['weightedPercentage'] = weightedPct;
        }
      }

      final result = ScanResult(
        assessmentId: assessment.id,
        studentId: resolvedId,
        studentName: resolvedName,
        imagePath: imagePath,
        enhancedImagePath: enhancedPath,
        answers: scoredAnswers,
        totalScore: totalScore,
        maxScore: maxScore,
        percentage: percentage,
        grade: _scoring.calculateGrade(percentage.toDouble(), rubricType),
        status: overallConfidence < 0.6
            ? ScanStatus.needsRescan
            : ScanStatus.graded,
        confidence: overallConfidence,
        metadata: metadata,
      );

      AppLog.info(
        this,
        'gradePaper',
        '${result.studentName} → ${result.totalScore}/${result.maxScore} (${result.grade}, ${(result.confidence * 100).toStringAsFixed(0)}% conf, ${metadata['detectedMethod']})',
      );

      // Auto-save with retry — never let persistence break the grading flow
      await _saveWithRetry(result);

      return result;
    } catch (e, stackTrace) {
      AppErrorHandler.catchError(this, 'gradePaper', e, stackTrace);
      return _failedResult(
        assessmentId: assessment.id,
        studentId: resolvedId,
        studentName: resolvedName,
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
    // Class-aware matching (optional)
    String? classId,
    List<Student>? classStudents,
    Future<Student?> Function(String scannedName, String classId)?
    onStudentNotFound,
    // Weighted scoring (optional)
    WeightedGradeScale? weightedScale,
    int concurrency = 1,
  }) async {
    await initialize();

    final results = List<ScanResult?>.filled(imagePaths.length, null);
    var processed = 0;

    Future<void> gradeOne(int i) async {
      final name = (studentNames != null && i < studentNames.length)
          ? studentNames[i]
          : null;

      final result = await gradePaper(
        imagePath: imagePaths[i],
        assessment: assessment,
        studentId: 'student_${i + 1}',
        studentName: name ?? 'Student ${i + 1}',
        template: template,
        classId: classId,
        classStudents: classStudents,
        onStudentNotFound: onStudentNotFound,
        weightedScale: weightedScale,
      );

      results[i] = result;
      processed++;
      onProgress?.call(processed, imagePaths.length);
    }

    if (concurrency <= 1) {
      for (int i = 0; i < imagePaths.length; i++) {
        await gradeOne(i);
      }
    } else {
      final queue = <Future<void>>[];
      for (int i = 0; i < imagePaths.length; i++) {
        queue.add(gradeOne(i));
        if (queue.length >= concurrency || i == imagePaths.length - 1) {
          await Future.wait(queue);
          queue.clear();
        }
      }
    }

    final validResults = results.whereType<ScanResult>().toList();
    AppLog.info(
      this,
      'gradeBatch',
      'batch complete — ${validResults.where((r) => r.status == ScanStatus.graded).length} graded, '
          '${validResults.where((r) => r.status == ScanStatus.needsRescan).length} need rescan',
    );

    return validResults;
  }

  /// Re-grade a single paper (e.g., after teacher manually adjusts image).
  Future<ScanResult> regradePaper({
    required String imagePath,
    required Assessment assessment,
    required String studentId,
    required String studentName,
    BubbleTemplate? template,
    String? classId,
    List<Student>? classStudents,
    WeightedGradeScale? weightedScale,
  }) async {
    AppLog.info(this, 'regradePaper', 're-grading $studentName');
    return gradePaper(
      imagePath: imagePath,
      assessment: assessment,
      studentId: studentId,
      studentName: studentName,
      template: template,
      classId: classId,
      classStudents: classStudents,
      weightedScale: weightedScale,
    );
  }

  /// Parse OCR text regions into DetectedAnswers.
  List<DetectedAnswer> _parseOcrAnswers(
    List<TextRegion> regions,
    Assessment assessment,
  ) {
    const parser = AnswerParser();
    final inputs = regions
        .map(
          (r) => TextRegionInput(
            text: r.text,
            confidence: r.confidence,
            x: r.x,
            y: r.y,
          ),
        )
        .toList();

    return parser
        .parseAnswers(inputs)
        .map(
          (p) => DetectedAnswer(
            questionNumber: p.questionNumber,
            answer: p.answer,
            confidence: p.confidence,
            rawText: p.rawText,
          ),
        )
        .toList();
  }

  /// Merge OMR and OCR answers using the hybrid strategy.
  ///
  /// - MCQ / TrueFalse → OMR wins if confidence >= 0.5, else OCR
  /// - Short answer / Essay / MultiAnswer → OCR wins
  /// - Both sources missing → MISSING
  List<DetectedAnswer> _mergeOmrOcr({
    required List<DetectedAnswer> ocrAnswers,
    required List<DetectedAnswer> omrAnswers,
    required Assessment assessment,
  }) {
    final merged = <DetectedAnswer>[];
    final omrByQuestion = {for (var a in omrAnswers) a.questionNumber: a};
    final ocrByQuestion = {for (var a in ocrAnswers) a.questionNumber: a};
    final allQuestions = {...omrByQuestion.keys, ...ocrByQuestion.keys};

    for (final qNum in allQuestions) {
      final omr = omrByQuestion[qNum];
      final ocr = ocrByQuestion[qNum];
      final question = assessment.questions.firstWhere(
        (q) => q.number == qNum,
        orElse: () => Question(
          number: qNum,
          text: 'Q$qNum',
          type: QuestionType.mcq,
          correctAnswer: '',
          points: 1,
        ),
      );

      final isObjective =
          question.type == QuestionType.mcq ||
          question.type == QuestionType.trueFalse;

      if (isObjective) {
        // Objective: OMR wins if confident, else OCR
        if (omr != null && omr.confidence >= 0.5) {
          merged.add(omr);
        } else if (ocr != null) {
          merged.add(ocr);
        } else if (omr != null) {
          // OMR exists but low confidence — include flagged for review
          merged.add(
            omr.copyWith(needsReview: true, source: 'omr-low-confidence'),
          );
        }
      } else {
        // Subjective: OCR wins
        if (ocr != null) {
          merged.add(ocr);
        }
      }
    }

    return merged;
  }

  /// Load calibrated template for an assessment, if available.
  Future<BubbleTemplate?> _loadCalibratedTemplate(String assessmentId) async {
    try {
      final calibrationService = OmrCalibrationService();
      return await calibrationService.loadCalibration(assessmentId);
    } catch (e) {
      AppLog.warn(
        this,
        '_loadCalibratedTemplate',
        'Failed to load calibration: $e',
      );
      return null;
    }
  }

  // ── Persistence ───────────────────────────────────────────────────

  /// Public save method for external callers (e.g., review screen overrides).
  /// Persists an updated ScanResult to Hive with retry logic.
  /// Call after teacher overrides scores, edits comments, or adds voice notes.
  Future<bool> saveScanResult(ScanResult result) async {
    try {
      await _saveWithRetry(result);
      return true;
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'saveScanResult', e, st);
      return false;
    }
  }

  /// Persist a ScanResult to the encrypted lazy box.
  /// On failure: retry once after 500ms, then queue for later.
  Future<void> _saveWithRetry(ScanResult result) async {
    // Validate before writing
    final validation = _validator.validateScanResult(result);
    if (!validation.isValid) {
      AppLog.warn(
        this,
        '_saveWithRetry',
        'scan result validation failed: ${validation.errors}',
      );
      // Still save — validation is advisory, not blocking
    }

    try {
      final box = await openBox(_scanResultsBoxName);
      await box.put(result.id, result.toMap());
      AppLog.info(this, '_saveWithRetry', 'saved scan result ${result.id}');

      // Opportunistically flush pending saves
      await flushPendingSaves();

      // Trigger auto-backup check (every N scans)
      BackupService.instance.recordScanAndMaybeBackup();
    } catch (e) {
      AppLog.warn(
        this,
        '_saveWithRetry',
        'save failed (${e.runtimeType}), retrying in 500ms…',
      );
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        final box = await openBox(_scanResultsBoxName);
        await box.put(result.id, result.toMap());
        AppLog.info(this, '_saveWithRetry', 'retry succeeded for ${result.id}');
        await flushPendingSaves();
      } catch (e2, st2) {
        AppErrorHandler.catchError(this, '_saveWithRetry/retry', e2, st2);
        _pendingSaves.add(result);
      }
    }
  }

  /// Retry all items in the pending-saves queue.
  /// Removes entries on success; keeps them on failure.
  Future<void> flushPendingSaves() async {
    if (_pendingSaves.isEmpty) return;

    final box = await openBox(_scanResultsBoxName);
    final succeeded = <ScanResult>[];

    for (final result in _pendingSaves) {
      try {
        await box.put(result.id, result.toMap());
        succeeded.add(result);
      } catch (e, st) {
        AppErrorHandler.catchError(this, 'flushPendingSaves', e, st);
      }
    }

    _pendingSaves.removeWhere(succeeded.contains);
    if (succeeded.isNotEmpty) {
      AppLog.info(
        this,
        'flushPendingSaves',
        'flushed ${succeeded.length} pending saves',
      );
    }
  }

  // ── Queries ───────────────────────────────────────────────────────

  /// Load all scan results for a specific assessment.
  /// Sorts by score descending (best first).
  ///
  /// When [throwOnError] is true, storage failures are rethrown so the
  /// caller can surface a real error state instead of silently treating
  /// the failure as "no results".
  Future<List<ScanResult>> loadScanResults(
    String assessmentId, {
    bool throwOnError = false,
  }) async {
    try {
      final box = await openBox(_scanResultsBoxName);
      final results = <ScanResult>[];

      for (final key in box.keys) {
        final data = await box.get(key);
        if (data == null) continue;
        final map = _deepCastMap(data);
        if (map['assessmentId'] == assessmentId) {
          results.add(ScanResult.fromMap(map));
        }
      }

      results.sort((a, b) => b.totalScore.compareTo(a.totalScore));
      return results;
    } catch (e, st) {
      if (throwOnError) rethrow;
      AppErrorHandler.catchError(this, 'loadScanResults', e, st);
      return [];
    }
  }

  /// Load ALL scan results from the box.
  ///
  /// When [throwOnError] is true, storage failures are rethrown so the
  /// caller can surface a real error state instead of an empty list.
  Future<List<ScanResult>> loadAllScanResults({
    bool throwOnError = false,
  }) async {
    try {
      final box = await openBox(_scanResultsBoxName);
      final results = <ScanResult>[];

      for (final key in box.keys) {
        final data = await box.get(key);
        if (data == null) continue;
        results.add(ScanResult.fromMap(_deepCastMap(data)));
      }

      return results;
    } catch (e, st) {
      if (throwOnError) rethrow;
      AppErrorHandler.catchError(this, 'loadAllScanResults', e, st);
      return [];
    }
  }

  /// Single lookup by ID. Returns `null` when not found.
  Future<ScanResult?> getScanResultById(String id) async {
    try {
      final box = await openBox(_scanResultsBoxName);
      final data = await box.get(id);
      if (data == null) return null;
      return ScanResult.fromMap(_deepCastMap(data));
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'getScanResultById', e, st);
      return null;
    }
  }

  /// Deep-cast a Map from Hive (Map<dynamic,dynamic>) to Map<String,dynamic>.
  static Map<String, dynamic> _deepCastMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((key, value) {
        if (value is Map) return MapEntry(key.toString(), _deepCastMap(value));
        if (value is List) {
          return MapEntry(
            key.toString(),
            value.map((e) {
              if (e is Map) return _deepCastMap(e);
              return e;
            }).toList(),
          );
        }
        return MapEntry(key.toString(), value);
      });
    }
    return {};
  }

  /// Remove a scan result from the box AND delete associated image files.
  Future<bool> deleteScanResult(String id) async {
    try {
      final box = await openBox(_scanResultsBoxName);
      final data = await box.get(id);

      // Delete image files before removing the record
      if (data != null) {
        final map = Map<String, dynamic>.from(data as Map);
        await _deleteImageFile(map['imagePath'] as String?);
        await _deleteImageFile(map['enhancedImagePath'] as String?);
      }

      await box.delete(id);
      AppLog.info(this, 'deleteScanResult', 'deleted scan result $id + images');
      return true;
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'deleteScanResult', e, st);
      return false;
    }
  }

  /// Delete a single image file. Never throws.
  Future<void> _deleteImageFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        AppLog.info(this, '_deleteImageFile', 'deleted image $path');
      }
    } catch (e, st) {
      AppErrorHandler.catchError(this, '_deleteImageFile', e, st);
    }
  }

  /// Load all results for a single student across all assessments.
  /// Sorts by date descending (most recent first).
  Future<List<ScanResult>> getResultsForStudent(String studentId) async {
    try {
      final box = await openBox(_scanResultsBoxName);
      final results = <ScanResult>[];

      for (final key in box.keys) {
        final data = await box.get(key);
        if (data == null) continue;
        final map = _deepCastMap(data);
        if (map['studentId'] == studentId) {
          results.add(ScanResult.fromMap(map));
        }
      }

      results.sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
      return results;
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'getResultsForStudent', e, st);
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
