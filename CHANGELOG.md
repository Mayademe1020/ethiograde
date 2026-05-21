# Changelog

All notable changes to EthioGrade will be documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

### Added
- **Integration test: batch scan pipeline** — 12 tests in `integration_test/batch_scan_test.dart`. Multi-image OMR processing (5 different sheets, 10 identical sheets), scoring consistency (all-correct, varying batch sizes), duplicate detection (identical/different byte comparison), pipeline resilience (corrupt image recovery, missing file, zero-byte, empty batch, rapid concurrent scans). Pure Dart, no device needed.
- **Integration test: coordinate-map OMR pipeline** — 13 tests in `integration_test/coordinate_map_omr_test.dart`. Pipeline basics (scan with coord map, missing/corrupt/zero-byte images), CoordinateMap model (findBubble, anchor positions, roundtrip JSON, question types/bubbles), CoordinateMapOmrResult (empty state, answerKey extraction), resilience (sequential scans, different question counts 1/5/15/25). Builds CoordinateMap programmatically matching synthetic image pixel→mm mapping.
- **Fix: missing scan_result.dart import in existing integration test** — `scan_grade_test.dart` used `AnswerMatch` without importing its defining file. Added explicit import.

### Removed
- **Telebirr payment integration** — Deferred to future release. Deleted `docs/TELEBIRR_RESEARCH.md`, `docs/FEATURE_SPLIT_PROPOSAL.md`, `lib/screens/subscription/subscription_screen.dart`. Removed subscription route, dashboard menu item, onboarding mode selector, and all Telebirr references from PROJECT_STATE.md.

### Changed
- **Auto-backup triggers on scan completion** — HybridGradingService._saveWithRetry() now calls BackupService.recordScanAndMaybeBackup() after every successful save. Previously the auto-backup infrastructure existed but was never called — dead code. Now backs up every 10 scans automatically.
- **Storage usage indicator in Settings** — New _StorageInfoTile in Settings → Data & Privacy shows total disk used (Hive + images) with a progress bar and scanned image count.
- **Corruption recovery banner** — If any Hive box is corrupt at startup, the app now shows an orange healing banner: "Some data was recovered from a corrupted storage file" instead of silently deleting data.

### Changed
- **Hive corruption: preserve instead of delete** — _openBoxSafe/_openLazyBoxSafe now copy corrupt .hive files to .corrupt.N (with timestamp) before deleting the original. Previously corrupt boxes were deleted immediately with no recovery path. Preserved files can be manually inspected or recovered.
- **deleteScanResult now cleans up image files** — When a scan result is deleted, both the original and enhanced image files are now deleted from the filesystem. Previously image files leaked permanently, filling storage over time.

### Fixed
- **DATA-001: Auto-backup was dead code** — recordScanAndMaybeBackup() was defined but never called from any code path. Backup infrastructure existed but produced zero backups.
- **DATA-002: Hive corruption wiped all data** — Corrupt boxes were deleted and recreated empty, losing all grade records silently. Now boxes are preserved for recovery.
- **DATA-003: Image files leaked on deletion** — Scan result deletion only removed the Hive entry, leaving image files on disk permanently. Over time this filled device storage.
- **"Read All Scores" on ReviewScreen** — Volume icon in AppBar reads each student's name, score, percentage, and grade sequentially. Stop button cancels mid-read. Visual highlight on current student card.
- **"Read All Scores" on GradeReviewScreen** — Same TTS pattern on the summary review screen. Row highlights during read.
- **"Read Score" on SideBySideReview** — Volume_up button now shows stop icon while speaking, stops TTS on dispose. Already wired to readScore() — now works with real TTS.
- **APK size gate in CI** — `build-apk` job prints APK size in MB, fails build if exceeds 25MB threshold.
- **MockCameraPlatform** — `integration_test/mock_camera_platform.dart` implements CameraPlatform with synthetic answer sheet image generation. `generateSyntheticAnswerSheet()` creates 1200x1600 white image with corner anchors + MCQ bubble grid. Registers as CameraPlatform.instance for tests.
- **Scan→grade pipeline integration tests** — `integration_test/scan_grade_test.dart` (10 tests): synthetic image JPEG validity/decodability, OMR template scanning (synthetic/empty/missing file), scoring pipeline (all correct/wrong/MISSING), end-to-end image→OMR→score, crash resilience (corrupt JPEG, zero-byte file). Pure Dart — runs without device.
- **Voice service tests** — 14 tests in `test/services/voice_playback_test.dart`: singleton identity, fileExists (non-existent, empty, valid), stub safety (listening, recording, playback, amplitude, playback stream), dispose, locale.

