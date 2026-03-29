# Changelog

All notable changes to EthioGrade are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/):
- **MAJOR** (x.0.0) — Breaking changes, production release milestones
- **MINOR** (0.x.0) — New features, non-breaking
- **PATCH** (0.0.x) — Bug fixes, improvements, docs

Categories: `Added` `Changed` `Fixed` `Improved` `Removed` `Deprecated` `Security` `Performance` `Docs` `Infra`

---

## [Unreleased]

### Added
- Encrypted Hive initialization in `main.dart`
  - AES-256 encryption for all Hive boxes via `HiveAesCipher`
  - 32-byte key generated on first launch via `dart:math` `Random.secure()`
  - Key stored in `flutter_secure_storage` (Android EncryptedSharedPreferences)
  - Three encrypted boxes: `students` (regular), `assessments` (regular), `scan_results` (lazy)
  - Corrupt-box recovery: delete + recreate on open failure, never blocks app launch
  - `box.compact()` after opening to optimise storage
  - Fallback mode: if any Hive init fails, app starts with in-memory state and shows a dismissable warning banner
- `flutter_secure_storage: ^9.0.0` dependency for platform-keystore key storage
- `ValidationService`: pure-Dart model validator (no platform deps)
  - `validateStudent`: name non-empty ≤100 chars, grade 1–12 or University(0)
  - `validateAssessment`: title non-empty, questions non-empty, correct answers valid per type (A–E for MCQ, True/False for TF, non-empty for short answer)
  - `validateScanResult`: score ≥0 and ≤max, confidence 0–1, percentage 0–100, IDs non-empty
  - `ValidationResult` type with `isValid` bool and `errors` list
  - 25+ unit tests: happy paths, edge cases, boundary values, mixed valid/invalid
- `StudentProvider` rewritten with real Hive CRUD
  - `loadStudents`: reads from encrypted `students` box, sorts by name, error-safe
  - `addStudent`: validates → UUID generation → duplicate check → Hive write → memory update
  - `updateStudent`: validates → existence check → overwrite → notify
  - `deleteStudent`: existence check → delete → keeps associated scan results for history
  - `searchStudents`: case-insensitive English + Amharic name search
  - `addStudents`: bulk add with count return
  - `Result<T>` type: `{success, data, error}` — callers never need try/catch
- `AssessmentProvider` rewritten with real Hive CRUD
  - `loadAssessments`: reads from encrypted `assessments` box, sorts newest-first
  - `addAssessment`: validates → duplicate check → Hive write → memory update
  - `updateAssessment`: validates → existence check → overwrite → notify
  - `deleteAssessment`: existence check → delete → clears current if matched
  - `getRecentAssessments(limit)`: returns N most recent
  - `saveAssessment` kept as backward-compatible wrapper (add-or-update)
  - `Result<T>` type matching StudentProvider pattern

### Planned (Sprint 1)
- Real device testing on 2GB phone with actual exam papers
- Unit tests for PDF service
- Widget tests for dashboard, create assessment, review screens
- Pure Dart perspective correction
- Camera guidance overlay
- Score override/edit flow

## [0.1.0-hybrid-grading] — 2026-03-30

### Added
- `HybridGradingService`: high-level grading orchestrator
  - Stable API for screens — screens no longer call OcrService directly
  - `gradePaper()`: single-paper grading with file existence check, error handling
  - `gradeBatch()`: sequential batch processing with progress callback (safe for 2GB)
  - `regradePaper()`: re-scan a single paper with separate logging
  - Graceful failure: never throws, returns `needsRescan` ScanResult on error
- Unit tests for OcrService: 40+ cases
  - TextRegion model: construction, zero values
  - enhanceImage: path naming, downscaling large images, no upscale for small images, grayscale conversion, PNG→JPEG conversion, invalid file handling, contrast boost verification
  - parseAnswers integration: standard MCQ, confidence preservation, noise filtering, concatenated format, True/False, Amharic, empty input, trailing punctuation
  - Scoring pipeline: perfect/all-wrong/missing/partial answers, confidence averaging, grade boundaries for all 3 rubric types
  - Edge cases: Q# >200 rejected, Q# 0 rejected, empty string, prose lines, zero max score, unknown rubric fallback
  - ScanResult model: round-trip serialization, needsReview logic, copyWith
