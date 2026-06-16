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
import '../../services/settings_provider.dart';
import '../../services/paper_image_intake_service.dart';
import '../../widgets/student_not_found_dialog.dart';
import '../../widgets/mini_stat.dart';
import 'master_key_confirmation_sheet.dart';
import 'quick_grade_sheets.dart';
import 'student_assignment_sheet.dart';
import '../../widgets/batch_review_widgets.dart';
import 'batch_completion_review_sheet.dart';
import 'batch_processor.dart';

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
  String? _temporaryImageSource;

  String? _classId;
  bool _didInitArgs = false;

  late final BatchProcessor _processor;

  @override
  void initState() {
    super.initState();
    _processor = BatchProcessor(
      callbacks: BatchProcessorCallbacks(
        onProgress: (processed, total) {
          if (mounted) setState(() { _processedCount = processed; _totalCount = total; });
        },
        onResultsChanged: (results) {
          if (mounted) setState(() { _results..clear()..addAll(results); });
        },
        onDuplicatesChanged: (duplicates) {
          if (mounted) setState(() { _duplicates = duplicates; });
        },
        onProcessingChanged: (processing) {
          if (mounted) setState(() { _isProcessing = processing; });
        },
        onMasterKeyStateChanged: (ready, error) {
          if (mounted) setState(() { _masterKeyReady = ready; _masterKeyError = error; });
        },
        onStudentNotFound: _showStudentNotFoundDialog,
      ),
    );
  }

  bool get _isNoRosterMode =>
      _assessment?.isQuickGrade == true ||
      _assessment?.settings['examDayMode'] == 'noRoster' ||
      _assessment?.settings['studentMode'] == 'noRoster';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitArgs) return;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args != null) {
      _didInitArgs = true;
      // Handle both Map args (normal + draft resume) and Assessment args (direct)
      if (args is Map) {
        final assessment = args['assessment'] as Assessment?;
        final images = args['images'] as List<String>?;
        _classId = args['classId'] as String?;
        _masterOnly = args['masterOnly'] == true;
        final imageSource = args['imageSource'] as String?;
        if (imageSource == PaperImageSource.upload.name ||
            imageSource == PaperImageSource.camera.name) {
          _temporaryImageSource = imageSource;
        }

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
              setState(() {
                _isProcessing = false;
                _masterKeyReady = false;
                _masterKeyError = 'No master answer sheet image found.';
                _processedCount = _totalCount == 0 ? 0 : 1;
              });
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

    await _processor.processBatch(
      context: context,
      images: images,
      assessment: assessment,
      classId: _classId,
      isNoRosterMode: _isNoRosterMode,
      temporaryImageSource: _temporaryImageSource,
      existingResults: _results,
      startCount: _processedCount,
    );
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

    await _processor.processMasterKey(
      context: context,
      imagePath: imagePath,
      assessment: assessment,
    );

    if (mounted) {
      setState(() => _isProcessing = false);

      // After master key is confirmed, navigate to confirmation screen
      if (_masterKeyReady && mounted) {
        // Reload assessment to get updated answer key
        final updatedAssessment = context.read<AssessmentProvider>().getAssessmentById(assessment.id);
        if (updatedAssessment != null && mounted) {
          Navigator.pushReplacementNamed(
            context,
            AppRoutes.answerKeyConfirmation,
            arguments: updatedAssessment,
          );
        }
      }
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
                          child: MiniStat(
                            label: 'Avg',
                            value: _average.toStringAsFixed(1),
                            color: AppTheme.primaryGreen,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: MiniStat(
                            label: 'High',
                            value: _highest.toStringAsFixed(1),
                            color: AppTheme.info,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: MiniStat(
                            label: 'Low',
                            value: _lowest.toStringAsFixed(1),
                            color: AppTheme.primaryRed,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: MiniStat(
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
        const SnackBar(
          content: Text(
            'No class selected — pick a class first to assign students',
          ),
        ),
      );
      return;
    }

    final selected = await showStudentAssignmentSheet(
      context: context,
      classId: _classId!,
      results: _results,
      resultIndex: resultIndex,
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
      final action = await showQuickGradeDialog(context);
      if (!mounted) return;

      if (action == QuickGradeAction.save) {
        await showRenameSheet(
          context: context,
          assessment: _assessment!,
          onSaved: (updated) => _assessment = updated,
        );
      } else if (action == QuickGradeAction.discard) {
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
    return showBatchCompletionReview(
      context: context,
      results: _results,
      duplicates: _duplicates,
      classId: _classId,
      assessment: _assessment,
      noRoster: _isNoRosterMode,
      onResultsChanged: (updated) {
        setState(() {
          _results
            ..clear()
            ..addAll(updated);
          _processedCount = _results.length;
          _recomputeDuplicates();
        });
        _saveDraftSnapshot();
      },
      onAssignStudent: _assignStudent,
    );
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
        mode: context.read<SettingsProvider>().voiceFeedbackMode,
        needsReview: _results.map((r) => r.needsReview).toList(),
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



