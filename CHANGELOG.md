# Changelog

All notable changes to EthioGrade are documented here.
Format: date, what changed, impact.

---

## [0.1.0] — 2026-03-29

### Added
- Initial project scaffold with full directory structure
- 31 Dart files: models, services, screens, widgets, config
- Ethiopian-inspired theme (green/yellow/red) with dark mode
- Amharic/English bilingual toggle
- Camera screen with scan guide overlay and flash control
- Image enhancement pipeline (white balance, contrast, sharpen, denoise, binarize)
- Answer parser supporting EN (A/B/C/D/E, True/False) and AM (እውነት/ሐሰት, ሀ-ሠ letters)
- Scoring engine with MoE national, international, and university grading scales
- PDF report generation (student cards + class reports)
- Voice service: STT, TTS, audio recording
- Excel student import from .xlsx
- Analytics: grade distribution, question stats, topic scores, difficulty analysis
- All screens: Onboarding, Dashboard, Create Assessment, Answer Key, Camera, Batch Scan, Review, Analytics, Reports, Students, Subscription
- PROGRESS.md — living project status tracker

### Known Limitations
- OCR uses mock data (hardcoded text regions, not real ML Kit)
- No TFLite Amharic model bundled
- Font files missing from `assets/fonts/`
- Splash logo missing from Android drawable
- Teacher management, re-scan, search are stub TODOs
- No tests
- Telebirr payment is placeholder only

---

*Update this file with every commit. Keep it honest — what shipped, what broke, what improved.*
