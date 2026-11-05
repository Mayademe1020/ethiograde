import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/assessment.dart';
import '../../models/scan_result.dart';
import '../../services/class_provider.dart';
import '../../services/hybrid_grading_service.dart';
import '../../services/draft_service.dart';
import '../../services/error_handler.dart';
import '../../screens/home/dashboard_actions.dart';

class AssessmentCard extends StatelessWidget {
  final Assessment assessment;
  final List<ScanResult>? results;
  final VoidCallback? onTap;

  const AssessmentCard({
    super.key,
    required this.assessment,
    this.results,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final resolved = resolveOperationalStatus(assessment);
    final (statusColor, statusIcon) = switch (resolved.status) {
      OperationalStatus.setupIncomplete => (
        context.warning,
        Icons.help_outline,
      ),
      OperationalStatus.readyToGrade => (
        AppTheme.success,
        Icons.radio_button_on,
      ),
      OperationalStatus.gradingInProgress => (AppTheme.info, Icons.sync),
      OperationalStatus.graded => (
        AppTheme.success,
        Icons.check_circle_outline,
      ),
    };

    final action = resolveAssessmentAction(
      assessment: assessment,
      results: results,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: InkWell(
          onTap: onTap ?? () => _openAction(context, action),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              children: [
                // ── Top accent bar (coloured by status) ──────────────
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.xl),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Title row ──────────────────────────────────
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  assessment.title,
                                  style: tt.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (assessment.subject.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    assessment.subject,
                                    style: tt.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          // Status badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(
                                AppRadius.full,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(statusIcon, size: 11, color: statusColor),
                                const SizedBox(width: 4),
                                Text(
                                  resolved.label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: statusColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.sm + 2),

                      // ── Metadata row ───────────────────────────────
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: 4,
                        children: [
                          _MetaBadge(
                            icon: Icons.help_outline,
                            label: '${assessment.questionCount} Q',
                            color: cs.onSurfaceVariant,
                          ),
                          _MetaBadge(
                            icon: Icons.star_border_rounded,
                            label: '${assessment.maxScore.toInt()} pts',
                            color: cs.onSurfaceVariant,
                          ),
                          if (assessment.className.isNotEmpty) ...[
                            _MetaBadge(
                              icon: Icons.class_outlined,
                              label: assessment.className,
                              color: cs.onSurfaceVariant,
                            ),
                          ],
                          // Academic year from class
                          if (assessment.className.isNotEmpty) ...[
                            Builder(
                              builder: (context) {
                                final classProv = context.read<ClassProvider>();
                                final cls = classProv.classes.isNotEmpty
                                    ? classProv.classes.firstWhere(
                                        (c) => c.name == assessment.className,
                                        orElse: () => classProv.classes.last,
                                      )
                                    : null;
                                if (cls == null || cls.academicYear.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                return _MetaBadge(
                                  icon: Icons.calendar_today_outlined,
                                  label: cls.academicYear,
                                  color: cs.onSurfaceVariant,
                                );
                              },
                            ),
                          ],
                        ],
                      ),

                      // ── Question type pills ────────────────────────
                      if (assessment.mcqCount > 0 ||
                          assessment.trueFalseCount > 0 ||
                          assessment.shortAnswerCount > 0 ||
                          assessment.essayCount > 0) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: [
                            if (assessment.mcqCount > 0)
                              _TypePill(
                                label: 'MCQ ${assessment.mcqCount}',
                                color: AppTheme.success,
                              ),
                            if (assessment.trueFalseCount > 0)
                              _TypePill(
                                label: 'T/F ${assessment.trueFalseCount}',
                                color: AppTheme.info,
                              ),
                            if (assessment.shortAnswerCount > 0)
                              _TypePill(
                                label: 'Short ${assessment.shortAnswerCount}',
                                color: context.warning,
                              ),
                            if (assessment.essayCount > 0)
                              _TypePill(
                                label: 'Essay ${assessment.essayCount}',
                                color: context.error,
                              ),
                          ],
                        ),
                      ],

                      // ── Answer key status ──────────────────────────
                      if (assessment.questions.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _AnswerKeyBar(assessment: assessment),
                      ],
                      const SizedBox(height: AppSpacing.sm),

                      // ── Next action ──────────────────────────
                      _NextActionCard(
                        action: action,
                        onTap: () => _openAction(context, action),
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

  void _openAction(BuildContext context, AssessmentAction action) {
    switch (action.kind) {
      case AssessmentActionKind.reviewPapers:
        _openReview(context);
      case AssessmentActionKind.addAnswerKey:
        Navigator.pushNamed(
          context,
          AppRoutes.answerKey,
          arguments: assessment,
        );
      case AssessmentActionKind.scanPapers:
        Navigator.pushNamed(context, AppRoutes.camera);
      case AssessmentActionKind.resumeGrading:
        _resumeGrading(context);
      case AssessmentActionKind.viewResults:
        _openResults(context);
    }
  }

  Future<void> _openReview(BuildContext context) async {
    final loaded =
        results ??
        await HybridGradingService().loadScanResults(
          assessment.id,
          throwOnError: true,
        );
    if (!context.mounted) return;
    Navigator.pushNamed(context, AppRoutes.review, arguments: loaded);
  }

  Future<void> _resumeGrading(BuildContext context) async {
    try {
      final drafts = await DraftService().getAllDrafts(throwOnError: true);
      if (!context.mounted) return;
      final matches = drafts.where((d) => d.assessmentId == assessment.id);
      if (matches.isEmpty) {
        Navigator.pushNamed(context, AppRoutes.review, arguments: results);
        return;
      }
      final draft = matches.first;
      final completedResults = draft.completedResults
          .map((m) => ScanResult.fromMap(Map<String, dynamic>.from(m)))
          .toList();
      Navigator.pushNamed(
        context,
        AppRoutes.batchScan,
        arguments: {
          'assessment': assessment,
          'draftCompletedResults': completedResults,
          'draftCurrentIndex': draft.currentStudentIndex,
        },
      );
    } catch (e, st) {
      AppErrorHandler.catchError(this, '_resumeGrading', e, st);
      if (context.mounted) {
        _showLoadError(context);
      }
    }
  }

  Future<void> _openResults(BuildContext context) async {
    try {
      final loaded =
          results ??
          await HybridGradingService().loadScanResults(
            assessment.id,
            throwOnError: true,
          );
      if (!context.mounted) return;
      Navigator.pushNamed(
        context,
        AppRoutes.gradeReview,
        arguments: {
          'assessment': assessment,
          'results': loaded,
          'readOnly': true,
        },
      );
    } catch (e, st) {
      AppErrorHandler.catchError(this, '_openResults', e, st);
      if (context.mounted) {
        _showLoadError(context);
      }
    }
  }

  void _showLoadError(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Couldn\'t load this exam\'s saved data. Please try again.',
        ),
        backgroundColor: context.error,
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _MetaBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _TypePill extends StatelessWidget {
  final String label;
  final Color color;

  const _TypePill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Thin progress bar showing how complete the answer key is.
class _AnswerKeyBar extends StatelessWidget {
  final Assessment assessment;

  const _AnswerKeyBar({required this.assessment});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final complete = assessment.isAnswerKeyComplete;
    final ratio = assessment.answerKeyCompleteness;

    final color = complete
        ? AppTheme.success
        : ratio > 0.5
        ? context.warning
        : cs.onSurfaceVariant;

    final icon = complete
        ? Icons.check_circle_outline
        : ratio > 0
        ? Icons.pending_outlined
        : Icons.radio_button_unchecked;

    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 4,
              backgroundColor: cs.outlineVariant,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          assessment.answerKeyStatus,
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _NextActionCard extends StatelessWidget {
  final AssessmentAction action;
  final VoidCallback onTap;

  const _NextActionCard({required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, color) = switch (action.kind) {
      AssessmentActionKind.reviewPapers => (
        Icons.fact_check_outlined,
        context.warning,
      ),
      AssessmentActionKind.addAnswerKey => (
        Icons.edit_note_outlined,
        context.warning,
      ),
      AssessmentActionKind.scanPapers => (
        Icons.document_scanner_outlined,
        context.primaryGreen,
      ),
      AssessmentActionKind.resumeGrading => (
        Icons.play_circle_outline,
        AppTheme.info,
      ),
      AssessmentActionKind.viewResults => (
        Icons.bar_chart_outlined,
        AppTheme.success,
      ),
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  Text(
                    action.description,
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: color),
          ],
        ),
      ),
    );
  }
}
