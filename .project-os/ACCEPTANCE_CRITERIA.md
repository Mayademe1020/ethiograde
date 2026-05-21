# Acceptance Criteria

Use this file to define "done" for safe shipping. Future Codex sessions should add task-specific criteria before coding.

## Global Definition Of Done

A change is not done until:

- the intended user workflow is described
- affected files are listed
- targeted tests are run or the reason they were not run is recorded
- known failures are added to `RISKS.md`
- no unrelated files are modified
- `SESSION_SUMMARY.md` is updated
- `NEXT_PROMPT.md` is updated when follow-up work remains

## Repo Stabilization Done

- `git status` is understood and summarized
- dirty tracked files are classified
- untracked files are classified
- build outputs and generated artifacts are handled intentionally
- stale QA logs/screenshots are either archived, ignored, or kept with reason
- current test status is known
- current app build status is known or explicitly unknown

## Core Product Acceptance

The app should support these core workflows before being treated as launch-ready:

1. Teacher can open app after fresh install.
2. Teacher can create or select class.
3. Teacher can add/import students.
4. Teacher can create an assessment.
5. Teacher can enter a complete answer key.
6. Teacher can generate/use answer sheet setup when needed.
7. Teacher can scan objective answers through OMR.
8. Teacher can use OCR-assisted flow where written answers are supported.
9. Teacher can manually enter grades when scanning is not suitable.
10. Teacher can review and correct uncertain results.
11. Teacher can save grades offline.
12. Teacher can export/share/backup data.
13. App works without internet.
14. App remains usable on low-spec Android devices.

## Safety Acceptance

For storage, grading, OCR/OMR, backup, or migrations:

- no silent data loss
- no casual Hive field renumbering
- no unreviewed grading of uncertain written answers
- corrupt local data should fail safely where possible
- teacher can correct or review low-confidence results

## Mode-Based Grading Acceptance

Before changing grading behavior:

- Bubble Sheet / OMR Mode is selected intentionally, not inferred from mixed question types alone
- Normal Paper / OCR Assist Mode is selected intentionally and does not run OMR by default
- Manual / Quick Entry Mode saves manual scores without scan processing
- `ScanResult` provenance records intended mode and actual processor used
- re-scan preserves the original intended mode unless the teacher explicitly changes mode
- old results without mode metadata still load safely
- no Hive field or enum is added without explicit migration/default plan and generated adapter policy
- tests prove mode intent before `hybrid_grading_service.dart` behavior changes are committed
- tests cover future metadata keys `scanMode` and `scanSource` before behavior changes rely on them

## Quality Commands

Preferred checks:

```powershell
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
dart format --output=none --set-exit-if-changed .
flutter analyze --no-pub --fatal-infos
flutter test
flutter build apk --release --split-per-abi
```

Lightweight script:

```powershell
bash scripts/quality_gate.sh
```

Unknown: whether all commands currently pass locally.