### Fixed
- **Onboarding language page broken (BUG-013)** — Amharic removal left the "language" `_OnboardingPage` with missing `titleEn` and `descEn` assigned a constructor object instead of String. Duplicate offline pages. Extra closing brace. Replaced with 4 accurate feature pages: Scan & Grade, 100% Offline, Quick Enter, Track Grades.
- **Roster preview SnackBar broken (BUG-014)** — `_saveAll()` in `roster_preview_screen.dart` had truncated ternary string `"$saved saved${failed > 0 ? "` from Amharic removal — missing else branch + closing paren. Completed ternary.
- **Dashboard truncated mid-expression (BUG-015)** — `main_dashboard.dart` was missing ~124 lines: `_showPrivacyPolicy`, `_confirmClearData`, `_clearAllData` methods + `_SettingsSection`/`_SettingsTile` classes deleted during Amharic removal. Restored English-only versions. Verified all 74 lib files brace-balanced.
- **ImportCsvScreen broken ternary** — Text widget had dangling `:` without `?` (line ~57) from Amharic removal. Instruction text now renders correctly.
- **ImportCsvScreen dead Amharic fields** — Empty Text widget + two Amharic name TextFields (firstNameAmCtrl, lastNameAmCtrl) still rendered in manual entry form but never used. Removed header, fields, and controller declarations. 4 dead lines of controller setup + dispose eliminated.

### Added
- **Integration test: full grading flow** — 10 tests in `integration_test/grading_flow_test.dart`. Covers: onboarding → demo data seeding → dashboard verification → create assessment → answer key → settings tab → bottom navigation → class detail with roster → add student from class detail. Core teacher journey end-to-end.
- **Widget tests: Quick Enter screen** — 7 tests in `test/widgets/quick_enter_test.dart`. Covers: assessment picker empty state, score table headers, no-students message, score cell dashes, save button, bottom sheet on tap. Core manual grading flow.
- **Widget tests: Import CSV screen** — 12 tests in `test/widgets/import_csv_test.dart`. Covers: instructions card, buttons, manual entry sheet open, validation (empty form, missing gender, ID too long), successful add shows student, remove from list, save all snackbar. Teacher CSV import workflow.
- **Widget tests: Transfer dialog** — 8 tests in `test/widgets/transfer_dialog_test.dart`. Covers: title/student info, class picker excludes source class, reason field, transfer button disabled/enabled, cancel closes, no-classes message. Class roster transfer flow.

### Removed
- **6 one-time Amharic cleanup scripts** — cleanup_amharic.py, fix_final.py, fix_final2.py, fix_remaining.py, fix_tests.py, clean_residual.py. Already ran, no longer needed. Only build_adapters.sh retained.
- **Orphaned services** — locale_provider.dart (dead English-only stub, never imported), topic_mastery_service.dart + model + tests (never wired up after analytics removal).
- **All Amharic i18n fields** — Stripped firstNameAmharic, lastNameAmharic, titleAmharic, textAmharic, nameAmharic from Student, Assessment, WeightedGrade, GradingScale models + their toMap/fromMap/copyWith. Removed Amharic search from StudentProvider. Removed Amharic column patterns from ExcelService. Removed Amharic seed data from DemoDataService.
- **LocaleProvider** — Deleted from codebase. Removed from main.dart provider tree. All screens converted to hardcoded English. Removed Consumer2<LocaleProvider, SettingsProvider> → Consumer<SettingsProvider>.
- **Amharic UI labels** — Removed "Name (Amharic)", "Title (Amharic)", "Amharic name" labels from 8 screens. Removed Amharic feature card from onboarding.
- **Dead Amharic test groups** — Removed ~230 lines of widget tests testing Amharic locale toggle, Amharic labels, Amharic mode navigation. Kept OCR/parsing tests for Amharic script recognition (ሀ/ለ/ሐ) — still functional for paper scanning.
- **Stale docs** — AMHARIC_REMOVAL.md (completed), CALIBRATION_GUIDE.md (outdated), FLOW_TEST.md (stale), TEACHER_GUIDE.md (outdated).
- **TopicMastery Hive adapter** — Removed TopicMasteryAdapter + MasteryLevelAdapter registration from hive_adapters.dart.

