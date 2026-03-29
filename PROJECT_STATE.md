# EthioGrade — Project State

> The single source of truth. Read this before touching anything.
> Updated with every meaningful change. Stale = broken.

---

## 📡 Project Health

| Signal | Status | Detail |
|--------|--------|--------|
| **Build** | 🟡 Partial | Fonts + splash + OCR wired; needs real-paper validation |
| **Tests** | 🟡 Partial | 30+ tests for answer parser; zero coverage for scoring, services |
| **CI/CD** | ⚫ None | No pipeline configured |
| **Crash-free rate** | — | Not in production yet |
| **Performance** | 🟡 Unverified | Image processing untested on real devices |
| **Security audit** | ⚫ None | No audit performed |
| **Accessibility** | 🟡 Partial | Theme contrast not verified, no screen reader tests |
| **i18n coverage** | 🟡 Partial | UI strings bilingual, but no extraction/validation tool |

**Overall Status:** 🟠 Pre-Alpha — Scaffold complete, core features are mock data

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
| F02 | Image enhancement | ✅ Done | ML | — | Medium | Pixel loops slow on device — needs isolate |
| F03 | **Real OCR extraction** | ✅ Done | ML | F02 | Medium | ML Kit TextRecognizer + confidence filter + image downscale |
| F04 | **Amharic handwriting model** | ❌ Missing | ML | F03 | 🔴 High | No model trained or sourced |
| F05 | Answer parsing (EN+AM) | ✅ Done | ML | F03 | Medium | AnswerParser extracted, concatenated format, 30+ tests |
| F06 | Scoring engine | ✅ Done | Backend | F05 | Low | MoE, international, university scales |
| F07 | Student model + storage | ✅ Done | Backend | — | Low | Hive adapters generated |
| F08 | Assessment CRUD | ✅ Done | Mobile | F07 | Low | Create, edit, answer key |
| F09 | Review screen | ✅ Done | UX | F06 | Low | Side-by-side, manual overrides |
| F10 | PDF reports | ✅ Done | Mobile | F06 | Low | Student + class reports |
| F11 | Excel import | ✅ Done | Mobile | F07 | Low | .xlsx via file_picker |
| F12 | **Font assets** | ✅ Done | Design | — | Low | NotoSansEthiopic Regular + Bold (OFL) |
| F13 | **Splash screen** | ✅ Done | Design | — | Low | 512x512 PNG, Ethiopian green + checkmark |
| F14 | Voice commands (STT/TTS) | ✅ Done | Mobile | — | Low | Recording + playback |

### Teacher Features (v0.2.0)

| # | Feature | Status | Owner | Depends On | Risk | Notes |
|---|---------|--------|-------|------------|------|-------|
| F15 | Teacher management | ❌ Stub | Backend | F07 | Medium | Dialog exists, no persistence |
| F16 | Re-scan paper | ❌ Stub | Mobile | F01 | Low | Button exists, no logic |
| F17 | Dashboard search | ❌ Stub | Mobile | F07 | Low | Icon visible, no implementation |
| F18 | Voice recording playback | ❌ Placeholder | Mobile | F14 | Low | Speaks "playing voice note" |
| F19 | Batch scan flow | ✅ Done | Mobile | F01, F03 | Medium | UI done, depends on real OCR |

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

**Current Sprint:** Sprint 0 — Foundation
**Goal:** Get the app buildable with real OCR
**Velocity:** Baseline (first sprint)

| Task | Status | Assignee | Points | Notes |
|------|--------|----------|--------|-------|
| Add font files (NotoSansEthiopic) | ✅ Done | Design | 1 | NotoSansEthiopic-Regular.ttf + Bold.ttf (OFL) |
| Add splash logo | ✅ Done | Design | 1 | 512x512 PNG, green bg + white checkmark + yellow accent |
| Wire ML Kit text recognition | ✅ Done | ML | 5 | google_mlkit_text_recognition, on-device, graceful failure |
| Harden OCR: confidence filter + image cap | ✅ Done | ML | 2 | Reject noise <0.5 confidence, downscale >2048px |
| Validate answer parser against ML Kit output | ✅ Done | ML | 3 | AnswerParser extracted, 30+ test cases, edge cases fixed |
| Move image processing to isolate | ⬜ Todo | Mobile | 3 | Prevent UI jank |
| Add unit tests for scoring engine | ⬜ Todo | QA | 2 | — |
| Add unit tests for answer parser | ✅ Done | QA | 2 | 30+ test cases in test/services/answer_parser_test.dart |

**Sprint Burndown:** 14/19 points complete

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

*Last Updated: 2026-03-29*
