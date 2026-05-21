# PROJECT_STATE.md

## Health: 🟢 Active Development — v0.1.0 stable. Sprint board complete. v0.2.0 roadmap created (Voice, Camera Mock, Polish).

| Metric | Value |
|--------|-------|
| Version | 0.1.0+1 |
| Flutter SDK | >=3.41.6 |
| Compile/Target SDK | 36 (Android 16) — required by camera, shared_preferences, integration_test plugins |
| Dart SDK | >=3.8.0 <4.0.0 |
| Lib LOC | ~24,500 (incl. generated Hive adapters) |
| Test LOC | ~14,900 |
| Files | 74 lib + 56 test + 3 integration |
| Hive Boxes | students, assessments, scan_results (lazy), settings_pii, metadata, audit_trail, grading_drafts, student_transfers, weighted_scales |
| Encryption | AES-256 via HiveAesCipher + FlutterSecureStorage |

## Feature Matrix

| Feature | Status | Notes |
|---------|--------|-------|
| Onboarding | ✅ Done | English-only, 4 feature pages (Scan & Grade, Offline, Quick Enter, Track Grades) + setup |
| Dashboard | ✅ Done | Stats, classes, quick actions |
| Class Management | ✅ Done | Create, detail, roster, multi-class students |
| Student CRUD | ✅ Done | Add, edit, import CSV, search, class filter |
| Assessment Create | ✅ Done | MCQ, T/F, short answer, essay types |
| Answer Key | ✅ Done | Per-question correct answers |
| Camera Scanning | ✅ Done | ML Kit OCR, perspective correction, rotation |
| OMR Bubbles | ✅ Done | Template-based, auto-scale, pencil detection |
| Hybrid Grading | ✅ Done | OCR + OMR parallel, best-result selection |
| Batch Scan | ✅ Done | Multi-paper, duplicate detection |
| Quick Grade | ✅ Done | No assessment needed, fast one-off grading |
| Quick Enter | ✅ Done | Manual score entry for calculation-heavy subjects |
| Review Screen | ✅ Done | Score overview, side-by-side, rescan |
| Analytics | 🗑️ Removed | Screen + service deleted. Topic mastery service kept. |
| Reports | 🗑️ Removed | Screen + PDF report generation deleted. Answer sheet PDF extracted to AnswerSheetPdfService. |
| Attendance | 🗑️ Removed | Screen + service deleted. CSV roster parsing still strips attendance marks. |
| Exam Scheduling | 🗑️ Removed | Screen, provider, model, and Hive adapter all deleted. |
| Excel Import/Export | ✅ Done | CSV-based (pure Dart, no native deps) |
| Backup/Restore | ✅ Done | Encrypted JSON export/import |
| Custom Grading Scales | ✅ Done | Teacher/school-specific rubrics |
| ~~Bilingual (Am/En)~~ | 🗑️ Removed | English-only. LocaleProvider deleted, all Amharic fields stripped. |
| **Amharic Removal** | ✅ Done | All Amharic fields, labels, locale provider, and toggle fully stripped. 0 refs in lib/. English-only codebase. |
| Voice Feedback | 🔶 Stub | Deferred to v0.2.0 |
| Correction Learner | ✅ Done | Adaptive pattern matching |
| **Audit Trail** | ✅ Done | Who/when/what/why for every grade change + UI viewer. Includes scale_change entries for grading rubric modifications. |
| **Undo/Revert** | ✅ Done | Audit trail enables revert; confirmation dialog pattern |
| **Auto-Save Drafts** | ✅ Done | Per-session grading drafts, recover on restart + dashboard banner |
| **Weighted Grades** | ✅ Fixed | Composite scoring + per-paper weighted scoring now linked. Components auto-populate assessmentIds on save. HybridGradingService applies weights during scan. |
| **Student Transfers** | ✅ Fixed | Transfer dialog now updates ClassProvider rosters + uses correct student state on undo |
| **Scale Recalculation** | ✅ Done | Recompute letter grades on rubric change |
| **Grade Review Screen** | ✅ Done | Summary table, class stats, edit per row, confirm & save |
| **Per-Question Review** | ✅ Done | Side-by-side view, detected vs correct, raw OCR text, confidence indicator, edit per question |
| **Fix Wrong Mode** | ✅ Done | Step-through wrong/MISSING answers one at a time with quick-entry buttons |
| **MISSING Answer Recovery** | ✅ Done | Prominent card for unread questions with A/B/C/D/E or T/F quick-entry |
| **Grading Scale Confirmation** | ✅ Done | Confirmation dialog before saving scale changes. Explains impact on future sessions. Audit trail entry recorded via AuditService.recordScaleChange(). |
| **Matching Question Type** | ✅ Done | New QuestionType.matching + answer parser detects letter sequences (G D → MATCH:G-D) + scoring supports exact match and partial credit |
| **Worksheet Format Parsing** | ✅ Done | AnswerParser extracts answers from mixed question+answer lines ("What is the greeting? A" → A). Spatial-aware parsing groups answers by position. |
| **Handwritten T/F Detection** | ✅ Done | AnswerParser handles True/False/እውነት/ሐሰτ at end of question lines. Amharic + English. |
| **Demo Data on First Launch** | ✅ Done | Seeds Grade 5A Math class + 5 students (bilingual) + 10-question MCQ/TF assessment on first launch. Idempotent. |
| **Answer Sheet PDF + Coordinate Map** | ✅ Done | Full 4-phase OMR pipeline + integration. Phase 1: AnswerSheetGenerator + CoordinateMap. Phase 2: Setup screen. Phase 3: Answer key gate. Phase 4: CoordinateMapOmrService. Integration: coordinateMapPath on Assessment, BatchScanScreen routes to coordinate-map OMR when available, falls back to hybrid grading. Batch tracking + undo + duplicate detection working. |
| **Half-Sheet Paper Saving** | ✅ Done | SheetLayout.halfSheet — two answer sheets per A4 with table bubbles (│ 1 │ ○ │ ○ │ ○ │ ○ │), 5 MCQ options, answer key checkbox, cut line. 50% paper savings. Setup screen toggle. |