- Unit tests for HybridGradingService: 10+ cases
  - gradePaper: file-not-found graceful failure, real image processing, result structure validation
  - gradeBatch: empty list, progress callbacks, custom names, auto-generated names, partial names, mixed valid/invalid images
  - regradePaper: result structure matches gradePaper

### Changed
- `batch_scan_screen.dart`: replaced direct OcrService calls with HybridGradingService
  - Cleaner batch loop: single `gradeBatch()` call with progress callback
  - No more try/catch per image — HybridGradingService handles errors internally
  - Removed unused `dart:io` import
- `camera_screen.dart`: replaced direct OcrService calls with HybridGradingService
  - Single-paper scan now goes through `gradePaper()`
  - Same error handling benefits as batch scan
- Removed unused `dart:io` import from batch_scan_screen

## [0.1.0-analytics] — 2026-03-29

### Added
- `AnalyticsService`: pure-Dart analytics engine extracted from AnalyticsProvider
  - No Flutter/platform deps — independently testable
  - Public API: `computeAnalytics`, `getDifficultQuestions`, `getEasyQuestions`, `getTopicHeatmap`
  - Pass marks as constants: MoE 50%, international 60%, university 50%
- Unit tests: 20+ cases for analytics engine
  - computeAnalytics: empty/single/multiple students, averages, median, pass rate, grade distribution
  - Pass mark varies by rubric type
  - Question analytics: correct rate, answer distribution, topic scores
  - getDifficultQuestions / getEasyQuestions: threshold filtering, sorting
  - getTopicHeatmap: topic × subject, General fallback, empty input
  - QuestionAnalytics.isDifficult / isEasy flags

### Changed
- AnalyticsProvider delegates computation to AnalyticsService (zero behavior change)
- Removed 4 private methods from AnalyticsProvider: `computeAnalytics` body, `_median`, `_getPassMark`, heatmap logic

## [0.1.0-scoring] — 2026-03-29

### Added
- `ScoringService`: pure-Dart scoring engine extracted from OcrService
  - No Flutter/platform deps — independently testable
  - Public API: `checkAnswer`, `scoreAnswers`, `deduplicateAnswers`, `calculateGrade`, `calculateConfidence`, `calculateTotalScore`, `calculatePercentage`
  - Grading scales as constants: MoE national (11 bands), private international (6 bands), university (10 bands)
- Unit tests: 40+ cases for scoring engine
  - checkAnswer: MCQ, T/F, short answer (list + string), null safety
  - scoreAnswers: full/zero/partial/missing/mixed-type scenarios
  - deduplicateAnswers: confidence-based dedup, sort order, empty input
  - calculateGrade: every boundary value across all 3 scales
  - End-to-end pipelines: 20-question MCQ, perfect, zero, mixed types

### Changed
- OcrService delegates scoring to ScoringService (zero behavior change)
- Removed 5 private methods from OcrService: `_scoreAnswers`, `_checkAnswer`, `_calculateGrade`, `_getGradingScale`, `_calculateConfidence`, `_deduplicateAnswers`
- `DetectedAnswer` class moved from ocr_service.dart to scoring_service.dart

---

## [0.1.0-pipeline] — 2026-03-29

### Changed
- Image enhancement: replaced 6-step pipeline with 4 native operations
  - Removed: white balance (pixel loop), sharpen (pixel loop), denoise (blur), adaptive threshold (pixel loop, ~47M reads)
  - Kept: downscale to 1600px, grayscale, contrast boost 1.2x
  - Rationale: ML Kit has internal preprocessing. Our pixel loops were destroying information it could use, while adding 3-8s latency on 2GB devices.
- Enhanced images saved as JPEG 92% instead of PNG (5x smaller, faster ML Kit loading)

