# Model Usage Rules

Use model strength based on risk.

## Low / Fast

Use for mechanical actions:

- formatting text
- listing files
- small doc edits
- simple shell inspection
- applying an already-approved patch
- updating `.project-os/` wording

Do not use Low/Fast for storage, grading, OCR/OMR, Android build, architecture, or release decisions.

## Medium / Balanced

Use for diff/source-test inspection:

- reading changed files
- reviewing a narrow diff
- checking test coverage around a touched file
- planning a small bug fix
- choosing targeted tests
- validating that a commit scope is narrow

Medium/Balanced is the default for ordinary repo work.

## High / Strong / Deep

Use for high-risk decisions:

- Hive model fields/adapters/type IDs
- migrations/default values
- encrypted storage
- backup/restore compatibility
- grading architecture
- OCR behavior
- OMR behavior
- scoring behavior
- confidence/review behavior
- Android build config
- APK/AAB size decisions
- dependency additions
- release decisions

High/Strong/Deep work must include explicit risk notes and targeted test recommendations before commit.

## Operating Rule

If a change can affect teacher trust, saved data, grading correctness, Android release behavior, or app size, treat it as High/Strong/Deep.
