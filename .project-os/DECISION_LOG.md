# Decision Log

This file records product and engineering decisions future sessions should not reopen casually.

## 2026-05-06 - Keep EthioGrade Offline-First

Decision: EthioGrade remains an offline-first Android grading app.

Reason: the core teacher workflow must work in classrooms where internet may be unavailable, unreliable, expensive, or inappropriate for student data.

Do not add now:

- Supabase
- Firebase
- cloud database
- required network sync

Revisit when: the owner explicitly starts a cloud sync or multi-device phase.

## 2026-05-06 - Use Local Hive/Encrypted Storage Carefully

Decision: local storage remains Hive/encrypted local data.

Reason: teacher trust depends on private, durable, locally available student and grade data.

Do not casually change:

- Hive fields
- Hive adapters
- `typeId`
- `@HiveField` numbers
- migration behavior
- encryption setup
- backup/restore compatibility

Revisit when: a storage migration is explicitly planned with tests and rollback thinking.

## 2026-05-06 - Grading Is Mode-Based

Decision: grading should be mode-based, not hybrid-by-default.

Supported modes:

- Bubble Sheet / OMR Mode
- Normal Paper / OCR Assist Mode
- Manual / Quick Entry Mode

Reason: Ethiopian teacher workflows usually separate bubble-sheet grading, normal-paper OCR assistance, and manual/calculation-heavy entry. Mixed question types do not automatically mean OCR and OMR should run together.

Implication: future architecture should choose an intended grading mode before processing instead of silently running every possible processor.

Do not casually change:

- OCR behavior
- OMR behavior
- scoring behavior
- confidence/review behavior
- `HybridGradingService` behavior

Revisit when: mode-contract tests exist and the owner approves the behavior slice.

## 2026-05-06 - Dependency Additions Require Review

Decision: do not add dependencies without dependency review.

Reason: dependencies can affect APK size, Android compatibility, offline behavior, privacy, build stability, and maintenance.

Required review:

- why the dependency is needed
- whether existing code can solve it
- APK/build impact
- offline/privacy impact
- license/maintenance risk
- tests needed before commit

## 2026-05-06 - Commits Must Be Narrow

Decision: avoid broad mixed commits.

Reason: the worktree can contain unrelated app, test, doc, and generated changes. Mixed commits make review and rollback risky.

Rule: stage only files that belong to the approved task.

## Decision Template

```text
## YYYY-MM-DD - Decision Title

Decision:

Reason:

Do not casually change:

Tests required:

Owner approval:

Revisit when:
```

## 2026-06-13 - Dashboard Phase 1 Foundation

Decision: Wireframe 3 (Classroom Ready) is the selected information-architecture foundation for the dashboard, refined with Wireframe 2 calmness.

Reason: Wireframe 3 best addresses the teacher's operational needs — resume interrupted work, see what to do next, understand what needs attention. Wireframe 2 prevents visual clutter. The dashboard must behave like an assistant, not a menu.

Do not casually change:
- the unified next-action resolver priority order
- the single-dominant-CTA constraint
- the operational-status resolver states

Tests required: 25 widget and unit tests (all passing)

Owner approval: approved 2026-06-13

## 2026-06-13 - Navigation Preserved in Phase 1

Decision: Bottom navigation remains Home / Assess / Students / Settings for Phase 1. Navigation restructuring is deferred.

Reason: Changing navigation risks breaking existing workflows and tests. Phase 1 focuses on dashboard content, not navigation architecture.

Do not casually change: navigation tab count, tab labels, or tab destinations

Revisit when: Phase 3 — Classes root and More destination are audited

## 2026-06-13 - Formal Master Scan Is Source-Connected

Decision: The formal master-paper scanning workflow is source-connected end-to-end but not production-validated.

Reason: The code path exists and links UI → camera → OMR → confirmation → persistence. However, it lacks end-to-end tests, real-device validation, and low-quality image testing.

Do not casually change: CoordinateMapOmrService, BatchProcessor.processMasterKey, master key confirmation flow

Revisit when: real-device testing is conducted

## 2026-06-13 - Quick Grade Master Scan Is Missing

Decision: Quick Grade currently requires manual answer-key entry. Master-paper scanning is not available.

Reason: QuickGradeScreen was implemented as a manual-entry-only path. Adding master-scan support requires integrating AnswerSheetSetupScreen and CoordinateMapOmrService into the Quick Grade flow.

Do not casually change: QuickGradeScreen without adding master-scan support

Revisit when: P1 teacher-effort task is scheduled

## 2026-06-13 - Answer-Key Stale-Result Protection Is Next P0

Decision: The next implementation task is answer-key change safety — preventing stale scores when the answer key is edited after grading.

Reason: Current behavior silently presents stale scores. No version tracking exists. The review screen has only a partial navigation-specific detection mechanism. This is a correctness and trust issue.

Do not casually change: ScoringService.scoreAnswers, AnswerKeyScreen save flow, ScanResult persistence

Tests required: fingerprint generation, staleness detection, recalculation prompt, backward compatibility

Owner approval: audit completed 2026-06-13, implementation pending

## 2026-06-13 - Unresolved Review State and Matching Order Are Subsequent P0

Decision: After answer-key safety, the next P0 tasks are:
1. Fix resolved vs unresolved review state (requiresTeacherAction resolver)
2. Match exact student ID before fuzzy name in StudentMatcher

Reason: Both are correctness issues that affect teacher trust. The review-state issue causes inflated "needs review" counts. The matching issue can assign papers to wrong students.

Do not casually change: ScanResult.needsReview, BatchReviewService.summarize, StudentMatcher.matchFromOcr

Revisit when: answer-key safety is implemented

## 2026-06-14 - Answer-Key Change Safety Architecture

Decision: Use deterministic canonical serialization + SHA-256 fingerprint with a monotonic revision counter.

Reason: Fingerprint is the correctness mechanism (detects actual scoring-behavior changes). Revision is the ordering/UI mechanism. Runtime hashCode is non-deterministic. Revision alone cannot detect canceling edits. Revision + fingerprint covers both.

Architecture:
- Add `answerKeyRevision` (int, HiveField 18) and `answerKeyFingerprint` (String, HiveField 19) to Assessment
- Stamp `scoredWithKeyFingerprint` and `scoredWithKeyRevision` in ScanResult.metadata at scoring time
- IntegrityState enum: current, legacyBaseline, unknown, outdated, recalculating, recalculationFailed, currentButNeedsManualReview
- Recalculation: re-run checkAnswer() from persisted detectedAnswer + new key (no image re-scan needed for objective types)
- Manual overrides preserved: isManualEntry, teacher-corrected answers (detected by ocrRawText "(manual:" prefix), force-toggled correct/incorrect
- Checkpoint-based recalculation with progressive persistence
- Finalization blocked when outdated results exist
- Legacy: lazy fingerprint generation on first read

Do not casually change:
- answerKeyFingerprint computation (canonical form must be deterministic)
- IntegrityState resolution logic
- Recalculation eligibility rules (manual overrides must be preserved)
- Finalization gate (must not allow stale results to be finalized)

Tests required: fingerprint computation, recalculation per question type, integrity state resolution, checkpoint recovery, finalization gate

Owner approval: architecture confirmed 2026-06-14, implementation pending (7 slices)

Revisit when: implementing each slice; review before Slice 4 (first behavioral change)
