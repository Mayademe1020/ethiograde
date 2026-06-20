import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/student.dart';
import '../../models/scan_result.dart';
import '../../services/hybrid_grading_service.dart';
import '../../services/assessment_provider.dart';
import '../../services/student_provider.dart';
import '../../widgets/ui_components.dart';

class StudentDetailScreen extends StatefulWidget {
  final Student student;

  const StudentDetailScreen({super.key, required this.student});

  @override
  State<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> {
  List<ScanResult>? _results;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadResults();
  }

  Future<void> _loadResults() async {
    final results =
        await HybridGradingService().getResultsForStudent(widget.student.id);
    if (mounted) {
      setState(() {
        _results = results;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = widget.student;
    final results = _results ?? [];
    final stats = _computeStats(results);

    return Scaffold(
      appBar: AppBar(
        title: Text(student.fullName),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => _editStudent(context),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _deleteStudent(context);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: AppTheme.error, size: 20),
                    SizedBox(width: 8),
                    Text('Delete Student'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildProfileHeader(student, context),
                const SizedBox(height: 16),
                _buildStatsRow(stats),
                const SizedBox(height: 24),
                _buildGradeHistory(context, results),
              ],
            ),
    );
  }

  Widget _buildProfileHeader(Student student, BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.primary.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: cs.primary.withOpacity(0.1),
            child: Text(
              student.fullName.isNotEmpty
                  ? student.fullName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: cs.primary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.fullName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                if (student.studentId.isNotEmpty)
                  Text(
                    'ID: ${student.studentId}',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                if (student.gender.isNotEmpty)
                  Text(
                    student.gender == 'M' ? 'Male' : 'Female',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                if (student.classIds.isNotEmpty)
                  Text(
                    'Class: ${student.className.isNotEmpty ? student.className : student.classIds.first}',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                if (student.parentPhone != null &&
                    student.parentPhone!.isNotEmpty)
                  Text(
                    'Parent: ${student.parentPhone}',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(_StudentStats stats) {
    return Row(
      children: [
        _StatCard(
          label: 'Exams',
          value: '${stats.examCount}',
          icon: Icons.assignment_outlined,
        ),
        const SizedBox(width: 12),
        _StatCard(
          label: 'Average',
          value: stats.examCount > 0
              ? '${stats.average.toStringAsFixed(1)}%'
              : '--',
          icon: Icons.analytics_outlined,
        ),
        const SizedBox(width: 12),
        _StatCard(
          label: 'Top Grade',
          value: stats.topGrade.isNotEmpty ? stats.topGrade : '--',
          icon: Icons.emoji_events_outlined,
        ),
      ],
    );
  }

  Widget _buildGradeHistory(BuildContext context, List<ScanResult> results) {
    if (results.isEmpty) {
      return AppEmptyState(
        icon: Icons.school_outlined,
        title: 'No results yet',
        message: "This student hasn't been graded in any exam.",
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Grade History',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        ...results.map((result) => _ResultRow(
              result: result,
              onTap: () => _openExamResult(context, result),
            )),
      ],
    );
  }

  _StudentStats _computeStats(List<ScanResult> results) {
    if (results.isEmpty) {
      return const _StudentStats(
        examCount: 0,
        average: 0,
        topGrade: '',
      );
    }

    double totalWeighted = 0;
    double totalMax = 0;
    String topGrade = '';
    double highestPct = 0;

    for (final r in results) {
      totalWeighted += r.totalScore;
      totalMax += r.maxScore;
      if (r.percentage > highestPct) {
        highestPct = r.percentage;
        topGrade = r.grade;
      }
    }

    final avg = totalMax > 0 ? (totalWeighted / totalMax) * 100 : 0.0;

    return _StudentStats(
      examCount: results.length,
      average: avg,
      topGrade: topGrade,
    );
  }

  void _openExamResult(BuildContext context, ScanResult result) {
    final assessment = context
        .read<AssessmentProvider>()
        .getAssessmentById(result.assessmentId);
    if (assessment == null) return;

    Navigator.pushNamed(
      context,
      AppRoutes.gradeReview,
      arguments: {
        'assessment': assessment,
        'results': [result],
        'readOnly': true,
      },
    );
  }

  void _editStudent(BuildContext context) async {
    await Navigator.pushNamed(
      context,
      AppRoutes.addStudent,
      arguments: widget.student,
    );
    if (mounted) _loadResults();
  }

  void _deleteStudent(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete Student'),
        content: Text(
          'Remove ${widget.student.fullName}? Their exam results will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await context.read<StudentProvider>().deleteStudent(widget.student.id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

class _StudentStats {
  final int examCount;
  final double average;
  final String topGrade;

  const _StudentStats({
    required this.examCount,
    required this.average,
    required this.topGrade,
  });
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: cs.primary),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final ScanResult result;
  final VoidCallback onTap;

  const _ResultRow({
    required this.result,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final passed = result.percentage >= 50;
    final date = result.scannedAt;
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateStr = '${months[date.month - 1]} ${date.day}, ${date.year}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _assessmentTitle(context),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${result.totalScore.toInt()}/${result.maxScore.toInt()}  •  $dateStr',
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: passed
                        ? AppTheme.primaryGreen.withOpacity(0.1)
                        : AppTheme.primaryRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
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
                Icon(
                  Icons.chevron_right,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _assessmentTitle(BuildContext context) {
    final assessment = context
        .read<AssessmentProvider>()
        .getAssessmentById(result.assessmentId);
    return assessment?.title ?? 'Unknown Exam';
  }
}
