import '../models/assessment.dart';
import '../models/scan_result.dart';
import '../models/student.dart';
import '../config/integrity_metadata_keys.dart';
import 'integrity_state_resolver.dart';

/// Result of checking whether an assessment is ready for finalization.
class CompletionCheck {
  final bool isReady;
  final List<CompletionItem> items;

  const CompletionCheck({
    required this.isReady,
    required this.items,
  });

  List<CompletionItem> get blocking => items.where((i) => i.severity == CompletionSeverity.blocking).toList();
  List<CompletionItem> get needsAttention => items.where((i) => i.severity == CompletionSeverity.needsAttention).toList();
  List<CompletionItem> get ready => items.where((i) => i.severity == CompletionSeverity.ready).toList();
}

/// A single completion check item.
class CompletionItem {
  final String label;
  final String? explanation;
  final CompletionSeverity severity;
  final String? actionRoute;
  final String? actionLabel;

  const CompletionItem({
    required this.label,
    this.explanation,
    required this.severity,
    this.actionRoute,
    this.actionLabel,
  });
}

enum CompletionSeverity { ready, needsAttention, blocking }

/// Centralized assessment completion-readiness checker.
///
/// All final-save, finalization, report, and export paths MUST call this.
/// Do not duplicate completion logic inside widgets.
class AssessmentCompletionGate {
  const AssessmentCompletionGate({
    IntegrityStateResolver? integrityResolver,
  }) : _integrityResolver = integrityResolver ?? const IntegrityStateResolver();

  final IntegrityStateResolver _integrityResolver;

