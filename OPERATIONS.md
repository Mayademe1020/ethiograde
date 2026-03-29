# EthioGrade — Operations Manual

> How we build, ship, and operate this product.
> Not suggestions. Process. Follow it.

---

## 🏗️ Architecture Principles

These are non-negotiable. Every decision is measured against them.

| # | Principle | What It Means |
|---|-----------|---------------|
| 1 | **Offline-first** | Every core feature works without internet. Online is enhancement, not requirement. |
| 2 | **Low-spec primary** | 2GB RAM, Android 8, rear camera. If it doesn't run here, it doesn't ship. |
| 3 | **Bilingual by default** | Every user-facing string exists in Amharic AND English. No exceptions. No "we'll add it later." |
| 4 | **Data stays on device** | Teacher owns their data. Nothing leaves the phone unless they explicitly share it. |
| 5 | **Crash-proof core** | A crash during scanning loses zero data. Auto-save after every paper. |
| 6 | **Accessible** | Teachers range from tech-savvy to first-smartphone. Design for the beginner. |
| 7 | **Fast** | Scan a paper → see the grade in < 5 seconds. Teachers have 40+ students. |

---

## 🌿 Branching Strategy

```
main          ← Always deployable. Protected. PR-only.
├── dev       ← Integration branch. Features merge here first.
│   ├── feature/ocr-mlkit      ← Feature branches
│   ├── feature/teacher-mgmt
│   ├── fix/camera-crash
│   └── perf/image-isolate
└── hotfix/*  ← Emergency fixes off main
```

### Rules
- **Never push directly to `main`** — always through PR
- **Feature branches** named: `feature/[short-desc]` or `fix/[short-desc]`
- **One branch = one concern** — don't mix OCR fix with UI changes
- **Delete branch after merge**
- **Rebase on `dev` before PR** — keep history clean

### Commit Messages

```
[Area] Imperative short summary (≤72 chars)

Body: what and why (not how). Wrap at 80 chars.

Refs: #issue-number
```

**Areas:** `[OCR]` `[Camera]` `[PDF]` `[Voice]` `[Analytics]` `[UI]` `[i18n]` `[Data]` `[Build]` `[Docs]` `[Test]` `[Security]` `[Perf]` `[UX]`

**Examples:**
```
[OCR] Replace mock extractor with ML Kit text recognition

The previous implementation returned hardcoded TextRegion objects.
This wires google_mlkit_text_recognition to detect real text from
enhanced paper images, parsing question numbers and answers.

- Handles rotated images via EXIF correction
- Confidence threshold set to 0.7 (configurable)
- Falls back gracefully on detection failure

Refs: #12
```

---

## 🔍 Code Review Protocol

Every PR must pass review. No self-merges.

### Reviewer Checklist

**Functionality**
- [ ] Does what the PR description says
- [ ] No regressions in existing features
- [ ] Works in both Amharic and English
- [ ] Handles edge cases: empty data, missing permissions, back button

**Quality**
- [ ] No `// TODO` without PROGRESS.md tracking entry
- [ ] No hardcoded magic numbers
- [ ] Functions < 50 lines
- [ ] Named parameters for >2 argument functions
- [ ] No `print()` in production code — use `debugPrint()`

**Security**
- [ ] No PII in logs
- [ ] External input validated
- [ ] File paths sanitized
- [ ] No secrets in code

**Performance**
- [ ] No synchronous heavy computation on UI thread
- [ ] Lists use lazy builders
- [ ] Images decoded at display size, not full resolution
- [ ] Controllers and listeners properly disposed

**UX**
- [ ] Loading states for async operations
- [ ] Error states with actionable messages
- [ ] Touch targets ≥ 48dp
- [ ] Follows theme (green/yellow/red)
- [ ] Amharic strings are natural, not machine-translated

---

## 🚀 Release Process

### Versioning
- `0.x.0` — Pre-1.0 minor releases (features)
- `0.0.x` — Pre-1.0 patches (fixes)
- `1.0.0` — First production release
- Follow semver after 1.0

### Pre-Release Checklist

