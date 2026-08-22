import '../../models/assessment.dart';
import '../../models/scan_result.dart';
import '../../services/draft_service.dart';

// ─────────────────────────────────────────────────────────────────────
//  Dashboard Next-Action Resolver
//
//  Determines the single winning primary action for the dashboard.
//  Returns exactly one DashboardAction — never two competing CTAs.
// ─────────────────────────────────────────────────────────────────────

enum DashboardActionType {
  resumeDraft,
  finishSetup,
  reviewPapers,
  startScanning,
  gradePapers,
}

class DashboardAction {
  final DashboardActionType type;
  final int priority;
  final String title;
  final String description;
  final String ctaLabel;
  final Assessment? assessment;
  final int? completedCount;
  final int? totalCount;
  final String reason;

  const DashboardAction({
    required this.type,
    required this.priority,
    required this.title,
    required this.description,
    required this.ctaLabel,
    this.assessment,
    this.completedCount,
    this.totalCount,
    required this.reason,
  });
}

/// Resolve the single winning dashboard action from current app state.
///
/// Priority order:
/// 1. Valid interrupted draft
/// 2. Incomplete answer key or setup
/// 3. Scanned papers needing teacher review
/// 4. Ready-to-grade assessment
/// 5. Generic start-grading action
///
/// A draft is valid when:
/// - it exists and is < 7 days old
/// - its assessment exists in the full collection (any lifecycle status
///   that permits grading recovery: active, grading)
/// - it has completed results (restorable state)
///
/// [allAssessments] is the full unfiltered collection — used for draft
/// lookup so that assessments with status `grading` are not rejected.
/// [activeAssessments] is the filtered active-only list — used for
/// setup/ready prioritization.
/// [resultsByAssessment] maps assessment ID → its scan results, used to
/// detect papers needing teacher review (blocking completion). Optional —
/// when omitted, review-aware actions are skipped.
Future<DashboardAction> resolveDashboardAction({
  required List<Assessment> allAssessments,
  required List<Assessment> activeAssessments,
  Map<String, List<ScanResult>>? resultsByAssessment,
}) async {
  // ── Priority 1: Valid interrupted draft ──
  // Look up assessment from full collection (not just active) so that
  // assessments with status `grading` are not rejected.
  final drafts = await DraftService().getAllDrafts(throwOnError: true);
  for (final draft in drafts) {
    if (draft.age.inDays >= 7) continue;
    if (draft.completedResults.isEmpty) continue;

    final assessment = allAssessments
        .where((a) => a.id == draft.assessmentId)
        .firstOrNull;
    if (assessment == null) continue;

    // Only permit recovery for assessments in a recoverable lifecycle
    if (assessment.status != AssessmentStatus.active &&
        assessment.status != AssessmentStatus.grading) {
      continue;
    }

    return DashboardAction(
      type: DashboardActionType.resumeDraft,
      priority: 1,
      title: 'Resume grading',
      description:
          '${assessment.title} — ${draft.completedCount} papers graded ${draft.ageLabel}',
      ctaLabel: 'Resume',
      assessment: assessment,
      completedCount: draft.completedCount,
      reason: 'Valid interrupted draft exists',
    );
  }

  // ── Priority 2: Incomplete answer key or setup ──
  final setupAssessments = activeAssessments
      .where((a) => !a.isAnswerKeyComplete)
      .toList(growable: false);
  if (setupAssessments.isNotEmpty) {
    final a = setupAssessments.first;
    return DashboardAction(
      type: DashboardActionType.finishSetup,
      priority: 2,
      title: 'Finish answer key',
      description: '${a.title} needs its answer key before grading.',
      ctaLabel: 'Set Answer Key',
      assessment: a,
      reason: 'Active assessment has incomplete answer key',
    );
  }

  // ── Priority 3: Papers needing teacher review ──
  if (resultsByAssessment != null) {
    final reviewAssessments = activeAssessments
        .where((a) {
          final results = resultsByAssessment[a.id];
          return results != null && results.any((r) => r.requiresTeacherAction);
        })
        .toList(growable: false);
    if (reviewAssessments.isNotEmpty) {
      final a = reviewAssessments.first;
      final results = resultsByAssessment[a.id]!;
      final needAction = results.where((r) => r.requiresTeacherAction).length;
      return DashboardAction(
        type: DashboardActionType.reviewPapers,
        priority: 3,
        title: 'Review papers',
        description:
            '$needAction of ${results.length} papers in '
            '${a.title} need your review.',
        ctaLabel: 'Review',
        assessment: a,
        completedCount: results.length - needAction,
        totalCount: results.length,
        reason: 'Scanned papers need teacher action',
      );
    }
  }

  // ── Priority 4: Ready-to-grade assessment ──
  final readyAssessments = activeAssessments
      .where((a) => a.isAnswerKeyComplete)
      .toList(growable: false);
  if (readyAssessments.isNotEmpty) {
    final a = readyAssessments.first;
    return DashboardAction(
      type: DashboardActionType.startScanning,
      priority: 4,
      title: 'Start scanning',
      description: '${a.title} is ready. Scan student papers to grade.',
      ctaLabel: 'Start Scanning',
      assessment: a,
      reason: 'Active assessment has complete answer key',
    );
  }

  // ── Priority 5: Generic start-grading action ──
  return const DashboardAction(
    type: DashboardActionType.gradePapers,
    priority: 5,
    title: 'Grade papers',
    description: 'Scan answer sheets or enter scores. Quick and accurate.',
    ctaLabel: 'Grade Papers',
    reason: 'No active assessments or drafts',
  );
}

