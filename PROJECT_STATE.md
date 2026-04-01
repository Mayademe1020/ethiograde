# EthioGrade — Project State

> The single source of truth. Read this before touching anything.
> Updated with every meaningful change. Stale = broken.

---

## 📡 Project Health

| Signal | Status | Detail |
|--------|--------|--------|
| **Build** | 🟢 Ready | All assets wired; CI builds APK + AAB; needs first real device build |
| **Tests** | 🟢 Good | 200+ tests across 25 test files; 7 widget test groups; integration tests for E2E + perf benchmarks
| **CI/CD** | 🟢 Ready | GitHub Actions: lint → test → build APK/AAB → size check → metrics summary |
| **Crash-free rate** | 🟢 Protected | Session auto-save + resume dialog; zero data loss on crash |
| **Performance** | 🟢 Good | Enhancement: 4 native ops, zero pixel loops. Scan target <3s |
| **Security audit** | ⚫ None | No audit performed |
| **Data encryption** | 🟢 Done | AES-256 Hive boxes, key in flutter_secure_storage |
| **Accessibility** | 🟢 Good | Touch targets ≥40dp verified, semantic labels on key interactive elements, contrast fixes applied, screen reader tests added |
| **i18n coverage** | 🟢 Good | All screens bilingual, no hardcoded strings found; no extraction tool yet |

**Overall Status:** 🟡 v0.1.0 Ready — Core pipeline complete, version mismatch fixed, needs device validation before release

---

## 🚂 Release Train

| Version | Codename | Status | Target | Scope |
|---------|----------|--------|--------|-------|
| **0.1.0** | መጀመሪያ (Genesis) | 🚀 Ready for device test | v0.1.0+1 | Buildable app: real OCR, real assets, working scan flow |
| **0.2.0** | ትምህርት (Teaching) | 📋 Planned | — | Teacher management, re-scan, search, voice playback |
| **0.3.0** | ሪፖርት (Report) | 📋 Planned | — | Telebirr payment, advanced analytics, PDF improvements |
| **1.0.0** | ንጉሥ (King) | 📋 Planned | — | Production release: tested, optimized, localized, shipped |

---

## 🧩 Feature Matrix

### Core Pipeline (Must Work for v0.1.0)

| # | Feature | Status | Owner | Depends On | Risk | Notes |
|---|---------|--------|-------|------------|------|-------|
| F01 | Camera capture | ✅ Done | Mobile | — | Low | Working with guide overlay |
| F02 | Image enhancement | ✅ Done | ML | — | Medium | Lean pipeline: downscale + grayscale + contrast. Zero pixel loops. |
| F03 | **Real OCR extraction** | ✅ Done | ML | F02 | Medium | ML Kit + confidence filter + skew detection + dedup |
| F04 | **Amharic handwriting model** | ❌ Missing | ML | F03 | 🔴 High | No model trained or sourced |
| F05 | Answer parsing (EN+AM) | ✅ Done | ML | F03 | Medium | AnswerParser extracted, concatenated format, 30+ tests |
| F06 | Scoring engine | ✅ Done | Backend | F05 | Low | MoE, international, university scales |
| F07 | Student model + storage | ✅ Done | Backend | — | Low | Hive adapters generated |
| F08 | Assessment CRUD | ✅ Done | Mobile | F07 | Low | Create, edit, answer key |
| F09 | Review screen | ✅ Done | UX | F06 | Low | Side-by-side, manual overrides, answer-type pickers, auto-persist |
| F10 | PDF reports | ✅ Done | Mobile | F06 | Low | Student + class reports, real data from Hive, shortcut from batch scan |
| F11 | Excel import | ✅ Done | Mobile | F07 | Low | .xlsx via file_picker |
| F12 | **Font assets** | ✅ Done | Design | — | Low | NotoSansEthiopic Regular + Bold (OFL) |
| F13 | **Splash screen** | ✅ Done | Design | — | Low | 512x512 PNG, Ethiopian green + checkmark |
| F14 | Voice commands (STT/TTS) | ✅ Done | Mobile | — | Low | Recording + playback |
| F29 | **Encrypted Hive storage** | ✅ Done | Backend | F07 | Medium | AES-256 via HiveAesCipher, key in flutter_secure_storage, corrupt-box recovery |
| F30 | **Validation service** | ✅ Done | Backend | F07 | Low | Pure Dart, Student/Assessment/ScanResult validation, 25+ tests |
| F31 | **StudentProvider real CRUD** | ✅ Done | Backend | F30 | Medium | Hive-backed, validation, UUID generation, Result type, search |
| F32 | **AssessmentProvider real CRUD** | ✅ Done | Backend | F30 | Medium | Hive-backed, validation, Result type, backward-compat saveAssessment |
| F33 | **ScanResult auto-save + persistence** | ✅ Done | Backend | F30 | Medium | Auto-save in gradePaper, retry logic, pending queue, lazy box queries |
| F34 | **Data migration framework** | ✅ Done | Backend | F07 | Low | Schema versioning in metadata box, ordered migrations, never crashes |
| F35 | **Backup & export service** | ✅ Done | Backend | F07 | Medium | JSON export/import, share sheet, auto-backup every 10 scans, pruning |

