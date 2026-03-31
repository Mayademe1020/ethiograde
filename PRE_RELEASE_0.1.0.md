# EthioGrade v0.1.0 Pre-Release Checklist

> መጀመሪያ (Genesis) — First buildable release.

## Automated (CI)

| Gate | Status | Notes |
|------|--------|-------|
| `flutter analyze` — 0 errors | 📋 Pending | Run on first CI push |
| `dart format` — no violations | 📋 Pending | Run on first CI push |
| `flutter test` — all pass | 📋 Pending | 200+ tests across 25 files |
| Coverage ≥ 50% | 📋 Pending | lcov report from CI |
| APK size < 50MB (release) | 📋 Pending | Measured in CI Step Summary |
| AAB builds successfully | 📋 Pending | Play Store artifact |

## Manual (Device Testing)

### Low-Spec Simulation (2GB RAM, Android 8)

| Check | Status | Notes |
|-------|--------|-------|
| Cold start < 3s | 📋 Pending | `integration_test/perf_benchmark.dart` |
| Dashboard renders < 500ms | 📋 Pending | Benchmark test |
| 10-paper batch scan completes | 📋 Pending | Camera → BatchScan → Review |
| Memory peak < 150MB | 📋 Pending | `adb shell dumpsys meminfo` |
| No OOM crash during scan | 📋 Pending | 50+ papers in single session |

### Core Flow

| Check | Status | Notes |
|-------|--------|-------|
| Create assessment with MCQ + T/F | 📋 Pending | |
| Camera captures paper image | 📋 Pending | |
| OCR detects answers from photo | 📋 Pending | Real paper, not synthetic |
| Score calculation correct | 📋 Pending | MoE rubric |
| Review screen shows results | 📋 Pending | |
| Manual override saves to Hive | 📋 Pending | |
| PDF student report generates | 📋 Pending | |
| PDF class report generates | 📋 Pending | |
| Excel import works | 📋 Pending | |
| Data persists after app kill | 📋 Pending | |

### Bilingual

| Check | Status | Notes |
|-------|--------|-------|
| Switch to Amharic mode | 📋 Pending | |
| All screens show Amharic text | 📋 Pending | |
| No English bleed-through | 📋 Pending | |
| Ethiopian calendar dates render | 📋 Pending | |
| Amharic month names correct | 📋 Pending | |

### Crash Resilience

| Check | Status | Notes |
|-------|--------|-------|
| Crash during scan → resume dialog | 📋 Pending | |
| Kill app mid-batch → data survives | 📋 Pending | |
| Rapid back button → no crash | 📋 Pending | |
| Background + resume → no crash | 📋 Pending | |

### Accessibility

| Check | Status | Notes |
|-------|--------|-------|
| All buttons ≥ 48dp touch target | 📋 Pending | Verified in code review |
| Screen reader announces buttons | 📋 Pending | Semantics labels added |
| Text contrast ≥ 4.5:1 | 📋 Pending | white60 → white fix applied |

## Code Quality

| Check | Status | Notes |
|-------|--------|-------|
| No `print()` in lib/ | ✅ Pass | Verified: 0 calls |
| No unused imports | ✅ Pass | |
| Controllers disposed properly | ✅ Pass | Fixed 2 leaks in main_dashboard |
| All screens bilingual | ✅ Pass | 11 screens, 22-94 refs each |
| No hardcoded strings in widgets | ✅ Pass | |

## Release Artifacts

| Artifact | Status | Notes |
|----------|--------|-------|
| CHANGELOG.md updated | ✅ Pass | [0.1.0] section ready |
| Version bumped in pubspec.yaml | ✅ Pass | 0.1.0+1 |
| PROJECT_STATE.md updated | ✅ Pass | Release train: 🔨 → 🚀 |
| Git tag created | 📋 Pending | After push |
