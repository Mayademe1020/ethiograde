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

### In Progress
- Validate answer parser against real ML Kit output on actual exam papers

### Planned (Sprint 0)
- Move image processing to Dart isolates for 2GB device performance
- Unit tests for scoring engine and answer parser

---

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