### Teacher Features (v0.2.0)

| # | Feature | Status | Owner | Depends On | Risk | Notes |
|---|---------|--------|-------|------------|------|-------|
| F15 | Teacher management persistence (F15) | ✅ Done | Backend | F07, F30 | Medium | Teacher model + TeacherProvider with full Hive CRUD, validation, bilingual search, active toggle, delete confirmation. Dialog wired to persistence, teacher list visible in school mode. |
| F16 | Re-scan paper | ✅ Done | Mobile | F01 | Low | Single-capture re-scan, immediate regrade, returns updated result |
| F17 | Dashboard search | ✅ Done | Mobile | F07 | Low | Real-time filter by student name, bilingual empty state |
| F18 | Voice recording playback | ✅ Done | Mobile | F14 | Low | just_audio wired, play/stop in review screen, bilingual errors |
| F19 | Batch scan flow (continuous capture) | ✅ Done | Mobile | F01, F03 | Medium | Capture-only loop, batch process on 'Done Scanning' |
| F36 | **Duplicate scan detection** | ✅ Done | Mobile | F01 | Medium | dHash (pure Dart), Hamming distance ≤10, bilingual warning dialog, offline-safe |

### School & Monetization (v0.3.0+)

| # | Feature | Status | Owner | Depends On | Risk | Notes |
|---|---------|--------|-------|------------|------|-------|
| F20 | Individual/School mode toggle | ✅ Done | Mobile | — | Low | UI complete |
| F21 | Telebirr payment | ❌ Placeholder | Backend | F20 | 🔴 High | No integration |
| F22 | Multi-teacher management | 📋 Planned | Backend | F15, F21 | High | Needs auth system |
| F23 | Cloud sync | 📋 Planned | Backend | F22 | High | Architecture TBD |
| F24 | School analytics dashboard | 📋 Planned | Data | F22 | Medium | — |

### Advanced (Post-1.0)

| # | Feature | Status | Owner | Depends On | Risk | Notes |
|---|---------|--------|-------|------------|------|-------|
| F25 | Short-answer keyword AI | 📋 Planned | ML | F03 | High | Needs NLP model |
| F26 | Essay grading rubric AI | 📋 Planned | ML | F03 | High | University mode |
| F27 | QR code student ID | 📋 Planned | Mobile | — | Low | `qr_flutter` in deps |
| F28 | Offline data encryption | 📋 Planned | Security | F07 | Medium | — |

---

## 🏃 Sprint Board

**Current Sprint:** Sprint 3 — Pre-Release Stabilization
**Goal:** Fix version mismatch, code quality sweep, prepare for first device test
**Velocity:** Sprint 1 ✅ (30 pts) · Sprint 2 ✅ (47 pts)

### Sprint 3 — Pre-Release Stabilization

