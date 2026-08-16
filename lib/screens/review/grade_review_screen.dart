import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/scan_result.dart';
import '../../models/assessment.dart';
import '../../models/weighted_grade.dart';
import '../../models/student.dart';
import '../../services/draft_service.dart';
import '../../services/audit_service.dart';
import '../../services/teacher_provider.dart';
import '../../services/weighted_grade_provider.dart';
import '../../services/weighted_grade_service.dart';
import '../../services/class_provider.dart';
import '../../services/student_provider.dart';
import '../../services/voice_service.dart';
import '../../services/settings_provider.dart';
import '../../services/assessment_completion_gate.dart';
import '../../services/results_pdf_service.dart';
import '../analytics/item_analysis_screen.dart';

/// Summary screen shown after completing grade entry, before final submit.
///
/// Shows:
/// - Table of all students with scores and grades
/// - Class statistics (average, median, pass rate)
/// - Highlights: highest, lowest
/// - Edit button per row
/// - Confirm & Save button
///
/// After confirm: creates audit entries, clears draft, pops with results.
class GradeReviewScreen extends StatefulWidget {
  final Assessment assessment;
  final List<ScanResult> results;
  final bool readOnly;

  const GradeReviewScreen({
    super.key,
    required this.assessment,
    required this.results,
    this.readOnly = false,
  });

  @override
  State<GradeReviewScreen> createState() => _GradeReviewScreenState();
}

class _GradeReviewScreenState extends State<GradeReviewScreen> {
  final VoiceService _voice = VoiceService();
  bool _isReading = false;
  int _readingIndex = -1;

  Assessment get assessment => widget.assessment;
  List<ScanResult> get results => widget.results;

  Future<void> _readAllScores() async {
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

  Future<void> _exportPdf(BuildContext context) async {
    try {
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
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Compute stats
    final percentages = results.map((r) => r.percentage).toList()..sort();
    final avg = percentages.isNotEmpty
        ? percentages.reduce((a, b) => a + b) / percentages.length
        : 0.0;
    final median = percentages.isNotEmpty ? _median(percentages) : 0.0;
    final passCount = results.where((r) => r.percentage >= 50).length;
    final passRate = results.isNotEmpty
        ? passCount / results.length * 100
        : 0.0;
    final highest = percentages.isNotEmpty ? percentages.last : 0.0;
    final lowest = percentages.isNotEmpty ? percentages.first : 0.0;

    // Find highest/lowest students
    ScanResult? highestStudent;
    ScanResult? lowestStudent;
    if (results.isNotEmpty) {
      highestStudent = results.reduce(
        (a, b) => a.percentage > b.percentage ? a : b,
      );
      lowestStudent = results.reduce(
        (a, b) => a.percentage < b.percentage ? a : b,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.readOnly ? 'Results' : 'Review & Confirm'),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            onPressed: results.isNotEmpty
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ItemAnalysisScreen(
                          assessment: assessment,
                          results: results,
                        ),
                      ),
                    )
                : null,
            tooltip: 'Item Analysis',
          ),
          IconButton(
            icon: Icon(
              _isReading ? Icons.stop_circle : Icons.volume_up,
              color: _isReading ? AppTheme.primaryRed : null,
            ),
            onPressed: results.isNotEmpty ? _readAllScores : null,
            tooltip: _isReading ? 'Stop' : 'Read All Scores',
          ),
          if (results.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              onPressed: () => _exportPdf(context),
              tooltip: 'Export PDF',
            ),
        ],
      ),
      body: results.isEmpty
          ? const Center(
              child: Text(
                'No results to review',
                style: TextStyle(color: AppTheme.lightText),
              ),
            )
          : Column(
              children: [
                // Stats summary
                _StatsHeader(
                  average: avg,
                  median: median,
                  passRate: passRate,
                  passCount: passCount,
                  total: results.length,
                  highest: highest,
                  lowest: lowest,
                ),
                const Divider(height: 1),
                // Weighted composite grade banner (if configured)
                if (assessment.weightedScaleId != null)
                  _WeightedGradeBanner(assessment: assessment),
                // Student table
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: results.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, index) {
                      final result = results[index];
                      final isHighest = result == highestStudent;
                      final isLowest = result == lowestStudent;
                      return _StudentRow(
                        result: result,
                        rank: index + 1,
                        isHighest: isHighest,
                        isLowest: isLowest,
                        isReading: index == _readingIndex,
                        readOnly: widget.readOnly,
                        onEdit: () => Navigator.pop(context, result),
                      );
                    },
                  ),
                ),
                // Confirm button (hidden in read-only mode)
                if (!widget.readOnly)
                  SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: () => _confirmAndSave(context),
                        icon: const Icon(Icons.check_circle),
                        label: const Text(
                          'Confirm & Save',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  void _confirmAndSave(BuildContext context) async {
    // Check completion gate before saving
    const gate = AssessmentCompletionGate();
    final check = gate.check(assessment: assessment, results: results);

    if (!check.isReady) {
      final blockingLabels = check.blocking.map((i) => '• ${i.label}').join('\n');
      if (context.mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Issues remain'),
            content: Text(
              'The following blocking issues exist:\n\n$blockingLabels\n\n'
              'Save anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save anyway'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
    }

    // Pull real teacher identity from TeacherProvider
    final teacher = context.read<TeacherProvider>().activeTeacher;
    final teacherName = teacher?.name ?? ('Unknown Teacher');
    final teacherId = teacher?.id ?? 'unknown';

    for (final result in results) {
      await AuditService().recordCreated(
        result: result,
        teacherId: teacherId,
        teacherName: teacherName,
      );
    }

    // Clear the grading draft
    await DraftService().clearDraft(assessment.id);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${results.length} results saved'),
          backgroundColor: AppTheme.primaryGreen,
        ),
      );
      // Pop with results to indicate success
      Navigator.pop(context, results);
    }
  }

  double _median(List<double> sorted) {
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }
}

