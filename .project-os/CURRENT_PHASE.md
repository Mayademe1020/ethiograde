# Current Phase

## Phase Name

Project Operating System Setup and Stabilization

## Phase Goal

Give future EthioGrade sessions a clear operating system before more product or code work continues.

This phase is documentation and discipline first: preserve the product direction, protect sensitive code paths, and make commits easier to review.

## Current State

As of 2026-05-06:

- working directory: `D:\ethiograde_fresh`
- product: offline-first Android grading app for Ethiopian teachers
- core value: reduce grading time while preserving teacher trust and review
- storage direction: local/offline-first Hive with encrypted local data
- cloud database direction: do not add Supabase/cloud database now
- grading direction: mode-based, not hybrid-by-default
- repo has unrelated dirty app files outside `.project-os/`
- this setup task must not stage, commit, or run tests

## Allowed In This Phase

- update files under `.project-os/`
- classify risks and decisions
- plan targeted tests
- recommend narrow commits
- document dependency and model-usage rules

## Not Allowed Without Explicit Approval

- new product features
- UI redesign
- `lib/` changes
- `test/` changes
- `android/` changes
- Hive field/adapter changes
- OCR/OMR/scoring behavior changes
- Android build config changes
- dependency additions
- broad mixed commits

## Exit Criteria

This phase is complete when:

- `.project-os/` has the current product brief, phase, decisions, risks, model rules, bug log, dependency policy, session summary, and next prompt
- future sessions know that grading is mode-based
- future sessions know not to add cloud database work now
- future sessions know to use targeted tests before commits
- the first commit can safely contain only `.project-os/` files

## Next Recommended Action

Commit only the `.project-os/` operating-system files after reviewing the diff.
