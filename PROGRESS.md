# EthioGrade — Project Progress

> **Last Updated:** 2026-03-29
> **Current Phase:** Foundation & Scaffold
> **Overall Completion:** ~30%

---

## ✅ Done

| # | Area | What's Complete |
|---|------|-----------------|
| 1 | **Architecture** | Full project scaffold — 31 Dart files across models, services, screens, widgets |
| 2 | **Models** | Student, Assessment, Question, ScanResult, ClassInfo — all with Hive adapters |
| 3 | **State Management** | Provider setup for: students, assessments, analytics, settings, locale |
| 4 | **Theme** | Ethiopian-inspired theme (green/yellow/red) with dark mode support |
| 5 | **Routing** | Named routes for all screens |
| 6 | **Bilingual Support** | Amharic/English toggle wired through LocaleProvider |
| 7 | **Camera Screen** | Camera preview, flash toggle, scan guide overlay, capture flow |
| 8 | **Image Enhancement** | White balance, contrast, sharpen, denoise, adaptive threshold — working |
| 9 | **Answer Parsing** | Regex-based parser for "1. A", "1-A", "1) እውነት" formats (EN + AM) |
| 10 | **Scoring Engine** | MCQ, True/False, short-answer matching with configurable grading scales |
| 11 | **PDF Reports** | Student report cards + class reports with school branding |
| 12 | **Voice Service** | STT, TTS, audio recording — wired and functional |
| 13 | **Excel Import** | Student list import from .xlsx via file_picker |
| 14 | **Analytics** | Grade distribution, question-level stats, topic scores, difficulty analysis |
| 15 | **Screens** | Onboarding, Dashboard (4 tabs), Create Assessment, Answer Key, Camera, Batch Scan, Review, Analytics, Reports, Students, Subscription |
| 16 | **UI Components** | StatCard, AssessmentCard, LanguageToggle |

---

## 🔄 In Progress

| # | Area | Status |
|---|------|--------|
| — | *No active work items* | — |

---

## ❌ Not Done — Critical (Blocks Core Functionality)

| # | Priority | Task | Details | Est. Effort |
|---|----------|------|---------|-------------|
| 1 | **P0** | **Real OCR integration** | `_extractTextRegions()` in `ocr_service.dart:106` returns hardcoded dummy data. Must wire up `google_mlkit_text_recognition` for actual text detection. | Medium |
| 2 | **P0** | **Amharic TFLite model** | `assets/models/` is empty. Need a trained `amharic_ocr.tflite` + `labels.txt` for handwriting recognition. | Large |
| 3 | **P0** | **Missing font files** | `assets/fonts/` is empty. App won't compile without `NotoSansEthiopic-Regular.ttf` and `NotoSansEthiopic-Bold.ttf`. | Small |
| 4 | **P0** | **Missing splash logo** | `android/app/src/main/res/drawable/` has no splash image. Build will warn/fail. | Small |

## ❌ Not Done — Features (Code Has TODOs)

| # | Priority | Task | Location | Details |
|---|----------|------|----------|---------|
| 5 | **P1** | **Teacher management** | `subscription_screen.dart:225` | "Add Teacher" dialog exists but doesn't persist anything |
| 6 | **P1** | **Re-scan paper** | `review_screen.dart:437` | Button exists, no camera re-launch logic |
| 7 | **P1** | **Dashboard search** | `main_dashboard.dart:513` | Search icon visible, no implementation |
| 8 | **P1** | **Play voice recordings** | `voice_service.dart` | `playRecording()` just speaks placeholder text |
| 9 | **P2** | **Telebirr payment** | `subscription_screen.dart` | Only a "coming soon" dialog — no integration |

## ❌ Not Done — Planned Future Work (from README)

| # | Priority | Task |
|---|----------|------|
| 10 | **P2** | Short-answer keyword matching AI |
| 11 | **P2** | Essay grading rubric AI (university mode) |
| 12 | **P2** | QR code student ID scanning |
| 13 | **P3** | School admin multi-teacher management |
| 14 | **P3** | Cloud sync (optional, for school mode) |

## ⚠️ Technical Debt

| # | Issue | Impact |
|---|-------|--------|
| 1 | **No tests** — `test/` directory is empty | No safety net for refactoring |
| 2 | **Slow image processing** — pixel-by-pixel Dart loops in `_adaptiveThreshold()` | Will freeze UI on real devices |
| 3 | **No error handling** on OCR pipeline | Crashes on corrupt images, permission failures |
| 4 | **No unit tests for answer parsing** | Regex patterns unverified against real handwriting output |
| 5 | **Hardcoded student IDs** — camera screen uses `student_$_scanCount` | Not linked to actual student records |

---

## 📋 Next Up (Execution Order)

```
1.  Add missing fonts + splash image          → get it building
2.  Wire real ML Kit text recognition          → real OCR
3.  Source/train Amharic TFLite model          → core value prop
4.  Fix answer parsing to match real OCR output→ accuracy
5.  Wire teacher management to Hive            → feature complete
6.  Implement re-scan flow                     → UX fix
7.  Add dashboard search                       → UX fix
8.  Fix voice recording playback               → feature complete
9.  Add unit tests for scoring + parsing       → stability
10. Optimize image processing                  → performance
```

---

*This file is the source of truth for project status. Update it with every meaningful commit.*
