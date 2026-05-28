# Project Brief

## Product

EthioGrade is an offline-first Android grading app for Ethiopian teachers.

It helps teachers reduce the time spent grading exams while preserving teacher trust, review, and control over final results.

## Core User

Primary user: Ethiopian classroom teachers who spend too much time grading exams, often on Android phones with limited storage, limited connectivity, and classroom pressure.

Teacher needs:

- grade papers faster
- keep student data private and local
- review uncertain answers before saving grades
- trust the scoring result
- use the app without internet
- avoid complicated dashboard-first workflows

## Core Value

Reduce grading time while preserving teacher trust and review.

The app should feel like a reliable grading assistant, not an opaque automation system.

## Product Principles

- Offline-first by default.
- Teacher trust before automation.
- Mode-based grading, not hybrid-by-default.
- Local data safety before feature speed.
- Small, targeted, tested changes before commits.
- No broad mixed commits.

## Storage Direction

Storage is local/offline-first with Hive and encrypted local data.

Do not add Supabase, Firebase, cloud sync, or any cloud database now.

Do not casually change:

- Hive model fields
- Hive adapters
- Hive `typeId`
- `@HiveField` numbering
- encryption setup
- backup/restore compatibility
- migrations/default values

## Grading Modes

Grading should be mode-based, not hybrid-by-default.

Supported product modes:

- Bubble Sheet / OMR Mode
- Normal Paper / OCR Assist Mode
- Manual / Quick Entry Mode

Mixed question types do not automatically mean OCR and OMR should run together on the same paper.

## Sensitive Areas

Do not casually change:

- OCR behavior
- OMR behavior
- scoring behavior
- review/confidence behavior
- Android build config
- storage schema or adapters
- dependencies

## Current Operating Rule

Before any implementation session, load `.project-os/` first and keep changes narrow to the approved scope.
