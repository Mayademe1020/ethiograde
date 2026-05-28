import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/assessment.dart';
import '../../services/draft_service.dart';
import '../../services/assessment_provider.dart';

import '../../models/scan_result.dart';

/// Banner shown on the dashboard when a grading draft exists.
///
/// "Resume grading? [Class] - [Exam] • 15/30 graded • 2 hours ago"
///
/// Tap → navigates to the grading screen pre-filled with draft data.
/// Swipe/dismiss → "Discard draft?" confirmation.
/// Auto-clears when grading is completed and submitted.
class ResumeGradingBanner extends StatefulWidget {
  const ResumeGradingBanner({super.key});

  @override
  State<ResumeGradingBanner> createState() => _ResumeGradingBannerState();
}

class _ResumeGradingBannerState extends State<ResumeGradingBanner> {
  GradingDraft? _draft;
  Assessment? _assessment;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _checkForDraft();
  }

  void _checkForDraft() {
    final drafts = DraftService().getAllDrafts();
    if (drafts.isEmpty) return;

    final draft = drafts.first; // Most recent
    final assessment = context
        .read<AssessmentProvider>()
        .getAssessmentById(draft.assessmentId);

    // Only show if assessment still exists and draft is < 7 days old
    if (assessment != null && draft.age.inDays < 7) {
      setState(() {
        _draft = draft;
        _assessment = assessment;
      });
    }
  }

  void _resumeGrading() {
    if (_draft == null || _assessment == null) return;

    // Parse completed scan results from draft
    final completedResults = _draft!.completedResults
        .map((m) => ScanResult.fromMap(Map<String, dynamic>.from(m)))
        .toList();

    Navigator.pushNamed(
      context,
      AppRoutes.batchScan,
      arguments: {
        'assessment': _assessment,
        'draftCompletedResults': completedResults,
        'draftCurrentIndex': _draft!.currentStudentIndex,
      });
  }

  void _dismissWithConfirm() async {

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Discard Draft?'),
        content: Text(
          "${_draft!.completedCount} graded results will be lost. This cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: Text('Discard')),
        ]));

    if (confirm == true && mounted) {
      await DraftService().clearDraft(_draft!.assessmentId);
      setState(() {
        _dismissed = true;
        _draft = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_draft == null || _assessment == null || _dismissed) {
      return const SizedBox.shrink();
    }

    final assessment = _assessment!;
    final draft = _draft!;

    return Dismissible(
      key: ValueKey(draft.assessmentId),
      direction: DismissDirection.horizontal,
      confirmDismiss: (_) async {
        _dismissWithConfirm();
        return false; // Don't actually dismiss — we handle it in the dialog
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primaryGreen.withOpacity(0.08),
              AppTheme.info.withOpacity(0.08),
            ]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.3))),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _resumeGrading,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12)),
                    child: const Icon(
                      Icons.play_circle_fill,
                      color: AppTheme.primaryGreen,
                      size: 24)),
                  const SizedBox(width: 12),
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resume grading?',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(
                          '${assessment.className.isNotEmpty ? "${assessment.className} — " : ""}${assessment.title}',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.darkText),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 12,
                              color: AppTheme.lightText),
                            const SizedBox(width: 4),
                            Text(
                              "${draft.completedCount} graded",
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.lightText)),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.access_time,
                              size: 12,
                              color: AppTheme.lightText),
                            const SizedBox(width: 4),
                            Text(
                              draft.ageLabel,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.lightText)),
                          ]),
                      ])),
                  // Arrow
                  Icon(
                    Icons.chevron_right,
                    color: AppTheme.primaryGreen,
                    size: 24),
                ]))))));
  }
}
