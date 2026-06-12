import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../services/assessment_provider.dart';
import '../../models/assessment.dart';
import '../../widgets/assessment_card.dart';
import '../../widgets/product_components.dart';

class AssessmentsTab extends StatelessWidget {
  const AssessmentsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final assessments = context.watch<AssessmentProvider>();
    final readyAssessments = assessments.activeAssessments
        .where((assessment) => assessment.isAnswerKeyComplete)
        .toList(growable: false);
    final setupAssessments = assessments.activeAssessments
        .where((assessment) => !assessment.isAnswerKeyComplete)
        .toList(growable: false);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
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
              ],
            ),
          ),
          Expanded(
            child: assessments.activeAssessments.isEmpty
                ? _buildEmptyState(context)
                : _buildAssessmentList(
                    context,
                    readyAssessments,
                    setupAssessments,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: AppEmptyState(
        icon: Icons.assignment_outlined,
        title: 'No assessments yet',
        message: 'Create your first assessment to start grading',
        buttonLabel: 'Grade Papers',
        onPressed: () =>
            Navigator.pushNamed(context, AppRoutes.createAssessment),
      ),
    );
  }

  Widget _buildAssessmentList(
    BuildContext context,
    List<Assessment> ready,
    List<Assessment> setup,
  ) {
    return CustomScrollView(
      slivers: [
        if (setup.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            sliver: SliverList.builder(
              itemCount: setup.length,
              itemBuilder: (_, index) => AssessmentCard(
                assessment: setup[index],
              ),
            ),
          ),
        ],
        if (ready.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            sliver: SliverList.builder(
              itemCount: ready.length,
              itemBuilder: (_, index) => AssessmentCard(
                assessment: ready[index],
              ),
            ),
          ),
        ],
        if (ready.isEmpty && setup.isEmpty)
          SliverFillRemaining(
            child: _buildEmptyState(context),
          ),
      ],
    );
  }
}
