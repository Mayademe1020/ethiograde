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
- **OutOfMemoryError retry at 1080p in enhanceImage()**
  - 2GB phones scanning 5MP images could OOM and crash with no recovery
  - Extracted `_enhanceImageAtDimension(imagePath, maxDim)` as core logic
  - `enhanceImage()` now wraps call in try-catch for OutOfMemoryError
  - On OOM: logs warning, retries at `_oomRetryDimension` (1080p — ~4x less memory)
  - On second failure: returns original path, never crashes pipeline
  - Crash-proof principle: grading pipeline never breaks on memory pressure

### Fixed
- **setState() called after dispose in batch scan screen**
  - `_processBatch()` called setState after `await gradeBatch()` without checking mounted
  - `onProgress` callback also called setState without mounted guard
  - Teacher navigating away during processing → Flutter crash "setState() called after dispose"
  - Added `if (!mounted) return;` before all post-await setState calls
  - Wrapped onProgress setState in mounted guard
- **Voice service using print() instead of debugPrint()**
  - 2 raw `print()` calls in `voice_service.dart` speech error/status callbacks
  - print() can leak PII in debug logs and pollute production crash reports
  - Replaced with `debugPrint()`, added `flutter/foundation.dart` import
  - Verified: `grep -Prn "\bprint\(" lib/` returns zero hits

### Fixed
- **PDF reports now use real scan results instead of hardcoded data**
  - Student report: loads actual ScanResult from Hive via HybridGradingService.loadScanResults()
    instead of creating a dummy ScanResult with score 75/B for every student
  - Class report: passes real scan results list instead of empty [] — student list table now shows actual data
  - Added bilingual error messages when no scan results exist for the selected assessment
  - Added Report (PDF) shortcut icon in BatchScanScreen app bar — scan → PDF in one tap
  - Added Student model import for type safety

### Added
- **Persist score overrides to Hive on confirm/save**
  - `HybridGradingService.saveScanResult()`: public save method for external callers (review screen)
  - SideBySideReview Confirm button: auto-saves to Hive with retry before popping back, shows "Saved" snackbar
  - ReviewScreen: "Save All" / "ሁሉን አስቀምጥ" button appears when overrides exist, persists all reviewed results
  - Unsaved-changes indicator in app bar, loading spinner during save
  - Non-blocking: teacher can keep reviewing while save runs in background
- **Enhanced score override in review screen (answer type-aware editing)**
  - Fix: `_recalculateAndRefresh()` no longer hardcodes 'moe_national' — looks up actual
    assessment rubric type via AssessmentProvider using ScanResult.assessmentId
  - New override dialog with question-type-specific answer pickers:
    - MCQ: tappable A/B/C/D/E chips, highlights current + shows correct-answer indicator
    - True/False: large visual buttons with Ethiopian green/red colors + Amharic labels (እውነት/ሐሰት)
    - Short answer: inline text editor with submit button (works with Amharic input)
  - `_applyAnswerChange()`: replaces the detected answer, auto-checks correctness against answer key,
    sets confidence to 1.0 (teacher verified), recalculates total/grade/percentage
  - Kept quick correct/wrong toggle as fallback for all question types
  - All bilingual (Amharic/English)
- **Answer-pattern duplicate detection for batch scans**
  - Solves the fundamental dHash limitation: 64-bit perceptual hashing can't distinguish
    same-format MCQ papers (different students, same layout). Only ~10% of pixels differ
    (bubble fills), which averages out at 9×8 resolution.
  - `ScoringService.generateAnswerFingerprint()`: normalizes detected answers into a
    sorted "Q#:ANSWER" string (e.g., "1:A|2:B|3:TRUE"). Excludes [MISSING] entries.
    Case-insensitive, deterministic, ~O(n) on answer count.
  - `ScoringService.compareFingerprints()`: compares two fingerprints question-by-question.
    Only counts questions present in both (avoids penalizing partial scans). Returns 0.0–1.0 ratio.
  - `ScoringService.detectAnswerDuplicates()`: compares all pairs in a batch. Returns
    `AnswerDuplicate` entries for pairs matching ≥ 90% (configurable threshold).
  - `HybridGradingService.detectBatchDuplicates()`: high-level API for screens. Takes
    graded ScanResult list, returns duplicate pairs.
  - `BatchScanScreen`: bilingual warning banner after batch processing completes.
    Shows "Possible Duplicates" / "ሊመሰሉ የሚችሉ ቅጂዎች" with student name pairs and match %.
  - 28 new unit tests: fingerprint generation (7), fingerprint comparison (7),
    duplicate detection (11), HybridGradingService integration (3). Total: 70+ scoring tests.
  - Stage 2 of two-stage duplicate detection: dHash (camera, instant, catches same-image
    re-scans) + answer-pattern (batch, post-OCR, catches same-answers duplicates).
  - Works offline, pure Dart, zero new dependencies.

### Fixed
- **EXIF orientation correction in `enhanceImage()`**
  - Camera photos carry EXIF orientation metadata (phone in landscape, front camera, etc.)
  - ML Kit reads raw pixels without applying EXIF — rotated images produced incorrect text region coordinates and reduced OCR accuracy
  - Added `img.bakeOrientation(image)` before downscale step
  - Single native operation, zero pixel loops, zero latency impact on 2GB devices
  - Most common case: orientation 6 (90° CW, phone held landscape) now produces correct upright image
  - Added unit test validating orientation 6 swaps dimensions correctly (200×400 → 400×200)
  - Graceful: if EXIF data is missing or corrupt, `bakeOrientation` returns image unchanged