## Known Issues

**→ See [KNOWN_ISSUES.md](KNOWN_ISSUES.md) — the single source of truth for all bugs and friction.**

### Recently Fixed
- **BUG-013: Onboarding language page broken** — Amharic removal left the "language" `_OnboardingPage` with missing `titleEn` and `descEn` assigned a `_OnboardingPage` constructor instead of a String. Duplicate offline page. Extra closing brace. Fixed: replaced with 4 accurate feature pages (Scan & Grade, Offline, Quick Enter, Track Grades).
- **BUG-014: Roster preview SnackBar truncated** — `_saveAll()` in `roster_preview_screen.dart` had broken ternary string from Amharic removal: `"$saved saved${failed > 0 ? "` — missing else branch and closing paren. Fixed: completed ternary expression.
- **BUG-015: Dashboard truncated mid-expression** — `main_dashboard.dart` was missing ~124 lines after `_showPrivacyPolicy` method declaration. `_confirmClearData`, `_clearAllData`, `_SettingsSection`, `_SettingsTile` all deleted during Amharic removal. Restored English-only versions. All 74 lib files now brace-balanced (verified).
- **BUG-012: Weighted grading crashes HybridGradingService** — `metadata` map referenced before declaration in `gradePaper()` (lines 181-182 before 187). When weighted scale was active, `NoSuchMethodError` on null map. Fixed by moving metadata declaration before weighted scoring block. Pilot-blocking for any teacher using weighted grades.

Every session reads KNOWN_ISSUES.md first. Every bug found goes there. Every fix removes it. No re-discovery.

## Sprint Board

### Sprint: Governance & Stability ✅ Complete

| Task | Status | Priority |
|------|--------|----------|
| Create PROJECT_STATE.md | ✅ Done | P0 |
| Create CHANGELOG.md | ✅ Done | P0 |
| Create OPERATIONS.md | ✅ Done | P0 |
| Fix OcrService resource leak (dispose) | ✅ Done | P1 |
| Close Hive boxes on app exit | ✅ Done | P2 |
| Add GitHub Actions CI | ✅ Done | P2 |
| Hive type adapters (type-safe serialization) | ✅ Done | P3 |

### Sprint: Testing & Quality

