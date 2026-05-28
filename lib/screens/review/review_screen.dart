import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/scan_result.dart';
import '../../models/assessment.dart';
import '../../models/student.dart';
import '../../services/scoring_service.dart';
import '../../services/voice_service.dart';
import '../../services/assessment_provider.dart';
import '../../services/hybrid_grading_service.dart';
import '../../services/excel_service.dart';
import '../../services/student_provider.dart';
import '../../services/correction_learner.dart';
import '../../models/audit_entry.dart';
import '../../services/audit_service.dart';
import '../../services/teacher_provider.dart';
import '../scanning/camera_screen.dart';
import 'audit_trail_sheet.dart' as audit;

// Alias for use in _ResultCard
typedef _AuditTrailSheet = audit.AuditTrailSheet;

// ──── Review List ────

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  List<ScanResult>? _results;
  _SortMode _sortMode = _SortMode.highestFirst;
  bool _hasUnsavedChanges = false;
  bool _isSaving = false;
  bool _isExporting = false;
  final VoiceService _voice = VoiceService();
  bool _isReading = false;
  int _readingIndex = -1; // which student is currently being read aloud

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Capture route args once so we can sort a local copy.
    _results ??=
        (ModalRoute.of(context)?.settings.arguments as List<ScanResult>? ?? [])
            .toList();
  }

  void _applySort() {
    setState(() {
      switch (_sortMode) {
        case _SortMode.lowestFirst:
          _results!.sort((a, b) => a.percentage.compareTo(b.percentage));
        case _SortMode.highestFirst:
          _results!.sort((a, b) => b.percentage.compareTo(a.percentage));
        case _SortMode.needsReviewFirst:
          _results!.sort((a, b) {
            // needs-review first, then lowest score
            if (a.needsReview != b.needsReview) {
              return a.needsReview ? -1 : 1;
            }
            return a.percentage.compareTo(b.percentage);
          });
      }
    });
  }

  /// Replace a single result after teacher overrides scores.
  void _updateResult(int index, ScanResult updated) {
    setState(() {
      _results![index] = updated;
      _hasUnsavedChanges = true;
    });
  }

  /// Reassign a scan result to a different student.
  void _reassignStudent(ScanResult result) async {
    // Get class students if available
    final studentProv = context.read<StudentProvider>();
    final allStudents = studentProv.students;

    final selected = await showModalBottomSheet<Student>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _StudentPickerSheet(
        students: allStudents,
        currentStudentId: result.studentId,
      ),
    );

    if (selected == null || !mounted) return;

    // Update the result
    final index = _results!.indexWhere((r) => r.id == result.id);
    if (index >= 0) {
      // We can't modify studentId/studentName via copyWith directly,
      // so we need to create a new result with the updated fields.
      setState(() {
        // Replace with updated student info
        _results![index] = ScanResult(
          id: result.id,
          assessmentId: result.assessmentId,
          studentId: selected.id,
          studentName: selected.fullName,
          imagePath: result.imagePath,
          enhancedImagePath: result.enhancedImagePath,
          answers: result.answers,
          totalScore: result.totalScore,
          maxScore: result.maxScore,
          percentage: result.percentage,
          grade: result.grade,
          status: result.status,
          scannedAt: result.scannedAt,
          voiceNotePath: result.voiceNotePath,
          teacherComment: result.teacherComment,
          confidence: result.confidence,
          imageHash: result.imageHash,
          metadata: result.metadata,
        );
        _hasUnsavedChanges = true;
      });

      // Record audit trail for reassignment
      final teacher = context.read<TeacherProvider>().activeTeacher;
      AuditService().recordReassignment(
        scanResultId: result.id,
        teacherId: teacher?.id ?? 'unknown',
        teacherName: teacher?.name ?? ('Unknown Teacher'),
        oldStudentId: result.studentId,
        oldStudentName: result.studentName,
        newStudentId: selected.id,
        newStudentName: selected.fullName,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Reassigned to ${selected.fullName}"),
          backgroundColor: AppTheme.primaryGreen,
        ),
      );
    }
  }

  /// Revert a scan result to the state recorded in an audit entry.
  void _revertToEntry(int index, ScanResult current, AuditEntry entry) async {
    final prev = entry.previousValues;

    // Build reverted result from previousValues
    ScanResult reverted = current;
    if (prev.containsKey('totalScore')) {
      reverted = reverted.copyWith(
        totalScore: (prev['totalScore'] as num).toDouble(),
        percentage:
            (prev['percentage'] as num?)?.toDouble() ?? reverted.percentage,
        grade: prev['grade'] as String? ?? reverted.grade,
      );
    }
    // Note: studentId/studentName are immutable on ScanResult —
    // reassignment revert would need to create a new ScanResult.
    // For now, only score/grade reverts are supported.

    // Record revert in audit trail
    final teacher = context.read<TeacherProvider>().activeTeacher;
    await AuditService().recordScoreOverride(
      scanResultId: current.id,
      teacherId: teacher?.id ?? 'unknown',
      teacherName: teacher?.name ?? 'Teacher',
      oldScore: current.totalScore,
      newScore: reverted.totalScore,
      oldPercentage: current.percentage,
      newPercentage: reverted.percentage,
      oldGrade: current.grade,
      newGrade: reverted.grade,
      reason: 'Reverted to previous state (${entry.description})',
    );

    // Update in-memory + mark for save
    _updateResult(index, reverted.copyWith(status: ScanStatus.reviewed));

    if (mounted) {
      Navigator.pop(context); // Close the audit sheet
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Grade reverted'),
          backgroundColor: AppTheme.warning,
        ),
      );
    }
  }

  /// Save every result in the batch so clean scans are not lost.
  Future<int> _saveAll({bool showMessage = true}) async {
    if (_results == null || _results!.isEmpty) return 0;
    setState(() => _isSaving = true);

    final grading = HybridGradingService();
    int saved = 0;
    int failed = 0;

    for (final result in _results!) {
      final ok = await grading.saveScanResult(result);
      if (ok) {
        saved++;
      } else {
        failed++;
      }
    }

    if (mounted) {
      setState(() {
        _isSaving = false;
        _hasUnsavedChanges = false;
      });
      if (showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failed == 0
                  ? ('$saved result(s) saved')
                  : ("$saved saved, $failed failed"),
            ),
          ),
        );
      }
    }

    return saved;
  }

  Future<void> _saveAndExportCsv() async {
    final results = _results;
    if (results == null || results.isEmpty || _isExporting) return;

    setState(() => _isExporting = true);
    final saved = await _saveAll(showMessage: false);
    if (!mounted) return;

    try {
      final path = await ImportService().exportResults(
        assessmentTitle: _assessmentTitle(results),
        results: results.map((result) {
          final row = result.toMap();
          row['paperLabel'] = result.studentName;
          row['reviewStatus'] = result.needsReview
              ? 'Needs review'
              : 'Reviewed';
          return row;
        }).toList(),
      );

      if (!mounted) return;
      setState(() => _isExporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$saved saved. CSV ready.'),
          backgroundColor: AppTheme.primaryGreen,
          action: SnackBarAction(
            label: 'Share',
            onPressed: () => Share.shareXFiles([XFile(path)]),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isExporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not export CSV'),
          backgroundColor: AppTheme.primaryRed,
        ),
      );
    }
  }

  String _assessmentTitle(List<ScanResult> results) {
    final assessment = context.read<AssessmentProvider>().getAssessmentById(
      results.first.assessmentId,
    );
    return assessment?.title ?? 'EthioGrade Results';
  }

  @override
  Widget build(BuildContext context) {
    final results = _results ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text('Review Results'),
        actions: [
          if (results.isNotEmpty)
            IconButton(
              icon: Icon(
                _isReading ? Icons.stop_circle : Icons.volume_up,
                color: _isReading ? AppTheme.primaryRed : null,
              ),
              onPressed: () => _readAllScores(),
              tooltip: _isReading ? 'Stop' : 'Read All Scores',
            ),
          if (_hasUnsavedChanges && !_isSaving)
            TextButton.icon(
              onPressed: () => _saveAll(),
              icon: const Icon(Icons.save, size: 18),
              label: Text('Save All'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryGreen,
              ),
            ),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () => _showSortOptions(context),
          ),
        ],
      ),
      body: results.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No results to review',
                    style: TextStyle(color: AppTheme.lightText, fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: results.length,
              itemBuilder: (context, index) {
                final result = results[index];
                return _ResultCard(
                  result: result,
                  isReading: index == _readingIndex,
                  onReassign: () => _reassignStudent(result),
                  onRevert: (entry) => _revertToEntry(index, result, entry),
                  onTap: () async {
                    final updated = await Navigator.pushNamed(
                      context,
                      AppRoutes.sideBySide,
                      arguments: result,
                    );
                    if (updated is ScanResult) {
                      _updateResult(index, updated);
                    }
                  },
                );
              },
            ),
      bottomNavigationBar: results.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isSaving || _isExporting
                            ? null
                            : () => _saveAll(),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _isSaving || _isExporting
                            ? null
                            : _saveAndExportCsv,
                        icon: _isExporting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.ios_share_outlined),
                        label: Text(
                          _isExporting ? 'Exporting...' : 'Save and export',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// Read all student scores aloud via TTS.
  Future<void> _readAllScores() async {
    final results = _results;
    if (results == null || results.isEmpty) return;

    if (_isReading) {
      await _voice.stopSpeaking();
      if (mounted) setState(() => _isReading = false);
      return;
    }

    setState(() => _isReading = true);

    await _voice.readAllScores(
      studentNames: results.map((r) => r.studentName).toList(),
      scores: results.map((r) => r.totalScore.toDouble()).toList(),
      maxScores: results.map((r) => r.maxScore.toDouble()).toList(),
      percentages: results.map((r) => r.percentage).toList(),
      grades: results.map((r) => r.grade).toList(),
      onReadingIndex: (i) {
        if (mounted) setState(() => _readingIndex = i);
      },
    );

    if (mounted)
      setState(() {
        _isReading = false;
        _readingIndex = -1;
      });
  }

  @override
  void dispose() {
    _voice.stopSpeaking();
    super.dispose();
  }

  void _showSortOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.arrow_downward),
              title: Text('Lowest to Highest'),
              trailing: _sortMode == _SortMode.lowestFirst
                  ? const Icon(Icons.check, color: AppTheme.primaryGreen)
                  : null,
              onTap: () {
                _sortMode = _SortMode.lowestFirst;
                _applySort();
                Navigator.pop(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: Text('Highest to Lowest'),
              trailing: _sortMode == _SortMode.highestFirst
                  ? const Icon(Icons.check, color: AppTheme.primaryGreen)
                  : null,
              onTap: () {
                _sortMode = _SortMode.highestFirst;
                _applySort();
                Navigator.pop(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.warning),
              title: Text('Needs Review First'),
              trailing: _sortMode == _SortMode.needsReviewFirst
                  ? const Icon(Icons.check, color: AppTheme.primaryGreen)
                  : null,
              onTap: () {
                _sortMode = _SortMode.needsReviewFirst;
                _applySort();
                Navigator.pop(c);
              },
            ),
          ],
        ),
      ),
    );
  }
}