/// Stats summary header at the top of the review screen.
class _StatsHeader extends StatelessWidget {
  final double average;
  final double median;
  final double passRate;
  final int passCount;
  final int total;
  final double highest;
  final double lowest;
  const _StatsHeader({
    required this.average,
    required this.median,
    required this.passRate,
    required this.passCount,
    required this.total,
    required this.highest,
    required this.lowest,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey.shade50,
      child: Column(
        children: [
          Row(
            children: [
              _StatChip(
                label: 'Average',
                value: '${average.toStringAsFixed(1)}%',
                color: AppTheme.info,
              ),
              const SizedBox(width: 8),
              _StatChip(
                label: 'Median',
                value: '${median.toStringAsFixed(1)}%',
                color: AppTheme.info,
              ),
              const SizedBox(width: 8),
              _StatChip(
                label: 'Pass',
                value: '$passCount/$total (${passRate.toStringAsFixed(0)}%)',
                color: passRate >= 50
                    ? AppTheme.primaryGreen
                    : AppTheme.primaryRed,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _StatChip(
                label: 'Highest',
                value: '${highest.toStringAsFixed(1)}%',
                color: AppTheme.primaryGreen,
              ),
              const SizedBox(width: 8),
              _StatChip(
                label: 'Lowest',
                value: '${lowest.toStringAsFixed(1)}%',
                color: AppTheme.primaryRed,
              ),
              const SizedBox(width: 8),
              _StatChip(
                label: 'Total',
                value: '$total',
                color: AppTheme.darkText,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: color)),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single row in the student review table.
class _StudentRow extends StatelessWidget {
  final ScanResult result;
  final int rank;
  final bool isHighest;
  final bool isLowest;
  final bool isReading;
  final bool readOnly;
  final VoidCallback onEdit;

  const _StudentRow({
    required this.result,
    required this.rank,
    required this.isHighest,
    required this.isLowest,
    this.isReading = false,
    this.readOnly = false,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final passed = result.percentage >= 50;
    final highlightColor = isHighest
        ? AppTheme.primaryGreen
        : isLowest
        ? AppTheme.primaryRed
        : null;

    return ColoredBox(
      color: isReading ? AppTheme.info.withValues(alpha: 0.06) : Colors.transparent,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (highlightColor ?? AppTheme.lightText).withValues(alpha: 
            0.1,
          ),
          child: isReading
              ? const Icon(Icons.volume_up, color: AppTheme.info, size: 20)
              : Text(
                  '$rank',
                  style: TextStyle(
                    color: highlightColor ?? AppTheme.darkText,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                result.studentName,
                style: TextStyle(
                  fontWeight: isHighest || isLowest
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ),
            if (isHighest)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Top',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.primaryGreen,
                  ),
                ),
              ),
            if (isLowest)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Low',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.primaryRed,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${result.totalScore.toInt()}/${result.maxScore.toInt()}',
          style: const TextStyle(fontSize: 12, color: AppTheme.lightText),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: passed
                    ? AppTheme.primaryGreen.withValues(alpha: 0.1)
                    : AppTheme.primaryRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    result.grade,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: passed
                          ? AppTheme.primaryGreen
                          : AppTheme.primaryRed,
                    ),
                  ),
                  Text(
                    '${result.percentage.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 11,
                      color: passed
                          ? AppTheme.primaryGreen
                          : AppTheme.primaryRed,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!readOnly)
              IconButton(
                icon: const Icon(Icons.edit, size: 18, color: AppTheme.lightText),
                onPressed: onEdit,
                tooltip: 'Edit',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
    );
  }
}

/// Banner showing weighted composite grade status for assessments with weighted scoring.
///
/// When the assessment has a [weightedScaleId], this widget:
/// - Shows the weight configuration (e.g., "Quiz 20% + Midterm 30% + Final 50%")
/// - Computes and displays composite grades when all component data is available
/// - Shows which components are still pending
class _WeightedGradeBanner extends StatelessWidget {
  final Assessment assessment;
  const _WeightedGradeBanner({required this.assessment});

  @override
  Widget build(BuildContext context) {
    final weightedProvider = context.watch<WeightedGradeProvider>();
    final scale = assessment.weightedScaleId != null
        ? weightedProvider.getForExam(assessment.id)
        : null;

    if (scale == null) {
      return const SizedBox.shrink();
    }

    // Show weight configuration
    final weightSummary = scale.components
        .map((c) => '${c.getDisplayName()} ${(c.weight * 100).toInt()}%')
        .join(' + ');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.info.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.info.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.balance, size: 18, color: AppTheme.info),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Weighted Composite Grade',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.info,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            weightSummary,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
          // Composite grades via FutureBuilder
          FutureBuilder<List<CompositeGrade>?>(
            future: _loadCompositeGrades(context, weightedProvider),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                );
              }

              final grades = snapshot.data;
              if (grades == null || grades.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Composite grades appear once all components are graded',
                    style: TextStyle(fontSize: 11, color: AppTheme.lightText),
                  ),
                );
              }

              // Show composite stats
              const service = WeightedGradeService();
              final stats = service.computeClassStats(grades);
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _CompositeStat(
                      label: 'Average',
                      value: '${stats.average.toStringAsFixed(1)}%',
                    ),
                    _CompositeStat(
                      label: 'Pass Rate',
                      value: '${stats.passRate.toStringAsFixed(0)}%',
                    ),
                    _CompositeStat(
                      label: 'Students',
                      value: '${stats.studentCount}',
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<List<CompositeGrade>?> _loadCompositeGrades(
    BuildContext context,
    WeightedGradeProvider provider,
  ) async {
    // Get students for the class
    final classProvider = context.read<ClassProvider>();
    final studentProvider = context.read<StudentProvider>();
    final classId = assessment.className.isNotEmpty ? assessment.className : '';

    // Find students — use class if available, otherwise all students
    List<Student> students;
    if (classId.isNotEmpty) {
      final cls = classProvider.classes
          .where((c) => c.id == classId || c.displayName == classId)
          .firstOrNull;
      students = cls != null
          ? studentProvider.studentsByClassId(cls.id)
          : studentProvider.students;
    } else {
      students = studentProvider.students;
    }

    return provider.computeForExam(examId: assessment.id, students: students);
  }
}

/// Small stat display for composite grade summary.
class _CompositeStat extends StatelessWidget {
  final String label;
  final String value;
  const _CompositeStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: AppTheme.info,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.lightText)),
      ],
    );
  }
}