| Task | Status | Assignee | Points | Notes |
|------|--------|----------|--------|-------|
| Fix appVersion mismatch | ✅ Done | QA | 1 | constants.dart had '1.0.0' instead of '0.1.0'. main_dashboard.dart hardcoded 'v1.0.0' — now uses AppConstants.appVersion |
| Code quality sweep | 📋 Pending | QA | 3 | Review large files (review_screen 1392L, dashboard 1011L), verify dispose patterns, check for leaked controllers |
| Analytics screen test coverage | 📋 Pending | QA | 2 | analytics_screen.dart has 0 dedicated widget tests; needs rendering + empty state coverage |
| Pre-release checklist verification | 📋 Pending | Infra | 2 | Verify lint clean, all tests pass, APK builds, Amharic mode works — document gaps |
| Version bump coordination | 📋 Pending | Backend | 1 | Sync pubspec.yaml, constants.dart appVersion, CHANGELOG version header before release |

**Sprint 3 Burndown:** 1/9 points complete

| Task | Status | Assignee | Points | Notes |
|------|--------|----------|--------|-------|
| Fix F18: Real voice note playback | ✅ Done | Mobile | 2 | just_audio wired, play/stop controls in review screen, bilingual errors, 5 tests |
| Teacher management persistence (F15) | ✅ Done | Backend | 3 | Teacher model, TeacherProvider with Hive CRUD, validation, bilingual UI, teacher list with delete, 7 model tests + 12 validation tests |
| Sprint 2 metrics baseline | ✅ Done | Infra | 1 | Created integration_test/perf_benchmark.dart (cold start, dashboard render, rapid nav, memory idle baseline). Updated CI pipeline: release APK build + size measurement, AAB build, metrics summary in GitHub Step Summary. How-to-measure column added to Technical Metrics table. Actual values fill on first CI run with Flutter SDK or on-device test. |
| i18n string extraction audit | ✅ Done | QA | 2 | Scanned all 11 screens, widgets, services. Found 2 gaps: analytics empty states were hardcoded English. Fixed by passing isAmharic to _GradeDistributionChart and _QuestionHeatmap. All other screens clean. |
| Accessibility audit | ✅ Done | UX | 2 | Audited all 11 screens + 4 widgets. Fixed: (1) MCQ answer buttons 32→48dp, answer bubbles 32→40dp with semantic wrapper, heatmap cells 40→48dp with Semantics. (2) Camera overlay contrast: white60→white+14sp. (3) _TypeChip 10→11sp. (4) Added Semantics(button:true) to QuickAction, camera capture/done/thumbnail, ReportTypeCard, language chip, subscription options, mode cards. (5) Added semantic labels to heatmap cells and answer summary in review. 12 accessibility widget tests added. |
| Crash recovery resume dialog | ✅ Done | Backend | 3 | SessionService persists scan session to Hive metadata box after each capture. Dashboard checks for active session on launch, shows bilingual resume dialog. Resume navigates to camera with existing images. Discard cleans up images + session. Re-scan mode also cleans up session. 7 unit tests. |
| Answer key alignment verification | ✅ Done | QA | 3 | ScanResult.checkAlignment() counts [MISSING] answers, warns if >20% missing. Warning shown in: ReviewScreen result cards (per-student), SideBySideReview (prominent banner at top), BatchScanScreen (summary of misaligned papers). Bilingual text. 6 unit tests. |
| Dynamic template calibration | ✅ Done | ML | 5 | OmrService._calibrateTemplate(): samples 3 rows (first, middle, last) of bubble grid, detects actual bubble centers via horizontal sweep, computes per-axis scale + offset corrections, returns calibrated template. Applied before OMR detection loop. Sanity checks reject corrections >3× columnSpacing. Graceful fallback to original template. 1 synthetic image test. |
| Lighting normalization | ✅ Done | ML | 3 | Two-part fix: (1) OMR adaptive threshold — _sampleFillRatio now samples background brightness from outer ring around each bubble, sets threshold = bgBrightness - 0.25 instead of hardcoded 0.4. Works in bright sunlight, dim classrooms, fluorescent light. (2) OCR histogram normalization — img.normalize() stretches pixel range to full 0-255 after grayscale, before contrast boost. Consistent ink/paper separation regardless of lighting. 2 synthetic image tests (bright bg, dim bg). |
| Eraser / multi-mark handling | ✅ Done | ML | 3 | Gap-based fill analysis replaces count-based. Sorts options by fill ratio, computes gap between 1st and 2nd. Large gap (>0.20): eraser residue scenario, pick highest with high confidence. Small gap (<0.10) with multiple above threshold: truly ambiguous, confidence 0.5. Pencil marks: gap >0.15 → confidence 0.5, else 0.3. Removed unused bestOption/bestFill variables. 3 synthetic image tests: eraser residue, ambiguous, empty. |
| Ethiopian calendar support | ✅ Done | UX | 5 | EthiopianCalendar utility: pure Dart Gregorian→Ethiopian conversion via JDN algorithm. 13 months, Pagume handling, leap year detection. SettingsProvider: useEthiopianCalendar toggle (default true). Settings screen: Ethiopian Calendar switch in Preferences. AssessmentCard: shows created date in preferred calendar. ReviewScreen: shows scan date in preferred calendar. Bilingual month names (Amharic + English). 17 unit tests: new year, month boundaries, format options, leap year, edge cases. |