```
□ All tests passing
□ No lint warnings
□ PROGRESS.md reflects current state
□ CHANGELOG.md updated with all changes
□ Version bumped in pubspec.yaml
□ APK builds for release (aab for Play Store)
□ Tested on low-end device (2GB RAM)
□ Tested in Amharic mode
□ Tested offline (airplane mode)
□ Camera tested in low light
□ PDF export tested
□ No crash on: back button, minimize, orientation change, kill and reopen
```

### Staged Rollout (Post-1.0)

| Stage | % | Duration | Gate |
|-------|---|----------|------|
| Internal | 100% (team) | 2 days | Manual testing |
| Closed Beta | 50 teachers | 1 week | Crash-free ≥ 99%, NPS ≥ 7 |
| Open Beta | 500 teachers | 2 weeks | Crash-free ≥ 99.5%, no P0 bugs |
| Production | 100% | — | Monitor for 48h post-rollout |

### Hotfix Process

```
1. Branch hotfix/[desc] from main
2. Fix + test
3. PR to main (fast-track review)
4. Tag patch version
5. Deploy
6. Cherry-pick to dev
```

---

## 🧪 Testing Strategy

### Unit Tests (Priority: High)

| Module | What to Test | Coverage Target |
|--------|-------------|-----------------|
| `OcrService` | Answer parsing, normalization, grading scales | 90% |
| `AnalyticsProvider` | Score computation, grade distribution, stats | 85% |
| `PdfService` | Report generation (mock data is fine) | 80% |
| `ExcelService` | Import/export round-trip | 80% |
| Models | Serialization, Hive read/write | 90% |

### Widget Tests (Priority: Medium)

| Screen | What to Test |
|--------|-------------|
| Dashboard | Renders stats, navigates to tabs |
| Create Assessment | Form validation, saves assessment |
| Review | Displays scores, manual override works |

### Integration Tests (Priority: Post-1.0)

- Full scan flow: Camera → Capture → OCR → Score → Review → PDF
- Excel import → Student list → Assessment → Scan → Report

### Device Testing Matrix

| | Android 8 (2GB) | Android 10 (4GB) | Android 13 (6GB+) |
|---|---|---|---|
| Camera scan | Must work | Must work | Must work |
| Batch scan (10) | < 30s | < 20s | < 15s |
| PDF generation | < 5s | < 3s | < 2s |
| Memory peak | < 150MB | < 150MB | < 200MB |

---

## 🔒 Security Protocol

### Data Classification

| Data | Classification | Storage | Sharing |
|------|---------------|---------|---------|
| Student names | PII — Internal | Hive (on-device only) | Never auto-shared |
| Scores/grades | Sensitive | Hive | PDF export (teacher-initiated only) |
| Assessment answers | Internal | Hive | Never |
| School name | Public | Hive | Included in reports |
| Voice recordings | Sensitive | App documents dir | Teacher-initiated only |
| App settings | Non-sensitive | SharedPreferences | Never |

### Rules
1. **No network calls in Individual mode** — everything stays on device
2. **No analytics SDKs pre-1.0** — add Firebase/Crashlytics only at beta
3. **Encrypt Hive boxes** containing PII if storing > 1000 students (future)
4. **Validate all file imports** — Excel, images, audio: check format, size, content
5. **No student data in crash reports** — strip PII from error payloads

---

## 🌍 Localization (i18n) Workflow

### String Extraction
- All UI strings live in `lib/config/constants.dart` or a dedicated `l10n/` file (future)
- Never hardcode strings in widget trees
- Format: `isAm ? amharicString : englishString` (current pattern)
- Future: migrate to ARB files + `flutter gen-l10n`

### Translation Rules
- Amharic translations must be **natural**, not Google Translated
- Teacher-facing language: formal but warm
- Error messages: clear, actionable, no jargon
- Grade labels: use official MoE terminology
- Verify with native Amharic speaker before shipping

### Coverage Check
Before release, every screen must be tested in both languages:
- [ ] All labels visible (no truncation — Amharic is wider)
- [ ] No English bleed-through in Amharic mode
- [ ] Numbers formatted correctly (Ethiopian context)
- [ ] RTL not needed (Amharic is LTR), but verify layout doesn't break

