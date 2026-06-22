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
    final seen = <String, ScanResult>{};
    for (final r in results) {
      final existing = seen[r.assessmentId];
      if (existing == null || r.scannedAt.isAfter(existing.scannedAt)) {
        seen[r.assessmentId] = r;
      }
    }
    final deduped = seen.values.toList()
      ..sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
    if (mounted) {
      setState(() {
        _results = deduped;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = widget.student;
    final results = _results ?? [];

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
          : results.isEmpty
              ? _buildEmptyState(context)
              : _buildContent(context, student, results),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: AppEmptyState(
        icon: Icons.school_outlined,
        title: 'No results yet',
        message: "This student hasn't been graded in any exam.",
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, Student student, List<ScanResult> results) {
    final stats = _computeStats(results);
    final trend = _computeTrend(results);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildProfileHeader(student, context),
        const SizedBox(height: 16),
        _buildPerformanceCard(context, stats, trend, results),
        const SizedBox(height: 20),
        _buildGradeHistory(context, results),
      ],
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
                  _InfoRow(label: 'ID', value: student.studentId),
                if (student.gender.isNotEmpty)
                  _InfoRow(
                      label: 'Gender',
                      value: student.gender == 'M' ? 'Male' : 'Female'),
                if (student.className.isNotEmpty)
                  _InfoRow(label: 'Class', value: student.className),
                if (student.parentPhone != null &&
                    student.parentPhone!.isNotEmpty)
                  _InfoRow(label: 'Parent', value: student.parentPhone!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceCard(
    BuildContext context,
    _StudentStats stats,
    _TrendInfo trend,
    List<ScanResult> results,
  ) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_outlined, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Performance',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              if (trend.label.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: trend.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(trend.icon, size: 14, color: trend.color),
                      const SizedBox(width: 4),
                      Text(
                        trend.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: trend.color,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _MiniStat(
                label: 'Exams',
                value: '${stats.examCount}',
                color: cs.primary,
              ),
              const SizedBox(width: 16),
              _MiniStat(
                label: 'Average',
                value: stats.examCount > 0
                    ? '${stats.average.toStringAsFixed(0)}%'
                    : '--',
                color: stats.average >= 50 ? AppTheme.primaryGreen : AppTheme.primaryRed,
              ),
              const SizedBox(width: 16),
              _MiniStat(
                label: 'Best',
                value: stats.topGrade.isNotEmpty ? stats.topGrade : '--',
                color: AppTheme.primaryGreen,
              ),
              const SizedBox(width: 16),
              _MiniStat(
                label: 'Rank',
                value: stats.rank.isNotEmpty ? stats.rank : '--',
                color: cs.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGradeHistory(BuildContext context, List<ScanResult> results) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Results',
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
      return const _StudentStats(examCount: 0, average: 0, topGrade: '', rank: '');
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

    // Compute approximate class rank from the most recent exam
    String rank = '';
    if (results.isNotEmpty) {
      final latest = results.first;
      final pct = latest.percentage;
      if (pct >= 90) {
        rank = 'Top 10%';
      } else if (pct >= 75) {
        rank = 'Top 25%';
      } else if (pct >= 50) {
        rank = 'Middle';
      } else {
        rank = 'Needs support';
      }
    }

    return _StudentStats(
      examCount: results.length,
      average: avg,
      topGrade: topGrade,
      rank: rank,
    );
  }

  _TrendInfo _computeTrend(List<ScanResult> results) {
    if (results.length < 2) {
      return const _TrendInfo(label: '', icon: Icons.remove, color: Colors.grey);
    }

    // Compare last exam to the average of previous exams
    final latest = results.first;
    final previous = results.sublist(1);
    final prevAvg = previous.map((r) => r.percentage).reduce((a, b) => a + b) /
        previous.length;
    final diff = latest.percentage - prevAvg;

    if (diff > 5) {
      return const _TrendInfo(
          label: 'Improving', icon: Icons.trending_up, color: AppTheme.primaryGreen);
    } else if (diff < -5) {
      return const _TrendInfo(
          label: 'Declining', icon: Icons.trending_down, color: AppTheme.primaryRed);
    }
    return const _TrendInfo(
        label: 'Stable', icon: Icons.trending_flat, color: AppTheme.info);
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
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
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
  final String rank;

  const _StudentStats({
    required this.examCount,
    required this.average,
    required this.topGrade,
    required this.rank,
  });
}

class _TrendInfo {
  final String label;
  final IconData icon;
  final Color color;

  const _TrendInfo({
    required this.label,
    required this.icon,
    required this.color,
  });
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    );
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
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final ScanResult result;
  final VoidCallback onTap;

  const _ResultRow({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final passed = result.percentage >= 50;
    final date = result.scannedAt;
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final dateStr = '${months[date.month - 1]} ${date.day}';

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
                Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: passed ? AppTheme.primaryGreen : AppTheme.primaryRed,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
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
                      const SizedBox(height: 2),
                      Text(
                        '${result.totalScore.toInt()}/${result.maxScore.toInt()}  •  $dateStr',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