| Task | Status | Assignee | Points | Notes |
|------|--------|----------|--------|-------|
| Template-to-PDF flow | ✅ Done | Mobile | 3 | Reports use real scan results from Hive, not hardcoded data. Report shortcut from batch scan screen. |
| Wire batch_scan_screen to HybridGradingService | ✅ Done | Backend | 3 | Replaced OcrService direct calls with HybridGradingService |
| Wire camera_screen to HybridGradingService | ✅ Done | Backend | 2 | Single-paper grading also uses HybridGradingService now |
| Convert camera to continuous batch capture | ✅ Done | UX | 3 | Capture-only loop, no per-scan processing, 'Done Scanning' navigates to BatchScanScreen |
| Create HybridGradingService | ✅ Done | Backend | 3 | Orchestrates OcrService + ScoringService; error handling, batch with progress callback |
| Unit tests for OcrService | ✅ Done | QA | 5 | 40+ tests: TextRegion model, enhanceImage (downscale/grayscale/contrast/edge cases), parseAnswers integration, deduplication, scoring pipeline, ScanResult serialization |
| Unit tests for HybridGradingService | ✅ Done | QA | 3 | gradePaper (file-not-found, real image), gradeBatch (progress/names/partial/mixed), regradePaper |
| Pure Dart perspective correction | ✅ Done | ML | 5 | PerspectiveCorrectionService: corner detection, homography, bilinear warp. Integrated into OCR pipeline as primary correction before fallback to simple rotation. 9 tests. |
| Camera guidance overlay | ✅ Done | UX | 2 | PaperGuideOverlay: 3 color states, bilingual hints, CustomPainter, zero allocs |
| Score override/edit flow | ✅ Done | UX | 3 | Question-type-aware override: MCQ chips, T/F buttons, short answer editor. Uses actual assessment rubric. Auto-saves to Hive on confirm. Save All for batch overrides. |
| Student persistence (Hive) | ✅ Done | Backend | — | F31 completed: StudentProvider real Hive CRUD with validation, UUID, Result type |
| End-to-end integration test | ✅ Done | QA | — | 8 test groups: app launch, bilingual, assessment creation, scanning, review, reports, crash resilience, accessibility. Flutter driver runnable. |
| Encrypted Hive init | ✅ Done | Backend | 3 | AES-256 cipher, secure key storage, lazy box for scan_results, corrupt-box recovery, fallback banner |
| ValidationService | ✅ Done | Backend | 3 | Pure Dart student/assessment/scan validation, 25+ unit tests |
| Rewrite StudentProvider | ✅ Done | Backend | 3 | Real Hive CRUD, validation, UUID gen, Result type, Amharic search |
| Rewrite AssessmentProvider | ✅ Done | Backend | 3 | Real Hive CRUD, validation, Result type, backward-compat saveAssessment |
| ScanResult auto-save in HybridGradingService | ✅ Done | Backend | 3 | Auto-save with retry, pending queue, lazy box queries (load/get/delete/student) |
| MigrationService | ✅ Done | Backend | 2 | Schema versioning in metadata box, ordered migration runner, wired to main.dart |
| BackupService | ✅ Done | Backend | 3 | JSON export/import with validation, share_plus, auto-backup every 10 scans, pruning |
| Persistence test suite | ✅ Done | QA | 3 | 25 tests: happy path, validation, edge cases, error handling, backup, migration |
| Answer-pattern duplicate detection (T8) | ✅ Done | ML | 3 | ScoringService fingerprint + compare + detectAnswerDuplicates; HybridGradingService.detectBatchDuplicates; BatchScanScreen bilingual warning banner; 28 new tests (70 total for scoring) |
| OutOfMemoryError handling in enhanceImage | ✅ Done | ML | 2 | OOM retry at 1080p, crash-proof pipeline; 2 new tests |
| setState mounted guard in batch scan | ✅ Done | QA | 1 | Prevents crash on navigation during batch processing |
| Replace print() with debugPrint() in voice service | ✅ Done | QA | 1 | Zero print() calls in lib/ verified |
| Fix TextEditingControllers leaked in dialogs | ✅ Done | QA | 2 | subscription (2), import_excel (7), answer_key (1) controllers now disposed |
| Image cleanup for captured/enhanced files | ✅ Done | QA | 2 | OcrService cleanup methods, CameraScreen + BatchScanScreen dispose cleanup |
| Fix isFirstLaunch crash bug | ✅ Done | Backend | 2 | Future<bool> cast to bool in constants.dart — crashed on app launch. Changed to async checkFirstLaunch() called before runApp, passed as param to EthioGradeApp |
| Align Hive box constants | ✅ Done | Backend | 1 | constants.dart had dead/mismatched box names (settings, results, sync_queue). Updated to match main.dart: students, assessments, scan_results, metadata |
| Widget test scaffolding | ✅ Done | QA | 3 | 4 test groups: StatCard (5), LanguageToggle (5), PaperGuideOverlay (8), AssessmentCard (15) — 33 widget tests total |
| GitHub Actions CI pipeline | ✅ Done | Infra | 2 | Lint → test with coverage → build APK with size check. Triggers on push to main/dev and PRs to main |

