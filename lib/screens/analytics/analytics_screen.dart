import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/scan_result.dart';
import '../../services/analytics_service.dart';
import '../../services/assessment_provider.dart';
import '../../services/hybrid_grading_service.dart';
import '../../services/student_provider.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _analytics = const AnalyticsService();
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final assessments = context.watch<AssessmentProvider>();
    final students = context.watch<StudentProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Class Analytics'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                _TabButton(
                  label: 'Overview',
                  selected: _selectedIndex == 0,
                  onTap: () => setState(() => _selectedIndex = 0),
                ),
                const SizedBox(width: AppSpacing.sm),
                _TabButton(
                  label: 'At-Risk',
                  selected: _selectedIndex == 1,
                  onTap: () => setState(() => _selectedIndex = 1),
                ),
                const SizedBox(width: AppSpacing.sm),
                _TabButton(
                  label: 'Trends',
                  selected: _selectedIndex == 2,
                  onTap: () => setState(() => _selectedIndex = 2),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<List<ScanResult>>(
          future: HybridGradingService().loadAllScanResults(),
          builder: (context, snapshot) {
            final allResults = snapshot.data ?? <ScanResult>[];
            return IndexedStack(
              index: _selectedIndex,
              children: [
                _OverviewTab(analytics: _analytics, assessments: assessments, allResults: allResults),
                _AtRiskTab(analytics: _analytics, assessments: assessments, students: students, allResults: allResults),
                _TrendsTab(analytics: _analytics, assessments: assessments, students: students, allResults: allResults),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? cs.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? cs.onPrimary : cs.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final AnalyticsService analytics;
  final AssessmentProvider assessments;
  final List<ScanResult> allResults;

  const _OverviewTab({
    required this.analytics,
    required this.assessments,
    required this.allResults,
  });

  @override
  Widget build(BuildContext context) {
    if (assessments.assessments.isEmpty) {
      return const _EmptyState(
        icon: Icons.analytics_outlined,
        message: 'No assessments yet. Create an assessment to see analytics.',
      );
    }

    final subjects = analytics.computeBySubject(
      assessments: assessments.assessments,
      allResults: allResults,
    );

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          'Subject Performance',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ...subjects.map((s) => _SubjectCard(subject: s)),
      ],
    );
  }
}

class _SubjectCard extends StatelessWidget {
  final SubjectPerformance subject;

  const _SubjectCard({required this.subject});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject.subject,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${subject.assessmentCount} results',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                '${subject.classAverage.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AtRiskTab extends StatelessWidget {
  final AnalyticsService analytics;
  final AssessmentProvider assessments;
  final StudentProvider students;
  final List<ScanResult> allResults;

  const _AtRiskTab({
    required this.analytics,
    required this.assessments,
    required this.students,
    required this.allResults,
  });

  @override
  Widget build(BuildContext context) {
    if (assessments.assessments.isEmpty) {
      return const _EmptyState(
        icon: Icons.warning_amber_outlined,
        message: 'No data. Create assessments to identify at-risk students.',
      );
    }

    final atRisk = analytics.findAtRiskStudents(
      assessments: assessments.assessments,
      allResults: allResults,
      students: students.students,
    );

    if (atRisk.isEmpty) {
      return const _EmptyState(
        icon: Icons.check_circle_outline,
        message: 'No at-risk students detected. Great job!',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: context.errorContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber, color: context.error),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${atRisk.length} student(s) need attention',
                  style: TextStyle(
                    color: context.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ...atRisk.map((s) => _AtRiskCard(student: s)),
      ],
    );
  }
}

class _AtRiskCard extends StatelessWidget {
  final AtRiskStudent student;

  const _AtRiskCard({required this.student});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: context.errorContainer,
              child: Text(
                student.student.fullName[0].toUpperCase(),
                style: TextStyle(
                  color: context.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.student.fullName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    student.reason,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.error,
                        ),
                  ),
                ],
              ),
            ),
            Text(
              '${student.averagePercentage.toStringAsFixed(0)}%',
              style: TextStyle(
                color: context.error,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendsTab extends StatelessWidget {
  final AnalyticsService analytics;
  final AssessmentProvider assessments;
  final StudentProvider students;
  final List<ScanResult> allResults;

  const _TrendsTab({
    required this.analytics,
    required this.assessments,
    required this.students,
    required this.allResults,
  });

  @override
  Widget build(BuildContext context) {
    if (assessments.assessments.length < 2) {
      return const _EmptyState(
        icon: Icons.trending_up,
        message: 'Need at least 2 assessments to show trends.',
      );
    }

    final trends = analytics.computeTrends(
      assessments: assessments.assessments,
      allResults: allResults,
      students: students.students,
    );

    if (trends.isEmpty) {
      return const _EmptyState(
        icon: Icons.people_outline,
        message: 'No student has enough data for trend analysis.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          'Student Trends',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ...trends.map((t) => _TrendCard(trend: t)),
      ],
    );
  }
}

class _TrendCard extends StatelessWidget {
  final StudentTrend trend;

  const _TrendCard({required this.trend});

  @override
  Widget build(BuildContext context) {
    final directionIcon = switch (trend.direction) {
      TrendDirection.improving => Icons.trending_up,
      TrendDirection.declining => Icons.trending_down,
      TrendDirection.stable => Icons.trending_flat,
    };

    final directionColor = switch (trend.direction) {
      TrendDirection.improving => AppTheme.success,
      TrendDirection.declining => context.error,
      TrendDirection.stable => context.lightText,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: directionColor.withValues(alpha: 0.1),
              child: Icon(directionIcon, color: directionColor),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trend.studentName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${trend.points.length} assessments',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(
              trend.direction.name,
              style: TextStyle(
                color: directionColor,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: context.lightText),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.lightText),
            ),
          ],
        ),
      ),
    );
  }
}