### Added
- Paper skew detection: estimates tilt angle from ML Kit text block alignment
- Duplicate answer deduplication: same Q# detected twice keeps highest confidence
- Scan quality metadata: text lines detected, skew angle, warnings
- Auto-flag low-confidence scans as needsRescan (overall < 0.6)
- `dart:math` import for atan2 skew calculation

### Removed
- `_autoWhiteBalance` — pixel loop over every pixel, redundant with ML Kit
- `_sharpen` — gaussianBlur + pixel loop, introduced artifacts
- `_denoise` — aggressive gaussianBlur destroyed thin text strokes
- `_adaptiveThreshold` — 225 pixel reads per pixel, 47M total on 1600px image

## [0.1.0-parser] — 2026-03-29

### Added
- `AnswerParser` class: extracted from OcrService for testability
- Unit tests: 30+ cases covering MCQ, T/F, Amharic, concatenated formats, noise filtering
- Concatenated format support: "1A", "10B", "1true" (bubbled answer sheets)
- yes/no → True/False normalization

### Fixed
- Pattern 2 narrowed to 1-2 char answers — prevents prose lines from false-matching
- Concatenated pattern now handles lowercase true/false
- Trailing OCR punctuation stripped from answers ("A." → "A", "True." → "True")

### Changed
- OcrService delegates parsing to AnswerParser (single responsibility)

## [0.1.0-ocr] — 2026-03-29

### Improved
- OCR confidence filtering: text lines below 0.5 confidence discarded as noise
- Image downscaling: images >2048px resized before enhancement to protect 2GB devices
- Line sorting: proportional Y-tolerance (5% of vertical span) replaces hardcoded 10px
- Error logging: exception type only, no file paths in debug output

### Changed
- Replaced mock OCR extractor with real Google ML Kit TextRecognizer
- `_extractTextRegions()` now processes actual images on-device (no internet required)
- Text lines sorted top→bottom, left→right for natural reading order
- Confidence scores calculated from ML Kit character-level detection
- Graceful failure: returns empty on error instead of crashing — teacher can manually enter answers via review screen

### Removed
- Hardcoded mock OCR data (5 fake TextRegion objects)

### Security
- No network calls — ML Kit runs entirely on-device
- No student data in error logs

---

## [0.1.0-assets] — 2026-03-29

### Added
- NotoSansEthiopic font files (Regular + Bold) — OFL licensed, from Google Fonts
- Splash screen logo (512x512 PNG) — Ethiopian green with white checkmark and yellow accent dot
- `.gitkeep` in assets/images/ to preserve directory structure

### Fixed
- App can now compile (fonts were missing from assets/fonts/)
- Android splash screen drawable references resolved (splash_logo.png now exists)

---

## [0.1.0-scaffold] — 2026-03-29

> The foundation. Nothing works end-to-end yet, but the architecture is sound.

### Added
- Project scaffold: 31 Dart files across models, services, screens, widgets, config
- **Models:** Student, Assessment, Question, ScanResult, ClassInfo with Hive adapters
- **State management:** Provider pattern for students, assessments, analytics, settings, locale
- **Theme:** Ethiopian-inspired palette (green/yellow/red) with dark mode, Material 3
- **Routing:** Named routes for all 11 screens
- **Bilingual:** Amharic/English toggle via LocaleProvider
- **Camera:** Full-screen preview, flash toggle, scan guide overlay
- **Image enhancement:** White balance → contrast → sharpen → denoise → binarize
- **Answer parser:** Regex for EN (A/B/C/D/E, True/False) and AM (እውነት/ሐሰት, ሀ-ሠ)
- **Scoring engine:** MCQ, True/False, short-answer; MoE/international/university scales
- **PDF reports:** Student + class reports
- **Voice:** STT, TTS, audio recording
- **Excel import:** Student list from .xlsx
- **Analytics:** Grade distribution, question stats, topic scores
- **Screens (11):** Onboarding, Dashboard, Assessment CRUD, Camera, Batch Scan, Review, Analytics, Reports, Students, Subscription

---

## [0.0.0] — Project Inception

- Repository created
- Initial README with feature vision, tech stack, project structure

---

*Every entry answers: What changed? Why? What broke? What's next?*
*If it's not in the changelog, it didn't happen.*
