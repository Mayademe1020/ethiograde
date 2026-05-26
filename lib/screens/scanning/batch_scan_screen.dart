import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/assessment.dart';
import '../../models/scan_result.dart';
import '../../models/student.dart';
import '../../models/coordinate_map.dart';
import '../../services/hybrid_grading_service.dart';
import '../../services/ocr_service.dart';
import '../../services/coordinate_map_omr_service.dart';
import '../../services/answer_sheet_generator.dart';
import '../../services/scoring_service.dart';
import '../../services/assessment_provider.dart';
import '../../services/class_provider.dart';
import '../../services/student_provider.dart';
import '../../services/voice_service.dart';
import '../../services/draft_service.dart';
import '../../services/weighted_grade_provider.dart';
import '../../services/batch_review_service.dart';
import '../../widgets/student_not_found_dialog.dart';

/// Actions for the Quick Grade save/discard dialog.
enum _QuickGradeAction { save, discard }

class BatchScanScreen extends StatefulWidget {
  const BatchScanScreen({super.key});

  @override
  State<BatchScanScreen> createState() => _BatchScanScreenState();
}

class _BatchScanScreenState extends State<BatchScanScreen> {
  final List<ScanResult> _results = [];
  List<AnswerDuplicate> _duplicates = [];
  bool _isProcessing = false;
  bool _isSpeaking = false;
  bool _masterOnly = false;
  bool _masterKeyReady = false;
  String? _masterKeyError;
  int _processedCount = 0;
  int _totalCount = 0;
  List<String> _imagePaths = [];
  Assessment? _assessment;
  bool _isDraftResume = false;

  String? _classId;