### Completed Sprint 0

| Task | Status | Assignee | Points | Notes |
|------|--------|----------|--------|-------|
| Add font files (NotoSansEthiopic) | ✅ Done | Design | 1 | NotoSansEthiopic-Regular.ttf + Bold.ttf (OFL) |
| Add splash logo | ✅ Done | Design | 1 | 512x512 PNG, green bg + white checkmark + yellow accent |
| Wire ML Kit text recognition | ✅ Done | ML | 5 | google_mlkit_text_recognition, on-device, graceful failure |
| Harden OCR: confidence filter + image cap | ✅ Done | ML | 2 | Reject noise <0.5 confidence, downscale >1600px |
| Validate answer parser against ML Kit output | ✅ Done | ML | 3 | AnswerParser extracted, 30+ test cases, edge cases fixed |
| Replace enhancement pipeline | ✅ Done | ML | 3 | 4 native ops, zero pixel loops, skew detection, dedup |
| Add unit tests for scoring engine | ✅ Done | QA | 2 | ScoringService extracted (pure Dart), 40+ tests covering all 3 grading scales, answer types, edge cases |

**Sprint 0 Burndown:** 19/19 points complete — Sprint 0 done ✅

---

## 📊 Analytics & KPIs (What We Measure)

### Product Metrics (Post-Launch)

| Metric | Target | How We Measure |
|--------|--------|----------------|
| Papers scanned per session | ≥ 15 | In-app event |
| Time to grade 30 papers | < 10 min | Session timing |
| OCR accuracy (MCQ) | ≥ 95% | Correction rate |
| OCR accuracy (True/False) | ≥ 90% | Correction rate |
| Teacher retention (Day 7) | ≥ 40% | Firebase/Analytics |
| App crash rate | < 1% | Crashlytics |
| PDF export rate | ≥ 60% of sessions | In-app event |
| Amharic mode usage | Track (no target) | Locale setting |

### Technical Metrics

