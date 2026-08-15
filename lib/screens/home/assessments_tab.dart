import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../config/responsive.dart';
import '../../services/assessment_provider.dart';
import '../../services/hybrid_grading_service.dart';
import '../../models/assessment.dart';
import '../../widgets/assessment_card.dart';
import '../../widgets/ui_components.dart';

class AssessmentsTab extends StatefulWidget {
  const AssessmentsTab({super.key});

  @override
  State<AssessmentsTab> createState() => _AssessmentsTabState();
}

class _AssessmentsTabState extends State<AssessmentsTab> {
  bool _showCompleted = false;

  @override
  Widget build(BuildContext context) {
    final assessments = context.watch<AssessmentProvider>();
    final activeAssessments = assessments.activeAssessments;
    final completedAssessments = assessments.completedAssessments;
    final hp = ResponsiveLayout.horizontalPadding(context);

    final readyAssessments = activeAssessments
        .where((assessment) => assessment.isAnswerKeyComplete)
        .toList(growable: false);
    final setupAssessments = activeAssessments
        .where((assessment) => !assessment.isAnswerKeyComplete)
        .toList(growable: false);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(hp, 20, hp, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assessments',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pushNamed(
                      context,
                      AppRoutes.createAssessment,
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Grade papers'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRoutes.quickGrade),
                    icon: const Icon(Icons.flash_on),
                    label: const Text('Quick Grade'),
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Active'),
                      icon: Icon(Icons.play_circle_outline, size: 18),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Completed'),
                      icon: Icon(Icons.check_circle_outline, size: 18),
                    ),
                  ],
                  selected: {_showCompleted},
                  onSelectionChanged: (selected) =>
                      setState(() => _showCompleted = selected.first),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _showCompleted
                ? _buildCompletedList(context, completedAssessments)
                : _buildActiveList(context, readyAssessments, setupAssessments),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveList(
    BuildContext context,
    List<Assessment> ready,
    List<Assessment> setup,
  ) {
    final hp = ResponsiveLayout.horizontalPadding(context);
    if (ready.isEmpty && setup.isEmpty) {
      return Center(
        child: AppEmptyState(
          icon: Icons.assignment_outlined,
          title: 'No active exams',
          message: 'Create one or check your completed exams.',
          buttonLabel: 'Grade Papers',
          onPressed: () =>
              Navigator.pushNamed(context, AppRoutes.createAssessment),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        if (setup.isNotEmpty) ...[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(hp, 8, hp, 4),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Needs Setup (${setup.length})',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppTheme.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: hp, vertical: 4),
            sliver: SliverList.builder(
              itemCount: setup.length,
              itemBuilder: (_, index) =>
                  AssessmentCard(assessment: setup[index]),
            ),
          ),
        ],
        if (ready.isNotEmpty) ...[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(hp, 16, hp, 4),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Ready to Scan (${ready.length})',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppTheme.primaryGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: hp, vertical: 4),
            sliver: SliverList.builder(
              itemCount: ready.length,
              itemBuilder: (_, index) =>
                  AssessmentCard(assessment: ready[index]),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCompletedList(BuildContext context, List<Assessment> completed) {
    final hp = ResponsiveLayout.horizontalPadding(context);
    if (completed.isEmpty) {
      return const Center(
        child: AppEmptyState(
          icon: Icons.check_circle_outline,
          title: 'No completed exams yet',
          message: 'Grade your first exam to see results here.',
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(hp, 8, hp, 4),
          sliver: SliverToBoxAdapter(
            child: Text(
              'Completed (${completed.length})',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppTheme.primaryGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: hp, vertical: 4),
          sliver: SliverList.builder(
            itemCount: completed.length,
            itemBuilder: (_, index) => AssessmentCard(
              assessment: completed[index],
              onTap: () => _openCompletedExam(context, completed[index]),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
      ],
    );
  }

  void _openCompletedExam(BuildContext context, Assessment assessment) async {
    final results = await HybridGradingService().loadScanResults(assessment.id);

    if (!context.mounted) return;

    Navigator.pushNamed(
      context,
      AppRoutes.gradeReview,
      arguments: {
        'assessment': assessment,
        'results': results,
        'readOnly': true,
      },
    );
  }
}
