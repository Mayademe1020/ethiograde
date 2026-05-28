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