---

## 📈 Analytics Event Schema (Post-1.0)

| Event | Parameters | When |
|-------|-----------|------|
| `scan_paper` | `assessment_id`, `student_id`, `ocr_confidence`, `time_ms` | After each paper scanned |
| `batch_scan_complete` | `assessment_id`, `paper_count`, `total_time_ms`, `avg_confidence` | After batch done |
| `manual_override` | `assessment_id`, `question_number`, `original`, `corrected` | Teacher changes a grade |
| `pdf_export` | `type` (student/class), `assessment_id`, `page_count` | PDF generated |
| `share_report` | `channel` (whatsapp/telegram/other), `type` | Report shared |
| `excel_import` | `student_count`, `success_count`, `error_count` | Import completed |
| `language_switch` | `from`, `to` | Language toggled |
| `mode_switch` | `from`, `to` (individual/school) | Subscription changed |
| `voice_note_record` | `duration_ms`, `assessment_id` | Voice note saved |
| `error_ocr_failed` | `error_type`, `image_path_hash` | OCR failure |

**Privacy:** Never log student names, scores, or assessment content in events.

---

## 🎨 Design System

### Colors (Ethiopian Flag Inspired)

| Token | Hex | Usage |
|-------|-----|-------|
| `primaryGreen` | `#009639` | Primary actions, success, headers |
| `primaryYellow` | `#FCDD09` | Highlights, warnings, accents |
| `primaryRed` | `#DA121A` | Errors, destructive actions |
| `background` | `#FAFAFA` | Page background |
| `surface` | `#FFFFFF` | Cards, dialogs |
| `textPrimary` | `#1A1A1A` | Body text |
| `textSecondary` | `#6B7280` | Captions, labels |
| `darkBackground` | `#121212` | Dark mode background |
| `darkSurface` | `#1E1E1E` | Dark mode cards |

### Typography

| Style | Font | Size | Weight | Usage |
|-------|------|------|--------|-------|
| Heading 1 | NotoSansEthiopic | 24sp | Bold | Screen titles |
| Heading 2 | NotoSansEthiopic | 20sp | Bold | Section headers |
| Body | NotoSansEthiopic | 16sp | Regular | Content text |
| Caption | NotoSansEthiopic | 12sp | Regular | Labels, metadata |
| Button | NotoSansEthiopic | 14sp | SemiBold | Button labels |

### Spacing Scale
`4px → 8px → 12px → 16px → 24px → 32px → 48px → 64px`

### Component Rules
- Corner radius: 12px (cards), 8px (buttons), 16px (dialogs)
- Elevation: 0 (flat), 2 (raised), 8 (dialog)
- Touch target: minimum 48x48dp
- Minimum text size: 12sp (never smaller)

---

## 🔄 Session Protocol

### Starting a Session

```
1. git pull origin main
2. Read PROJECT_STATE.md    → current health, sprint board, risks
3. Read CHANGELOG.md        → what changed last time
4. Read OPERATIONS.md       → this file — re-anchor on process
5. Identify today's task    → must exist in PROJECT_STATE.md Sprint Board
6. Move task to "In Progress" in PROJECT_STATE.md
7. Plan approach            → state it before coding
```

### During a Session

- Small, focused commits — one logical change each
- Test as you build — don't accumulate untested code
- If you discover a new issue → add to PROJECT_STATE.md Risk Register or Technical Debt
- Don't scope-creep — note it, move on

### Ending a Session

```
1. Commit all work
2. Update PROJECT_STATE.md:
   - Move completed tasks to Done
   - Update Sprint Board
   - Update Health signals if changed
   - Update Feature Matrix status
3. Update CHANGELOG.md:
   - Add entry under [Unreleased] or new version
4. git push origin main
5. State: what was accomplished, what's next, any blockers
```

---

*This document is the law of the land. When in doubt, check here first.*
*When this document is wrong, update it. When it's outdated, that's a bug.*

*Last Updated: 2026-03-29*