### Fixed
- **BUG-012: Weighted grading crashes HybridGradingService** — `metadata` map was referenced (lines 181-182: `metadata['weightedScoring'] = true`) before its declaration (line 187: `final metadata = <String, dynamic>{...}`). When a teacher used weighted scoring during batch scanning, `gradePaper()` threw `NoSuchMethodError` on null. Moved metadata declaration before the weighted scoring block. Pilot-blocking for any teacher using weighted grades.
- **Dead analytics comment in batch_scan_screen** — Removed empty "Compute analytics after batch completes" if-block left over from analytics feature removal.

### Removed
- **Reports screen** — Deleted `lib/screens/reports/reports_screen.dart` (665 lines). Removed route, dashboard quick action, and scan screen report button.
- **Exam scheduling** — Deleted `lib/screens/exams/create_exam_sheet.dart` (188 lines). Removed `_ExamScheduleSection` and `_ExamTile` from class detail screen. Removed `ExamProvider` from app provider tree. Model (`exam_event.dart`) and Hive adapter kept — no migration cost.
- **Report PDF generation** — Deleted `lib/services/pdf_service.dart` (2,153 lines). All report-specific methods removed: student report cards, class reports, progress reports, admin summaries, print-optimized report cards.
- **Progress service** — Deleted `lib/services/progress_service.dart` (~240 lines) and `lib/services/text_report_service.dart` (162 lines). Only used by Reports screen.
- **Dead test files** — Deleted `test/services/attendance_test.dart`, `test/services/analytics_service_test.dart`, `test/services/pdf_service_test.dart` (835 lines), `test/services/text_report_service_test.dart` (299 lines), `test/services/progress_service_test.dart` (601 lines), `test/widgets/analytics_test.dart`, `test/widgets/reports_test.dart`. Removed StudentProgress integration tests from `topic_mastery_service_test.dart`.
- **Attendance/analytics dead references** — Attendance/Analytics screens were already deleted in prior sessions. Removed dead test files and cleaned up remaining imports.

### Added
- **AnswerSheetPdfService** — Extracted answer sheet PDF generation into `lib/services/answer_sheet_pdf_service.dart` (~390 lines). Contains `generateAnswerSheetTemplate()`, `generateBlockCapitalTemplate()`, `printPdf()`, and supporting builders. Pure Dart, offline-first. Used by `answer_key_screen.dart`.

### Changed
- **Amharic removal complete** — Removed all isAm/isAmharic ternaries, parameter passing, and field declarations across 142 files. Automated via 5-pass Python scripts (cleanup_amharic.py, fix_tests.py, fix_remaining.py, fix_final.py, fix_final2.py). 0 isAm refs remaining, 1 stub getter kept. Amharic-specific test cases rewritten for English-only behavior. ~2,500 lines of bilingual ternary code eliminated. LocaleProvider kept as English-only stub. Bilingual string fields (titleAm, nameAmharic) retained on models — not worth migration cost.

### Added
- **Widget tests: Add Student screen** — 30 tests in `test/widgets/add_student_test.dart`. Covers: English labels (title, form fields, gender chips, save button), Amharic labels (title, student ID, name, gender, save), form field text input (student ID, first/last name, Amharic names), gender selection (Male, Female, switch), validation (empty form, missing gender, student ID too long, valid form passes), class dropdown visibility, preselected class, edit mode (title EN/Am, pre-fills all fields, button text EN/Am), optional parent phone field, save flow (success snackbar shows name, screen pops on save), UI structure (Scaffold, AppBar, Form, FilledButton, icons). Pilot-critical for roster setup.
- **Widget tests: Reports screen** — 18 tests in `test/widgets/reports_test.dart`. UI structure (Scaffold, AppBar, assessment dropdown, 6 report type cards, Data Export section). Assessment dropdown: empty state, filtered to grading/completed, selection updates value. Validation: all 7 cards/exports show error snackbar without selection. Icons + scrollable body verified.
- **Widget tests: Analytics screen** — 13 tests in `test/widgets/analytics_test.dart`. Empty state (icon, message, grey). With data: summary stat cards, grade distribution, question difficulty, insights, scrollable. Topic scores shown/hidden. Insights logic. Locale (English-only). Fixed `isAm` compile error in analytics_screen.dart.

