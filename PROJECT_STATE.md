# EthioGrade — Project State

> The single source of truth. Read this before touching anything.
> Updated with every meaningful change. Stale = broken.

---

## 📡 Project Health

| Signal | Status | Detail |
|--------|--------|--------|
| **Build** | 🟡 Partial | Fonts + splash + OCR wired; needs real-paper validation |
| **Tests** | 🟡 Partial | 30+ tests for answer parser, 70+ tests for scoring (incl. answer-pattern duplicate detection), 20+ tests for analytics, 40+ tests for OCR service (incl. OOM recovery), 13+ tests for HybridGradingService, 25+ tests for validation service, 25+ tests for persistence layer; zero coverage for PDF and Excel |
| **CI/CD** | ⚫ None | No pipeline configured |
| **Crash-free rate** | — | Not in production yet |
| **Performance** | 🟢 Good | Enhancement: 4 native ops, zero pixel loops. Scan target <3s |
| **Security audit** | ⚫ None | No audit performed |
| **Data encryption** | 🟢 Done | AES-256 Hive boxes, key in flutter_secure_storage |
| **Accessibility** | 🟡 Partial | Theme contrast not verified, no screen reader tests |
| **i18n coverage** | 🟡 Partial | UI strings bilingual, but no extraction/validation tool |

**Overall Status:** 🟠 Pre-Alpha — Core pipeline real, EXIF orientation fix applied

---

## 🚂 Release Train

| Version | Codename | Status | Target | Scope |
|---------|----------|--------|--------|-------|
| **0.1.0** | መጀመሪያ (Genesis) | 🔨 Building | TBD | Buildable app: real OCR, real assets, working scan flow |
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
| F15 | Teacher management | ❌ Stub | Backend | F07 | Medium | Dialog exists, no persistence |
| F16 | Re-scan paper | ❌ Stub | Mobile | F01 | Low | Button exists, no logic |
| F17 | Dashboard search | ❌ Stub | Mobile | F07 | Low | Icon visible, no implementation |
| F18 | Voice recording playback | ❌ Placeholder | Mobile | F14 | Low | Speaks "playing voice note" |
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

**Current Sprint:** Sprint 1 — Integration
**Goal:** Wire services to screens, add test coverage, build HybridGradingService
**Velocity:** In progress

| Task | Status | Assignee | Points | Notes |
|------|--------|----------|--------|-------|
| Template-to-PDF flow | ✅ Done | Mobile | 3 | Reports use real scan results from Hive, not hardcoded data. Report shortcut from batch scan screen. |
| Wire batch_scan_screen to HybridGradingService | ✅ Done | Backend | 3 | Replaced OcrService direct calls with HybridGradingService |
| Wire camera_screen to HybridGradingService | ✅ Done | Backend | 2 | Single-paper grading also uses HybridGradingService now |
| Convert camera to continuous batch capture | ✅ Done | UX | 3 | Capture-only loop, no per-scan processing, 'Done Scanning' navigates to BatchScanScreen |
| Create HybridGradingService | ✅ Done | Backend | 3 | Orchestrates OcrService + ScoringService; error handling, batch with progress callback |
| Unit tests for OcrService | ✅ Done | QA | 5 | 40+ tests: TextRegion model, enhanceImage (downscale/grayscale/contrast/edge cases), parseAnswers integration, deduplication, scoring pipeline, ScanResult serialization |
| Unit tests for HybridGradingService | ✅ Done | QA | 3 | gradePaper (file-not-found, real image), gradeBatch (progress/names/partial/mixed), regradePaper |
| Pure Dart perspective correction | 📋 Pending | ML | — | Sprint 1 task 3 |
| Camera guidance overlay | ✅ Done | UX | 2 | PaperGuideOverlay: 3 color states, bilingual hints, CustomPainter, zero allocs |
| Score override/edit flow | ✅ Done | UX | 3 | Question-type-aware override: MCQ chips, T/F buttons, short answer editor. Uses actual assessment rubric. Auto-saves to Hive on confirm. Save All for batch overrides. |
| Student persistence (Hive) | 📋 Pending | Backend | — | Sprint 1 task 6 |
| End-to-end integration test | 📋 Pending | QA | — | Sprint 1 task 7 |
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

| Metric | Target | Current |
|--------|--------|---------|
| Cold start time | < 3s | Unknown |
| Scan-to-result time | < 5s | Unknown (mock: 0.8s) |
| APK size | < 50MB | Unknown |
| Memory peak | < 150MB | Unknown |
| Test coverage | ≥ 60% | 0% |
| Lint warnings | 0 | Unknown |

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
| R2 | ML Kit accuracy too low for real papers | 🔴 Fatal | Medium | Test with real exam papers early; have manual fallback |
| R3 | Image processing too slow on 2GB devices | 🟡 High | High | Move to Dart isolates; optimize algorithms |
| R4 | Telebirr API integration blocked | 🟡 High | Medium | Ship free tier first; payment in v0.3.0 |
| R5 | Font licensing issues | 🟡 Medium | Low | NotoSansEthiopic is OFL — free to use |
| R6 | Google Play rejection (permissions) | 🟡 Medium | Medium | Camera + storage only; justify in store listing |
| R7 | Offline data loss on app crash | 🟡 Medium | Medium | Auto-save after each scan; Hive is crash-safe |

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

*Last Updated: 2026-03-31*
