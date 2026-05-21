# Risks

This is the active risk register for EthioGrade.

## High Risks

### Wrong Grades

Status: ongoing

OCR, OMR, scoring, confidence, and review behavior directly affect teacher trust.

Why it matters: a fast grading app that gives wrong grades will lose adoption immediately.

Operating rule: do not casually change OCR/OMR/scoring behavior. Use targeted tests before commits.

### Hive Data Compatibility

Status: ongoing

Hive fields, adapters, type IDs, encryption, migrations, backup, and restore affect existing teacher data.

Why it matters: a storage mistake can make local grades unreadable or corrupt.

Operating rule: no casual Hive field/adapter changes. Treat storage changes as High/Strong/Deep model work with explicit tests.

### Hybrid-By-Default Grading Drift

Status: open

Product decision is mode-based grading, not hybrid-by-default.

Why it matters: running OCR and OMR together by default can confuse provenance, reduce trust, and create scoring behavior teachers did not choose.

Next action: add or plan mode-contract tests before changing grading behavior.

### Dirty Worktree / Broad Mixed Commits

Status: open

The worktree has unrelated modifications outside `.project-os/`.

Why it matters: unrelated changes can be accidentally staged, committed, or reverted.

Operating rule: inspect scope before staging. Commit only approved files.

## Medium Risks

### Android Build Config Sensitivity

Status: ongoing

Android build config affects release size, ABI support, signing, minification, and install behavior.

Operating rule: do not casually touch `android/`. Use High/Strong/Deep model work for build/release decisions.

### Dependency Creep

Status: ongoing

New packages can increase APK size, break offline assumptions, introduce privacy risk, or complicate Android builds.

Operating rule: no dependency additions without dependency review.

### Unknown Test Health

Status: open

Current full test/build health is not established in this setup task.

Operating rule: future code commits should run targeted tests for touched behavior before commit.

## Low Risks / Deferred

### Cloud Database Requests

Status: deferred

Do not add Supabase/cloud database now. Revisit only when the owner explicitly starts a cloud sync phase.

### Deferred Live Grading Contract

Status: deferred

Untracked slice identified but intentionally deferred:

- `lib/services/live_grading_contract.dart`
- `test/services/live_grading_contract_test.dart`

Why it matters: even though it is self-contained, it encodes protected-risk scan/save/fallback behavior (auto-save/manual-save/skip-save) and OCR fallback thresholds. It should not be committed until mode-based grading architecture and live-grading direction are explicitly approved.

Targeted test when revisited:

- `flutter test test/services/live_grading_contract_test.dart`

### Feature Expansion Before Trust

Status: watch

New features should not outrun grading correctness, review clarity, offline reliability, and data safety.