### Fixed
- **AnalyticsScreen compile error** — `isAm` was undefined after Amharic removal refactor. Added `import '../../services/locale_provider.dart'` and `final isAm = context.watch<LocaleProvider>().isAmharic` in `build()`.
- **BUG-001: Weighted grades now functional** — `_saveAssessment()` auto-populates `assessmentIds` on each weighted component with the assessment ID, so `computeForExam()` can find scan results. `HybridGradingService.gradePaper()` accepts `weightedScale` parameter and applies per-paper weighted scoring via `ScoringService.computeWeightedPercentage()`. Questions are matched to components by topic tag first, then proportionally by weight. Removed redundant `saveForExam` call in `WeightedGradeSetupSheet._save()`. All callers (batch_scan_screen, camera_screen) updated to pass weighted scale.
- **BUG-002: Student transfer roster sync** — Transfer dialog now updates ClassProvider rosters via `removeStudentFromClass` + `addStudentToClass` after student transfer. `_undoTransfer` now accepts the current student state instead of using stale `widget.student`.
- **BUG-003: Reassign now discoverable on review cards** — Replaced hidden 14px edit icon with a visible "Reassign" `ActionChip` (swap icon + bilingual label) on each student result card. Large tap target, Amharic label "ተማሪ ቀይር".
- **BUG-004: Transfer discoverable from class roster** — Replaced remove-only `IconButton` trailing on student ListTiles with a `PopupMenuButton` ("⋮") exposing both "Transfer" and "Remove" options with icons and bilingual labels.
- **BUG-005: VoiceService stubs verified safe** — Audited all stub methods: all return safe void futures or empty values. No exceptions thrown. Voice buttons exist in UI but service handles gracefully. Deferred to v0.2.0.
- **BUG-008: Demo data on first launch** — `DemoDataService` seeds a demo class (Grade 5A Math) with 5 Ethiopian-named students (bilingual Amharic + English) and 1 assessment (10 MCQ/TF math questions with answer key) on first launch. Idempotent — skips if demo class already exists. Called from `OnboardingScreen._completeSetup()`. Empty dashboard no longer greets new teachers.
- **KNOWN_ISSUES.md reconciliation** — BUG-003, 004, 006, 007 were fixed in prior session but KNOWN_ISSUES.md still marked them OPEN. Moved to ✅ Fixed section with fix dates and descriptions.
- **BUG-006: Audit trail now has revert** — `AuditTrailSheet` shows a "Revert to this" button on each historical audit entry (except latest). Tapping restores the previous score/grade/percentage and records a new audit entry with revert reason. Bilingual (አማርኛ/English).
- **BUG-007: Undo last scan in batch mode** — New "Undo Last" button in batch scan bottom actions. Removes the last scan result, updates progress count, recomputes duplicates, and updates crash-recovery draft. Bilingual snackbar confirmation.
- **BUG-009 Phase 1: Answer sheet PDF + coordinate map** — `AnswerSheetGenerator` creates A4 portrait PDF with 4 corner anchors (8mm black squares), MCQ rows (4 bubbles A-D, ~4mm circles), T/F rows (2 bubbles, wider spacing), mixed type on same page, and dual-column layout for >60 questions. `CoordinateMap` JSON maps every bubble to mm positions on the page. 20 tests (coordinate map model + generator).
- **BUG-009 Phase 2: Answer sheet setup screen** — `AnswerSheetSetupScreen` lets teachers configure answer sheet generation. Features: assessment selector (dropdown or pre-selected card), auto-detected question type breakdown (MCQ/TF ranges), questions per page (Auto/30/50), header fields (school/exam/subject, pre-filled from settings), student name mode (blank or prefill with roster preview), answer key status widget with progress bar and "Fix" button. Generates PDF via AnswerSheetGenerator + share sheet. Bilingual (Amharic/English). 14 widget tests + 11 config model tests.
- **BUG-009 Phase 3: Answer key gate + status** — `Assessment` model gains `answeredQuestionCount`, `answerKeyCompleteness`, `isAnswerKeyComplete` getters and bilingual `answerKeyStatus()` method. `AssessmentCard` shows answer key progress chip (green ✓ / orange ⚠ / red ✗). Dashboard scan button gated: dialog blocks scanning if no active assessment has complete answer key, with "Fix Answer Key" button. Answer key screen scan button warns if key incomplete. 12 unit tests for model getters.
- **BUG-009 Phase 4: Coordinate-map OMR scanning** — `CoordinateMapOmrService` scans filled answer sheets using coordinate map. Pipeline: (1) Detect 4 anchor squares by searching near known mm positions, measuring darkness. (2) Compute perspective transform (mm→pixel) from anchor correspondences using homography + Gaussian elimination. (3) Sample bubble fill at each coordinate map position. (4) MCQ: 4 bubbles, T/F: 2 bubbles per question. (5) Threshold detection: >0.35 filled, >0.20 pencil (low confidence). (6) `CoordinateMapOmrResult` with per-question answers, confidence, fill ratios, correct/total/missing counts. Pure Dart — no ML, no network. 6 unit tests for result model.
- **OMR Pipeline Integration** — `Assessment.coordinateMapPath` stores path to generated `.coordmap.json`. Set automatically when PDF is generated via `AnswerSheetSetupScreen`. `BatchScanScreen._processBatch()` checks `assessment.hasCoordinateMap` and routes to `CoordinateMapOmrService` when available, falls back to legacy `HybridGradingService` when not. Scan results converted from `CoordinateMapOmrResult` to `ScanResult` with `AnswerMatch` entries, scoring, and grade calculation.
- **BUG-011: Weighted setup discoverable in its own step** — Promoted "Weighted Setup" from a buried button inside the Rubric step to a dedicated step (Step 3) in the create assessment Stepper. Step title shows configured weights summary (e.g. "Weights: 20%+30%+50%") when a scale is set. Includes edit button, skip option for single-assessment use, and bilingual Amharic/English labels. Questions moved to Step 4. 6 widget tests added.
- **Per-student PDF generation tests** — Added 4 tests to `answer_sheet_generator_test.dart` verifying: multi-page PDF with prefill (3 students → 3 pages), blank mode fallback when prefill is on but no students, coordinate map identical between prefill and blank, and size scaling (30 pages >> 1 page).
- **Half-sheet answer sheet layout (2 per A4)** — New `SheetLayout.halfSheet` option in `AnswerSheetGenerator`. Two answer sheets per A4 page with dotted cut line. Each half-sheet (~210×143mm) has: compact header, table-style bubbles (`│ 1 │ ○ │ ○ │ ○ │ ○ │`), 5 MCQ options (A-E), 4 corner anchors (7mm), and answer key checkbox at bottom. Teacher fills one sheet, checks box, scans first — scanner detects key automatically. 50% paper savings. 12 tests added.
- **Scanner answer key detection** — `CoordinateMapOmrService` samples the answer key checkbox region (from coordinate map metadata). If filled >50%, sets `isAnswerKey: true`. `answerKey` getter extracts `Map<int, String>` from detected bubbles. Batch scan screen detects answer key sheets, saves answers to Assessment, skips from student results. Grades subsequent sheets against the scanned key. 4 tests added.
- **Half-sheet scanner support** — Batch scan handles combined half-sheet map format (`layout: 'halfSheet'`). For each image, tries both half-sheet coordinate maps and picks the one with best anchor detection. Works with cut half-sheets of any size.
- **BUG-010: Dashboard recent activity** — New _RecentActivityCard on dashboard home. Shows last completed assessment (title + question count) and in-progress assessments ready to scan (with answer key status). Auto-hides when no activity. Bilingual (Amharic/English).
- **Manual range override in setup screen** — Question type breakdown now has an Edit toggle. Teachers can modify start/end question numbers and switch between MCQ/T/F per range. Add/remove range rows. Auto-detected ranges load as defaults.
- **Teacher guide rewrite** — Complete workflow: Create → Generate → Print → Fill key → Scan key → Scan students → Review. Paper layout comparison, scanning tips, troubleshooting section. Bilingual references.

