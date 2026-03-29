# Changelog

All notable changes to EthioGrade are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/lang/am/):
- **MAJOR** (x.0.0) — Breaking changes, production release milestones
- **MINOR** (0.x.0) — New features, non-breaking
- **PATCH** (0.0.x) — Bug fixes, improvements, docs

Categories: `Added` `Changed` `Fixed` `Improved` `Removed` `Deprecated` `Security` `Performance` `Docs` `Infra`

---

## [Unreleased]

### In Progress
- Real OCR integration (ML Kit text recognition)
- Font assets (NotoSansEthiopic)
- Splash screen assets

### Planned (Sprint 0)
- Move image processing to Dart isolates for 2GB device performance
- Error handling for OCR pipeline (corrupt images, permissions, empty results)
- Unit tests for scoring engine and answer parser

---

## [0.1.0-scaffold] — 2026-03-29

> The foundation. Nothing works end-to-end yet, but the architecture is sound.

### Added
- Project scaffold: 31 Dart files across `lib/models/`, `lib/services/`, `lib/screens/`, `lib/widgets/`, `lib/config/`
- **Models:** `Student`, `Assessment`, `Question`, `ScanResult`, `ClassInfo` with Hive type adapters
- **State management:** Provider pattern for students, assessments, analytics, settings, locale
- **Theme:** Ethiopian-inspired palette (green/yellow/red) with dark mode, Material 3
- **Routing:** Named routes for all 11 screens
- **Bilingual:** Amharic/English toggle via `LocaleProvider` — all UI strings dual-language
- **Camera:** Full-screen preview, flash toggle, exposure/focus auto, scan guide overlay with corner brackets
- **Image enhancement pipeline:** Auto white balance → contrast boost → sharpen → denoise → grayscale → adaptive threshold binarization
- **Answer parser:** Regex engine for `"1. A"`, `"1-A"`, `"1) እውነት"` formats; handles Amharic True/False (እውነት/ሐሰት) and MCQ letters (ሀ-ሠ → A-E)
- **Scoring engine:** MCQ, True/False, short-answer matching; MoE national, international, and university grading scales
- **PDF reports:** Student report cards + class reports with school logo, teacher name, MoE format
- **Voice service:** Speech-to-text, text-to-speech, audio recording (Amharic + English)
- **Excel import:** Student list from `.xlsx` files via `file_picker`
- **Analytics:** Grade distribution, per-question stats, topic score averages, difficulty analysis
- **Screens (11):** Onboarding → Dashboard (4 tabs) → Create Assessment → Answer Key → Camera → Batch Scan → Review → Analytics → Reports → Students → Subscription
- **Widgets:** `StatCard`, `AssessmentCard`, `LanguageToggle`
- **Project docs:** `PROGRESS.md`, `CHANGELOG.md`, `WORKFLOW.md`, `SESSION_PROMPT.md`

### Known Issues
- ⚠️ OCR returns hardcoded mock data — not real text recognition
- ⚠️ No font files in `assets/fonts/` — app won't compile
- ⚠️ No splash logo in Android drawable
- ⚠️ No TFLite model in `assets/models/`
- ⚠️ "Add Teacher" dialog doesn't persist data
- ⚠️ Re-scan button has no logic
- ⚠️ Dashboard search is stub only
- ⚠️ Voice recording playback is placeholder
- ⚠️ Telebirr payment is "coming soon" dialog
- ⚠️ No tests, no CI/CD
- ⚠️ Image processing uses slow pixel-by-pixel Dart loops
- ⚠️ Hardcoded student IDs in camera flow

---

## [0.0.0] — Project Inception

- Repository created
- Initial README with feature vision, tech stack, project structure, and to-do list

---

*Every entry answers: What changed? Why? What broke? What's next?*
*If it's not in the changelog, it didn't happen.*