| Task | Status | Priority | Notes |
|------|--------|----------|-------|
| Generate Hive .g.dart adapters locally | 🔴 Blocked | P0 | Requires Flutter SDK (`build_runner`). CI now generates them automatically on every push; local generation still needs Flutter. |
| CI: generate adapters + upload APK | ✅ Done | P0 | build_runner runs before analyze/test/build in both CI jobs. APK uploaded as artifact (30-day retention). |
| Teacher install guide | ✅ Done | P1 | `TEACHER_GUIDE.md` — step-by-step APK download + feature walkthrough |
| Per-question raw OCR display | ✅ Done | P1 | `_AnswerTile` shows OCR raw text below "Detected:" when available |
| Fix Wrong mode (step-through) | ✅ Done | P1 | Toggle button filters to wrong/MISSING answers, step-through one at a time with prev/next |
| MISSING answer quick-entry | ✅ Done | P1 | Prominent "What did the student write?" card with A/B/C/D/E or T/F buttons, auto-advances |
| Widget tests: Dashboard, Review screens | ✅ Done | P1 | `test/widgets/dashboard_test.dart` (12 tests), `test/widgets/review_test.dart` (5 tests) |
| Widget tests: Scanning flow (BatchScan) | ✅ Done | P1 | `test/widgets/batch_scan_test.dart` (9 tests) — CameraScreen skipped (camera hardware dep) |
| Widget tests: Settings, Backup/Restore | ✅ Done | P1 | Settings tab covered in `dashboard_test.dart` (language toggle, privacy, backup buttons, version) |
| Integration test: full grading flow | ✅ Done | P2 | `integration_test/grading_flow_test.dart` (10 tests): onboarding, demo data, create assessment, answer key, navigation, class detail, add student |
| Widget tests: Grade Review Screen | ✅ Done | P2 | `test/widgets/grade_review_test.dart` (14 tests) |
| Widget tests: Quick Enter screen | ✅ Done | P1 | `test/widgets/quick_enter_test.dart` (7 tests) — picker, score table, no-students, cells, bottom sheet |
| Widget tests: Import CSV screen | ✅ Done | P1 | `test/widgets/import_csv_test.dart` (12 tests) — instructions, manual entry, validation, add/remove/save |
| Widget tests: Transfer dialog | ✅ Done | P1 | `test/widgets/transfer_dialog_test.dart` (8 tests) — title, class picker, reason, button states, no-classes |
| Widget tests: Grading Scale Editor | ✅ Done | P1 | `test/widgets/grading_scale_editor_test.dart` (8 tests) — default template, edit mode, confirmation dialog, impact warning, cancel, add/remove range |

### Sprint: UX Polish & Safety

| Task | Status | Priority | Bug | Notes |
|------|--------|----------|-----|-------|
| Make reassign visible on review cards | ✅ Done | P1 | BUG-003 | Visible "Reassign" ActionChip with swap icon + bilingual label |
| Add transfer icon to class roster | ✅ Done | P1 | BUG-004 | PopupMenuButton with Transfer + Remove options, bilingual |
| Audit trail revert button | ✅ Done | P1 | BUG-006 | "Revert to this" per audit entry, restores previous grade + records audit |
| Batch scan undo last scan | ✅ Done | P1 | BUG-007 | Undo Last button, removes last result, updates draft |
| Verify VoiceService safety | ✅ Done | P2 | BUG-005 | All stubs are safe no-ops, no crash risk |
| Demo data on first launch | ✅ Done | P1 | BUG-008 | DemoDataService seeds class + 5 students + 10-question assessment on first launch. Idempotent. 7 tests. |

### Sprint: OMR Pipeline — Phase 1: PDF + Coordinate Map ✅ Complete

| Task | Status | Priority | Notes |
|------|--------|----------|-------|
| CoordinateMap model (mm-based) | ✅ Done | P0 | CoordinateMap, PageDimensions, AnchorPoint, QuestionBubble, BubblePosition, SheetQuestionType |
| AnswerSheetGenerator service | ✅ Done | P0 | A4 PDF + JSON coordinate map. Corner anchors, MCQ/T/F rows, mixed type, dual column >60 Q |
| Coordinate map tests (10) | ✅ Done | P0 | Roundtrip JSON, findBubble, anchorPositions, type serialization, spacing validation |
| Generator tests (10) | ✅ Done | P0 | PDF existence, coordinate map structure, MCQ/T/F/mixed, column split, anchor positions, bounds checking |

### Sprint: OMR Pipeline — Phase 2: Answer Sheet Setup UI ✅ Complete