### Added
- **CoordinateMap model** — `lib/models/coordinate_map.dart`: CoordinateMap, PageDimensions (A4 210×297mm), AnchorPoint (corner anchors), QuestionBubble (question + bubbles), BubblePosition (mm coordinates), SheetQuestionType enum. Pure data model with toMap/fromMap JSON serialization.
- **AnswerSheetGenerator service** — `lib/services/answer_sheet_generator.dart`: Generates A4 PDF answer sheet + coordinate map JSON. Features: 4 corner anchors (8mm squares, 10mm inset), MCQ rows (4 bubbles A-D, 18mm spacing), T/F rows (2 bubbles, 30mm spacing), mixed type support, column splitting (Q1-60 left, Q61-120 right), bilingual header (school name, student info line).
- **Coordinate map tests** — `test/services/coordinate_map_test.dart` (10 tests): toMap/fromMap roundtrip, findBubble by question+option, case-insensitive lookup, anchorPositions flattening, type serialization, default dimensions.
- **Answer sheet generator tests** — `test/services/answer_sheet_generator_test.dart` (10 tests): PDF existence, coordinate map structure for MCQ/T/F/mixed, dual-column split verification, anchor corner validation, bubble bounds checking, spacing validation.
- **AnswerSheetConfig model** — `lib/models/answer_sheet_config.dart`: QuestionTypeRange (start/end/isMcq), detectRanges() auto-detects from assessment questions, StudentNameEntry, totalQuestions/mcqCount/tfCount getters, copyWith.
- **Answer Sheet Setup screen** — `lib/screens/assessment/answer_sheet_setup_screen.dart`: Full setup UI with assessment selector, question type breakdown cards, per-page options, header fields, student name mode toggle, answer key status with progress, generate PDF button with share sheet.
- **Answer sheet setup tests** — `test/widgets/answer_sheet_setup_test.dart` (14 tests), `test/services/answer_sheet_config_test.dart` (11 tests).
- **Route: answerSheetSetup** — `AppRoutes.answerSheetSetup` (`/assessment/answer-sheet-setup`), accepts optional Assessment argument.
- **CoordinateMapOmrService** — `lib/services/coordinate_map_omr_service.dart`: Scans filled answer sheets using coordinate map. Anchor-based perspective correction (homography from 4 corner correspondences), mm→pixel mapping, mixed-type bubble sampling (MCQ 4-bubble, T/F 2-bubble), darkness threshold detection (0.35 filled, 0.20 pencil), confidence scoring. Pure Dart + image package. Never throws.
- **CoordinateMapOmrResult** — Result model with per-question answers, fill ratios, correct/total/missing/lowConfidence counts, percentage, average confidence.
- **Coordinate map OMR tests** — `test/services/coordinate_map_omr_test.dart` (6 tests): result model, percentage, missing/lowConfidence counts, isEmpty.
- **Matching question type** — New `QuestionType.matching` enum value. Teachers can create matching exercises (e.g., "Match Column A to Column B"). Answer key accepts letter sequences like "G-D-E". Scoring supports exact match and proportional partial credit.
- **Worksheet format answer parsing** — `AnswerParser` now extracts answers from mixed question+answer lines common in Ethiopian handwritten worksheets: "What is the greeting? A" → answer A. Uses end-of-line pattern detection for MCQ letters, T/F words, and matching sequences.
- **Spatial-aware parsing** — New `parseAnswersWithPosition()` method uses OCR text region coordinates to group question numbers with answers on the same horizontal line. Handles worksheets where question number and answer are separate OCR text blocks.
- **Matching pair detection** — `AnswerParser._tryParseMatchingPair()` detects space/comma-separated letter sequences like "G D" or "G,D,E". Distinguishes matching (letters beyond E) from MCQ multi-select. Normalizes to "MATCH:G-D" format.
- **Matching score checking** — `ScoringService._checkMatchingAnswer()` compares letter sequences across formats (MATCH:G-D, "G D", "g-d"). Case-insensitive, format-agnostic.
- **Matching partial credit** — `ScoringService.scoreMatchingPartial()` awards proportional points per correct position. 3/5 correct on 10-point question = 6.0 points.
- **Handwritten T/F extraction** — `AnswerParser._extractAnswerFromText()` detects True/False/እውነት/ሐሰት at end of question lines. Works for both English and Amharic scripts.
- **Matching test suite** — `test/services/matching_scoring_test.dart` with 35+ tests covering: matching pair detection, worksheet format extraction, spatial parsing, real exam patterns, scoring exact/partial, regression for MCQ/TF.