  bool get _isNoRosterMode =>
      _assessment?.isQuickGrade == true ||
      _assessment?.settings['examDayMode'] == 'noRoster' ||
      _assessment?.settings['studentMode'] == 'noRoster';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args != null && _results.isEmpty) {
      // Handle both Map args (normal + draft resume) and Assessment args (direct)
      if (args is Map) {
        final assessment = args['assessment'] as Assessment?;
        final images = args['images'] as List<String>?;
        _classId = args['classId'] as String?;
        _masterOnly = args['masterOnly'] == true;

        // Draft resume: load completed results and continue
        final draftResults = args['draftCompletedResults'] as List<ScanResult>?;
        final draftIndex = args['draftCurrentIndex'] as int?;

        if (assessment != null &&
            draftResults != null &&
            draftResults.isNotEmpty) {
          _assessment = assessment;
          _classId ??= assessment.settings['classId'] as String?;
          _results.addAll(draftResults);
          _processedCount = draftResults.length;
          _totalCount = draftIndex ?? draftResults.length;
          _isDraftResume = true;
          // Don't auto-process — teacher needs to continue scanning
        } else if (assessment != null && images != null) {
          _assessment = assessment;
          _classId ??= assessment.settings['classId'] as String?;
          _imagePaths = List<String>.from(images);
          _totalCount = images.length;
          if (_masterOnly) {
            if (images.isEmpty) {
              _finishMasterKeyWithError('No master answer sheet image found.');
            } else {
              _processMasterKey(images.first, assessment);
            }
          } else {
            _processBatch(images, assessment);
          }
        }
      } else if (args is Assessment) {
        // Direct assessment arg (from Quick Grade or manual entry)
        _assessment = args;
        _classId ??= args.settings['classId'] as String?;
      }
    }
  }

  Future<void> _processBatch(List<String> images, Assessment assessment) async {
    if (!mounted) return;
    setState(() => _isProcessing = true);

    // Route to coordinate-map OMR if available, otherwise fall back to hybrid grading
    if (assessment.hasCoordinateMap) {
      await _processBatchCoordinateMap(images, assessment);
    } else {
      await _processBatchHybrid(images, assessment);
    }
  }

  Future<void> _processMasterKey(
    String imagePath,
    Assessment assessment,
  ) async {
    if (!mounted) return;
    setState(() {
      _isProcessing = true;
      _processedCount = 0;
      _totalCount = 1;
      _masterKeyError = null;
      _masterKeyReady = false;
    });

    if (!assessment.hasCoordinateMap) {
      _finishMasterKeyWithError(
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
        _finishMasterKeyWithError(
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

    if (!mounted) return;
    setState(() => _processedCount = 1);

    if (bestResult == null || !bestResult.isAnswerKey) {
      _finishMasterKeyWithError(
        'I could not detect the master checkbox. Check the answer-key box on the sheet, then rescan.',
      );
      return;
    }

    final confirmedKey = await _confirmScannedMasterKey(
      assessment: assessment,
      omrResult: bestResult,
    );
    if (!mounted) return;

    if (confirmedKey == null || confirmedKey.isEmpty) {
      _finishMasterKeyWithError('Master answer key was not saved.');
      return;
    }

    await _saveAnswerKeyToAssessment(assessment, confirmedKey);
    if (!mounted) return;

    setState(() {
      _isProcessing = false;
      _masterKeyReady = true;
      _masterKeyError = null;
    });
  }

  void _finishMasterKeyWithError(String message) {
    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      _masterKeyReady = false;
      _masterKeyError = message;
      _processedCount = _totalCount == 0 ? 0 : 1;
    });
  }

  /// Process batch using coordinate-map OMR (Phase 4 pipeline).
  ///
  /// Supports half-sheet layout (2 per page) and answer key detection.
  Future<void> _processBatchCoordinateMap(
    List<String> images,
    Assessment assessment,
  ) async {
    // Resolve coordinate map path (handles relative filenames + missing files)
    String resolvedPath = await AnswerSheetGenerator.resolveCoordinateMapPath(
      assessment.coordinateMapPath!,
    );
    var mapFile = File(resolvedPath);

    if (!await mapFile.exists()) {
      // File missing — try to regenerate from assessment
      debugPrint('BatchScan: coord map missing, regenerating...');
      final regenerated = await AnswerSheetGenerator.regenerateCoordinateMap(
        assessment,
      );
      if (regenerated != null && await regenerated.exists()) {
        mapFile = regenerated;
      } else {
        debugPrint(
          'BatchScan: regeneration failed, falling back to hybrid grading',
        );
        await _processBatchHybrid(images, assessment);
        return;
      }
    }

    final mapJson = jsonDecode(await mapFile.readAsString());

    // Determine layout: fullA4 or halfSheet
    final layout = mapJson['layout'] ?? 'fullA4';

    // Build coordinate maps to try per image
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
    final startCount = _processedCount;
    Map<int, String>? savedAnswerKey;
    int answerKeySheetsScanned = 0;

    for (int i = 0; i < images.length; i++) {
      if (!mounted) break;

      // Try each coordinate map, pick the one with best anchor detection
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

      if (bestResult == null) {
        debugPrint('BatchScan: no result for image $i');
        continue;
      }

      // Handle answer key detection
      if (bestResult.isAnswerKey) {
        answerKeySheetsScanned++;
        final confirmedKey = await _confirmScannedMasterKey(
          assessment: assessment,
          omrResult: bestResult,
        );
        if (!mounted) return;
        if (confirmedKey != null && confirmedKey.isNotEmpty) {
          savedAnswerKey = confirmedKey;
          final key = confirmedKey;
          debugPrint('BatchScan: Answer key captured — ${key.length} answers');

          // Save answer key after teacher confirmation.
          await _saveAnswerKeyToAssessment(assessment, confirmedKey);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "Master answer key saved (${confirmedKey.length})",
                ),
                backgroundColor: AppTheme.primaryGreen,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
        // Don't add key sheet to results — continue to next image
        setState(() {
          _processedCount = startCount + i + 1;
        });
        continue;
      }

      // Grade student sheet — use saved answer key if available
      final scanResult = _omrResultToScanResult(
        omrResult: bestResult,
        assessment: assessment,
        imagePath: images[i],
        studentIndex: startCount + i + 1 - answerKeySheetsScanned,
        answerKey: savedAnswerKey,
      );

      results.add(scanResult);

      // Update progress after each scan
      setState(() {
        _processedCount = startCount + i + 1;
      });
    }

    if (!mounted) return;
    setState(() {
      _results.addAll(results);
      _isProcessing = false;
    });

    // Show answer key summary if any sheets were detected as keys
    if (answerKeySheetsScanned > 0 && mounted) {
      debugPrint(
        'BatchScan: $answerKeySheetsScanned answer key sheet(s) detected and skipped',
      );
    }

    // Duplicate detection
    if (_results.length >= 2) {
      _duplicates = HybridGradingService().detectBatchDuplicates(_results);
    }

    if (_results.isNotEmpty) {}

    // Draft save
    if (_results.isNotEmpty) {
      DraftService().saveDraft(
        assessmentId: assessment.id,
        completedResults: _results.map((r) => r.toMap()).toList(),
        currentStudentIndex: _processedCount,
        metadata: {'classId': _classId ?? ''},
      );
    }
  }

  /// Save scanned answer key to assessment model.
  Future<void> _saveAnswerKeyToAssessment(
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
    _assessment = updated;
  }

  Future<Map<int, String>?> _confirmScannedMasterKey({
    required Assessment assessment,
    required CoordinateMapOmrResult omrResult,
  }) {
    final objectiveQuestions = assessment.questions
        .where(
          (q) => q.type == QuestionType.mcq || q.type == QuestionType.trueFalse,
        )
        .toList(growable: false);
    final answerByQuestion = {
      for (final answer in omrResult.answers) answer.questionNumber: answer,
    };
    final draft = <int, String>{
      for (final answer in omrResult.answers)
        if (answer.detectedAnswer.isNotEmpty)
          answer.questionNumber: answer.detectedAnswer,
    };

    return showModalBottomSheet<Map<int, String>>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final missing = objectiveQuestions
                .where((question) => (draft[question.number] ?? '').isEmpty)
                .length;
            final weak = objectiveQuestions.where((question) {
              final scanned = answerByQuestion[question.number];
              return scanned != null &&
                  scanned.detectedAnswer.isNotEmpty &&
                  scanned.confidence < 0.6;
            }).length;
            final ready = objectiveQuestions.isNotEmpty && missing == 0;

            return SafeArea(
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.88,
                minChildSize: 0.58,
                maxChildSize: 0.96,
                builder: (context, controller) {
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryGreen.withOpacity(
                                      0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.document_scanner_outlined,
                                    color: AppTheme.primaryGreen,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Confirm master answer sheet',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        missing == 0 && weak == 0
                                            ? 'Looks clean. Check once, then use it as the answer key.'
                                            : 'Only fix the highlighted answers. The rest can stay as detected.',
                                        style: TextStyle(
                                          color: AppTheme.lightText,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _MasterKeyStat(
                                    label: 'Detected',
                                    value:
                                        '${objectiveQuestions.length - missing}/${objectiveQuestions.length}',
                                    color: AppTheme.primaryGreen,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _MasterKeyStat(
                                    label: 'Needs tap',
                                    value: '$missing',
                                    color: missing == 0
                                        ? AppTheme.primaryGreen
                                        : AppTheme.primaryRed,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _MasterKeyStat(
                                    label: 'Weak',
                                    value: '$weak',
                                    color: weak == 0
                                        ? AppTheme.primaryGreen
                                        : AppTheme.warning,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                          itemCount: objectiveQuestions.length,
                          itemBuilder: (context, index) {
                            final question = objectiveQuestions[index];
                            final scanned = answerByQuestion[question.number];
                            final selected = draft[question.number] ?? '';
                            final isMissing = selected.isEmpty;
                            final isWeak =
                                !isMissing &&
                                scanned != null &&
                                scanned.confidence < 0.6;
                            final choices =
                                question.type == QuestionType.trueFalse
                                ? const ['True', 'False']
                                : const ['A', 'B', 'C', 'D', 'E'];

                            return _MasterKeyAnswerRow(
                              questionNumber: question.number,
                              choices: choices,
                              selected: selected,
                              confidence: scanned?.confidence,
                              isMissing: isMissing,
                              isWeak: isWeak,
                              onSelected: (value) {
                                setSheetState(() {
                                  draft[question.number] = value;
                                });
                              },
                            );
                          },
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          border: Border(
                            top: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => Navigator.pop(ctx),
                                icon: const Icon(Icons.camera_alt_outlined),
                                label: const Text('Rescan'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: FilledButton.icon(
                                onPressed: ready
                                    ? () => Navigator.pop(
                                        ctx,
                                        Map<int, String>.from(draft),
                                      )
                                    : null,
                                icon: const Icon(Icons.check_circle_outline),
                                label: Text(
                                  ready
                                      ? 'Use as answer key'
                                      : 'Fix $missing missing',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  /// Convert CoordinateMapOmrResult to ScanResult.
  ///
  /// [answerKey] — optional override from scanned answer key sheet.
  /// If provided, correct answers come from the key rather than the assessment.
  ScanResult _omrResultToScanResult({
    required CoordinateMapOmrResult omrResult,
    required Assessment assessment,
    required String imagePath,
    required int studentIndex,
    Map<int, String>? answerKey,
  }) {
    final answers = omrResult.answers.map((a) {
      // Find matching assessment question for scoring
      final q = assessment.questions.firstWhere(
        (q) => q.number == a.questionNumber,
        orElse: () =>
            Question(number: a.questionNumber, type: QuestionType.mcq),
      );

      // Use scanned answer key if available, otherwise assessment's stored key
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

    return ScanResult(
      assessmentId: assessment.id,
      studentId: _isNoRosterMode ? '' : 'scan-$studentIndex',
      studentName: _isNoRosterMode
          ? 'Paper $studentIndex'
          : 'Student $studentIndex',
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
  }

  /// Process batch using legacy hybrid grading (OCR + pixel-based OMR).
  Future<void> _processBatchHybrid(
    List<String> images,
    Assessment assessment,
  ) async {
    final grading = HybridGradingService();

    // Get class students for matching
    List<Student>? classStudents;
    if (_classId != null) {
      final classProv = context.read<ClassProvider>();
      final studentProv = context.read<StudentProvider>();
      final cls = classProv.getClassById(_classId!);
      if (cls != null) {
        classStudents = cls.studentIds
            .map(studentProv.getStudentById)
            .whereType<Student>()
            .toList();
      }
    }

    // Load weighted scale if configured
    final weightedScale = assessment.weightedScaleId != null
        ? context.read<WeightedGradeProvider>().getForExam(assessment.id)
        : null;

    final results = await grading.gradeBatch(
      imagePaths: images,
      assessment: assessment,
      classId: _classId,
      classStudents: classStudents,
      onStudentNotFound: _classId != null ? _showStudentNotFoundDialog : null,
      weightedScale: weightedScale,
      onProgress: (processed, total) {
        if (mounted) {
          setState(() {
            _processedCount = processed;
          });
        }
      },
    );

    if (!mounted) return;
    setState(() {
      _results.addAll(results);
      _isProcessing = false;
    });

    // Detect answer-pattern duplicates (post-OCR)
    if (_results.length >= 2) {
      _duplicates = grading.detectBatchDuplicates(_results);
      if (_duplicates.isNotEmpty) {
        debugPrint(
          'BatchScan: ${_duplicates.length} answer-pattern duplicate(s) detected',
        );
      }
    }

    // Auto-save draft after each batch (crash recovery)
    if (_results.isNotEmpty) {
      DraftService().saveDraft(
        assessmentId: assessment.id,
        completedResults: _results.map((r) => r.toMap()).toList(),
        currentStudentIndex: _processedCount,
        metadata: {'classId': _classId ?? ''},
      );
    }
  }

  /// Show student not found dialog. Returns the added student, or null if skipped.
  Future<Student?> _showStudentNotFoundDialog(
    String scannedName,
    String classId,
  ) async {
    if (!mounted) return null;
    return StudentNotFoundDialog.show(
      context: context,
      scannedName: scannedName,
      classId: classId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_masterOnly ? 'Grading Session' : 'Batch Scan'),
        actions: [
          if (_results.isNotEmpty && !_isProcessing)
            TextButton.icon(
              onPressed: () {
                // Clear draft — teacher is done grading
                if (_assessment != null) {
                  DraftService().clearDraft(_assessment!.id);
                }
                Navigator.pushNamed(
                  context,
                  AppRoutes.review,
                  arguments: _results,
                );
              },
              icon: const Icon(Icons.rate_review),
              label: Text('Review'),
            ),
        ],
      ),
      body: _masterOnly && !_isProcessing && _results.isEmpty
          ? _buildMasterSessionBody()
          : Column(
              children: [
                // Draft resume banner
                if (_isDraftResume)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    color: AppTheme.info.withOpacity(0.08),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.play_circle_outline,
                          color: AppTheme.info,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Resuming: $_processedCount/$_totalCount already graded",
                            style: const TextStyle(
                              color: AppTheme.info,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Progress header
                Container(
                  padding: const EdgeInsets.all(16),
                  color: AppTheme.primaryGreen.withOpacity(0.05),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Progress',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '$_processedCount / $_totalCount',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _totalCount > 0
                              ? _processedCount / _totalCount
                              : 0,
                          minHeight: 8,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppTheme.primaryGreen,
                          ),
                        ),
                      ),
                      if (_isProcessing)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Processing...',
                                style: TextStyle(
                                  color: AppTheme.lightText,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                // Summary stats (when done)
                if (!_isProcessing && _results.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _MiniStat(
                            label: 'Avg',
                            value: _average.toStringAsFixed(1),
                            color: AppTheme.primaryGreen,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MiniStat(
                            label: 'High',
                            value: _highest.toStringAsFixed(1),
                            color: AppTheme.info,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MiniStat(
                            label: 'Low',
                            value: _lowest.toStringAsFixed(1),
                            color: AppTheme.primaryRed,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MiniStat(
                            label: 'Pass',
                            value: '${_passRate.toStringAsFixed(0)}%',
                            color: AppTheme.success,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Duplicate warnings (answer-pattern detection)
                if (_duplicates.isNotEmpty && !_isProcessing)
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryYellow.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.primaryYellow.withOpacity(0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: AppTheme.primaryYellow,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Possible Duplicates',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...(_duplicates.map((d) {
                          final nameA = d.scanIndexA < _results.length
                              ? _results[d.scanIndexA].studentName
                              : '#${d.scanIndexA + 1}';
                          final nameB = d.scanIndexB < _results.length
                              ? _results[d.scanIndexB].studentName
                              : '#${d.scanIndexB + 1}';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              "  #$nameA & #$nameB — answers ${d.matchPercent.toStringAsFixed(0)}% match",
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        })),
                      ],
                    ),
                  ),

                // Results list
                Expanded(
                  child: _results.isEmpty && !_isProcessing
                      ? Center(
                          child: Text(
                            'No results yet',
                            style: TextStyle(color: AppTheme.lightText),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final r = _results[index];
                            final passed = r.percentage >= 50;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: passed
                                      ? AppTheme.primaryGreen.withOpacity(0.1)
                                      : AppTheme.primaryRed.withOpacity(0.1),
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      color: passed
                                          ? AppTheme.primaryGreen
                                          : AppTheme.primaryRed,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(r.studentName),
                                subtitle: Text(
                                  '${r.totalScore.toInt()}/${r.maxScore.toInt()} • ${r.grade}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Assign student button
                                    if (r.studentName.startsWith('Student '))
                                      IconButton(
                                        icon: const Icon(
                                          Icons.person_add_outlined,
                                          size: 20,
                                        ),
                                        color: AppTheme.primaryGreen,
                                        tooltip: 'Assign student',
                                        onPressed: () => _assignStudent(index),
                                      ),
                                    Text(
                                      '${r.percentage.toStringAsFixed(1)}%',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: passed
                                            ? AppTheme.primaryGreen
                                            : AppTheme.primaryRed,
                                      ),
                                    ),
                                  ],
                                ),
                                onLongPress: () => _assignStudent(index),
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.sideBySide,
                                  arguments: r,
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Bottom actions
                if (!_isProcessing && _results.isNotEmpty)
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Voice readout button
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _isSpeaking
                                  ? () => VoiceService().stopSpeaking().then(
                                      (_) =>
                                          setState(() => _isSpeaking = false),
                                    )
                                  : _readScoresAloud,
                              icon: Icon(
                                _isSpeaking
                                    ? Icons.stop_circle
                                    : Icons.volume_up,
                                size: 20,
                              ),
                              label: Text(
                                _isSpeaking ? ('Stop') : ('Read Scores Aloud'),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _isSpeaking
                                    ? AppTheme.primaryRed
                                    : AppTheme.primaryGreen,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _undoLastResult(),
                                  icon: const Icon(Icons.undo),
                                  label: Text('Undo Last'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.warning,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _handleReviewAll(),
                              icon: const Icon(Icons.rate_review),
                              label: Text('Review All'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildMasterSessionBody() {
    final assessment = _assessment;
    final ready = _masterKeyReady && assessment != null;
    final completeCount =
        assessment?.questions
            .where((q) => (q.correctAnswer ?? '').toString().isNotEmpty)
            .length ??
        0;
    final totalCount = assessment?.questions.length ?? 0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ready
                    ? AppTheme.primaryGreen.withOpacity(0.08)
                    : AppTheme.primaryRed.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: ready
                      ? AppTheme.primaryGreen.withOpacity(0.24)
                      : AppTheme.primaryRed.withOpacity(0.24),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    ready
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_rounded,
                    color: ready ? AppTheme.primaryGreen : AppTheme.primaryRed,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ready
                              ? 'Master answer key saved'
                              : 'Master scan needs attention',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ready
                              ? '$completeCount/$totalCount answers confirmed. Student papers will use this key.'
                              : (_masterKeyError ??
                                    'Rescan the master answer sheet or enter the answer key manually.'),
                          style: TextStyle(
                            color: AppTheme.lightText,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (assessment != null) ...[
              Text(
                assessment.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '${assessment.subject} • ${assessment.questionCount} questions',
                style: TextStyle(color: AppTheme.lightText),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: ready ? _showMasterKeySheet : null,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('View/Edit answer key'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: ready
                    ? () => Navigator.pushReplacementNamed(
                        context,
                        AppRoutes.camera,
                        arguments: assessment,
                      )
                    : null,
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Start scanning student papers'),
              ),
              const SizedBox(height: 12),
              if (!ready)
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Rescan master answer sheet'),
                ),
              if (!ready)
                TextButton.icon(
                  onPressed: () => Navigator.pushReplacementNamed(
                    context,
                    AppRoutes.answerKey,
                    arguments: assessment,
                  ),
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Enter answer key manually'),
                ),
            ],
            const Spacer(),
            Text(
              'Next: scan student papers one by one or in a batch. Scores stay reviewable before final save.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.lightText, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  void _showMasterKeySheet() {
    final assessment = _assessment;
    if (assessment == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          minChildSize: 0.45,
          maxChildSize: 0.94,
          builder: (context, controller) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Master Answer Key',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: assessment.questions.length,
                  itemBuilder: (context, index) {
                    final question = assessment.questions[index];
                    final answer = (question.correctAnswer ?? '').toString();
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        child: Text('${question.number}'),
                      ),
                      title: Text(answer.isEmpty ? 'Missing' : answer),
                      trailing: answer.isEmpty
                          ? const Icon(Icons.warning_amber_rounded)
                          : const Icon(Icons.check_circle_outline),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pushNamed(
                      context,
                      AppRoutes.answerKey,
                      arguments: assessment,
                    );
                  },
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Edit answer key'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Assign a student from the class roster to a scan result.
  Future<void> _assignStudent(int resultIndex) async {
    if (_classId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No class selected — pick a class first to assign students',
          ),
        ),
      );
      return;
    }

    final classProv = context.read<ClassProvider>();
    final studentProv = context.read<StudentProvider>();
    final cls = classProv.getClassById(_classId!);
    if (cls == null) return;

    final students =
        cls.studentIds
            .map(studentProv.getStudentById)
            .whereType<Student>()
            .toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName));

    if (students.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No students in this class')));
      return;
    }

    final selected = await showModalBottomSheet<Student>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Student',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: students.length,
                itemBuilder: (_, i) {
                  final s = students[i];
                  // Check if already assigned to another scan
                  final alreadyAssigned = _results.any(
                    (r) =>
                        r.studentId == s.id &&
                        _results.indexOf(r) != resultIndex,
                  );
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: alreadyAssigned
                          ? Colors.orange.withOpacity(0.2)
                          : AppTheme.primaryGreen.withOpacity(0.1),
                      child: Text(
                        s.studentId.isNotEmpty ? s.studentId : '${i + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          color: alreadyAssigned
                              ? Colors.orange
                              : AppTheme.primaryGreen,
                        ),
                      ),
                    ),
                    title: Text(s.fullName),
                    subtitle: alreadyAssigned
                        ? Text(
                            'Already assigned',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 11,
                            ),
                          )
                        : null,
                    trailing: alreadyAssigned
                        ? const Icon(
                            Icons.warning_amber,
                            color: Colors.orange,
                            size: 18,
                          )
                        : null,
                    onTap: () => Navigator.pop(ctx, s),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selected == null || !mounted) return;

    setState(() {
      final old = _results[resultIndex];
      _results[resultIndex] = const BatchReviewService().assignStudent(
        old,
        selected,
      );
      _recomputeDuplicates();
    });

    _saveDraftSnapshot();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Assigned to ${selected.fullName}"),
        backgroundColor: AppTheme.primaryGreen,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Remove the last scan result (undo last scan).
  void _undoLastResult() {
    if (_results.isEmpty) return;
    setState(() {
      _results.removeLast();
      _processedCount = _results.length;
      _recomputeDuplicates();
    });
    _saveDraftSnapshot();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Last scan removed'),
        backgroundColor: AppTheme.warning,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _recomputeDuplicates() {
    if (_results.length < 2) {
      _duplicates = [];
      return;
    }
    _duplicates = HybridGradingService()
        .detectBatchDuplicates(_results)
        .where((duplicate) => !_isDuplicateReviewed(duplicate))
        .toList();
  }

  bool _isDuplicateReviewed(AnswerDuplicate duplicate) {
    if (duplicate.scanIndexA >= _results.length ||
        duplicate.scanIndexB >= _results.length) {
      return true;
    }
    return _results[duplicate.scanIndexA].metadata['duplicateReviewed'] ==
            true &&
        _results[duplicate.scanIndexB].metadata['duplicateReviewed'] == true;
  }

  void _saveDraftSnapshot() {
    if (_assessment == null) return;
    DraftService().saveDraft(
      assessmentId: _assessment!.id,
      completedResults: _results.map((r) => r.toMap()).toList(),
      currentStudentIndex: _processedCount,
      metadata: {'classId': _classId ?? ''},
    );
  }

  /// Handle "Review All" — for Quick Grade assessments, show save dialog first.
  Future<void> _handleReviewAll() async {
    if (_assessment?.isQuickGrade == true) {
      final action = await _showQuickGradeDialog();
      if (!mounted) return;

      if (action == _QuickGradeAction.save) {
        await _showRenameSheet();
      } else if (action == _QuickGradeAction.discard) {
        await _discardQuickGrade();
        return;
      }
      // action == null (back button) or save completed — proceed to review
    }

    if (!mounted) return;
    // Clear draft — teacher is done grading
    final confirmed = await _showBatchCompletionReview();
    if (!mounted || confirmed != true) return;

    if (_assessment != null) {
      DraftService().clearDraft(_assessment!.id);
    }
    Navigator.pushNamed(context, AppRoutes.review, arguments: _results);
  }

  Future<bool?> _showBatchCompletionReview() {
    final noRoster = _isNoRosterMode;
    final review = const BatchReviewService();

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, sheetSetState) {
          final students = context.read<StudentProvider>().studentsByClassId(
            _classId,
          );
          final summary = review.summarize(
            results: _results,
            roster: students,
            duplicateCount: _duplicates.length,
            noRoster: noRoster,
          );

          void refresh() {
            sheetSetState(() {});
            _saveDraftSnapshot();
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.86,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Review before saving',
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      noRoster
                          ? 'These papers can stay as Paper 1, Paper 2, and so on. Assign names later if needed.'
                          : 'Choose what happened before results are saved. Nothing is silently marked zero.',
                      style: TextStyle(color: AppTheme.lightText, height: 1.35),
                    ),
                    const SizedBox(height: 16),
                    _BatchReviewMetric(
                      icon: Icons.fact_check_outlined,
                      label: 'Scanned papers',
                      value: '${summary.scannedPapers}',
                      color: AppTheme.primaryGreen,
                    ),
                    _BatchReviewMetric(
                      icon: Icons.report_gmailerrorred_outlined,
                      label: 'Low-confidence papers',
                      value: '${summary.lowConfidencePapers}',
                      color: summary.lowConfidencePapers == 0
                          ? AppTheme.primaryGreen
                          : AppTheme.warning,
                    ),
                    _BatchReviewMetric(
                      icon: Icons.copy_all_outlined,
                      label: 'Possible duplicates',
                      value: '${summary.possibleDuplicates}',
                      color: summary.possibleDuplicates == 0
                          ? AppTheme.primaryGreen
                          : AppTheme.primaryRed,
                    ),
                    if (!noRoster)
                      _BatchReviewMetric(
                        icon: Icons.person_search_outlined,
                        label: 'Missing students',
                        value: '${summary.missingStudents.length}',
                        color: summary.missingStudents.isEmpty
                            ? AppTheme.primaryGreen
                            : AppTheme.warning,
                      ),
                    if (noRoster)
                      _BatchReviewMetric(
                        icon: Icons.label_outline,
                        label: 'Unassigned papers',
                        value: '${summary.unassignedPapers}',
                        color: AppTheme.info,
                      ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (summary.missingStudents.isNotEmpty)
                              _MissingStudentActions(
                                students: summary.missingStudents,
                                onMarkAbsent: (student) {
                                  if (_assessment == null) return;
                                  final updated = review.appendIfMissingStudent(
                                    _results,
                                    review.markAbsent(
                                      assessment: _assessment!,
                                      student: student,
                                    ),
                                  );
                                  setState(() {
                                    _results
                                      ..clear()
                                      ..addAll(updated);
                                    _processedCount = _results.length;
                                    _recomputeDuplicates();
                                  });
                                  refresh();
                                },
                                onLeaveUngraded: (student) {
                                  if (_assessment == null) return;
                                  final updated = review.appendIfMissingStudent(
                                    _results,
                                    review.leaveUngraded(
                                      assessment: _assessment!,
                                      student: student,
                                    ),
                                  );
                                  setState(() {
                                    _results
                                      ..clear()
                                      ..addAll(updated);
                                    _processedCount = _results.length;
                                    _recomputeDuplicates();
                                  });
                                  refresh();
                                },
                                onManualEntry: (student) {
                                  if (_assessment == null) return;
                                  final updated = review.appendIfMissingStudent(
                                    _results,
                                    review.needsManualEntry(
                                      assessment: _assessment!,
                                      student: student,
                                    ),
                                  );
                                  setState(() {
                                    _results
                                      ..clear()
                                      ..addAll(updated);
                                    _processedCount = _results.length;
                                    _recomputeDuplicates();
                                  });
                                  refresh();
                                },
                              ),
                            if (_duplicates.isNotEmpty)
                              _DuplicateActions(
                                duplicates: _duplicates,
                                results: _results,
                                onKeepBoth: (duplicate) {
                                  setState(() {
                                    if (duplicate.scanIndexA <
                                        _results.length) {
                                      _results[duplicate.scanIndexA] = review
                                          .markDuplicateReviewed(
                                            _results[duplicate.scanIndexA],
                                          );
                                    }
                                    if (duplicate.scanIndexB <
                                        _results.length) {
                                      _results[duplicate.scanIndexB] = review
                                          .markDuplicateReviewed(
                                            _results[duplicate.scanIndexB],
                                          );
                                    }
                                    _recomputeDuplicates();
                                  });
                                  refresh();
                                },
                                onKeepFirst: (duplicate) {
                                  final updated = review.removeAt(
                                    _results,
                                    duplicate.scanIndexB,
                                  );
                                  setState(() {
                                    _results
                                      ..clear()
                                      ..addAll(updated);
                                    _processedCount = _results.length;
                                    _recomputeDuplicates();
                                  });
                                  refresh();
                                },
                                onKeepSecond: (duplicate) {
                                  final updated = review.removeAt(
                                    _results,
                                    duplicate.scanIndexA,
                                  );
                                  setState(() {
                                    _results
                                      ..clear()
                                      ..addAll(updated);
                                    _processedCount = _results.length;
                                    _recomputeDuplicates();
                                  });
                                  refresh();
                                },
                                onAssign: (duplicate) {
                                  Navigator.pop(ctx, false);
                                  _assignStudent(duplicate.scanIndexB);
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.pop(ctx, false),
                            icon: const Icon(Icons.add_a_photo_outlined),
                            label: const Text('Scan later'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => Navigator.pop(ctx, true),
                            icon: const Icon(Icons.rate_review_outlined),
                            label: const Text('Review'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Show "Save or Discard?" dialog for Quick Grade assessments.
  Future<_QuickGradeAction?> _showQuickGradeDialog() async {
    return showDialog<_QuickGradeAction>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text('Save this assessment?'),
        content: Text('Save to reuse later and generate full reports.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _QuickGradeAction.discard),
            child: Text('No, Discard'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, _QuickGradeAction.save),
            child: Text('Yes, Save'),
          ),
        ],
      ),
    );
  }

  /// Show rename bottom sheet so teacher can give Quick Grade a proper title.
  Future<void> _showRenameSheet() async {
    if (_assessment == null) return;

    final controller = TextEditingController(text: _assessment!.title);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Name this assessment',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Give it a name so you can find it later.',
              style: TextStyle(color: AppTheme.lightText, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Assessment name',
                hintText: 'e.g. Math Unit 1 Test',
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text('Keep as is'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final newTitle = controller.text.trim();
                      if (newTitle.isNotEmpty) {
                        final updated = Assessment(
                          id: _assessment!.id,
                          title: newTitle,
                          subject: _assessment!.subject,
                          rubricType: _assessment!.rubricType,
                          questions: _assessment!.questions,
                          status: _assessment!.status,
                          isQuickGrade: false, // Promoted to real assessment
                          createdAt: _assessment!.createdAt,
                          weightedScaleId: _assessment!.weightedScaleId,
                        );
                        await context.read<AssessmentProvider>().addAssessment(
                          updated,
                        );
                        _assessment = updated;
                      }
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    },
                    child: Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    controller.dispose();

    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Assessment saved'),
          backgroundColor: AppTheme.primaryGreen,
        ),
      );
    }
  }

  /// Delete Quick Grade assessment and its scan results.
  Future<void> _discardQuickGrade() async {
    if (_assessment == null) return;

    // Delete scan results
    final grading = HybridGradingService();
    for (final result in _results) {
      await grading.deleteScanResult(result.id);
    }

    // Delete assessment
    await context.read<AssessmentProvider>().deleteAssessment(_assessment!.id);

    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Assessment discarded')));

    if (!context.mounted) return;
    Navigator.pop(context); // Back to dashboard
  }

  double get _average {
    if (_results.isEmpty) return 0;
    return _results.fold(0.0, (s, r) => s + r.percentage) / _results.length;
  }

  double get _highest {
    if (_results.isEmpty) return 0;
    return _results.map((r) => r.percentage).reduce((a, b) => a > b ? a : b);
  }

  double get _lowest {
    if (_results.isEmpty) return 0;
    return _results.map((r) => r.percentage).reduce((a, b) => a < b ? a : b);
  }

  double get _passRate {
    if (_results.isEmpty) return 0;
    final passed = _results.where((r) => r.percentage >= 50).length;
    return passed / _results.length * 100;
  }

  /// Read all scores aloud using TTS.
  Future<void> _readScoresAloud() async {
    if (_results.isEmpty) return;
    setState(() => _isSpeaking = true);

    try {
      await VoiceService().readAllScores(
        studentNames: _results.map((r) => r.studentName).toList(),
        scores: _results.map((r) => r.totalScore.toDouble()).toList(),
        maxScores: _results.map((r) => r.maxScore.toDouble()).toList(),
        percentages: _results.map((r) => r.percentage).toList(),
        grades: _results.map((r) => r.grade).toList(),
        onReadingIndex: (index) {
          // Could highlight the current student in the list
        },
      );
    } catch (e) {
      debugPrint('BatchScan: voice readout error: $e');
    }

    if (mounted) setState(() => _isSpeaking = false);
  }

  @override
  void dispose() {
    // Clean up enhanced/corrected images after grading completes.
    // Original captured images are managed by CameraScreen.
    if (_imagePaths.isNotEmpty) {
      for (final path in _imagePaths) {
        OcrService().cleanupEnhancedImages(path);
      }
    }
    super.dispose();
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: AppTheme.lightText),
          ),
        ],
      ),
    );
  }
}

class _BatchReviewMetric extends StatelessWidget {
  const _BatchReviewMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingStudentActions extends StatelessWidget {
  const _MissingStudentActions({
    required this.students,
    required this.onMarkAbsent,
    required this.onLeaveUngraded,
    required this.onManualEntry,
  });

  final List<Student> students;
  final ValueChanged<Student> onMarkAbsent;
  final ValueChanged<Student> onLeaveUngraded;
  final ValueChanged<Student> onManualEntry;

  @override
  Widget build(BuildContext context) {
    return _ReviewActionSection(
      icon: Icons.person_search_outlined,
      title: 'Missing students',
      message: 'Choose what happened. The app will not turn them into zero.',
      children: students.take(6).map((student) {
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.fullName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.event_busy, size: 18),
                        label: const Text('Mark absent'),
                        onPressed: () => onMarkAbsent(student),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.pending_actions, size: 18),
                        label: const Text('Leave ungraded'),
                        onPressed: () => onLeaveUngraded(student),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.edit_note, size: 18),
                        label: const Text('Enter manually'),
                        onPressed: () => onManualEntry(student),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _DuplicateActions extends StatelessWidget {
  const _DuplicateActions({
    required this.duplicates,
    required this.results,
    required this.onKeepBoth,
    required this.onKeepFirst,
    required this.onKeepSecond,
    required this.onAssign,
  });

  final List<AnswerDuplicate> duplicates;
  final List<ScanResult> results;
  final ValueChanged<AnswerDuplicate> onKeepBoth;
  final ValueChanged<AnswerDuplicate> onKeepFirst;
  final ValueChanged<AnswerDuplicate> onKeepSecond;
  final ValueChanged<AnswerDuplicate> onAssign;

  @override
  Widget build(BuildContext context) {
    return _ReviewActionSection(
      icon: Icons.copy_all_outlined,
      title: 'Possible duplicates',
      message: 'Resolve repeated papers before saving the batch.',
      children: duplicates.take(4).map((duplicate) {
        final first = duplicate.scanIndexA < results.length
            ? results[duplicate.scanIndexA]
            : null;
        final second = duplicate.scanIndexB < results.length
            ? results[duplicate.scanIndexB]
            : null;
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${first?.studentName ?? 'Paper ${duplicate.scanIndexA + 1}'} and '
                    '${second?.studentName ?? 'Paper ${duplicate.scanIndexB + 1}'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${duplicate.matchPercent.toStringAsFixed(0)}% answer match',
                    style: TextStyle(color: AppTheme.lightText, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.done_all, size: 18),
                        label: const Text('Keep both'),
                        onPressed: () => onKeepBoth(duplicate),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.looks_one, size: 18),
                        label: const Text('Keep first'),
                        onPressed: () => onKeepFirst(duplicate),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.looks_two, size: 18),
                        label: const Text('Keep second'),
                        onPressed: () => onKeepSecond(duplicate),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.person_add_alt, size: 18),
                        label: const Text('Assign'),
                        onPressed: () => onAssign(duplicate),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ReviewActionSection extends StatelessWidget {
  const _ReviewActionSection({
    required this.icon,
    required this.title,
    required this.message,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String message;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.warning.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: TextStyle(color: AppTheme.lightText, height: 1.3),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _MasterKeyStat extends StatelessWidget {
  const _MasterKeyStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.lightText,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MasterKeyAnswerRow extends StatelessWidget {
  const _MasterKeyAnswerRow({
    required this.questionNumber,
    required this.choices,
    required this.selected,
    required this.isMissing,
    required this.isWeak,
    required this.onSelected,
    this.confidence,
  });

  final int questionNumber;
  final List<String> choices;
  final String selected;
  final bool isMissing;
  final bool isWeak;
  final double? confidence;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final statusColor = isMissing
        ? AppTheme.primaryRed
        : isWeak
        ? AppTheme.warning
        : AppTheme.primaryGreen;
    final statusText = isMissing
        ? 'Missing'
        : isWeak
        ? 'Check'
        : 'OK';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(isMissing || isWeak ? 0.08 : 0.035),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: statusColor.withOpacity(isMissing || isWeak ? 0.45 : 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$questionNumber',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Question $questionNumber',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  confidence == null
                      ? statusText
                      : '$statusText ${(confidence! * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: choices.map((choice) {
              final isSelected = selected == choice;
              return ChoiceChip(
                label: Text(choice),
                selected: isSelected,
                onSelected: (_) => onSelected(choice),
                selectedColor: AppTheme.primaryGreen.withOpacity(0.18),
                labelStyle: TextStyle(
                  color: isSelected ? AppTheme.primaryGreen : AppTheme.darkText,
                  fontWeight: FontWeight.w800,
                ),
                side: BorderSide(
                  color: isSelected
                      ? AppTheme.primaryGreen
                      : Colors.grey.shade300,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