enum _SortMode { lowestFirst, highestFirst, needsReviewFirst }

// ──── Result Card ────

class _ResultCard extends StatelessWidget {
  final ScanResult result;
  final bool isReading;
  final VoidCallback onTap;
  final VoidCallback onReassign;
  final void Function(AuditEntry entry) onRevert;

  const _ResultCard({
    required this.result,
    this.isReading = false,
    required this.onTap,
    required this.onReassign,
    required this.onRevert,
  });

  @override
  Widget build(BuildContext context) {
    final passMark = 50;
    final passed = result.percentage >= passMark;
    final needsReview = result.needsReview;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: isReading
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppTheme.info, width: 2),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Student avatar
                  CircleAvatar(
                    backgroundColor: passed
                        ? AppTheme.primaryGreen.withOpacity(0.1)
                        : AppTheme.primaryRed.withOpacity(0.1),
                    child: Text(
                      result.studentName.isNotEmpty
                          ? result.studentName[0]
                          : '?',
                      style: TextStyle(
                        color: passed
                            ? AppTheme.primaryGreen
                            : AppTheme.primaryRed,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.studentName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        if (isReading)
                          Row(
                            children: [
                              Icon(
                                Icons.volume_up,
                                size: 14,
                                color: AppTheme.info,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Reading...',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.info,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 4),
                        ActionChip(
                          avatar: Icon(
                            Icons.swap_horiz,
                            size: 16,
                            color: AppTheme.info,
                          ),
                          label: Text(
                            'Reassign',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.info,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          backgroundColor: AppTheme.info.withOpacity(0.08),
                          side: BorderSide(
                            color: AppTheme.info.withOpacity(0.3),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onPressed: onReassign,
                        ),
                        if (needsReview)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.warning.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              () {
                                final uncertainCount = result.answers
                                    .where(
                                      (a) =>
                                          a.confidence > 0 &&
                                          a.confidence < 0.6,
                                    )
                                    .length;
                                final base = 'Needs Review';
                                if (uncertainCount > 0) {
                                  return '$base · $uncertainCount ${'uncertain'}';
                                }
                                return base;
                              }(),
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.warning,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Score badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: passed
                          ? AppTheme.primaryGreen.withOpacity(0.1)
                          : AppTheme.primaryRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${result.percentage.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: passed
                                ? AppTheme.primaryGreen
                                : AppTheme.primaryRed,
                          ),
                        ),
                        Text(
                          result.grade,
                          style: TextStyle(
                            fontSize: 12,
                            color: passed
                                ? AppTheme.primaryGreen
                                : AppTheme.primaryRed,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Answer summary
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: result.answers.map((a) {
                  final isLowConfidence =
                      a.confidence > 0 && a.confidence < 0.6;
                  final bgColor = a.isCorrect
                      ? AppTheme.primaryGreen.withOpacity(0.15)
                      : a.detectedAnswer == '[MISSING]'
                      ? Colors.grey.shade200
                      : isLowConfidence
                      ? AppTheme.warning.withOpacity(0.2)
                      : AppTheme.primaryRed.withOpacity(0.15);
                  final borderColor = a.isCorrect
                      ? AppTheme.primaryGreen
                      : a.detectedAnswer == '[MISSING]'
                      ? Colors.grey
                      : isLowConfidence
                      ? AppTheme.warning
                      : AppTheme.primaryRed;
                  return Tooltip(
                    message: isLowConfidence
                        ? ('OCR unsure — please check')
                        : '',
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: borderColor,
                          width: isLowConfidence ? 2 : 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${a.questionNumber}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: a.isCorrect
                                ? AppTheme.primaryGreen
                                : a.detectedAnswer == '[MISSING]'
                                ? Colors.grey
                                : AppTheme.primaryRed,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${result.totalScore.toInt()}/${result.maxScore.toInt()}',
                    style: TextStyle(color: AppTheme.lightText, fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    '${'Confidence'}: ${(result.confidence * 100).toStringAsFixed(0)}%',
                    style: TextStyle(color: AppTheme.lightText, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  // View audit history button
                  InkWell(
                    onTap: () => _AuditTrailSheet.show(
                      context,
                      result,
                      onRevert: onRevert,
                    ),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history, size: 14, color: AppTheme.info),
                          const SizedBox(width: 4),
                          Text(
                            'History',
                            style: TextStyle(
                              color: AppTheme.info,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──── Side-by-Side Review ────

class SideBySideReview extends StatefulWidget {
  const SideBySideReview({super.key});

  @override
  State<SideBySideReview> createState() => _SideBySideReviewState();
}

class _SideBySideReviewState extends State<SideBySideReview> {
  final VoiceService _voice = VoiceService();
  late TextEditingController _commentController;

  // Mutable copy of the result — override buttons modify this.
  late ScanResult _result;
  bool _initialized = false;
  bool _isPlayingVoice = false;
  bool _isSpeakingTts = false; // TTS reading score aloud

  // Fix-wrong mode: show only incorrect/MISSING answers
  bool _fixMode = false;
  // Current index in fix-wrong step-through
  int _fixIndex = 0;
  // Cached wrong answers — rebuilt in setState when results change
  List<AnswerMatch> _cachedWrongAnswers = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _result =
          ModalRoute.of(context)?.settings.arguments as ScanResult? ??
          ScanResult(
            assessmentId: '',
            studentId: '',
            studentName: 'Unknown',
            imagePath: '',
          );
      _commentController = TextEditingController(
        text: _result.teacherComment ?? '',
      );
      _initialized = true;
    }
  }

  /// Recalculate totals after an answer override, then rebuild.
  void _recalculateAndRefresh() {
    final scoring = const ScoringService();

    // Look up the actual assessment for correct rubric type
    final assessments = context.read<AssessmentProvider>().assessments;
    final assessment = assessments.cast<Assessment?>().firstWhere(
      (a) => a?.id == _result.assessmentId,
      orElse: () => null,
    );
    final rubricType = assessment?.rubricType ?? 'moe_national';

    final newTotal = scoring.calculateTotalScore(_result.answers);
    final newPct = scoring.calculatePercentage(
      totalScore: newTotal,
      maxScore: _result.maxScore,
    );
    final newGrade = scoring.calculateGrade(newPct, rubricType);
    final newConfidence = scoring.calculateConfidence(_result.answers);

    setState(() {
      _result = _result.copyWith(
        answers: _result.answers,
        totalScore: newTotal,
        percentage: newPct,
        grade: newGrade,
        status: ScanStatus.reviewed,
        confidence: newConfidence,
      );
      // Keep wrong answers cache in sync if in fix mode
      if (_fixMode) _rebuildWrongAnswers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return Scaffold(
      appBar: AppBar(
        title: Text(result.studentName),
        actions: [
          IconButton(
            icon: Icon(
              _isSpeakingTts ? Icons.stop : Icons.volume_up,
              color: _isSpeakingTts ? AppTheme.primaryRed : null,
            ),
            onPressed: () async {
              if (_isSpeakingTts) {
                await _voice.stopSpeaking();
                if (mounted) setState(() => _isSpeakingTts = false);
              } else {
                setState(() => _isSpeakingTts = true);
                await _voice.readScore(
                  studentName: result.studentName,
                  score: result.totalScore.toDouble(),
                  maxScore: result.maxScore.toDouble(),
                  grade: result.grade,
                );
                if (mounted) setState(() => _isSpeakingTts = false);
              }
            },
            tooltip: _isSpeakingTts ? 'Stop' : 'Read Score',
          ),
          IconButton(
            icon: const Icon(Icons.mic),
            onPressed: () => _recordVoiceNote(),
            tooltip: 'Voice Note',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Score summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryGreen.withOpacity(0.1),
                    AppTheme.primaryGreen.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ScoreItem(
                    label: 'Score',
                    value:
                        '${result.totalScore.toInt()}/${result.maxScore.toInt()}',
                  ),
                  _ScoreItem(
                    label: '%',
                    value: '${result.percentage.toStringAsFixed(1)}%',
                  ),
                  _ScoreItem(label: 'Grade', value: result.grade),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Image preview
            if (result.imagePath.isNotEmpty)
              Container(
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(result.imagePath),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Answer table header with fix mode toggle
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Question-by-Question',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Fix Wrong toggle
                if (_wrongAnswers.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _fixMode = !_fixMode;
                        _fixIndex = 0;
                        if (_fixMode) _rebuildWrongAnswers();
                      });
                    },
                    icon: Icon(
                      _fixMode ? Icons.list : Icons.filter_list,
                      size: 18,
                    ),
                    label: Text(
                      _fixMode
                          ? ('Show All')
                          : '${'Fix Wrong'} (${_wrongAnswers.length})',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Step-through fix mode: show one wrong answer at a time
            if (_fixMode && _wrongAnswers.isNotEmpty)
              _buildFixModeStep()
            else
              // Normal mode: show all answers
              ...result.answers.map(
                (answer) => _AnswerTile(
                  answer: answer,
                  onOverride: () => _overrideScore(answer),
                ),
              ),

            const SizedBox(height: 16),

            // Comment section
            Text(
              'Comment',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Write feedback for this student...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.mic),
                  onPressed: () => _recordVoiceNote(),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Voice note indicator with playback
            if (result.voiceNotePath != null)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _toggleVoicePlayback(),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isPlayingVoice
                        ? AppTheme.primaryGreen.withOpacity(0.1)
                        : AppTheme.info.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isPlayingVoice ? Icons.stop_circle : Icons.play_circle,
                        color: _isPlayingVoice
                            ? AppTheme.primaryGreen
                            : AppTheme.info,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isPlayingVoice
                              ? ('Playing...')
                              : ('Tap to play voice note'),
                          style: TextStyle(
                            color: _isPlayingVoice
                                ? AppTheme.primaryGreen
                                : AppTheme.info,
                          ),
                        ),
                      ),
                      if (_isPlayingVoice)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      // Find the assessment for re-scan context
                      final assessments = context
                          .read<AssessmentProvider>()
                          .assessments;
                      final assessment = assessments
                          .cast<Assessment?>()
                          .firstWhere(
                            (a) => a?.id == _result.assessmentId,
                            orElse: () => null,
                          );
                      if (assessment == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Assessment not found')),
                        );
                        return;
                      }

                      // Navigate to camera in re-scan mode, await new result
                      final newResult = await Navigator.pushNamed(
                        context,
                        AppRoutes.camera,
                        arguments: ReScanArguments(
                          existingResult: _result,
                          assessment: assessment,
                        ),
                      );

                      if (newResult is ScanResult && mounted) {
                        setState(() {
                          _result = newResult;
                          _commentController.text =
                              newResult.teacherComment ?? '';
                        });
                      }
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: Text('Re-Scan'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      // Persist comment into the result
                      final finalResult = _result.copyWith(
                        teacherComment: _commentController.text,
                        status: ScanStatus.reviewed,
                      );

                      // Auto-save to Hive — teacher overrides must persist
                      final saved = await HybridGradingService().saveScanResult(
                        finalResult,
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(saved ? ('Saved') : ('Save failed')),
                          duration: const Duration(seconds: 1),
                        ),
                      );

                      if (!context.mounted) return;
                      Navigator.pop(context, finalResult);
                    },
                    icon: const Icon(Icons.check),
                    label: Text('Confirm'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Fix-wrong helpers ─────────────────────────────────────────────

  /// Rebuild cached wrong answers from current result.
  /// Called in setState context, never in build.
  void _rebuildWrongAnswers() {
    _cachedWrongAnswers =
        _result.answers
            .where((a) => !a.isCorrect || a.detectedAnswer == '[MISSING]')
            .toList()
          ..sort((a, b) {
            // MISSING first, then by question number
            final aMissing = a.detectedAnswer == '[MISSING]' ? 0 : 1;
            final bMissing = b.detectedAnswer == '[MISSING]' ? 0 : 1;
            if (aMissing != bMissing) return aMissing - bMissing;
            return a.questionNumber.compareTo(b.questionNumber);
          });
  }

  /// Current wrong answers (cached, rebuilt via [_rebuildWrongAnswers]).
  List<AnswerMatch> get _wrongAnswers => _cachedWrongAnswers;

  /// Build the step-through fix mode UI: one wrong answer at a time.
  Widget _buildFixModeStep() {
    final wrong = _wrongAnswers;
    if (wrong.isEmpty) return const SizedBox.shrink();

    // Clamp index — safe to do here since it's just reading
    final safeIndex = _fixIndex.clamp(0, wrong.length - 1);
    final current = wrong[safeIndex];
    final isMissing = current.detectedAnswer == '[MISSING]';

    return Column(
      key: ValueKey('fix_step_$safeIndex'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Progress indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.warning.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber, size: 16, color: AppTheme.warning),
              const SizedBox(width: 8),
              Text(
                '${'Wrong'} ${safeIndex + 1} / ${wrong.length}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.warning,
                ),
              ),
              const Spacer(),
              // Prev button
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: safeIndex > 0
                    ? () => setState(() => _fixIndex = safeIndex - 1)
                    : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              // Next button
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: safeIndex < wrong.length - 1
                    ? () => setState(() => _fixIndex = safeIndex + 1)
                    : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // The current wrong answer — prominent card
        _buildFixCard(current),
      ],
    );
  }

  /// Build a prominent fix card for a single wrong/MISSING answer.
  Widget _buildFixCard(AnswerMatch answer) {
    final isMissing = answer.detectedAnswer == '[MISSING]';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isMissing ? AppTheme.warning : AppTheme.primaryRed,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Question header
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      (isMissing ? AppTheme.warning : AppTheme.primaryRed)
                          .withOpacity(0.1),
                  child: Text(
                    '${answer.questionNumber}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isMissing ? AppTheme.warning : AppTheme.primaryRed,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${'Question'} ${answer.questionNumber}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${'Correct'}: ${answer.correctAnswer}',
                        style: TextStyle(
                          color: AppTheme.primaryGreen,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // MISSING: prominent "What did the student write?" button
            if (isMissing) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.visibility_off_outlined,
                      color: AppTheme.warning,
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'OCR could not read this answer',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.warning,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'What did the student write?',
                      style: TextStyle(color: AppTheme.lightText, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    // Quick entry buttons: A/B/C/D/E
                    _buildQuickEntry(answer),
                  ],
                ),
              ),
            ] else
              // Wrong answer: show what was detected, let teacher fix
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Detected answer display
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryRed.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search,
                          size: 16,
                          color: AppTheme.primaryRed,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${'Detected'}: ',
                          style: TextStyle(
                            color: AppTheme.lightText,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          answer.detectedAnswer,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryRed,
                            fontSize: 16,
                          ),
                        ),
                        if (answer.confidence > 0) ...[
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: answer.confidence < 0.6
                                  ? AppTheme.warning.withOpacity(0.15)
                                  : AppTheme.primaryRed.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${(answer.confidence * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 11,
                                color: answer.confidence < 0.6
                                    ? AppTheme.warning
                                    : AppTheme.primaryRed,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Show raw OCR text if available
                  if (answer.ocrRawText != null &&
                      answer.ocrRawText!.isNotEmpty &&
                      answer.ocrRawText != '[MISSING]')
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${'OCR read'}: "${answer.ocrRawText}"',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.lightText,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  // Fix buttons
                  _buildQuickEntry(answer),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Quick-entry buttons for fixing an answer: A/B/C/D/E or True/False.
  Widget _buildQuickEntry(AnswerMatch answer) {
    // Detect if this is a True/False question by the correct answer
    final isTF =
        answer.correctAnswer.toUpperCase() == 'TRUE' ||
        answer.correctAnswer.toUpperCase() == 'FALSE';

    if (isTF) {
      return Row(
        children: [
          Expanded(
            child: _QuickEntryButton(
              label: 'True',
              icon: Icons.check_circle_outline,
              color: AppTheme.primaryGreen,
              onTap: () {
                _applyAnswerChange(
                  answer.questionNumber,
                  newAnswer: 'True',
                  correctAnswer: answer.correctAnswer,
                );
                _advanceFixIndex();
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _QuickEntryButton(
              label: 'False',
              icon: Icons.cancel_outlined,
              color: AppTheme.primaryRed,
              onTap: () {
                _applyAnswerChange(
                  answer.questionNumber,
                  newAnswer: 'False',
                  correctAnswer: answer.correctAnswer,
                );
                _advanceFixIndex();
              },
            ),
          ),
        ],
      );
    }

    // MCQ: A/B/C/D/E buttons
    const options = ['A', 'B', 'C', 'D', 'E'];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final isCorrectAnswer =
            opt.toUpperCase() == answer.correctAnswer.toUpperCase();
        return _QuickEntryButton(
          label: opt,
          icon: isCorrectAnswer ? Icons.check : null,
          color: isCorrectAnswer ? AppTheme.primaryGreen : Colors.grey.shade600,
          onTap: () {
            _applyAnswerChange(
              answer.questionNumber,
              newAnswer: opt,
              correctAnswer: answer.correctAnswer,
            );
            _advanceFixIndex();
          },
        );
      }).toList(),
    );
  }

  /// Auto-advance to the next wrong answer after fixing one.
  void _advanceFixIndex() {
    if (!_fixMode) return;
    // Rebuild the cached list (the fixed answer may no longer be wrong)
    setState(() {
      _rebuildWrongAnswers();
      if (_cachedWrongAnswers.isEmpty) {
        // All fixed! Exit fix mode
        _fixMode = false;
      } else if (_fixIndex >= _cachedWrongAnswers.length) {
        _fixIndex = _cachedWrongAnswers.length - 1;
      }
      // else: stay on same index, which now shows the next wrong answer
    });

    if (!_fixMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ All answers corrected!'),
          backgroundColor: AppTheme.primaryGreen,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ── Score override ──────────────────────────────────────────────

  void _overrideScore(AnswerMatch answer) {
    // Look up question type from assessment for appropriate edit UI
    final assessments = context.read<AssessmentProvider>().assessments;
    final assessment = assessments.cast<Assessment?>().firstWhere(
      (a) => a?.id == _result.assessmentId,
      orElse: () => null,
    );
    final question = assessment?.questions.cast<Question?>().firstWhere(
      (q) => q?.number == answer.questionNumber,
      orElse: () => null,
    );
    final questionType = question?.type ?? QuestionType.mcq;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${'Question'} ${answer.questionNumber}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '${'Detected'}: ${answer.detectedAnswer}',
                style: TextStyle(color: AppTheme.lightText),
              ),

              // Correction suggestion from learned patterns
              Builder(
                builder: (_) {
                  final suggestion = CorrectionLearner().getSuggestion(
                    questionNumber: answer.questionNumber,
                    detectedAnswer: answer.detectedAnswer,
                  );
                  if (suggestion == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryYellow.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.primaryYellow.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.lightbulb_outline,
                            size: 16,
                            color: AppTheme.primaryYellow,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Previously corrected ${answer.detectedAnswer}→$suggestion",
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              _applyAnswerChange(
                                answer.questionNumber,
                                newAnswer: suggestion,
                                correctAnswer: answer.correctAnswer,
                              );
                              Navigator.pop(c);
                            },
                            child: Text(
                              'Apply',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryGreen,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Change answer section
              Text(
                'Change Answer',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),

              if (questionType == QuestionType.mcq)
                _McqAnswerPicker(
                  currentAnswer: answer.detectedAnswer,
                  correctAnswer: answer.correctAnswer,
                  onSelected: (newAnswer) {
                    _applyAnswerChange(
                      answer.questionNumber,
                      newAnswer: newAnswer,
                      correctAnswer: answer.correctAnswer,
                    );
                    Navigator.pop(c);
                  },
                )
              else if (questionType == QuestionType.trueFalse)
                _TfAnswerPicker(
                  currentAnswer: answer.detectedAnswer,
                  onSelected: (newAnswer) {
                    _applyAnswerChange(
                      answer.questionNumber,
                      newAnswer: newAnswer,
                      correctAnswer: answer.correctAnswer,
                    );
                    Navigator.pop(c);
                  },
                )
              else
                _ShortAnswerEditor(
                  currentAnswer: answer.detectedAnswer,
                  onSubmitted: (newAnswer) {
                    _applyAnswerChange(
                      answer.questionNumber,
                      newAnswer: newAnswer,
                      correctAnswer: answer.correctAnswer,
                    );
                    Navigator.pop(c);
                  },
                ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // Quick correct/wrong toggle
              Text(
                'Or Quick Toggle',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _applyOverride(
                          answer.questionNumber,
                          markCorrect: true,
                        );
                        Navigator.pop(c);
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: Text('Correct'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _applyOverride(
                          answer.questionNumber,
                          markCorrect: false,
                        );
                        Navigator.pop(c);
                      },
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryRed,
                      ),
                      label: Text('Wrong'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Change the actual detected answer for a question, then recalculate.
  void _applyAnswerChange(
    int questionNumber, {
    required String newAnswer,
    required String correctAnswer,
  }) {
    // Find the original detected answer before override
    final original = _result.answers.firstWhere(
      (a) => a.questionNumber == questionNumber,
      orElse: () => _result.answers.first,
    );

    final updatedAnswers = _result.answers.map((a) {
      if (a.questionNumber != questionNumber) return a;
      final isCorrect = newAnswer.toUpperCase() == correctAnswer.toUpperCase();
      return AnswerMatch(
        questionNumber: a.questionNumber,
        detectedAnswer: newAnswer,
        correctAnswer: a.correctAnswer,
        isCorrect: isCorrect,
        score: isCorrect ? a.maxScore : 0,
        maxScore: a.maxScore,
        confidence: 1.0, // teacher corrected → max confidence
        ocrRawText: '(manual: $newAnswer)',
        boundingBox: a.boundingBox,
      );
    }).toList();

    setState(() {
      _result = _result.copyWith(answers: updatedAnswers);
    });
    _recalculateAndRefresh();

    // Learn from this correction for future suggestions
    CorrectionLearner().recordCorrection(
      questionNumber: questionNumber,
      originalAnswer: original.detectedAnswer,
      correctedAnswer: newAnswer,
    );

    // Record audit trail
    final teacher = context.read<TeacherProvider>().activeTeacher;
    final corrected = _result.answers.firstWhere(
      (a) => a.questionNumber == questionNumber,
    );
    final isCorrect = corrected.isCorrect;
    AuditService().recordScoreOverride(
      scanResultId: _result.id,
      teacherId: teacher?.id ?? 'unknown',
      teacherName: teacher?.name ?? ('Unknown Teacher'),
      oldScore: original.score,
      newScore: isCorrect ? corrected.maxScore : 0,
      oldPercentage: _result.percentage,
      newPercentage: _result.percentage, // updated by _recalculateAndRefresh
      oldGrade: _result.grade,
      newGrade: _result.grade,
      reason: 'Q$questionNumber: ${original.detectedAnswer} → $newAnswer',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Q$questionNumber → $newAnswer'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// Flip isCorrect for [questionNumber], recalculate totals, rebuild.
  void _applyOverride(int questionNumber, {required bool markCorrect}) {
    final updatedAnswers = _result.answers.map((a) {
      if (a.questionNumber != questionNumber) return a;
      return AnswerMatch(
        questionNumber: a.questionNumber,
        detectedAnswer: a.detectedAnswer,
        correctAnswer: a.correctAnswer,
        isCorrect: markCorrect,
        score: markCorrect ? a.maxScore : 0,
        maxScore: a.maxScore,
        confidence: 1.0, // teacher verified → max confidence
        ocrRawText: a.ocrRawText,
        boundingBox: a.boundingBox,
      );
    }).toList();

    // Replace answers, then recalc totals.
    setState(() {
      _result = _result.copyWith(answers: updatedAnswers);
    });
    _recalculateAndRefresh();

    // Record audit trail
    final teacher = context.read<TeacherProvider>().activeTeacher;
    AuditService().recordScoreOverride(
      scanResultId: _result.id,
      teacherId: teacher?.id ?? 'unknown',
      teacherName: teacher?.name ?? 'Unknown Teacher',
      oldScore: markCorrect
          ? 0
          : _result.answers
                .firstWhere((a) => a.questionNumber == questionNumber)
                .maxScore,
      newScore: markCorrect
          ? _result.answers
                .firstWhere((a) => a.questionNumber == questionNumber)
                .maxScore
          : 0,
      oldPercentage: _result.percentage,
      newPercentage: _result.percentage,
      oldGrade: _result.grade,
      newGrade: _result.grade,
      reason:
          'Q$questionNumber: ${markCorrect ? "marked correct" : "marked incorrect"}',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          markCorrect
              ? 'Q$questionNumber → Correct'
              : 'Q$questionNumber → Wrong',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ── Voice note ──────────────────────────────────────────────────

  void _recordVoiceNote() async {
    if (_voice.isRecording) {
      final path = await _voice.stopRecording();
      if (path != null && mounted) {
        setState(() {
          _result = _result.copyWith(voiceNotePath: path);
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Voice note saved')));
      }
    } else {
      await _voice.startRecording();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Recording...')));
      }
    }
  }

  /// Toggle voice note playback (play / stop).
  Future<void> _toggleVoicePlayback() async {
    final path = _result.voiceNotePath;
    if (path == null) return;

    if (_isPlayingVoice) {
      await _voice.stopPlayback();
      if (mounted) {
        setState(() => _isPlayingVoice = false);
      }
    } else {
      try {
        if (!VoiceService.fileExists(path)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Voice note file not found')),
            );
          }
          return;
        }
        setState(() => _isPlayingVoice = true);
        await _voice.playRecording(path);
        // Playback finished naturally
        if (mounted) {
          setState(() => _isPlayingVoice = false);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isPlayingVoice = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not play voice note')));
        }
      }
    }
  }

  @override
  void dispose() {
    _voice.stopSpeaking();
    _voice.stopPlayback();
    _commentController.dispose();
    super.dispose();
  }
}

// ──── Answer picker widgets ────

/// MCQ answer selector: A, B, C, D, E as tappable chips.
class _McqAnswerPicker extends StatelessWidget {
  final String currentAnswer;
  final String correctAnswer;
  final ValueChanged<String> onSelected;

  const _McqAnswerPicker({
    required this.currentAnswer,
    required this.correctAnswer,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    const options = ['A', 'B', 'C', 'D', 'E'];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final isCurrent = opt.toUpperCase() == currentAnswer.toUpperCase();
        final isCorrect = opt.toUpperCase() == correctAnswer.toUpperCase();
        return ChoiceChip(
          label: Text(
            opt,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isCurrent ? Colors.white : null,
            ),
          ),
          selected: isCurrent,
          selectedColor: AppTheme.primaryGreen,
          avatar: isCorrect
              ? const Icon(Icons.check, size: 16, color: AppTheme.primaryGreen)
              : null,
          onSelected: (_) => onSelected(opt),
        );
      }).toList(),
    );
  }
}

/// True/False answer selector: two large tappable buttons.
class _TfAnswerPicker extends StatelessWidget {
  final String currentAnswer;
  final ValueChanged<String> onSelected;

  const _TfAnswerPicker({
    required this.currentAnswer,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isTrue = currentAnswer.toUpperCase() == 'TRUE';
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => onSelected('True'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: isTrue
                    ? AppTheme.primaryGreen.withOpacity(0.15)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isTrue ? AppTheme.primaryGreen : Colors.grey.shade300,
                  width: isTrue ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    isTrue ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: isTrue ? AppTheme.primaryGreen : Colors.grey,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'True',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isTrue
                          ? AppTheme.primaryGreen
                          : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () => onSelected('False'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: !isTrue
                    ? AppTheme.primaryRed.withOpacity(0.15)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: !isTrue ? AppTheme.primaryRed : Colors.grey.shade300,
                  width: !isTrue ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    !isTrue ? Icons.cancel : Icons.radio_button_unchecked,
                    color: !isTrue ? AppTheme.primaryRed : Colors.grey,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'False',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: !isTrue
                          ? AppTheme.primaryRed
                          : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Short answer text editor with submit button.
class _ShortAnswerEditor extends StatefulWidget {
  final String currentAnswer;
  final ValueChanged<String> onSubmitted;

  const _ShortAnswerEditor({
    required this.currentAnswer,
    required this.onSubmitted,
  });

  @override
  State<_ShortAnswerEditor> createState() => _ShortAnswerEditorState();
}

class _ShortAnswerEditorState extends State<_ShortAnswerEditor> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentAnswer);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Type answer...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
            onSubmitted: widget.onSubmitted,
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: () => widget.onSubmitted(_controller.text.trim()),
          icon: const Icon(Icons.check, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.primaryGreen,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

// ──── Shared widgets ────

/// Large tappable button for quick answer entry in fix mode.
class _QuickEntryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickEntryButton({
    required this.label,
    this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreItem extends StatelessWidget {
  final String label;
  final String value;
  const _ScoreItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: AppTheme.lightText)),
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _AnswerTile extends StatelessWidget {
  final AnswerMatch answer;
  final VoidCallback onOverride;

  const _AnswerTile({required this.answer, required this.onOverride});

  @override
  Widget build(BuildContext context) {
    final isMissing = answer.detectedAnswer == '[MISSING]';
    final isLowConfidence =
        !isMissing && answer.confidence > 0 && answer.confidence < 0.6;

    // MISSING answer: prominent recovery card
    if (isMissing) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: AppTheme.warning.withOpacity(0.5),
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: onOverride,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.warning.withOpacity(0.1),
                  child: Text(
                    '${answer.questionNumber}',
                    style: TextStyle(
                      color: AppTheme.warning,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Q${answer.questionNumber} — No answer detected",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.warning,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap to enter what the student wrote',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.lightText,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, size: 14, color: AppTheme.warning),
                      const SizedBox(width: 4),
                      Text(
                        'Enter',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.warning,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Normal answer tile (correct or wrong)
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: answer.isCorrect
              ? AppTheme.primaryGreen.withOpacity(0.1)
              : AppTheme.primaryRed.withOpacity(0.1),
          child: Text(
            '${answer.questionNumber}',
            style: TextStyle(
              color: answer.isCorrect
                  ? AppTheme.primaryGreen
                  : AppTheme.primaryRed,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          '${'Detected'}: ${answer.detectedAnswer}',
          style: TextStyle(
            color: answer.isCorrect ? AppTheme.darkText : AppTheme.primaryRed,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${'Correct'}: ${answer.correctAnswer}'),
            // Show raw OCR text when available
            if (answer.ocrRawText != null &&
                answer.ocrRawText!.isNotEmpty &&
                answer.ocrRawText != '[MISSING]')
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${'OCR read'}: "${answer.ocrRawText}"',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.lightText,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            // Low confidence warning
            if (isLowConfidence)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber,
                      size: 12,
                      color: AppTheme.warning,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${'Low confidence'} (${(answer.confidence * 100).toStringAsFixed(0)}%)',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.warning,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${answer.score.toInt()}/${answer.maxScore.toInt()}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: onOverride,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for picking a student from the class list.
class _StudentPickerSheet extends StatefulWidget {
  final List<Student> students;
  final String currentStudentId;
  const _StudentPickerSheet({
    required this.students,
    required this.currentStudentId,
  });

  @override
  State<_StudentPickerSheet> createState() => _StudentPickerSheetState();
}

class _StudentPickerSheetState extends State<_StudentPickerSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered =
        _search.isEmpty
              ? widget.students
              : widget.students.where((s) {
                  final q = _search.toLowerCase();
                  return s.fullName.toLowerCase().contains(q) ||
                      s.studentId.toLowerCase().contains(q);
                }).toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName));

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (_, controller) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
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
            const SizedBox(height: 12),
            Text(
              'Select Student',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No students found',
                        style: TextStyle(color: AppTheme.lightText),
                      ),
                    )
                  : ListView.builder(
                      controller: controller,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final s = filtered[i];
                        final isCurrent = s.id == widget.currentStudentId;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isCurrent
                                ? AppTheme.primaryGreen.withOpacity(0.15)
                                : Colors.grey.shade100,
                            child: Text(
                              s.studentId.isNotEmpty ? s.studentId : '${i + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isCurrent
                                    ? AppTheme.primaryGreen
                                    : AppTheme.lightText,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(s.fullName),
                          subtitle: s.gender.isNotEmpty
                              ? Text(
                                  s.gender == 'M' ? ('Male') : ('Female'),
                                  style: const TextStyle(fontSize: 12),
                                )
                              : null,
                          trailing: isCurrent
                              ? const Icon(
                                  Icons.check_circle,
                                  color: AppTheme.primaryGreen,
                                  size: 20,
                                )
                              : null,
                          onTap: () => Navigator.pop(context, s),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