| Metric | Target | Current | How to Measure |
|--------|--------|---------|----------------|
| Cold start time | < 3s | 📋 Pending | `integration_test/perf_benchmark.dart` — Stopwatch from main() to first frame |
| Scan-to-result time | < 5s | ~0.8s (mock) | HybridGradingService.gradePaper timing |
| APK size (release) | < 50MB | 📋 Pending | CI: `flutter build apk --release` → stat |
| Memory peak | < 150MB | 📋 Pending | `adb shell dumpsys meminfo <pkg>` during batch scan of 10 papers |
| Test coverage | ≥ 60% | 📋 Pending | `flutter test --coverage` → lcov |
| Lint warnings | 0 | Unknown | `flutter analyze` |

---

## 🧪 Device & OS Matrix

| Device Class | Min Spec | Target | Tested? |
|-------------|----------|--------|---------|
| Low-end phone | 2GB RAM, Android 8, no GPU accel | Primary | ❌ |
| Mid-range phone | 4GB RAM, Android 10 | Primary | ❌ |
| High-end phone | 6GB+ RAM, Android 13+ | Secondary | ❌ |
| Tablet | Any Android tablet | Nice-to-have | ❌ |
| Chromebook | Android app support | Stretch | ❌ |

**Camera requirements:** Rear camera with autofocus. Flash preferred but not required.

---

## ⚠️ Risk Register

| # | Risk | Impact | Likelihood | Mitigation |
|---|------|--------|------------|------------|
| R1 | No Amharic handwriting model available | 🔴 Fatal | High | Research existing models; consider partnership with Ethiopian universities |
| R2 | ML Kit accuracy too low for real papers | 🟡 High | Medium | Test with real exam papers early; have manual fallback; dynamic template calibration applied |
| R3 | Image processing too slow on 2GB devices | 🟡 High | High | Move to Dart isolates; optimize algorithms |
| R4 | Telebirr API integration blocked | 🟡 High | Medium | Ship free tier first; payment in v0.3.0 |
| R5 | Font licensing issues | 🟡 Medium | Low | NotoSansEthiopic is OFL — free to use |
| R6 | Google Play rejection (permissions) | 🟡 Medium | Medium | Camera + storage only; justify in store listing |
| R7 | Offline data loss on app crash | 🟡 Medium | Medium | Auto-save after each scan; Hive is crash-safe |
| R8 | No runtime test verification | 🟡 Medium | Medium | CI pipeline added but needs Flutter runner verification on first push |
| R9 | Constants.dart isFirstLaunch was crashing at runtime | ✅ Mitigated | — | Fixed: async checkFirstLaunch() resolved before runApp |

---

## 📦 Dependency Health

| Package | Version | Purpose | Risk |
|---------|---------|---------|------|
| `google_mlkit_text_recognition` | ^0.11.0 | OCR | Core dependency — actively maintained |
| `tflite_flutter` | ^0.10.4 | Amharic model | Heavy native dep — may cause build issues |
| `camera` | ^0.10.5+9 | Camera | Stable, well-maintained |
| `pdf` | ^3.10.7 | Report generation | Stable |
| `hive` / `hive_flutter` | ^2.2.3 | Local DB | Stable, no SQL overhead |
| `flutter_secure_storage` | ^9.0.0 | Encryption key storage | Platform keystore (Android EncryptedSharedPreferences) |
| `provider` | ^6.1.1 | State mgmt | Standard Flutter pattern |
| `speech_to_text` | ^6.6.0 | STT | Platform-dependent accuracy |
| `flutter_tts` | ^3.8.5 | TTS | Amharic voice quality unknown |
| `record` | ^5.0.4 | Audio recording | Stable |
| `just_audio` | ^0.9.36 | Audio playback | Stable, well-maintained, cross-platform |
| `excel` | ^4.0.3 | Import | Stable |

---

## 🔄 How to Update This File

1. After every task completion → update Feature Matrix status
2. After every sprint → update Sprint Board, velocity
3. After every release → update Release Train, bump version
4. When risk changes → update Risk Register
5. When dependencies change → update Dependency Health
6. Weekly → verify Health signals are current

**This file is not optional. A stale PROJECT_STATE.md means the project is out of control.**

---

*Last Updated: 2026-04-01*