### Changed
- **Question.isObjective** — Now includes `QuestionType.matching` (matching answers are programmatically verifiable). Hybrid grading merge uses OCR fallback for matching (OMR can't detect handwritten letter sequences).
- **AnswerParser.normalizeAnswer** — Extended with matching pair detection via `_tryParseMatchingPair()`. Existing MCQ/TF/short-answer normalization unchanged.
- **HybridGradingService._mergeAnswers** — Merge logic includes matching in objective question handling. OMR preferred when available, OCR fallback for handwritten worksheets.
- **ValidationService** — Added `QuestionType.matching` case: validates that matching correct answer is non-empty.
- **Create assessment screen** — Added "Matching" button row (ማዛመድ / Match). Default matching question has empty correct answer (teacher types sequence).
- **Answer key screen** — Added matching type label ("Match" / "ማዛመድ") and correct matches display.

### Changed
- **HybridGradingService API** — `gradePaper()`, `gradeBatch()`, and `regradePaper()` now accept optional `WeightedGradeScale? weightedScale` parameter for per-paper weighted scoring.

### Added
- **Fix Wrong mode** — "Fix Wrong" button on review screen filters to only wrong/MISSING answers. Step-through one at a time with prev/next navigation. Shows WRONG 1/3 progress. Auto-advances after fixing. Exits with "All answers corrected!" snackbar when done. MISSING answers shown first.
- **MISSING answer quick-entry** — When OCR misses a question entirely, shows prominent orange card with "What did the student write?" prompt. A/B/C/D/E (MCQ) or True/False buttons for one-tap entry. Auto-advances to next wrong answer.
- **Raw OCR text in answer tiles** — `_AnswerTile` now shows `OCR read: "1. A"` below detected answer when raw OCR text is available. Helps teachers verify scan quality.
- **Low confidence indicator** — Answer tiles show warning icon + percentage when confidence < 60%.
- **CI: build_runner step** — Both analyze-and-test and build-apk jobs now run `build_runner` before any compilation step, generating Hive `.g.dart` adapters automatically on every push.
- **CI: APK artifact upload** — Debug APK uploaded as downloadable artifact (30-day retention) after successful build. Teachers can grab it from the Actions tab.
- **Teacher install guide** — `TEACHER_GUIDE.md` with step-by-step APK download, installation, and feature walkthrough for pilot testing.
- **BatchScanScreen widget tests** — 9 tests covering empty state (EN/Am), app bar title, progress header, 0/0 counter, stats/review button absence. CameraScreen excluded (camera hardware dependency).
- **GradeReviewScreen widget tests** — 14 tests covering empty state (EN/Am), app bar title, student names, Average/Median/Pass/Highest/Lowest/Total stats, Top/Low badges, Confirm & Save button, score fractions, edit buttons, Amharic labels.
- **Sprint board updated** — Dashboard/Review tests marked ✅ Done, Settings tests marked ✅ Done (covered in dashboard_test.dart), BatchScan marked 🟡 In Progress, Flutter SDK blocker noted.

### Fixed
- **Revert compileSdk back to 36** — plugins (camera_android, shared_preferences_android, integration_test, flutter_plugin_android_lifecycle) all require Android SDK 36. Downgrading to 35 caused plugin incompatibility. User must install SDK 36 locally. CI now installs it automatically.
- **Downgrade compileSdk/targetSdk 36 → 35** — ~~Android 16 (API 36) SDK is too new and not widely installed. Builds failed with "Gradle build failed to produce an .apk file" on machines without it. API 35 (Android 15) is stable and universally available. No code changes needed — app uses no API 36 features.~~ REVERTED: plugins require SDK 36.
- Hive boxes now closed on app lifecycle detach via `Hive.close()` — prevents data corruption on force-close. Lifecycle observer fires only on `detached` (not `paused`) to avoid unnecessary teardown during app switches.
- OcrService TextRecognizer now disposed on app lifecycle detach — prevents native memory leak on low-spec Android phones
- Student.copyWith now accepts metadata parameter — enables transfer history persistence

### Added
- **Hive TypeAdapters** — All 24 model types annotated with @HiveType/@HiveField for type-safe binary serialization. Replaces fragile raw Map storage. Models: Student, ClassInfo, Assessment, Question, EssayRubric, ScanResult, AnswerMatch, BoundingBox, AttendanceEntry, AuditEntry, ExamEvent, GradingScale, GradeRange, Teacher, TopicMastery, WeightedGradeScale, GradeComponent + 7 enums. Migration service auto-converts existing Map data on first launch after upgrade.
- **GitHub Actions CI** — Runs `flutter analyze`, `flutter test --coverage`, `dart format` check, `print()` violation scan, and **debug APK build** on every push/PR to main. Uses `subosito/flutter-action` with dependency caching. Resolves "No CI pipeline" risk + catches build failures before merge.
- PROJECT_STATE.md, CHANGELOG.md, OPERATIONS.md governance files
- **Audit Trail** — AuditEntry model + AuditService records every grade change with who/when/what/why. Answers parent disputes by providing complete edit history.
- **Auto-Save Drafts** — DraftService saves grading progress every session. On crash or app kill, teacher resumes where they left off. Drafts stored in encrypted Hive.
- **Weighted Grades** — WeightedGradeScale model + WeightedGradeService computes composite grades (e.g., Quiz 20% + Midterm 30% + Final 50%). Supports drop-lowest-N, partial grading, and recalculation on scale change.
- **Student Transfers** — StudentTransferService handles mid-term class changes. Grade history follows the student via scan result records. Transfer log stored separately for analytics.
- **Scale Recalculation** — WeightedGradeService.recalculateWithNewScale() recomputes letter grades when school changes rubric type mid-year. Percentages unchanged, only letter mapping changes.
- **Edge-case Hive boxes** — audit_trail, grading_drafts, student_transfers, weighted_scales opened at startup with AES-256 encryption.
- Tests: weighted_grade_test.dart, audit_entry_test.dart, draft_service_test.dart, hive_lifecycle_test.dart, hive_adapter_test.dart

### Added
- **Quick Grade widget tests** — 28 tests covering EN/Amharic labels, form validation (empty fields, out-of-range count, wrong-format answers, count mismatch), answer key parsing (MCQ, T/F, mixed, semicolons, spaces, lowercase delimiters), navigation on valid submit, and UI structure (icons, fields, scroll). Critical for pilot — Quick Grade is the demo hook teachers try first.

### UI (New)
- **Audit Trail Viewer** — Bottom sheet showing timeline of grade changes. Accessible from "History" button on each result card. Shows who/when/what with bilingual descriptions.
- **Resume Grading Banner** — Dashboard banner when grading draft exists. Shows class, exam, progress, last-saved time. Tap to resume, swipe to discard with confirmation.
- **Grade Review Screen** — Summary table before final submit. Shows all students with scores, class stats (average, median, pass rate), highest/lowest highlights, edit per row.
- **Weighted Grade Setup Sheet** — Bottom sheet for defining components (name, weight %, drop-lowest). Live validation (must total 100%), example calculation preview.
- **Student Transfer Dialog** — Long-press student in class roster → transfer picker. Confirmation, reason field, undo snackbar (10s window).

## [0.1.0] - 2026-04-12

### Added
- Core app scaffold: onboarding, dashboard, 4-tab navigation
- Student management: CRUD, CSV import, multi-class support, search/filter
- Class management: create, detail view, roster preview
- Assessment creation: MCQ, T/F, short answer, essay question types
- Answer key editor with per-question configuration
- Camera scanning with ML Kit OCR (on-device, offline)
- OMR bubble detection with template-based pixel sampling
- Hybrid grading: parallel OCR + OMR, best-result selection
- Batch scanning with duplicate detection (image hash + answer fingerprint)
- Quick Grade mode (one-off grading without assessment setup)
- Quick Enter mode (manual score entry for calculation-heavy subjects)
- Review screen with score overview and side-by-side comparison
- Analytics dashboard: class performance, topic mastery, grade distribution
- PDF and text report export (bilingual)
- Attendance tracking per class
- Exam scheduling with calendar events
- Excel/CSV import and export (pure Dart, no native deps)
- Encrypted backup and restore (AES-256 JSON)
- Custom grading scales (teacher/school-specific rubrics)
- Full Amharic + English bilingual support
- Amharic name normalization for OCR matching
- Correction learner for adaptive pattern matching
- Ethiopian flag-inspired color palette
- Noto Sans Ethiopic font integration
- Perspective correction for angled photos
- Image enhancement pipeline (EXIF, downscale, grayscale, contrast)
- Encrypted Hive storage with auto-recovery on corruption

### Deferred (v0.2.0)
- Voice feedback (TTS + STT)
- Payment/subscription integration