| Task | Status | Priority | Notes |
|------|--------|----------|-------|
| AnswerSheetConfig model | ✅ Done | P0 | QuestionTypeRange, detectRanges(), StudentNameEntry, copyWith |
| AnswerSheetSetupScreen | ✅ Done | P0 | Assessment selector, type breakdown, per-page, header, student mode, answer key status, generate button |
| Route wiring | ✅ Done | P0 | AppRoutes.answerSheetSetup, accepts Assessment argument |
| Config model tests (11) | ✅ Done | P1 | detectRanges (MCQ/TF/mixed/alternating/empty/matching), QuestionTypeRange, computed properties |
| Widget tests (14) | ✅ Done | P1 | EN/Am labels, assessment card, type breakdown, per-page options, header fields, student mode, answer key status, generate button states |

### Sprint: OMR Pipeline — Phase 3: Answer Key Gate + Status ✅ Complete

| Task | Status | Priority | Notes |
|------|--------|----------|-------|
| Assessment.answeredQuestionCount getter | ✅ Done | P0 | Counts non-null, non-empty correct answers |
| Assessment.isAnswerKeyComplete getter | ✅ Done | P0 | True when all questions have answers |
| Assessment.answerKeyCompleteness getter | ✅ Done | P0 | 0.0–1.0 ratio |
| Assessment.answerKeyStatus() method | ✅ Done | P0 | Bilingual "12/40 answers set" |
| AnswerKeyStatusChip in AssessmentCard | ✅ Done | P1 | Green ✓ / orange ⚠ / red ✗ with count |
| Gate dashboard scan button | ✅ Done | P1 | Dialog if no active assessment with complete key |
| Gate answer key screen scan button | ✅ Done | P1 | Warning dialog if key incomplete |
| Answer key gate tests (12) | ✅ Done | P1 | answeredQuestionCount, completeness, isComplete, status string, T/F, mixed, empty |

### Sprint: OMR Pipeline — Phase 4: OMR Scanning ✅ Complete

| Task | Status | Priority | Notes |
|------|--------|----------|-------|
| CoordinateMapOmrService | ✅ Done | P0 | Anchor detection, perspective transform (mm→pixel), mixed-type sampling, fill threshold, confidence scoring |
| Result model (CoordinateMapOmrResult) | ✅ Done | P0 | answers, totalQuestions, correctAnswers, percentage, missingAnswers, lowConfidenceAnswers |
| Result model tests (6) | ✅ Done | P1 | empty, percentage, missingAnswers, lowConfidenceAnswers, isEmpty |
| Anchor detection (4 corners) | ✅ Done | P0 | Search near approximate mm positions, darkest-square matching, 0.5 darkness threshold |
| Perspective correction (anchor-based) | ✅ Done | P0 | Homography from 4 anchor correspondences (mm→pixel), Gaussian elimination, inverse mapping |
| Mixed-type sampling | ✅ Done | P0 | MCQ = sample 4 positions, T/F = sample 2 positions per coordinate map |
| Darkness threshold + confidence | ✅ Done | P0 | fill > 0.35 = filled, > 0.20 = pencil (low conf), confidence = sigmoid of fill ratio |

### Sprint: OMR Pipeline — Phase 5: Paper Saving + Answer Key Checkbox ✅ Complete

| Task | Status | Priority | Notes |
|------|--------|----------|-------|
| Half-sheet layout (2 per A4) | ✅ Done | P0 | SheetLayout.halfSheet, table bubbles │ 1 │ ○ │ ○ │, 5 options A-E, cut line |
| Answer key checkbox on sheet | ✅ Done | P0 | Checkbox at bottom of each half-sheet, coordinate map includes position |
| Paper layout toggle in setup screen | ✅ Done | P0 | Full A4 / Half-sheet selector, info box, bilingual |
| Half-sheet tests (12) | ✅ Done | P1 | Layout split, anchors, bounds, checkbox, prefill pairing |
| Scanner answer key detection | ✅ Done | P0 | Checkbox sample >0.50 → isAnswerKey + answerKey getter |
| CoordinateMapOmrService half-sheet support | ✅ Done | P0 | Tries both half-sheet maps, picks best anchors |
| Answer key save from scan | ✅ Done | P0 | _saveAnswerKeyToAssessment() updates questions with scanned answers |
| Scanner integration tests | ✅ Done | P1 | 4 tests: isAnswerKey default/set, answerKey extraction, empty |