// ─────────────────────────────────────────────────────────────────────
//  Per-Assessment Next-Action Resolver
//
//  Returns the single next action for an assessment card, mirroring the
//  dashboard priority order but scoped to one assessment:
//  1. Scanned papers needing teacher review
//  2. Incomplete answer key / setup
//  3. Ready to scan student papers
//  4. Grading in progress (resume)
//  5. Graded — view results
// ─────────────────────────────────────────────────────────────────────

enum AssessmentActionKind {
  reviewPapers,
  addAnswerKey,
  scanPapers,
  resumeGrading,
  viewResults,
}

class AssessmentAction {
  final AssessmentActionKind kind;
  final String label;
  final String description;

  const AssessmentAction({
    required this.kind,
    required this.label,
    required this.description,
  });
}

/// Resolve the next action for a single assessment card.
///
/// [results] is optional — when omitted, review-aware states are skipped
/// and setup/scanning states take precedence.
AssessmentAction resolveAssessmentAction({
  required Assessment assessment,
  List<ScanResult>? results,
}) {
  final resolved = resolveOperationalStatus(assessment);

  // Priority 1: scanned papers need teacher review
  if (results != null && results.isNotEmpty) {
    final needAction = results.where((r) => r.requiresTeacherAction).length;
    if (needAction > 0) {
      return AssessmentAction(
        kind: AssessmentActionKind.reviewPapers,
        label: 'Review $needAction paper${needAction == 1 ? '' : 's'}',
        description: results.length == 1
            ? 'One scanned paper needs your review.'
            : '${results.length} papers scanned — $needAction need review.',
      );
    }
  }

  switch (resolved.status) {
    case OperationalStatus.setupIncomplete:
      return const AssessmentAction(
        kind: AssessmentActionKind.addAnswerKey,
        label: 'Add answer key',
        description: 'Set the correct answers to start grading.',
      );
    case OperationalStatus.readyToGrade:
      return const AssessmentAction(
        kind: AssessmentActionKind.scanPapers,
        label: 'Scan student papers',
        description: 'Answer key is ready. Scan papers to grade.',
      );
    case OperationalStatus.gradingInProgress:
      return const AssessmentAction(
        kind: AssessmentActionKind.resumeGrading,
        label: 'Continue grading',
        description: 'Grading is in progress — pick up where you left off.',
      );
    case OperationalStatus.graded:
      return const AssessmentAction(
        kind: AssessmentActionKind.viewResults,
        label: 'View results',
        description: 'See final scores, grades, and exports.',
      );
  }
}

// ─────────────────────────────────────────────────────────────────────
//  Operational-Status Resolver
//
//  Derives a consistent display status for any assessment using only
//  reliable persisted data. Used by Dashboard, AssessmentCard, and
//  AssessmentsTab.
//
//  Supported states (Phase 1):
//  - Setup incomplete
//  - Ready to grade
//  - Grading in progress
//  - Graded
//
//  NOT supported in Phase 1:
//  - Needs review (review-state inconsistency not yet corrected)
//  - Published / Archived (no enum values)
//  - Result staleness (no tracking flag)
// ─────────────────────────────────────────────────────────────────────

enum OperationalStatus {
  setupIncomplete,
  readyToGrade,
  gradingInProgress,
  graded,
}

class ResolvedStatus {
  final OperationalStatus status;
  final String label;
  final String? detail;

  const ResolvedStatus({
    required this.status,
    required this.label,
    this.detail,
  });
}

/// Resolve the operational status of an assessment using persisted data.
///
/// Does NOT use draft existence as proof of grading progress.
/// Uses only: persisted AssessmentStatus, isAnswerKeyComplete, and
/// completedAt timestamp.
ResolvedStatus resolveOperationalStatus(Assessment assessment) {
  if (assessment.status == AssessmentStatus.completed) {
    return const ResolvedStatus(
      status: OperationalStatus.graded,
      label: 'Graded',
    );
  }

  if (assessment.status == AssessmentStatus.draft) {
    return const ResolvedStatus(
      status: OperationalStatus.setupIncomplete,
      label: 'Draft',
    );
  }

  // status is active or grading
  if (!assessment.isAnswerKeyComplete) {
    return const ResolvedStatus(
      status: OperationalStatus.setupIncomplete,
      label: 'Needs answer key',
    );
  }

  if (assessment.status == AssessmentStatus.grading) {
    return const ResolvedStatus(
      status: OperationalStatus.gradingInProgress,
      label: 'Grading in progress',
    );
  }

  // status is active, answer key complete
  return const ResolvedStatus(
    status: OperationalStatus.readyToGrade,
    label: 'Ready to grade',
  );
}
