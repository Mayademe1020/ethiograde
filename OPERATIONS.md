# OPERATIONS.md

## Architecture Principles

1. **Offline-first** — Every feature works without internet. No network calls anywhere.
2. **Low-spec phones** — Target 2GB RAM Android. Image processing in isolates, memory-safe.
3. ~~Bilingual~~ **English-only** — Amharic removed from codebase (~2,500 lines of ternaries eliminated). Bilingual string fields on models retained (no migration cost). LocaleProvider kept as stub.
4. **Local-data only** — AES-256 encrypted Hive. No cloud, no analytics SDKs.
5. **Crash-proof** — Graceful fallbacks everywhere. App always launches (in-memory fallback).
6. **Accessible for teachers** — Large touch targets, clear labels, minimal learning curve.
7. **Fast scanning & grading** — Scan a paper in <5s. Grade 30 papers in <3min.

## Code Standards

- **Pure Dart services** — No Flutter imports in services (except where ML Kit requires it).
- **Isolate-heavy** — Image processing via `compute()`. Never block the UI thread.
- **Const constructors** — Use `const` everywhere possible for widget rebuild perf.
- **Relative imports** — `import '../services/foo.dart'` not `import 'package:ethiograde/...'`.
- ~~Bilingual by default~~ — Amharic removed from codebase. English-only UI. Bilingual string fields retained on models (no migration cost).

## Quality Gates (pre-commit)

1. `flutter analyze` — zero warnings
2. `flutter test` — all tests pass
3. No `print()` — use `debugPrint()` only
4. No hardcoded strings in UI — use constants or inline bilingual maps
5. No network URLs in code (except dev-only comments)
6. No `// ignore:` without justification comment

## Commit Format

```
[Area] imperative description
```

Areas: `[Build]` `[Test]` `[Screen]` `[Service]` `[Data]` `[Docs]` `[Perf]` `[Fix]` `[UI]`

Examples:
- `[Test] Add 23 tests: BubbleTemplate, MigrationService, Result`
- `[Perf] Replace excel with csv — pure Dart, ~2MB saved`
- `[Fix] Add 'id' parameter to Student.copyWith`

## Branch Strategy

- `main` — always deployable
- No feature branches for solo dev — commit directly to main with quality gates

## Testing Strategy

- **Services** — Pure Dart unit tests in `test/services/`
- **Widgets** — `testWidgets` with mock providers in `test/widgets/`
- **No integration tests yet** — CI is set up. Pending: Flutter SDK on dev server for local runs.

## File Structure

```
lib/
├── config/          # Constants, routes, theme
├── models/          # Data classes (Student, Assessment, ScanResult, etc.)
├── screens/         # UI screens (one folder per feature)
│   ├── assessment/  # Create, answer key, answer sheet setup, weighted grade
│   ├── classes/     # Class detail, create, roster preview
│   ├── home/        # Main dashboard
│   ├── onboarding/  # First-launch flow
│   ├── quick_enter/ # Manual score entry
│   ├── quick_grade/ # No-assessment fast grading
│   ├── review/      # Grade review, per-question, audit trail
│   ├── scanning/    # Camera, batch scan, roster scan
│   ├── settings/    # Grading scale editor
│   ├── students/    # Add student, import CSV, transfer
├── services/        # Business logic (pure Dart where possible)
├── widgets/         # Reusable UI components
└── main.dart        # App entry, Hive init, providers

test/
├── services/        # Unit tests for services
└── widgets/         # Widget tests for screens
```

## Dependencies (key)

| Package | Purpose | Offline? |
|---------|---------|----------|
| hive + hive_flutter | Local encrypted storage | ✅ |
| google_mlkit_text_recognition | On-device OCR | ✅ |
| image | Image processing (isolates) | ✅ |
| pdf | Answer sheet PDF generation | ✅ |
| csv | Excel import/export | ✅ |
| camera | Camera access | ✅ |
| flutter_secure_storage | AES key storage | ✅ |
| encrypt | Backup file encryption | ✅ |
| provider | State management | ✅ |