### Sprint: Pilot Readiness — Test Coverage

| Task | Status | Priority | Notes |
|------|--------|----------|-------|
| Widget tests: Quick Grade screen | ✅ Done | P1 | 28 tests: EN/Am labels, form validation (empty, range, format, mismatch), answer key parsing (MCQ/TF/mixed, semicolons, spaces, lowercase), navigation, UI structure |
| Widget tests: Add Student screen | ✅ Done | P1 | 30 tests: EN/Am labels, form fields, gender selection, validation (empty, missing gender, too-long ID), class dropdown, preselected class, edit mode pre-fill/title/button, Amharic name input, optional fields, save flow (snackbar + pop), UI structure |
| Widget tests: Reports screen | 🗑️ Removed | Tests deleted with Reports screen. |
| Widget tests: Analytics screen | 🗑️ Removed | Tests deleted with Analytics screen. |
| Widget tests: Quick Enter screen | ✅ Done | P1 | `test/widgets/quick_enter_test.dart` (7 tests) |
| Widget tests: Import CSV screen | ✅ Done | P1 | `test/widgets/import_csv_test.dart` (12 tests) |
| Widget tests: Transfer dialog | ✅ Done | P1 | `test/widgets/transfer_dialog_test.dart` (8 tests) |
| Widget tests: Grading Scale Editor | ✅ Done | P1 | `test/widgets/grading_scale_editor_test.dart` (8 tests) |
| Integration test: full grading flow | ✅ Done | P2 | `integration_test/grading_flow_test.dart` (10 tests) |

---

## v0.2.0 Roadmap

### Sprint: Voice Feedback (TTS + Voice Notes)

| Task | Status | Priority | Notes |
|------|--------|----------|-------|
| Add flutter_tts dependency | ✅ Done | P0 | Only TTS re-enabled (~2MB APK delta). STT/record/playback kept as stubs. |
| Implement VoiceService real TTS methods | ✅ Done | P0 | flutter_tts integration: initialize, speak, stopSpeaking, readScore, readAllScores. English-only. |
| Add "Read Scores" button to ReviewScreen | ✅ Done | P1 | Volume icon in AppBar. Reads all students sequentially. Stop button. Visual highlight on current student. |
| Add "Read Scores" button to GradeReviewScreen | ✅ Done | P1 | Same pattern as ReviewScreen. Highlights current row during read. |
| Voice service widget tests | ✅ Done | P1 | 14 tests: singleton, fileExists, stub safety, stream, state. |
| Add "Read Score" to per-question review | ✅ Done | P2 | SideBySideReview volume_up button shows stop icon while speaking, calls stopSpeaking() on dispose. Already wired to readScore() — now works with real TTS. |
| APK size impact check | ✅ Done | P2 | CI build-apk job prints APK size, fails build if >25MB. |
| Research camera mock strategy | ✅ Done | P0 | MockCameraPlatform created: implements CameraPlatform with synthetic answer sheet images + image generation helper. |
| Create MockCameraPlatform | ✅ Done | P1 | `integration_test/mock_camera_platform.dart` — registers as CameraPlatform.instance, returns synthetic JPEG from takePicture(). generateSyntheticAnswerSheet() creates 1200x1600 white image with corner anchors + MCQ bubble grid. |
| Integration test: scan → grade pipeline | ✅ Done | P1 | `integration_test/scan_grade_test.dart` — 10 tests: synthetic image generation (JPEG validity, decodability, answer variation), OMR template scanning (synthetic, empty, missing file), scoring pipeline (correct/wrong/MISSING), end-to-end (image→OMR→score), resilience (corrupt JPEG, zero-byte file). Pure Dart — no device needed. |

### Sprint: Integration Test — Camera Mock

| Task | Status | Priority | Notes |
|------|--------|----------|-------|
| Research camera mock strategy | ✅ Done | P0 | CameraPlatform.instance override with mock implementation. |
| Create MockCameraPlatform | ✅ Done | P1 | `integration_test/mock_camera_platform.dart` — full CameraPlatform implementation. generateSyntheticAnswerSheet() for test images. |
| Integration test: scan → grade pipeline | ✅ Done | P1 | `integration_test/scan_grade_test.dart` — 10 tests covering image gen, OMR scanning, scoring, e2e pipeline, crash resilience. Pure Dart, no device needed. |
| Integration test: batch scan with mock | ✅ Done | P2 | 12 tests: multi-image OMR, scoring consistency, duplicate detection, pipeline resilience (corrupt/zero-byte/missing/rapid). |
| Integration test: answer sheet coordinate map OMR | ✅ Done | P2 | 13 tests: pipeline basics, CoordinateMap model (findBubble, anchors, roundtrip), CoordinateMapOmrResult, resilience. |

