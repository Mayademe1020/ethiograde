# Bug Log

This file is for known or suspected product bugs. Do not record feature ideas here.

## Open

### Mode-Based Grading Contract Not Yet Enforced

Status: open

Product decision: grading should be mode-based, not hybrid-by-default.

Observed risk: existing grading behavior may still assume OCR + OMR together by default in some paths.

Expected future behavior:

- Bubble Sheet / OMR Mode should use OMR intentionally.
- Normal Paper / OCR Assist Mode should use OCR assistance intentionally.
- Manual / Quick Entry Mode should preserve manual provenance.
- Re-scan should preserve original intended mode unless the teacher changes it.

Required before fix:

- targeted mode-contract tests
- no Hive field/adapter changes unless explicitly approved

### Unknown Current Full Test Health

Status: open

This setup task did not run tests by request.

Next action: before code commits, run targeted tests for the touched behavior.

## Resolved

No resolved bugs recorded in this project OS file yet.