### Added
- `PaperGuideOverlay` widget for camera paper alignment
  - Extracted from inline `_ScanGuidePainter` in camera_screen.dart
  - `PaperGuideState` enum: `idle` (white), `detected` (yellow), `aligned` (green)
  - Semi-transparent centered rect: 80% viewport width, 3:4 portrait aspect ratio
  - Four L-shaped corner brackets, 24dp arm length, proportional to screen width
  - Bilingual hint text: Amharic/English (idle+detected: "Align paper within the frame" / "ወረቀቱን በአገባቡ ያስተካክሉ", aligned: "Hold steady" / "የያዙትን ይቆዩ")
  - Zero allocations in `paint()` — pre-allocated Paint objects, no state changes
  - Scales proportionally on 480p–1440p screens
  - No new dependencies — pure CustomPainter
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
- **Duplicate scan detection via perceptual image hashing**
  - New `ImageHashService`: pure Dart dHash using existing `image` package (zero new deps)
  - Algorithm: resize to 9×8 grayscale, compare adjacent pixels → 64-bit hash
  - Hamming distance ≤ 10 bits (out of 64) = same paper (~15% tolerance)
  - ~1-2ms compute per image on 2GB devices — no isolate needed
  - `ScanResult.imageHash` field added for storage alongside scan data
  - `OcrService.processScannedPaper` computes hash before enhancement
  - `OcrService.checkDuplicate()` and `OcrService.hasher` exposed for UI use
  - `CameraScreen` checks new captures against batch hashes + existing Hive scans
  - Bilingual warning dialog: "Duplicate Paper" / "የተጻፈ ወረቀት" — Skip (red) or Keep
  - Hash failure never blocks scanning (returns null → skip check)
  - 26 unit tests: dHash computation, Hamming distance, thresholds, findDuplicate, edge cases

### Changed
- **Camera scan flow: continuous capture instead of per-scan processing**
  - Previous flow: tap capture → process immediately → show result → dismiss → tap capture again
  - New flow: tap capture → store image → tap capture → store image → ... → tap "Done Scanning" → batch process all
  - Removed `gradePaper()` call and `_showQuickResult()` bottom sheet from `_captureImage()`
  - Camera screen now purely captures — no grading, no result display
  - Paper counter shows "N papers captured" (bilingual Amharic/English)
  - Hint text below capture row guides first-time users
  - "Done Scanning" (✓ button) navigates to BatchScanScreen with all captured images
  - BatchScanScreen processes all images in one batch via `HybridGradingService.gradeBatch()`
  - Removed unused imports: `scan_result.dart`, `hybrid_grading_service.dart`
  - Benefits: faster capture on 2GB devices, no processing interruptions, crash-proof (no mid-scan failure)
  - Works offline — all processing is deferred until batch, runs entirely on-device

### Planned (Sprint 1)
- Real device testing on 2GB phone with actual exam papers
- Unit tests for PDF service
- Widget tests for dashboard, create assessment, review screens
- Pure Dart perspective correction
- Score override/edit flow

### Changed
- `HybridGradingService`: auto-persists every graded ScanResult
  - `gradePaper()` now saves to encrypted `scan_results` lazy box after scoring
  - Retry logic: on save failure, waits 500ms and retries once
  - On second failure: queues to in-memory `_pendingSaves` list
  - `flushPendingSaves()` runs opportunistically after every successful save
  - Validation via `ValidationService` before every write (advisory, not blocking)
  - Grading flow never breaks — persistence errors are logged, not thrown
  - New queries: `loadScanResults(assessmentId)`, `getScanResultById(id)`,
    `deleteScanResult(id)`, `getResultsForStudent(studentId)`
  - `pendingSaveCount` getter for monitoring queue depth
  - All queries use `Hive.lazyBox('scan_results')` (memory-safe on 2GB devices)
- `MigrationService`: schema versioning framework
  - Stores schema version in separate `metadata` Hive box
  - Ordered migration runner — runs pending migrations on app start
  - Each migration is a versioned function with description
  - Failed migrations log error but never block app launch
  - Wired into `main.dart` after box init, before Provider tree
  - Current schema version: 1 (baseline, no migrations yet)
- `BackupService`: data export, import, and auto-backup
  - `exportAllData()`: dumps all boxes to pretty-printed JSON with version + timestamp
  - `exportAndShare()`: export + open system share sheet via share_plus
  - `importData(path, replace: bool)`: reads JSON, validates every record via ValidationService, supports replace or merge mode, returns `{imported, skipped, errors}`
  - `recordScanAndMaybeBackup()`: auto-backup every 10 scans, keeps last 3 auto-backups, prunes older
  - `listBackups()`: returns all backup files with date, size, auto/manual flag
  - All file operations wrapped in try/catch
- `persistence_test.dart`: 25 integration tests for the full persistence layer
  - Happy path (7): box init, add/load student, add/load assessment, save/load scan result, update, delete, search
  - Validation (5): empty name, long name, invalid MCQ, negative grade, empty title
  - Edge cases (5): empty box, duplicate ID, delete nonexistent, 100 scan results bulk, corrupted data graceful
  - Error handling (3): Result type on failure, backward-compat saveAssessment, getRecentAssessments limit
  - Backup (3): JSON structure, import round-trip, merge dedup
  - Migration (2): schema version storage, framework execution
  - Each test uses fresh Hive boxes via setUp/tearDown — zero shared state
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