### Sprint: Data Safety — Critical Fixes

| Task | Status | Priority | Notes |
|------|--------|----------|-------|
| Auto-backup trigger on scan save | ✅ Done | P0 | HybridGradingService._saveWithRetry() now calls BackupService.recordScanAndMaybeBackup() after every successful save. Was dead code — never called. |
| Remove auto-delete on Hive corruption | ✅ Done | P0 | _openBoxSafe/_openLazyBoxSafe now rename corrupt .hive files to .corrupt.N (preserves bytes) instead of deleting. Original deleted only after copy succeeds. |
| Corruption recovery banner | ✅ Done | P0 | New _InitStatus.corruption + _InitBanner widget shows orange healing banner: "Some data was recovered from a corrupted storage file. Check Settings → Storage for details." |
| Delete image files on record deletion | ✅ Done | P1 | HybridGradingService.deleteScanResult() now loads record first, deletes imagePath + enhancedImagePath from filesystem, then deletes Hive entry. New _deleteImageFile() helper never throws. |
| Storage usage indicator in Settings | ✅ Done | P1 | _StorageInfoTile in Settings → Data & Privacy. Shows total MB used + scanned image count. Progress bar (green < 200MB, red > 200MB). FutureBuilder loads async. |
| Data safety tests | ✅ Done | P1 | 7 tests in test/services/data_safety_test.dart: image deletion (exists/missing/null), corrupt box preservation, storage calculation, ScanResult roundtrip. |

### Sprint: Polish & Hardening

| Task | Status | Priority | Notes |
|------|--------|----------|-------|
| APK size audit | 📋 Pending | P2 | Profile release APK. Target <20MB. Remove unused assets. |
| Accessibility audit (TalkBack) | 📋 Pending | P2 | Verify screen reader works for grading flow. Semantics labels. |
| Battery drain test on 2GB device | 📋 Pending | P2 | Extended batch scan session — monitor memory + thermal. |

## Risk Register

| Risk | Severity | Mitigation |
|------|----------|------------|
| TextRecognizer never disposed | 🔴 High | Fixed — dispose added to app lifecycle |
| No CI pipeline | ✅ Resolved | GitHub Actions CI with analyze + test + format check |
| No CI APK build — build failures undetected | ✅ Resolved | CI now builds debug APK + verifies output exists |
| compileSdk 36 requires Android 16 SDK | ✅ Resolved | compileSdk 36 is correct (plugins require it). User must install SDK 36 via Android Studio SDK Manager or `sdkmanager "platforms;android-36"` |
| No Hive adapters — raw Map serialization | ✅ Resolved | All 24 types annotated; migration service converts existing data; run `scripts/build_adapters.sh` to generate .g.dart |
| Flutter SDK not on CI server | ✅ Resolved | subosito/flutter-action with cache on GitHub-hosted runner |
| Voice features stubbed | 🟢 Low | Clear deferral to v0.2.0 |
| Flutter SDK not on dev server | ✅ Resolved | CI handles all Flutter ops. Integration test written. Dev server for code review + doc updates + pure-Dart work. 74 lib files verified brace-balanced. |
| No testable APK for teachers | ✅ Resolved | CI uploads debug APK as artifact (30-day retention). Teachers download from Actions tab. `TEACHER_GUIDE.md` created with install instructions. |
| Weighted grade not linked | ✅ Resolved | Components auto-populate with assessment ID on save; per-paper weighted scoring via ScoringService |
| Transfer roster stale | ✅ Resolved | Transfer dialog updates ClassProvider rosters; undo uses correct student state |

## Architecture

- **State:** Provider (ChangeNotifier)
- **Storage:** Hive (encrypted) + SharedPreferences (first-launch flag)
- **OCR:** ML Kit TextRecognizer (on-device, offline)
- **OMR:** Pixel sampling (pure Dart, image package)
- **PDF:** pdf package (pure Dart)
- **No network calls** — everything offline-first