  /// Check whether an assessment is ready for finalization.
  CompletionCheck check({
    required Assessment assessment,
    required List<ScanResult> results,
    List<Student>? roster,
  }) {
    final items = <CompletionItem>[];

    // 1. Answer key complete
    if (!assessment.isAnswerKeyComplete) {
      items.add(CompletionItem(
        label: 'Answer key is incomplete',
        explanation: assessment.answerKeyStatus,
        severity: CompletionSeverity.blocking,
        actionRoute: '/assessment/answer-key',
        actionLabel: 'Complete answer key',
      ));
    } else {
      items.add(CompletionItem(
        label: 'Answer key is complete',
        severity: CompletionSeverity.ready,
      ));
    }

    // 2. Current answer-key revision (no outdated results)
    if (results.isNotEmpty && assessment.answerKeyFingerprint.isNotEmpty) {
      final outdatedCount = results.where((r) =>
        _integrityResolver.resolve(result: r, assessment: assessment) == IntegrityState.outdated
      ).length;
      if (outdatedCount > 0) {
        items.add(CompletionItem(
          label: '$outdatedCount paper(s) have outdated scores',
          explanation: 'Scores were calculated with a previous answer key version.',
          severity: CompletionSeverity.blocking,
          actionLabel: 'Recalculate scores',
        ));
      } else {
        items.add(CompletionItem(
          label: 'All scores are current',
          severity: CompletionSeverity.ready,
        ));
      }
    }

    // 3. Recalculation failed
    if (assessment.settings[IntegrityMetadataKeys.recalculationFailed] == true) {
      items.add(CompletionItem(
        label: 'Score recalculation failed',
        explanation: 'Previous recalculation attempt encountered an error.',
        severity: CompletionSeverity.blocking,
        actionLabel: 'Retry recalculation',
      ));
    }

    // 4. Unresolved teacher-review items (low confidence, multiple marks)
    final unresolvedCount = results.where((r) => r.needsReview).length;
    if (unresolvedCount > 0) {
      items.add(CompletionItem(
        label: '$unresolvedCount paper(s) need teacher review',
        explanation: 'Low-confidence answers or unreadable responses require teacher judgment.',
        severity: CompletionSeverity.blocking,
        actionRoute: '/review',
        actionLabel: 'Review papers',
      ));
    } else if (results.isNotEmpty) {
      items.add(CompletionItem(
        label: 'All papers reviewed',
        severity: CompletionSeverity.ready,
      ));
    }

    // 5. Unmatched papers
    final unmatchedCount = results.where((r) => r.isUnmatched).length;
    if (unmatchedCount > 0) {
      items.add(CompletionItem(
        label: '$unmatchedCount paper(s) not assigned to a student',
        explanation: 'Each scanned paper must be matched to a student in the roster.',
        severity: CompletionSeverity.blocking,
        actionRoute: '/review',
        actionLabel: 'Assign students',
      ));
    }

    // 6. Unresolved duplicate papers
    final duplicateCount = results.where((r) =>
      r.metadata['duplicateReviewed'] != true &&
      r.metadata['answerDuplicate'] == true
    ).length;
    if (duplicateCount > 0) {
      items.add(CompletionItem(
        label: '$duplicateCount possible duplicate(s) unresolved',
        explanation: 'Similar answer patterns detected — teacher must confirm these are different students.',
        severity: CompletionSeverity.blocking,
        actionRoute: '/review',
        actionLabel: 'Resolve duplicates',
      ));
    }

    // 7. Multiple-mark responses
    final multipleMarkCount = results.expand((r) => r.answers).where((a) =>
      a.detectedAnswer == '[MULTIPLE]'
    ).length;
    if (multipleMarkCount > 0) {
      items.add(CompletionItem(
        label: '$multipleMarkCount answer(s) have multiple marks',
        explanation: 'More than one bubble was filled — teacher must select the intended answer.',
        severity: CompletionSeverity.blocking,
        actionRoute: '/review',
        actionLabel: 'Review multiple marks',
      ));
    }

    // 8. Expected roster students accounted for
    if (roster != null && roster.isNotEmpty) {
      final scannedStudentIds = results
          .where((r) => r.studentId.isNotEmpty)
          .map((r) => r.studentId)
          .toSet();
      final missingCount = roster.where((s) => !scannedStudentIds.contains(s.id)).length;
      if (missingCount > 0) {
        items.add(CompletionItem(
          label: '$missingCount student(s) have no scanned paper',
          explanation: 'These students may be absent or their papers were not scanned.',
          severity: CompletionSeverity.needsAttention,
          actionRoute: '/review',
          actionLabel: 'Mark absent or rescan',
        ));
      } else {
        items.add(CompletionItem(
          label: 'All roster students accounted for',
          severity: CompletionSeverity.ready,
        ));
      }
    }

    // 9. Missing students explicitly marked absent or not submitted
    final absentCount = results.where((r) =>
      r.metadata['batchReviewResolution'] == 'absent' ||
      r.metadata['batchReviewResolution'] == 'left_ungraded'
    ).length;
    if (absentCount > 0 && roster != null) {
      items.add(CompletionItem(
        label: '$absentCount student(s) marked absent or not submitted',
        severity: CompletionSeverity.ready,
      ));
    }

    // 10. Manual/essay questions scored
    final manualUnscored = results.expand((r) => r.answers).where((a) =>
      a.detectedAnswer == '[MISSING]' && a.maxScore > 0
    ).length;
    if (manualUnscored > 0) {
      items.add(CompletionItem(
        label: '$manualUnscored answer(s) still need scoring',
        explanation: 'Essay or manual questions require teacher scoring.',
        severity: CompletionSeverity.needsAttention,
        actionRoute: '/review',
        actionLabel: 'Score answers',
      ));
    }

    // 11. Grading scale is valid
    if (assessment.rubricType.isEmpty) {
      items.add(CompletionItem(
        label: 'Grading scale not configured',
        severity: CompletionSeverity.blocking,
        actionRoute: '/settings/grading-scale',
        actionLabel: 'Set grading scale',
      ));
    } else {
      items.add(CompletionItem(
        label: 'Grading scale is configured',
        severity: CompletionSeverity.ready,
      ));
    }

    // 12. Maximum marks and result totals are valid
    if (results.isNotEmpty) {
      final invalidScores = results.where((r) =>
        r.totalScore < 0 ||
        r.totalScore > r.maxScore ||
        r.maxScore != assessment.maxScore
      ).length;
      if (invalidScores > 0) {
        items.add(CompletionItem(
          label: '$invalidScores result(s) have invalid score totals',
          explanation: 'Scores must be between 0 and the maximum marks.',
          severity: CompletionSeverity.blocking,
          actionRoute: '/review',
          actionLabel: 'Review scores',
        ));
      } else {
        items.add(CompletionItem(
          label: 'All score totals are valid',
          severity: CompletionSeverity.ready,
        ));
      }
    }

    // 13. Results exist
    if (results.isEmpty) {
      items.add(CompletionItem(
        label: 'No results to finalize',
        explanation: 'Scan student papers or enter scores before finalizing.',
        severity: CompletionSeverity.needsAttention,
      ));
    }

    // 14. Required result persistence succeeded
    final unsavedCount = results.where((r) => r.id.isEmpty).length;
    if (unsavedCount > 0) {
      items.add(CompletionItem(
        label: '$unsavedCount result(s) not yet persisted',
        severity: CompletionSeverity.blocking,
      ));
    }

    final hasBlocking = items.any((i) => i.severity == CompletionSeverity.blocking);
    return CompletionCheck(isReady: !hasBlocking, items: items);
  }
}
