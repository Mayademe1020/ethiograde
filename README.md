# EthioGrade
**AI-Powered Offline Grading for Ethiopian Teachers**

An offline-first Android app built with Flutter for grading exams in Grades 1–12 and universities. Works without internet — designed for teachers across Ethiopia.

## Features
- 📸 **Any-Paper Scanning** — Camera scans regular exam papers, reads handwriting in Amharic & English
- 🤖 **Offline AI Grading** — Auto-enhances images (glare/shadow removal), OCR + local ML models
- 🔤 **Amharic + English** — Recognizes A/B/C/D/E, እውነት/ሐሰት (True/False), letters in both scripts
- 🎤 **Voice Commands** — Record feedback in Amharic or English
- 📊 **Analytics** — Class averages, topic heatmaps, difficulty analysis
- 📄 **PDF Reports** — Custom logo, MoE format or internal reports
- 📤 **Sharing** — Telegram/WhatsApp one-tap send
- 📥 **Excel Import** — Import class lists from .xlsx
- 🔀 **Dual Mode** — Individual Teacher (free) or School Admin (Telebirr placeholder)

## Tech Stack
- **Flutter** 3.x (Dart 3.1+)
- **State Management**: Provider + Hive (local DB)
- **Camera**: camera plugin with real-time preview
- **OCR**: Google ML Kit text recognition (offline)
- **PDF**: pdf + printing packages
- **Voice**: speech_to_text + flutter_tts + record
- **Excel**: excel + file_picker
- **Charts**: fl_chart
- **Target**: Android 8+ (API 26), 2GB RAM minimum

## Project Structure
```
ethiograde/
├── lib/
│   ├── main.dart                 # App entry, Hive init, providers
│   ├── config/
│   │   ├── routes.dart           # Navigation routes
│   │   ├── theme.dart            # Ethiopian-inspired theme (green/yellow/red)
│   │   └── constants.dart        # Grading scales, box names
│   ├── models/
│   │   ├── student.dart          # Student model (bilingual names)
│   │   ├── assessment.dart       # Assessment + Question models
│   │   ├── scan_result.dart      # OCR result + answer matching
│   │   └── class_info.dart       # Class + analytics models
│   ├── services/
│   │   ├── ocr_service.dart      # Image enhancement + offline OCR
│   │   ├── pdf_service.dart      # Report card + class report PDFs
│   │   ├── voice_service.dart    # STT + TTS + recording
│   │   ├── excel_service.dart    # Import/export students
│   │   ├── analytics_provider.dart  # Class analytics computation
│   │   ├── assessment_provider.dart # Assessment CRUD
│   │   ├── student_provider.dart    # Student CRUD
│   │   ├── settings_provider.dart   # App settings
│   │   └── locale_provider.dart     # Amharic/English toggle
│   ├── screens/
│   │   ├── onboarding/           # First-run setup
│   │   ├── home/                 # Dashboard (4 tabs)
│   │   ├── assessment/           # Create assessment, answer key
│   │   ├── scanning/             # Camera, batch scan
│   │   ├── review/               # Side-by-side review, overrides
│   │   ├── analytics/            # Charts, heatmaps, insights
│   │   ├── reports/              # PDF generation, sharing
│   │   ├── students/             # Excel import, manual add
│   │   └── subscription/         # Individual vs School mode
│   └── widgets/
│       ├── stat_card.dart        # Dashboard stat cards
│       ├── assessment_card.dart  # Assessment list item
│       └── language_toggle.dart  # EN ↔ አማ toggle
├── android/                      # Android build config (API 26+)
├── assets/                       # fonts, images, TFLite models (placeholder)
└── pubspec.yaml
```

## Getting Started

1. **Install Flutter SDK** (3.1+)
2. **Clone/copy** this project
3. **Add fonts**: Download `NotoSansEthiopic-Regular.ttf` and `NotoSansEthiopic-Bold.ttf` from Google Fonts, place in `assets/fonts/`
4. **Add splash logo**: Place `splash_logo.png` in `android/app/src/main/res/drawable/`
5. Run:
   ```bash
   flutter pub get
   flutter run
   ```

## To-Do / Future Work
- [ ] Add TFLite Amharic handwriting model (`assets/models/amharic_ocr.tflite`)
- [ ] Implement real ML Kit text recognition (currently mock OCR)
- [ ] Add Telebirr payment integration
- [ ] School admin multi-teacher management
- [ ] Cloud sync (optional, for school mode)
- [ ] Short-answer keyword matching AI
- [ ] Essay grading rubric AI (university mode)
- [ ] QR code student ID scanning

## License
Built for Ethiopian educators. Open source.
