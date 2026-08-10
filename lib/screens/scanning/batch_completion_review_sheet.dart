import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/responsive.dart';
import '../../models/assessment.dart';
import '../../models/scan_result.dart';
import '../../models/student.dart';
import '../../services/batch_review_service.dart';
import '../../services/scoring_service.dart';
import '../../services/student_provider.dart';
import '../../widgets/batch_review_widgets.dart';

/// Shows the batch completion review bottom sheet.
///
/// Returns `true` if teacher taps "Review", `false` for "Scan later",
/// or `null` if dismissed.
Future<bool?> showBatchCompletionReview({
  required BuildContext context,
  required List<ScanResult> results,
  required List<AnswerDuplicate> duplicates,
  required String? classId,
  required Assessment? assessment,
  required bool noRoster,
  required void Function(List<ScanResult> updated) onResultsChanged,
  required void Function(int resultIndex) onAssignStudent,
}) {
  const review = BatchReviewService();

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, sheetSetState) {
        final students = context.read<StudentProvider>().studentsByClassId(
          classId,
        );
        final summary = review.summarize(
          results: results,
          roster: students,
          duplicateCount: duplicates.length,
          noRoster: noRoster,
        );

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              ResponsiveLayout.horizontalPadding(context), 12,
              ResponsiveLayout.horizontalPadding(context), 20,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.86,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  const SizedBox(height: 18),
                  Text(
                    'Review before saving',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    noRoster
                        ? 'These papers can stay as Paper 1, Paper 2, and so on. Assign names later if needed.'
                        : 'Choose what happened before results are saved. Nothing is silently marked zero.',
                    style: const TextStyle(color: AppTheme.lightText, height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  BatchReviewMetric(
                    icon: Icons.fact_check_outlined,
                    label: 'Scanned papers',
                    value: '${summary.scannedPapers}',
                    color: AppTheme.primaryGreen,
                  ),
                  BatchReviewMetric(
                    icon: Icons.report_gmailerrorred_outlined,
                    label: 'Papers needing action',
                    value: '${summary.papersNeedingAction}',
                    color: summary.papersNeedingAction == 0
                        ? AppTheme.primaryGreen
                        : AppTheme.warning,
                  ),
                  BatchReviewMetric(
                    icon: Icons.copy_all_outlined,
                    label: 'Possible duplicates',
                    value: '${summary.possibleDuplicates}',
                    color: summary.possibleDuplicates == 0
                        ? AppTheme.primaryGreen
                        : AppTheme.primaryRed,
                  ),
                  if (!noRoster)
                    BatchReviewMetric(
                      icon: Icons.person_search_outlined,
                      label: 'Missing students',
                      value: '${summary.missingStudents.length}',
                      color: summary.missingStudents.isEmpty
                          ? AppTheme.primaryGreen
                          : AppTheme.warning,
                    ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (summary.missingStudents.isNotEmpty)
                            MissingStudentActions(
                              students: summary.missingStudents,
                              onMarkAbsent: (student) {
                                if (assessment == null) return;
                                final updated = review.appendIfMissingStudent(
                                  results,
                                  review.markAbsent(
                                    assessment: assessment,
                                    student: student,
                                  ),
                                );
                                onResultsChanged(updated);
                                sheetSetState(() {});
                              },
                              onLeaveUngraded: (student) {
                                if (assessment == null) return;
                                final updated = review.appendIfMissingStudent(
                                  results,
                                  review.leaveUngraded(
                                    assessment: assessment,
                                    student: student,
                                  ),
                                );
                                onResultsChanged(updated);
                                sheetSetState(() {});
                              },
                              onManualEntry: (student) {
                                if (assessment == null) return;
                                final updated = review.appendIfMissingStudent(
                                  results,
                                  review.needsManualEntry(
                                    assessment: assessment,
                                    student: student,
                                  ),
                                );
                                onResultsChanged(updated);
                                sheetSetState(() {});
                              },
                            ),
                          if (duplicates.isNotEmpty)
                            DuplicateActions(
                              duplicates: duplicates,
                              results: results,
                              onKeepBoth: (duplicate) {
                                final updated = List<ScanResult>.from(results);
                                if (duplicate.scanIndexA < updated.length) {
                                  updated[duplicate.scanIndexA] =
                                      review.markDuplicateReviewed(
                                        updated[duplicate.scanIndexA],
                                      );
                                }
                                if (duplicate.scanIndexB < updated.length) {
                                  updated[duplicate.scanIndexB] =
                                      review.markDuplicateReviewed(
                                        updated[duplicate.scanIndexB],
                                      );
                                }
                                onResultsChanged(updated);
                                sheetSetState(() {});
                              },
                              onKeepFirst: (duplicate) {
                                final updated = review.removeAt(
                                  results,
                                  duplicate.scanIndexB,
                                );
                                onResultsChanged(updated);
                                sheetSetState(() {});
                              },
                              onKeepSecond: (duplicate) {
                                final updated = review.removeAt(
                                  results,
                                  duplicate.scanIndexA,
                                );
                                onResultsChanged(updated);
                                sheetSetState(() {});
                              },
                              onAssign: (duplicate) {
                                Navigator.pop(ctx, false);
                                onAssignStudent(duplicate.scanIndexB);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(ctx, false),
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: const Text('Scan later'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(ctx, true),
                          icon: const Icon(Icons.rate_review_outlined),
                          label: const Text('Review'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Widget for handling missing student actions in the review sheet.
class MissingStudentActions extends StatelessWidget {
  const MissingStudentActions({
    super.key,
    required this.students,
    required this.onMarkAbsent,
    required this.onLeaveUngraded,
    required this.onManualEntry,
  });

  final List<Student> students;
  final ValueChanged<Student> onMarkAbsent;
  final ValueChanged<Student> onLeaveUngraded;
  final ValueChanged<Student> onManualEntry;

  @override
  Widget build(BuildContext context) {
    return ReviewActionSection(
      icon: Icons.person_search_outlined,
      title: 'Missing students',
      message: 'Choose what happened. The app will not turn them into zero.',
      children: students.take(6).map((student) {
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.fullName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.event_busy, size: 18),
                        label: const Text('Mark absent'),
                        onPressed: () => onMarkAbsent(student),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.pending_actions, size: 18),
                        label: const Text('Leave ungraded'),
                        onPressed: () => onLeaveUngraded(student),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.edit_note, size: 18),
                        label: const Text('Enter manually'),
                        onPressed: () => onManualEntry(student),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Widget for handling duplicate actions in the review sheet.
class DuplicateActions extends StatelessWidget {
  const DuplicateActions({
    super.key,
    required this.duplicates,
    required this.results,
    required this.onKeepBoth,
    required this.onKeepFirst,
    required this.onKeepSecond,
    required this.onAssign,
  });

  final List<AnswerDuplicate> duplicates;
  final List<ScanResult> results;
  final ValueChanged<AnswerDuplicate> onKeepBoth;
  final ValueChanged<AnswerDuplicate> onKeepFirst;
  final ValueChanged<AnswerDuplicate> onKeepSecond;
  final ValueChanged<AnswerDuplicate> onAssign;

  @override
  Widget build(BuildContext context) {
    return ReviewActionSection(
      icon: Icons.copy_all_outlined,
      title: 'Possible duplicates',
      message: 'Resolve repeated papers before saving the batch.',
      children: duplicates.take(4).map((duplicate) {
        final first = duplicate.scanIndexA < results.length
            ? results[duplicate.scanIndexA]
            : null;
        final second = duplicate.scanIndexB < results.length
            ? results[duplicate.scanIndexB]
            : null;
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${first?.studentName ?? 'Paper ${duplicate.scanIndexA + 1}'} and '
                    '${second?.studentName ?? 'Paper ${duplicate.scanIndexB + 1}'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${duplicate.matchPercent.toStringAsFixed(0)}% answer match',
                    style: const TextStyle(color: AppTheme.lightText, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.done_all, size: 18),
                        label: const Text('Keep both'),
                        onPressed: () => onKeepBoth(duplicate),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.looks_one, size: 18),
                        label: const Text('Keep first'),
                        onPressed: () => onKeepFirst(duplicate),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.looks_two, size: 18),
                        label: const Text('Keep second'),
                        onPressed: () => onKeepSecond(duplicate),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.person_add_alt, size: 18),
                        label: const Text('Assign'),
                        onPressed: () => onAssign(duplicate),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
