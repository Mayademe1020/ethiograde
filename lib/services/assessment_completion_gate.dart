import '../models/assessment.dart';
import '../models/scan_result.dart';
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
  final CompletionSeverity severity;
  final String? actionRoute;
  final String? actionLabel;

  const CompletionItem({
    required this.label,
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
  }) {
    final items = <CompletionItem>[];

    // 1. Answer key complete
    if (!assessment.isAnswerKeyComplete) {
      items.add(CompletionItem(
        label: 'Answer key is incomplete (${assessment.answerKeyStatus})',
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
        severity: CompletionSeverity.blocking,
        actionLabel: 'Retry recalculation',
      ));
    }

    // 4. Unresolved review issues
    final unresolvedCount = results.where((r) => r.needsReview).length;
    if (unresolvedCount > 0) {
      items.add(CompletionItem(
        label: '$unresolvedCount paper(s) need teacher review',
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
    final unmatchedCount = results.where((r) =>
      r.studentId.isEmpty || r.studentName.trim().isEmpty
    ).length;
    if (unmatchedCount > 0) {
      items.add(CompletionItem(
        label: '$unmatchedCount paper(s) not assigned to a student',
        severity: CompletionSeverity.blocking,
        actionRoute: '/review',
        actionLabel: 'Assign students',
      ));
    }

    // 6. Unresolved duplicates
    final duplicateCount = results.where((r) =>
      r.metadata['duplicateReviewed'] != true &&
      r.metadata['answerDuplicate'] == true
    ).length;
    if (duplicateCount > 0) {
      items.add(CompletionItem(
        label: '$duplicateCount possible duplicate(s) unresolved',
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
        severity: CompletionSeverity.blocking,
        actionRoute: '/review',
        actionLabel: 'Review multiple marks',
      ));
    }

    // 8. Required students accounted for (if roster exists)
    // This is checked via missing students in the review queue

    // 9. Manual/essay questions scored
    final manualUnscored = results.expand((r) => r.answers).where((a) =>
      a.detectedAnswer == '[MISSING]' && a.maxScore > 0
    ).length;
    if (manualUnscored > 0) {
      items.add(CompletionItem(
        label: '$manualUnscored answer(s) still need scoring',
        severity: CompletionSeverity.needsAttention,
        actionRoute: '/review',
        actionLabel: 'Score answers',
      ));
    }

    // 10. Results exist
    if (results.isEmpty) {
      items.add(CompletionItem(
        label: 'No results to finalize',
        severity: CompletionSeverity.needsAttention,
      ));
    }

    final hasBlocking = items.any((i) => i.severity == CompletionSeverity.blocking);
    return CompletionCheck(isReady: !hasBlocking, items: items);
  }
}
