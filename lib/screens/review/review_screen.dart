import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../config/responsive.dart';
import '../../models/scan_result.dart';
import '../../models/assessment.dart';
import '../../models/student.dart';
import '../../services/scoring_service.dart';
import '../../services/voice_service.dart';
import '../../services/assessment_provider.dart';
import '../../services/hybrid_grading_service.dart';
import '../../services/excel_service.dart';
import '../../services/student_provider.dart';
import '../../services/class_provider.dart';
import '../../services/settings_provider.dart';
import '../../services/paper_image_intake_service.dart';
import '../../services/ocr_service.dart';
import '../../services/draft_service.dart';
import '../../services/correction_learner.dart';
import '../../services/answer_key_fingerprint_service.dart';
import '../../services/answer_key_recalculation_service.dart';
import '../../services/integrity_state_resolver.dart';
import '../../services/assessment_completion_gate.dart';
import '../../models/audit_entry.dart';
import '../../services/audit_service.dart';
import '../../services/teacher_provider.dart';
import '../../services/results_pdf_service.dart';
import '../../services/sms_service.dart';
import '../assessment/answer_key_screen.dart';
import '../scanning/camera_screen.dart';
import 'audit_trail_sheet.dart' as audit;
import 'rescan_sheet.dart';

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
  bool _isRegrading = false;
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
        case _SortMode.answerKeyFirst:
          _results!.sort((a, b) {
            final aNeedsKey =
                a.metadata['answerKeyChangedNeedsRegrade'] == true;
            final bNeedsKey =
                b.metadata['answerKeyChangedNeedsRegrade'] == true;
            if (aNeedsKey != bNeedsKey) return aNeedsKey ? -1 : 1;
            return a.percentage.compareTo(b.percentage);
          });
        case _SortMode.identityFirst:
          _results!.sort((a, b) {
            final aNeedsName = _needsStudentIdentity(a);
            final bNeedsName = _needsStudentIdentity(b);
            if (aNeedsName != bNeedsName) return aNeedsName ? -1 : 1;
            if (a.needsReview != b.needsReview) {
              return a.needsReview ? -1 : 1;
            }
            return a.percentage.compareTo(b.percentage);
          });
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

  static bool _needsStudentIdentity(ScanResult result) {
    return result.studentId.isEmpty ||
        result.studentName.trim().isEmpty ||
        result.studentName.startsWith('Paper ');
  }

  void _focusReviewQueue(_SortMode mode) {
    _sortMode = mode;
    _applySort();
  }

  /// Replace a single result after teacher overrides scores.
  void _updateResult(int index, ScanResult updated) {
    setState(() {
      _results![index] = updated;
      _hasUnsavedChanges = true;
    });
  }

  void _markResultReviewed(int index, ScanResult result, _ReviewIssue issue) {
    final metadata = Map<String, dynamic>.from(result.metadata)
      ..remove('answerKeyChangedNeedsRegrade')
      ..['teacherReviewed'] = true
      ..['teacherReviewedAt'] = DateTime.now().toIso8601String();
    if (issue == _ReviewIssue.duplicate) {
      metadata['duplicateReviewed'] = true;
      metadata['duplicateReviewedAt'] = DateTime.now().toIso8601String();
    }

    _updateResult(
      index,
      result.copyWith(status: ScanStatus.reviewed, metadata: metadata),
    );

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Marked reviewed')));
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
          content: Text('Reassigned to ${selected.fullName}'),
          backgroundColor: context.primaryGreen,
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
          content: const Text('Grade reverted'),
          backgroundColor: context.warning,
        ),
      );
    }
  }

  /// Save every result in the batch so clean scans are not lost.
  Future<int> _saveAll({
    bool showMessage = true,
    bool skipReviewGate = false,
  }) async {
    if (_results == null || _results!.isEmpty) return 0;
    if (!skipReviewGate) {
      final canProceed = await _confirmFinalSaveIfNeeded();
      if (!canProceed) return 0;
    }
    setState(() => _isSaving = true);

    final grading = HybridGradingService();
    int saved = 0;
    int failed = 0;
    final updatedResults = <ScanResult>[];
    final imageIntake = PaperImageIntakeService();

    for (final result in _results!) {
      final resultToSave = _gradesOnlyIfTemporaryImage(result);
      final ok = await grading.saveScanResult(resultToSave);
      if (ok) {
        await _deleteTemporaryPaperImages(result, imageIntake);
        updatedResults.add(resultToSave);
        saved++;
      } else {
        updatedResults.add(result);
        failed++;
      }
    }

    if (mounted) {
      setState(() {
        _results!
          ..clear()
          ..addAll(updatedResults);
        _isSaving = false;
        _hasUnsavedChanges = false;
      });
      if (failed == 0 && updatedResults.isNotEmpty) {
        await DraftService().clearDraft(updatedResults.first.assessmentId);
        if (!mounted) return saved;
      }
      if (showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failed == 0
                  ? ('$saved result(s) saved')
                  : ('$saved saved, $failed failed'),
            ),
          ),
        );
      }
    }

    return saved;
  }

  void _sendResultsToParents() {
    if (_results == null || _results!.isEmpty) return;

    final students = context.read<StudentProvider>().students;
    final settings = context.read<SettingsProvider>();

    final messages = <Map<String, String>>[];
    final missingPhones = <String>[];

    for (final result in _results!) {
      final student = students
          .where((s) => s.id == result.studentId)
          .firstOrNull;
      if (student == null) continue;

      if (student.parentPhone == null || student.parentPhone!.isEmpty) {
        missingPhones.add(student.fullName);
        continue;
      }

      final message = DefaultTemplates.resultNotification.render(
        studentName: student.fullName,
        subject: result.assessmentId,
        percentage: result.percentage,
        schoolName: settings.schoolName.isEmpty
            ? 'School'
            : settings.schoolName,
        amharic: false,
      );

      messages.add({
        'phone': student.parentPhone!,
        'message': message,
        'student': student.fullName,
      });
    }

    if (missingPhones.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${missingPhones.length} student(s) missing parent phone number',
          ),
        ),
      );
    }

    if (messages.isNotEmpty && mounted) {
      Navigator.pushNamed(
        context,
        AppRoutes.smsCompose,
        arguments: {
          'messages': messages,
          'assessmentName': _results!.first.assessmentId,
        },
      );
    }
  }

  void _markAllReviewed() {
    if (_results == null || _results!.isEmpty) return;

    for (int i = 0; i < _results!.length; i++) {
      final result = _results![i];
      if (result.status == ScanStatus.reviewed) continue;

      final metadata = Map<String, dynamic>.from(result.metadata)
        ..['teacherReviewed'] = true
        ..['teacherReviewedAt'] = DateTime.now().toIso8601String();

      _updateResult(
        i,
        result.copyWith(status: ScanStatus.reviewed, metadata: metadata),
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_results!.length} result(s) marked as reviewed'),
      ),
    );
  }

  Future<void> _deleteTemporaryPaperImages(
    ScanResult result,
    PaperImageIntakeService imageIntake,
  ) async {
    if (result.metadata['paperImageRetention'] !=
        PaperImageIntakeService.temporaryRetention) {
      return;
    }

    final paths = [
      result.imagePath,
      result.enhancedImagePath,
    ].whereType<String>().where((path) => path.isNotEmpty).toList();
    if (paths.isEmpty) return;

    switch (result.metadata['imageSource']) {
      case 'camera':
        await OcrService().cleanupImages(paths);
        break;
      case 'upload':
        await imageIntake.deleteManagedTemporaryFiles(paths);
        break;
    }
  }

  ScanResult _gradesOnlyIfTemporaryImage(ScanResult result) {
    if (result.metadata['paperImageRetention'] !=
        PaperImageIntakeService.temporaryRetention) {
      return result;
    }
    final metadata = Map<String, dynamic>.from(result.metadata)
      ..remove('paperImageRetention')
      ..['paperImagesRemovedAfterSave'] = true;
    return result.copyWith(
      imagePath: '',
      enhancedImagePath: null,
      metadata: metadata,
    );
  }

  Future<void> _rescanResult(int index, ScanResult result) async {
    final assessment = context
        .read<AssessmentProvider>()
        .assessments
        .cast<Assessment?>()
        .firstWhere((a) => a?.id == result.assessmentId, orElse: () => null);
    if (assessment == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Assessment not found')));
      return;
    }

    final newResult = await showReScanSheet(
      context,
      assessment: assessment,
      existingResult: result,
    );
    if (!mounted || newResult == null) return;

    final metadata = {
      ...newResult.metadata,
      'imageSource': PaperImageSource.camera.name,
      'paperImageRetention': PaperImageIntakeService.temporaryRetention,
      'rescannedFromResultId': result.id,
      'rescannedAt': DateTime.now().toIso8601String(),
    }..remove('answerKeyChangedNeedsRegrade');

    _updateResult(index, newResult.copyWith(metadata: metadata));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${newResult.studentName} re-scanned')),
    );
  }

  Future<void> _showDuplicateResolution(int index) async {
    final results = _results;
    if (results == null || index < 0 || index >= results.length) return;

    final pairs = _duplicatePairsFor(index, results);
    if (pairs.isEmpty) {
      _markResultReviewed(index, results[index], _ReviewIssue.duplicate);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Possible duplicate',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose what should happen before final save.',
                  style: TextStyle(color: context.lightText, fontSize: 13),
                ),
                const SizedBox(height: 12),
                ...pairs.map(
                  (pair) => _DuplicatePairTile(
                    pair: pair,
                    results: results,
                    focusIndex: index,
                    onKeepBoth: () {
                      Navigator.pop(sheetContext);
                      _markDuplicatePairReviewed(pair);
                    },
                    onKeepIndex: (keepIndex) {
                      Navigator.pop(sheetContext);
                      _keepDuplicateIndex(pair, keepIndex);
                    },
                    onAssign: () {
                      Navigator.pop(sheetContext);
                      _reassignStudent(results[index]);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<AnswerDuplicate> _duplicatePairsFor(
    int index,
    List<ScanResult> results,
  ) {
    return HybridGradingService().detectBatchDuplicates(results).where((
      duplicate,
    ) {
      final involvesIndex =
          duplicate.scanIndexA == index || duplicate.scanIndexB == index;
      if (!involvesIndex ||
          duplicate.scanIndexA >= results.length ||
          duplicate.scanIndexB >= results.length) {
        return false;
      }
      return results[duplicate.scanIndexA].metadata['duplicateReviewed'] !=
              true ||
          results[duplicate.scanIndexB].metadata['duplicateReviewed'] != true;
    }).toList();
  }

  void _markDuplicatePairReviewed(AnswerDuplicate pair) {
    final results = _results;
    if (results == null ||
        pair.scanIndexA >= results.length ||
        pair.scanIndexB >= results.length) {
      return;
    }

    setState(() {
      for (final index in [pair.scanIndexA, pair.scanIndexB]) {
        final result = results[index];
        results[index] = result.copyWith(
          status: ScanStatus.reviewed,
          metadata: {
            ...result.metadata,
            'duplicateReviewed': true,
            'duplicateReviewedAt': DateTime.now().toIso8601String(),
          },
        );
      }
      _hasUnsavedChanges = true;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Duplicate checked')));
  }

  void _keepDuplicateIndex(AnswerDuplicate pair, int keepIndex) {
    final results = _results;
    if (results == null) return;
    final removeIndex = keepIndex == pair.scanIndexA
        ? pair.scanIndexB
        : pair.scanIndexA;
    if (removeIndex < 0 || removeIndex >= results.length) return;

    final removed = results[removeIndex];
    setState(() {
      results.removeAt(removeIndex);
      _hasUnsavedChanges = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${removed.studentName} removed from review')),
    );
  }

  Future<void> _saveAndExportCsv() async {
    final results = _results;
    if (results == null || results.isEmpty || _isExporting) return;

    final canProceed = await _confirmFinalSaveIfNeeded();
    if (!canProceed) return;

    setState(() => _isExporting = true);
    final saved = await _saveAll(showMessage: false, skipReviewGate: true);
    if (!mounted) return;

    try {
      final path = await ImportService().exportResults(
        assessmentTitle: _assessmentTitle(results),
        roster: _rosterForExport(results),
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
          backgroundColor: context.primaryGreen,
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
          content: const Text('Could not export CSV'),
          backgroundColor: context.primaryRed,
        ),
      );
    }
  }

  Future<void> _exportPdf(BuildContext context) async {
    final results = _results;
    if (results == null || results.isEmpty) return;

    try {
      final assessment = context.read<AssessmentProvider>().getAssessmentById(
        results.first.assessmentId,
      );
      if (assessment == null) return;

      final settings = context.read<SettingsProvider>();
      final pdfService = ResultsPdfService();
      final file = await pdfService.generateResultsReport(
        assessment: assessment,
        results: results,
        schoolName: settings.schoolName,
        teacherName: settings.teacherName,
      );

      if (!context.mounted) return;

      await pdfService.openFile(file);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate report: $e'),
            backgroundColor: context.error,
          ),
        );
      }
    }
  }

  String _assessmentTitle(List<ScanResult> results) {
    final assessment = context.read<AssessmentProvider>().getAssessmentById(
      results.first.assessmentId,
    );
    return assessment?.title ?? 'EthioGrade Results';
  }

  /// Resolves the class roster for the current assessment so the export can
  /// include students whose papers were not scanned as ungraded rows.
  List<Map<String, dynamic>> _rosterForExport(List<ScanResult> results) {
    if (results.isEmpty) return const [];
    final assessment = context.read<AssessmentProvider>().getAssessmentById(
      results.first.assessmentId,
    );
    if (assessment == null || assessment.className.isEmpty) return const [];

    final classProvider = context.read<ClassProvider>();
    final studentProvider = context.read<StudentProvider>();
    final cls = classProvider.classes
        .where(
          (c) =>
              c.id == assessment.className ||
              c.displayName == assessment.className,
        )
        .firstOrNull;
    if (cls == null) return const [];

    return studentProvider.studentsByClassId(cls.id).map((student) {
      return {'studentId': student.id, 'studentName': student.fullName};
    }).toList();
  }

  Future<bool> _confirmFinalSaveIfNeeded() async {
    final results = _results;
    if (results == null || results.isEmpty) return true;

    // Use centralized completion gate
    final assessment = results.isNotEmpty
        ? context.read<AssessmentProvider>().getAssessmentById(
            results.first.assessmentId,
          )
        : null;
    if (assessment == null) return true;

    const gate = AssessmentCompletionGate();
    final check = gate.check(assessment: assessment, results: results);

    if (check.isReady) return true;

    // Show blocking issues dialog
    final blockingItems = check.blocking;
    final attentionItems = check.needsAttention;

    if (!mounted) return false;

    final action = await showDialog<_ReviewSaveAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Assessment not ready'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (blockingItems.isNotEmpty) ...[
                const Text(
                  'Blocking issues:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...blockingItems.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.block, size: 16, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (item.explanation != null)
                                Text(
                                  item.explanation!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.lightText,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (attentionItems.isNotEmpty) ...[
                const Text(
                  'Needs attention:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...attentionItems.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber,
                          size: 16,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (item.explanation != null)
                                Text(
                                  item.explanation!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.lightText,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _ReviewSaveAction.keepReviewing),
            child: const Text('Review remaining'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, _ReviewSaveAction.draft),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save draft'),
          ),
          if (blockingItems.isEmpty)
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, _ReviewSaveAction.finalSaveAnyway),
              child: const Text('Final save anyway'),
            ),
        ],
      ),
    );

    if (!mounted) return false;
    if (action == _ReviewSaveAction.finalSaveAnyway) return true;
    if (action == _ReviewSaveAction.draft) {
      await _saveReviewDraft(
        _ReviewQueue.fromResults(results, assessment: assessment),
      );
    }
    return false;
  }

  Future<void> _saveReviewDraft(_ReviewQueue queue) async {
    final results = _results;
    if (results == null || results.isEmpty) return;

    await DraftService().saveDraft(
      assessmentId: results.first.assessmentId,
      completedResults: results.map((result) => result.toMap()).toList(),
      currentStudentIndex: results.length,
      metadata: {
        'source': 'review_queue',
        'openReviewIssues': queue.blockingCount,
        'savedFromReviewAt': DateTime.now().toIso8601String(),
      },
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Draft saved with ${queue.blockingCount} issue(s) open'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = _results ?? [];
    final assessment = _assessmentForResults(context, results);
    final queue = _ReviewQueue.fromResults(results, assessment: assessment);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Queue'),
        actions: [
          if (results.isNotEmpty)
            IconButton(
              icon: Icon(
                _isReading ? Icons.stop_circle : Icons.volume_up,
                color: _isReading ? context.primaryRed : null,
              ),
              onPressed: _readAllScores,
              tooltip: _isReading ? 'Stop' : 'Read All Scores',
            ),
          if (_hasUnsavedChanges && !_isSaving)
            TextButton.icon(
              onPressed: _saveAll,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Save All'),
              style: TextButton.styleFrom(
                foregroundColor: context.primaryGreen,
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
          if (!_isSaving && _results != null && _results!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: _sendResultsToParents,
              tooltip: 'Send Results to Parents',
            ),
          if (!_isSaving && _results != null && _results!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.done_all),
              onPressed: _markAllReviewed,
              tooltip: 'Mark All Reviewed',
            ),
          if (_isRegrading)
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
                  Icon(Icons.inbox, size: 64, color: context.outlineLight),
                  const SizedBox(height: 16),
                  Text(
                    'No results to review',
                    style: TextStyle(color: context.lightText, fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView(
              padding: EdgeInsets.symmetric(
                vertical: 16,
                horizontal: ResponsiveLayout.horizontalPadding(context) * 0.8,
              ),
              children: [
                _ReviewSituationPanel(
                  results: results,
                  queue: queue,
                  assessment: assessment,
                  onReviewFlagged: () =>
                      _focusReviewQueue(_SortMode.needsReviewFirst),
                  onMatchStudents: () =>
                      _focusReviewQueue(_SortMode.identityFirst),
                  onRegradeNeeded: () =>
                      _focusReviewQueue(_SortMode.answerKeyFirst),
                  onFixAnswerKey: assessment == null
                      ? null
                      : () => _openAnswerKeyEditor(assessment),
                ),
                ...queue.sections.expand(
                  (section) => [
                    _ReviewQueueHeader(section: section),
                    ...section.items.map(
                      (item) => _ResultCard(
                        result: item.result,
                        issue: item.issue,
                        isReading: item.resultIndex == _readingIndex,
                        onReassign: () => _reassignStudent(item.result),
                        onMarkReviewed: () => _markResultReviewed(
                          item.resultIndex,
                          item.result,
                          item.issue,
                        ),
                        onRescan: () =>
                            _rescanResult(item.resultIndex, item.result),
                        onResolveDuplicate: () =>
                            _showDuplicateResolution(item.resultIndex),
                        onRevert: (entry) => _revertToEntry(
                          item.resultIndex,
                          item.result,
                          entry,
                        ),
                        onTap: () async {
                          final updated = await Navigator.pushNamed(
                            context,
                            AppRoutes.sideBySide,
                            arguments: item.result,
                          );
                          if (updated is ScanResult) {
                            _updateResult(item.resultIndex, updated);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
      bottomNavigationBar: results.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isSaving || _isExporting || _isRegrading
                            ? null
                            : () => _saveReviewDraft(queue),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save draft'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _isSaving || _isExporting || _isRegrading
                          ? null
                          : () => _exportPdf(context),
                      icon: const Icon(Icons.picture_as_pdf),
                      tooltip: 'Export PDF',
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _isSaving || _isExporting || _isRegrading
                            ? null
                            : _saveAndExportCsv,
                        style: FilledButton.styleFrom(
                          backgroundColor: context.primaryGreen,
                          foregroundColor: Colors.white,
                        ),
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
                          _isExporting ? 'Exporting...' : 'Final save',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Assessment? _assessmentForResults(
    BuildContext context,
    List<ScanResult> results,
  ) {
    if (results.isEmpty) return null;
    final assessmentId = results.first.assessmentId;
    if (assessmentId.isEmpty) return null;

    final assessments = context.watch<AssessmentProvider>().assessments;
    for (final assessment in assessments) {
      if (assessment.id == assessmentId) return assessment;
    }
    return null;
  }

  Future<void> _openAnswerKeyEditor(Assessment assessment) async {
    final before = _answerKeySignature(assessment);
    final updated = await Navigator.pushNamed(
      context,
      AppRoutes.answerKey,
      arguments: AnswerKeyRouteArgs(
        assessment: assessment,
        returnToReview: true,
      ),
    );
    if (!mounted) return;

    final updatedAssessment = updated is Assessment
        ? updated
        : _assessmentForResults(context, _results ?? []);
    if (updatedAssessment == null) return;

    if (before == _answerKeySignature(updatedAssessment)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Answer key unchanged')));
      return;
    }

    await _showAnswerKeyChangedPrompt(updatedAssessment);
  }

  String _answerKeySignature(Assessment assessment) {
    return const AnswerKeyFingerprintService().compute(assessment);
  }

  Future<void> _showAnswerKeyChangedPrompt(Assessment assessment) async {
    final results = _results ?? [];
    if (results.isEmpty) return;

    final action = await showDialog<_AnswerKeyChangedAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Answer key changed'),
        content: Text(
          '${results.length} paper${results.length == 1 ? ' was' : 's were'} graded '
          'using the previous answer key. Their scores must be recalculated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              _AnswerKeyChangedAction.keepCurrentScores,
            ),
            child: const Text('Keep current'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(
              context,
              _AnswerKeyChangedAction.saveAndRecalculateLater,
            ),
            child: const Text('Save and recalculate later'),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pop(context, _AnswerKeyChangedAction.regradeAll),
            icon: const Icon(Icons.refresh),
            label: const Text('Recalculate now'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (action == _AnswerKeyChangedAction.regradeAll) {
      await _regradeAllWithAssessment(assessment);
    } else if (action == _AnswerKeyChangedAction.saveAndRecalculateLater) {
      // Mark results as needing regrade
      setState(() {
        _results = _results?.map(_markAnswerKeyChanged).toList();
        _hasUnsavedChanges = true;
      });
    }
    // keepCurrentScores: do nothing — results stay as-is
  }

  Future<void> _regradeAllWithAssessment(Assessment assessment) async {
    final results = _results;
    if (results == null || results.isEmpty) return;

    setState(() => _isRegrading = true);

    // Use the recalculation service for persisted-response rescoring
    final recalcService = AnswerKeyRecalculationService();
    final recalcResult = await recalcService.recalculateAll(
      assessment: assessment,
      results: results,
    );

    if (!mounted) return;
    setState(() {
      _results = recalcResult.updatedResults;
      _hasUnsavedChanges = true;
      _isRegrading = false;
      _sortMode = _SortMode.needsReviewFirst;
    });
    _applySort();

    final summary = StringBuffer();
    summary.write('${recalcResult.recalculated} recalculated');
    if (recalcResult.scoresChanged > 0) {
      summary.write(', ${recalcResult.scoresChanged} scores changed');
    }
    if (recalcResult.preserved > 0) {
      summary.write(', ${recalcResult.preserved} preserved (manual)');
    }
    if (recalcResult.failed > 0) {
      summary.write(', ${recalcResult.failed} failed');
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(summary.toString()),
        backgroundColor: recalcResult.allSucceeded
            ? context.primaryGreen
            : Colors.orange,
      ),
    );
  }

  ScanResult _markAnswerKeyChanged(ScanResult result) {
    return result.copyWith(
      metadata: {...result.metadata, 'answerKeyChangedNeedsRegrade': true},
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
      mode: context.read<SettingsProvider>().voiceFeedbackMode,
      needsReview: results.map((r) => r.needsReview).toList(),
      onReadingIndex: (i) {
        if (mounted) setState(() => _readingIndex = i);
      },
    );

    if (mounted) {
      setState(() {
        _isReading = false;
        _readingIndex = -1;
      });
    }
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
              title: const Text('Lowest to Highest'),
              trailing: _sortMode == _SortMode.lowestFirst
                  ? Icon(Icons.check, color: context.primaryGreen)
                  : null,
              onTap: () {
                _sortMode = _SortMode.lowestFirst;
                _applySort();
                Navigator.pop(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: const Text('Highest to Lowest'),
              trailing: _sortMode == _SortMode.highestFirst
                  ? Icon(Icons.check, color: context.primaryGreen)
                  : null,
              onTap: () {
                _sortMode = _SortMode.highestFirst;
                _applySort();
                Navigator.pop(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.warning),
              title: const Text('Needs Review First'),
              trailing: _sortMode == _SortMode.needsReviewFirst
                  ? Icon(Icons.check, color: context.primaryGreen)
                  : null,
              onTap: () {
                _sortMode = _SortMode.needsReviewFirst;
                _applySort();
                Navigator.pop(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_search_outlined),
              title: const Text('Missing Students First'),
              trailing: _sortMode == _SortMode.identityFirst
                  ? Icon(Icons.check, color: context.primaryGreen)
                  : null,
              onTap: () {
                _sortMode = _SortMode.identityFirst;
                _applySort();
                Navigator.pop(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.key_off_outlined),
              title: const Text('Answer Key Changes First'),
              trailing: _sortMode == _SortMode.answerKeyFirst
                  ? Icon(Icons.check, color: context.primaryGreen)
                  : null,
              onTap: () {
                _sortMode = _SortMode.answerKeyFirst;
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

enum _SortMode {
  lowestFirst,
  highestFirst,
  needsReviewFirst,
  identityFirst,
  answerKeyFirst,
}

enum _AnswerKeyChangedAction {
  regradeAll,
  keepCurrentScores,
  saveAndRecalculateLater,
}

enum _ReviewSaveAction { keepReviewing, draft, finalSaveAnyway }

enum _ReviewIssue { answerKey, missingStudent, duplicate, lowConfidence, ready }

class _ReviewQueue {
  const _ReviewQueue({required this.sections, required this.blockingCount});

  final List<_ReviewQueueSection> sections;
  final int blockingCount;

  bool get hasBlockingIssues => blockingCount > 0;

  factory _ReviewQueue.fromResults(
    List<ScanResult> results, {
    Assessment? assessment,
  }) {
    final duplicateIndexes = _duplicateIndexes(results);
    const resolver = IntegrityStateResolver();
    final grouped = <_ReviewIssue, List<_ReviewQueueItem>>{
      for (final issue in _ReviewIssue.values) issue: [],
    };

    for (var i = 0; i < results.length; i++) {
      final result = results[i];
      final issue = _issueFor(
        result,
        duplicateIndexes.contains(i),
        assessment: assessment,
        resolver: resolver,
      );
      grouped[issue]!.add(
        _ReviewQueueItem(resultIndex: i, result: result, issue: issue),
      );
    }

    final sections = <_ReviewQueueSection>[
      _ReviewQueueSection(
        issue: _ReviewIssue.answerKey,
        title: 'Regrade needed',
        subtitle: 'Answer key changed after scoring.',
        icon: Icons.key_off_outlined,
        color: AppTheme.primaryRed,
        items: grouped[_ReviewIssue.answerKey]!,
      ),
      _ReviewQueueSection(
        issue: _ReviewIssue.missingStudent,
        title: 'Needs student',
        subtitle: 'Match these papers to the roster.',
        icon: Icons.person_search_outlined,
        color: AppTheme.warning,
        items: grouped[_ReviewIssue.missingStudent]!,
      ),
      _ReviewQueueSection(
        issue: _ReviewIssue.duplicate,
        title: 'Possible duplicates',
        subtitle: 'Check papers that look like repeat scans.',
        icon: Icons.content_copy_outlined,
        color: AppTheme.warning,
        items: grouped[_ReviewIssue.duplicate]!,
      ),
      _ReviewQueueSection(
        issue: _ReviewIssue.lowConfidence,
        title: 'Needs review',
        subtitle: 'Unclear answers or low confidence.',
        icon: Icons.rule_folder_outlined,
        color: AppTheme.warning,
        items: grouped[_ReviewIssue.lowConfidence]!,
      ),
      _ReviewQueueSection(
        issue: _ReviewIssue.ready,
        title: 'Ready to save',
        subtitle: 'These results look clean.',
        icon: Icons.check_circle_outline,
        color: AppTheme.primaryGreen,
        items: grouped[_ReviewIssue.ready]!,
      ),
    ].where((section) => section.items.isNotEmpty).toList(growable: false);

    return _ReviewQueue(
      sections: sections,
      blockingCount: results.length - grouped[_ReviewIssue.ready]!.length,
    );
  }

  static Set<int> _duplicateIndexes(List<ScanResult> results) {
    if (results.length < 2) return {};
    final duplicates = HybridGradingService()
        .detectBatchDuplicates(results)
        .where((duplicate) {
          if (duplicate.scanIndexA >= results.length ||
              duplicate.scanIndexB >= results.length) {
            return false;
          }
          return results[duplicate.scanIndexA].metadata['duplicateReviewed'] !=
                  true ||
              results[duplicate.scanIndexB].metadata['duplicateReviewed'] !=
                  true;
        });
    return {
      for (final duplicate in duplicates) ...[
        duplicate.scanIndexA,
        duplicate.scanIndexB,
      ],
    };
  }

  static _ReviewIssue _issueFor(
    ScanResult result,
    bool isDuplicate, {
    Assessment? assessment,
    IntegrityStateResolver? resolver,
  }) {
    // Check integrity state first (new system)
    if (assessment != null && resolver != null) {
      final state = resolver.resolve(result: result, assessment: assessment);
      if (state == IntegrityState.outdated) {
        return _ReviewIssue.answerKey;
      }
    }
    // Fallback to old flag for backward compatibility
    if (result.metadata['answerKeyChangedNeedsRegrade'] == true) {
      return _ReviewIssue.answerKey;
    }
    if (_ReviewScreenState._needsStudentIdentity(result)) {
      return _ReviewIssue.missingStudent;
    }
    if (isDuplicate) return _ReviewIssue.duplicate;
    if (result.needsReview) return _ReviewIssue.lowConfidence;
    return _ReviewIssue.ready;
  }
}

class _ReviewQueueSection {
  const _ReviewQueueSection({
    required this.issue,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.items,
  });

  final _ReviewIssue issue;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<_ReviewQueueItem> items;
}

class _ReviewQueueItem {
  const _ReviewQueueItem({
    required this.resultIndex,
    required this.result,
    required this.issue,
  });

  final int resultIndex;
  final ScanResult result;
  final _ReviewIssue issue;
}

class _ReviewQueueHeader extends StatelessWidget {
  const _ReviewQueueHeader({required this.section});

  final _ReviewQueueSection section;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          Icon(section.icon, size: 18, color: section.color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${section.title} (${section.items.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  section.subtitle,
                  style: TextStyle(
                    color: context.lightText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DuplicatePairTile extends StatelessWidget {
  const _DuplicatePairTile({
    required this.pair,
    required this.results,
    required this.focusIndex,
    required this.onKeepBoth,
    required this.onKeepIndex,
    required this.onAssign,
  });

  final AnswerDuplicate pair;
  final List<ScanResult> results;
  final int focusIndex;
  final VoidCallback onKeepBoth;
  final ValueChanged<int> onKeepIndex;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final first = results[pair.scanIndexA];
    final second = results[pair.scanIndexB];
    final focus = results[focusIndex];
    final otherIndex = focusIndex == pair.scanIndexA
        ? pair.scanIndexB
        : pair.scanIndexA;
    final other = results[otherIndex];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.warning.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.warning.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.content_copy_outlined, color: context.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${first.studentName} and ${second.studentName}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${pair.matchPercent.toStringAsFixed(0)}% answer match',
            style: TextStyle(color: context.lightText, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onKeepBoth,
                icon: const Icon(Icons.done_all, size: 18),
                label: const Text('Keep both'),
              ),
              FilledButton.icon(
                onPressed: () => onKeepIndex(focusIndex),
                icon: const Icon(Icons.check, size: 18),
                label: Text('Keep ${focus.studentName}'),
              ),
              OutlinedButton.icon(
                onPressed: () => onKeepIndex(otherIndex),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: Text('Keep ${other.studentName}'),
              ),
              TextButton.icon(
                onPressed: onAssign,
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: const Text('Assign student'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewSituationPanel extends StatelessWidget {
  final List<ScanResult> results;
  final _ReviewQueue queue;
  final Assessment? assessment;
  final VoidCallback onReviewFlagged;
  final VoidCallback onMatchStudents;
  final VoidCallback onRegradeNeeded;
  final VoidCallback? onFixAnswerKey;

  const _ReviewSituationPanel({
    required this.results,
    required this.queue,
    required this.assessment,
    required this.onReviewFlagged,
    required this.onMatchStudents,
    required this.onRegradeNeeded,
    required this.onFixAnswerKey,
  });

  @override
  Widget build(BuildContext context) {
    final autoCount = results
        .where((result) => result.metadata['autoCaptured'] == true)
        .length;
    final rosterCount = results
        .where((result) => result.metadata['studentMatchMode'] == 'roster')
        .length;
    final paperNumberCount = results
        .where(
          (result) => result.metadata['studentMatchMode'] == 'paper-number',
        )
        .length;
    final needsReviewCount = results
        .where((result) => result.needsReview)
        .length;
    final missingIdentityCount = results
        .where(_ReviewScreenState._needsStudentIdentity)
        .length;
    final staleKeyCount = assessment != null
        ? results
              .where(
                (result) =>
                    const IntegrityStateResolver().resolve(
                      result: result,
                      assessment: assessment!,
                    ) ==
                    IntegrityState.outdated,
              )
              .length
        : results
              .where(
                (result) =>
                    result.metadata['answerKeyChangedNeedsRegrade'] == true,
              )
              .length;

    final nextAction = staleKeyCount > 0
        ? _QueueAction(
            icon: Icons.key_off_outlined,
            title: 'Do first: regrade answer-key change',
            subtitle: '$staleKeyCount papers may have old scores.',
            color: context.primaryRed,
            onTap: onRegradeNeeded,
          )
        : needsReviewCount > 0
        ? _QueueAction(
            icon: Icons.rule_folder_outlined,
            title: 'Check unclear answers',
            subtitle: '$needsReviewCount papers need a teacher look.',
            color: context.warning,
            onTap: onReviewFlagged,
          )
        : missingIdentityCount > 0
        ? _QueueAction(
            icon: Icons.person_search_outlined,
            title: 'Match paper names',
            subtitle: '$missingIdentityCount papers need a student.',
            color: context.warning,
            onTap: onMatchStudents,
          )
        : _QueueAction(
            icon: Icons.check_circle_outline,
            title: 'Ready for final save',
            subtitle: '${results.length} results look ready.',
            color: context.primaryGreen,
            onTap: () {},
          );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: AppTheme.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Review queue',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            assessment?.title ?? 'Review before final save',
            style: TextStyle(color: context.lightText, fontSize: 12),
          ),
          const SizedBox(height: 12),
          _QueueActionTile(action: nextAction, isPrimary: true),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _ReviewChip(
                icon: Icons.auto_awesome_motion_outlined,
                label: autoCount > 0
                    ? '$autoCount auto scanned'
                    : 'Manual batch',
                color: AppTheme.info,
              ),
              _ReviewChip(
                icon: Icons.groups_outlined,
                label: rosterCount > 0
                    ? '$rosterCount roster matched'
                    : paperNumberCount > 0
                    ? '$paperNumberCount paper labels'
                    : 'Roster not used',
                color: rosterCount > 0
                    ? context.primaryGreen
                    : context.warning,
              ),
              _ReviewChip(
                icon: needsReviewCount > 0
                    ? Icons.warning_amber_outlined
                    : Icons.check_circle_outline,
                label: needsReviewCount > 0
                    ? '$needsReviewCount need review'
                    : 'No review flags',
                color: needsReviewCount > 0
                    ? context.warning
                    : context.primaryGreen,
              ),
              _ReviewChip(
                icon: queue.hasBlockingIssues
                    ? Icons.playlist_add_check_circle_outlined
                    : Icons.verified_outlined,
                label: queue.hasBlockingIssues
                    ? '${queue.blockingCount} open issue(s)'
                    : 'Ready queue',
                color: queue.hasBlockingIssues
                    ? context.warning
                    : context.primaryGreen,
              ),
              if (staleKeyCount > 0)
                _ReviewChip(
                  icon: Icons.key_off_outlined,
                  label: '$staleKeyCount need regrade',
                  color: context.primaryRed,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Column(
            children: [
              _QueueActionTile(
                action: _QueueAction(
                  icon: Icons.rule_folder_outlined,
                  title: 'Check unclear answers',
                  subtitle: needsReviewCount > 0
                      ? '$needsReviewCount papers need review.'
                      : 'No unclear answers flagged.',
                  color: needsReviewCount > 0
                      ? context.warning
                      : context.primaryGreen,
                  onTap: onReviewFlagged,
                ),
              ),
              _QueueActionTile(
                action: _QueueAction(
                  icon: Icons.person_search_outlined,
                  title: 'Match paper names',
                  subtitle: missingIdentityCount > 0
                      ? '$missingIdentityCount papers need a student.'
                      : 'All papers have a student.',
                  color: missingIdentityCount > 0
                      ? context.warning
                      : context.primaryGreen,
                  onTap: onMatchStudents,
                ),
              ),
              _QueueActionTile(
                action: _QueueAction(
                  icon: Icons.key_outlined,
                  title: 'Answer key changes',
                  subtitle: staleKeyCount > 0
                      ? '$staleKeyCount papers need regrade.'
                      : 'Key is stable for this review.',
                  color: staleKeyCount > 0
                      ? context.primaryRed
                      : context.primaryGreen,
                  onTap: staleKeyCount > 0 ? onRegradeNeeded : onFixAnswerKey,
                ),
              ),
            ],
          ),
          if (missingIdentityCount > 0) ...[
            const SizedBox(height: 10),
            Text(
              '$missingIdentityCount papers still need a student name or roster match.',
              style: TextStyle(color: context.lightText, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'If the answer key is wrong, fix it before final save.',
                  style: TextStyle(color: context.lightText, fontSize: 12),
                ),
              ),
              TextButton.icon(
                onPressed: onFixAnswerKey,
                icon: const Icon(Icons.key_outlined, size: 18),
                label: const Text('Fix key'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QueueAction {
  const _QueueAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;
}

class _QueueActionTile extends StatelessWidget {
  const _QueueActionTile({required this.action, this.isPrimary = false});

  final _QueueAction action;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isPrimary ? 0 : 6),
      child: Material(
        color: isPrimary
            ? action.color.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isPrimary ? 12 : 0,
              vertical: isPrimary ? 12 : 6,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: isPrimary
                  ? Border.all(color: action.color.withValues(alpha: 0.35))
                  : null,
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: isPrimary ? 18 : 15,
                  backgroundColor: action.color.withValues(alpha: 0.12),
                  child: Icon(action.icon, size: 18, color: action.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action.title,
                        style: TextStyle(
                          fontWeight: isPrimary
                              ? FontWeight.w800
                              : FontWeight.w700,
                          color: context.darkText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        action.subtitle,
                        style: TextStyle(
                          color: context.lightText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: action.onTap == null
                      ? Theme.of(context).colorScheme.outlineVariant
                      : context.outlineLight,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ReviewChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ──── Result Card ────

class _ResultCard extends StatelessWidget {
  final ScanResult result;
  final _ReviewIssue issue;
  final bool isReading;
  final VoidCallback onTap;
  final VoidCallback onReassign;
  final VoidCallback onMarkReviewed;
  final VoidCallback onRescan;
  final VoidCallback onResolveDuplicate;
  final void Function(AuditEntry entry) onRevert;

  const _ResultCard({
    required this.result,
    required this.issue,
    this.isReading = false,
    required this.onTap,
    required this.onReassign,
    required this.onMarkReviewed,
    required this.onRescan,
    required this.onResolveDuplicate,
    required this.onRevert,
  });

  String get _studentMatchLabel {
    switch (result.metadata['studentMatchMode']) {
      case 'roster':
        return result.studentName.startsWith('Paper ')
            ? 'Roster check'
            : 'Roster matched';
      case 'paper-number':
        return 'Needs name';
      default:
        return result.studentName.startsWith('Paper ') ? 'Needs name' : 'Named';
    }
  }

  IconData get _studentMatchIcon {
    switch (result.metadata['studentMatchMode']) {
      case 'roster':
        return result.studentName.startsWith('Paper ')
            ? Icons.person_search_outlined
            : Icons.verified_user_outlined;
      case 'paper-number':
        return Icons.drive_file_rename_outline;
      default:
        return result.studentName.startsWith('Paper ')
            ? Icons.drive_file_rename_outline
            : Icons.person_outline;
    }
  }

  Color get _studentMatchColor {
    switch (result.metadata['studentMatchMode']) {
      case 'roster':
        return result.studentName.startsWith('Paper ')
            ? AppTheme.warning
            : AppTheme.primaryGreen;
      case 'paper-number':
        return AppTheme.warning;
      default:
        return result.studentName.startsWith('Paper ')
            ? AppTheme.warning
            : AppTheme.info;
    }
  }

  String get _issueActionLabel {
    switch (issue) {
      case _ReviewIssue.answerKey:
        return result.imagePath.isEmpty ? 'Check score' : 'Re-scan';
      case _ReviewIssue.missingStudent:
        return 'Assign student';
      case _ReviewIssue.duplicate:
        return 'Resolve duplicate';
      case _ReviewIssue.lowConfidence:
        return result.imagePath.isEmpty ? 'Mark reviewed' : 'Re-scan';
      case _ReviewIssue.ready:
        return 'Open';
    }
  }

  IconData get _issueActionIcon {
    switch (issue) {
      case _ReviewIssue.missingStudent:
        return Icons.person_add_alt_1_outlined;
      case _ReviewIssue.answerKey:
      case _ReviewIssue.lowConfidence:
        return result.imagePath.isEmpty
            ? Icons.check_circle_outline
            : Icons.camera_alt_outlined;
      case _ReviewIssue.duplicate:
        return Icons.rule_folder_outlined;
      case _ReviewIssue.ready:
        return Icons.open_in_new;
    }
  }

  VoidCallback get _issueAction {
    switch (issue) {
      case _ReviewIssue.missingStudent:
        return onReassign;
      case _ReviewIssue.answerKey:
      case _ReviewIssue.lowConfidence:
        return result.imagePath.isEmpty ? onMarkReviewed : onRescan;
      case _ReviewIssue.duplicate:
        return onResolveDuplicate;
      case _ReviewIssue.ready:
        return onTap;
    }
  }

  @override
  Widget build(BuildContext context) {
    const passMark = 50;
    final passed = result.percentage >= passMark;
    final needsReview = result.needsReview;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: isReading
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppTheme.info, width: 2),
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
                        ? context.primaryGreen.withValues(alpha: 0.1)
                        : context.primaryRed.withValues(alpha: 0.1),
                    child: Text(
                      result.studentName.isNotEmpty
                          ? result.studentName[0]
                          : '?',
                      style: TextStyle(
                        color: passed
                            ? context.primaryGreen
                            : context.primaryRed,
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
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        if (isReading)
                          const Row(
                            children: [
                              Icon(
                                Icons.volume_up,
                                size: 14,
                                color: AppTheme.info,
                              ),
                              SizedBox(width: 4),
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
                          avatar: Icon(_issueActionIcon, size: 16),
                          label: Text(
                            _issueActionLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onPressed: _issueAction,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (issue == _ReviewIssue.answerKey)
                              _ReviewChip(
                                icon: Icons.key_off_outlined,
                                label: 'Regrade needed',
                                color: context.primaryRed,
                              ),
                            if (result.metadata['autoCaptured'] == true)
                              const _ReviewChip(
                                icon: Icons.auto_awesome_motion_outlined,
                                label: 'Auto',
                                color: AppTheme.info,
                              ),
                            _ReviewChip(
                              icon: _studentMatchIcon,
                              label: _studentMatchLabel,
                              color: _studentMatchColor,
                            ),
                          ],
                        ),
                        if (needsReview)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: context.warning.withValues(alpha: 0.1),
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
                                const base = 'Needs Review';
                                if (uncertainCount > 0) {
                                  return '$base · $uncertainCount ${'uncertain'}';
                                }
                                return base;
                              }(),
                              style: TextStyle(
                                fontSize: 11,
                                color: context.warning,
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
                          ? context.primaryGreen.withValues(alpha: 0.1)
                          : context.primaryRed.withValues(alpha: 0.1),
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
                                ? context.primaryGreen
                                : context.primaryRed,
                          ),
                        ),
                        Text(
                          result.grade,
                          style: TextStyle(
                            fontSize: 12,
                            color: passed
                                ? context.primaryGreen
                                : context.primaryRed,
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
                      ? context.primaryGreen.withValues(alpha: 0.15)
                      : a.detectedAnswer == '[MISSING]'
                      ? context.warmGray
                      : isLowConfidence
                      ? context.warning.withValues(alpha: 0.2)
                      : context.primaryRed.withValues(alpha: 0.15);
                  final borderColor = a.isCorrect
                      ? context.primaryGreen
                      : a.detectedAnswer == '[MISSING]'
                      ? context.outlineLight
                      : isLowConfidence
                      ? context.warning
                      : context.primaryRed;
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
                                ? context.primaryGreen
                                : a.detectedAnswer == '[MISSING]'
                                ? context.lightText
                                : context.primaryRed,
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
                    style: TextStyle(
                      color: context.lightText,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${'Confidence'}: ${(result.confidence * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: context.lightText,
                      fontSize: 12,
                    ),
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
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history, size: 14, color: AppTheme.info),
                          SizedBox(width: 4),
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
    const scoring = ScoringService();

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
              color: _isSpeakingTts ? context.primaryRed : null,
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
                  mode: context.read<SettingsProvider>().voiceFeedbackMode,
                  needsReview: result.needsReview,
                );
                if (mounted) setState(() => _isSpeakingTts = false);
              }
            },
            tooltip: _isSpeakingTts ? 'Stop' : 'Read Score',
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
                    context.primaryGreen.withValues(alpha: 0.1),
                    context.primaryGreen.withValues(alpha: 0.05),
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
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
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
              decoration: const InputDecoration(
                hintText: 'Write feedback for this student...',
              ),
            ),
            const SizedBox(height: 16),

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
                          const SnackBar(content: Text('Assessment not found')),
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
                    label: const Text('Re-Scan'),
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
                    label: const Text('Confirm'),
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
    return Column(
      key: ValueKey('fix_step_$safeIndex'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Progress indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: context.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber,
                size: 16,
                color: context.warning,
              ),
              const SizedBox(width: 8),
              Text(
                '${'Wrong'} ${safeIndex + 1} / ${wrong.length}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.warning,
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
          color: isMissing ? context.warning : context.primaryRed,
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
                      (isMissing ? context.warning : context.primaryRed)
                          .withValues(alpha: 0.1),
                  child: Text(
                    '${answer.questionNumber}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isMissing ? context.warning : context.primaryRed,
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
                          color: context.primaryGreen,
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
                  color: context.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: context.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.visibility_off_outlined,
                      color: context.warning,
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'OCR could not read this answer',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: context.warning,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'What did the student write?',
                      style: TextStyle(color: context.lightText, fontSize: 13),
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
                      color: context.primaryRed.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search,
                          size: 16,
                          color: context.primaryRed,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${'Detected'}: ',
                          style: TextStyle(
                            color: context.lightText,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          answer.detectedAnswer,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: context.primaryRed,
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
                                  ? context.warning.withValues(alpha: 0.15)
                                  : context.primaryRed.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${(answer.confidence * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 11,
                                color: answer.confidence < 0.6
                                    ? context.warning
                                    : context.primaryRed,
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
                          color: context.lightText,
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
              color: context.primaryGreen,
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
              color: context.primaryRed,
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
          color: isCorrectAnswer ? context.primaryGreen : context.lightText,
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
          content: const Text('✓ All answers corrected!'),
          backgroundColor: context.primaryGreen,
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
                style: TextStyle(color: context.lightText),
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
                        color: context.primaryYellow.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: context.primaryYellow.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            size: 16,
                            color: context.primaryYellow,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Previously corrected ${answer.detectedAnswer}→$suggestion',
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
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: context.primaryGreen,
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
              const Text(
                'Change Answer',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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
              const Text(
                'Or Quick Toggle',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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
                      label: const Text('Correct'),
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
                        foregroundColor: context.primaryRed,
                      ),
                      label: const Text('Wrong'),
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

  @override
  void dispose() {
    _voice.stopSpeaking();
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
          selectedColor: context.primaryGreen,
          avatar: isCorrect
              ? Icon(Icons.check, size: 16, color: context.primaryGreen)
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
                    ? context.primaryGreen.withValues(alpha: 0.15)
                    : context.warmGray,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isTrue
                      ? context.primaryGreen
                      : Theme.of(context).colorScheme.outlineVariant,
                  width: isTrue ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    isTrue ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: isTrue ? context.primaryGreen : context.outlineLight,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'True',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isTrue
                          ? context.primaryGreen
                          : context.darkText,
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
                    ? context.primaryRed.withValues(alpha: 0.15)
                    : context.warmGray,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: !isTrue
                      ? context.primaryRed
                      : Theme.of(context).colorScheme.outlineVariant,
                  width: !isTrue ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    !isTrue ? Icons.cancel : Icons.radio_button_unchecked,
                    color: !isTrue ? context.primaryRed : context.outlineLight,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'False',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: !isTrue
                          ? context.primaryRed
                          : context.darkText,
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
            backgroundColor: context.primaryGreen,
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
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3)),
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
        Text(
          label,
          style: TextStyle(fontSize: 12, color: context.lightText),
        ),
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
            color: context.warning.withValues(alpha: 0.5),
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
                  backgroundColor: context.warning.withValues(alpha: 0.1),
                  child: Text(
                    '${answer.questionNumber}',
                    style: TextStyle(
                      color: context.warning,
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
                        'Q${answer.questionNumber} — No answer detected',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: context.warning,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap to enter what the student wrote',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.lightText,
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
                    color: context.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, size: 14, color: context.warning),
                      const SizedBox(width: 4),
                      Text(
                        'Enter',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.warning,
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
              ? context.primaryGreen.withValues(alpha: 0.1)
              : context.primaryRed.withValues(alpha: 0.1),
          child: Text(
            '${answer.questionNumber}',
            style: TextStyle(
              color: answer.isCorrect
                  ? context.primaryGreen
                  : context.primaryRed,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          '${'Detected'}: ${answer.detectedAnswer}',
          style: TextStyle(
            color: answer.isCorrect ? context.darkText : context.primaryRed,
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
                    color: context.lightText,
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
                      color: context.warning,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${'Low confidence'} (${(answer.confidence * 100).toStringAsFixed(0)}%)',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.warning,
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
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Select Student',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search...',
                prefixIcon: Icon(Icons.search),
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
                        style: TextStyle(color: context.lightText),
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
                                ? context.primaryGreen.withValues(alpha: 0.15)
                                : context.warmGray,
                            child: Text(
                              s.studentId.isNotEmpty ? s.studentId : '${i + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isCurrent
                                    ? context.primaryGreen
                                    : context.lightText,
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
                              ? Icon(
                                  Icons.check_circle,
                                  color: context.primaryGreen,
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
