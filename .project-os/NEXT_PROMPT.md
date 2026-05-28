# Next Prompt

Use this exact prompt to commit only the project operating system files.

```text
Commit only the EthioGrade project operating system files.

Working directory:
D:\ethiograde_fresh

Rules:
- Do not modify files.
- Do not run tests.
- Do not stage or commit anything outside .project-os/.
- Do not stage lib/.
- Do not stage test/.
- Do not stage android/.
- Do not stage root docs outside .project-os/.
- Do not include generated files or QA artifacts.

Steps:
1. Run git status --short.
2. Review git diff -- .project-os.
3. Stage only these files:
   - .project-os/PROJECT_BRIEF.md
   - .project-os/CURRENT_PHASE.md
   - .project-os/DECISION_LOG.md
   - .project-os/RISKS.md
   - .project-os/MODEL_USAGE_RULES.md
   - .project-os/NEXT_PROMPT.md
   - .project-os/BUG_LOG.md
   - .project-os/SESSION_SUMMARY.md
   - .project-os/DEPENDENCY_POLICY.md
4. Confirm staged diff contains only .project-os files:
   git diff --cached --name-only
5. Commit with:
   docs(project-os): establish EthioGrade operating rules

Return:
- staged files
- commit hash
- note that no tests were run because this is documentation-only
```

## Deferred Slice Note (Live Grading Contract)

Do not stage or commit these untracked files yet:

- `lib/services/live_grading_contract.dart`
- `test/services/live_grading_contract_test.dart`

Reason: protected-risk scan/save/fallback behavior. Revisit only after mode-based grading and live-grading direction are explicitly approved.

Targeted test when revisited:

- `flutter test test/services/live_grading_contract_test.dart`
