# EthioGrade – Task Board for OpenCode / Codespace
> Last updated: 2026-11-21 | Phase 1 committed to `main` branch

---

## ✅ DONE (Phase 1 — merged to `main`)

| File | What it does |
|---|---|
| `lib/models/proof_vault_entry.dart` | Bubble density vector + SHA-256 tamper-proof record |
| `lib/models/homeroom_report.dart` | Card Day data models (SubjectScoreBreakdown, StudentCardRecord, HomeroomClassReport) |
| `lib/services/homeroom_consolidation_service.dart` | Ranking engine, bilingual remarks, Finance Hold flag |
| `pubspec.yaml` | Fixed Dart 3.7.2 compat; removed `google_fonts`; added `excel ^4.0.6` |
| `lib/config/theme.dart` | Replaced `GoogleFonts.*` with local `_pjs()` helper |
| Dead code deleted | `appsscript/`, `smart_ocr_service`, `voice_service`, `student_transfer_service`, `cloud_grading_config` |

---

## 🔴 P0 — Build These Next (Critical Path)

### TASK-01 · Fix remaining `_buildTextTheme` in `theme.dart`
**File:** `lib/config/theme.dart` line ~155  
**Problem:** One line still calls `GoogleFonts.plusJakartaSansTextTheme()` — will cause compile error.  
**Fix:** Replace the entire `_buildTextTheme` function body:
```dart
static TextTheme _buildTextTheme(Color bodyColor, Color displayColor) {
  return TextTheme(
    displayLarge: _pjs(fontSize: 34, fontWeight: FontWeight.w800, color: displayColor, height: 1.1),
    displayMedium: _pjs(fontSize: 28, fontWeight: FontWeight.w800, color: displayColor, height: 1.15),
    headlineLarge: _pjs(fontSize: 24, fontWeight: FontWeight.w700, color: displayColor, height: 1.2),
    headlineMedium: _pjs(fontSize: 20, fontWeight: FontWeight.w700, color: displayColor, height: 1.25),
    headlineSmall: _pjs(fontSize: 18, fontWeight: FontWeight.w600, color: displayColor, height: 1.3),
    titleLarge: _pjs(fontSize: 17, fontWeight: FontWeight.w700, color: displayColor, height: 1.35),
    titleMedium: _pjs(fontSize: 15, fontWeight: FontWeight.w600, color: bodyColor, height: 1.4),
    titleSmall: _pjs(fontSize: 13, fontWeight: FontWeight.w600, color: bodyColor, height: 1.4),
    bodyLarge: _pjs(fontSize: 16, fontWeight: FontWeight.w400, color: bodyColor, height: 1.5),
    bodyMedium: _pjs(fontSize: 14, fontWeight: FontWeight.w400, color: bodyColor, height: 1.5),
    bodySmall: _pjs(fontSize: 12, fontWeight: FontWeight.w400, color: bodyColor.withValues(alpha: 0.7), height: 1.4),
    labelLarge: _pjs(fontSize: 14, fontWeight: FontWeight.w600, color: bodyColor),
    labelMedium: _pjs(fontSize: 12, fontWeight: FontWeight.w600, color: bodyColor),
    labelSmall: _pjs(fontSize: 11, fontWeight: FontWeight.w500, color: bodyColor.withValues(alpha: 0.7), letterSpacing: 0.5),
  );
}
```
**After:** Run `flutter pub get` then `flutter analyze` — should be 0 errors.

---

### TASK-02 · Download Noto Sans Ethiopic font
**Why:** Report Card PDFs **must** print Amharic (Fidel script). The `pdf` package needs an OTF/TTF file.  
**Steps:**
1. Download from: https://fonts.google.com/noto/specimen/Noto+Sans+Ethiopic  
   → Download "Noto Sans Ethiopic" → extract `NotoSansEthiopic-Regular.ttf`
2. Place it at: `assets/fonts/NotoSansEthiopic-Regular.ttf`
3. Add to `pubspec.yaml` flutter fonts section:
```yaml
    - family: NotoSansEthiopic
      fonts:
        - asset: assets/fonts/NotoSansEthiopic-Regular.ttf
```
**Verify:** `flutter pub get` succeeds.

---

### TASK-03 · Create `lib/services/proof_vault_service.dart`
**What it does:** Save/retrieve `ProofVaultEntry` records from Hive. This is the "anti-cheating shield."  
**Create the file with this content:**
```dart
import 'package:hive_flutter/hive_flutter.dart';
import '../models/proof_vault_entry.dart';

class ProofVaultService {
  static const String _boxName = 'proof_vault';

  Future<Box<Map>> _openBox() async {
    return await Hive.openBox<Map>(_boxName);
  }

  /// Save a scan record. Key = assessmentId_studentId
  Future<void> saveEntry(ProofVaultEntry entry) async {
    final box = await _openBox();
    await box.put('${entry.assessmentId}_${entry.studentId}', entry.toJson());
  }

  /// Retrieve an entry. Returns null if no scan exists yet.
  Future<ProofVaultEntry?> getEntry(String assessmentId, String studentId) async {
    final box = await _openBox();
    final raw = box.get('${assessmentId}_${studentId}');
    if (raw == null) return null;
    return ProofVaultEntry.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  /// Get all entries for a given assessment (for class-level review).
  Future<List<ProofVaultEntry>> getEntriesForAssessment(String assessmentId) async {
    final box = await _openBox();
    return box.keys
        .where((k) => (k as String).startsWith('${assessmentId}_'))
        .map((k) => ProofVaultEntry.fromJson(Map<String, dynamic>.from(box.get(k) as Map)))
        .toList();
  }

  /// Delete all entries for an assessment (when assessment is deleted).
  Future<void> deleteEntriesForAssessment(String assessmentId) async {
    final box = await _openBox();
    final keys = box.keys.where((k) => (k as String).startsWith('${assessmentId}_')).toList();
    await box.deleteAll(keys);
  }
}
```

---

### TASK-04 · Create `lib/services/report_card_pdf_service.dart`
**What it does:** Takes a `HomeroomClassReport` → outputs two PDF files:
- `AllCards.pdf` — 4 student card slips per A4 page
- `HeldCards.pdf` — only finance-hold students, watermarked

**Key requirements:**
- Uses `pdf: ^3.10.7` package (already in pubspec)
- Loads `NotoSansEthiopic-Regular.ttf` from assets for Amharic text
- Loads `PlusJakartaSans-Bold.ttf` for English text
- Bilingual labels:
  - Title: `የተማሪ ውጤት መግለጫ ካርድ` / "Student Report Card"
  - Name: `ስም` / "Name"
  - Rank: `ደረጃ` / "Rank"  
  - Average: `አማካይ` / "Average"
  - Teacher Remark: `የመምህሩ አስተያየት` / "Remark"
- Finance hold watermark text: `"SEE FINANCE OFFICE / ፋይናንስ ቢሮ ይጎብኙ"`
- Output path: use `path_provider` → `getExternalStorageDirectory()` or `getApplicationDocumentsDirectory()`

**Skeleton to build from:**
```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/homeroom_report.dart';

class ReportCardPdfService {
  Future<pw.Font> _loadFont(String asset) async {
    final data = await rootBundle.load(asset);
    return pw.Font.ttf(data);
  }

  Future<Map<String, String>> generateCardDay(HomeroomClassReport report) async {
    final ejFont = await _loadFont('assets/fonts/NotoSansEthiopic-Regular.ttf');
    final enFont = await _loadFont('assets/fonts/PlusJakartaSans-Bold.ttf');

    final allPdf = pw.Document();
    final heldPdf = pw.Document();

    // 4 students per page — build pages here
    // ... (see full implementation task)

    final dir = await getApplicationDocumentsDirectory();
    final allPath = '${dir.path}/AllCards_${report.className}.pdf';
    final heldPath = '${dir.path}/HeldCards_${report.className}.pdf';

    await File(allPath).writeAsBytes(await allPdf.save());
    await File(heldPath).writeAsBytes(await heldPdf.save());

    return {'allCards': allPath, 'heldCards': heldPath};
  }
}
```
**Complete the PDF layout logic** — 4-up card grid, subject rows, bilingual headers, watermark.

---

### TASK-05 · Create `lib/screens/homeroom/homeroom_card_screen.dart`
**What it does:** The teacher's "Card Day Hub" — combines all subject scans into one class view.  
**UI elements:**
1. `DropdownButton` → select class section
2. `DataTable` → rows = students, columns = subjects + Total + Average + Rank
   - Cell is gray if subject not yet submitted, green if complete
3. Per-student row tap → bottom sheet with:
   - Conduct grade picker: `[A] [B] [C] [D]`
   - Finance Hold toggle (switch with `እዳ ያለበት` label)
4. Bottom action bar:
   - `🖨️ Print Report Cards (PDF)` → calls `ReportCardPdfService.generateCardDay()`
   - `📊 Export Broadsheet (Excel)` → calls `ExcelService.exportMinistryBroadsheet()`
5. Status bar: `"X subjects submitted / Y total — Z students ranked"`

---

### TASK-06 · Write unit tests
**File to create:** `test/services/homeroom_consolidation_service_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/services/homeroom_consolidation_service.dart';
import 'package:ethiograde/models/homeroom_report.dart';

void main() {
  group('HomeroomConsolidationService', () {
    test('highest total gets rank 1', () { /* ... */ });
    test('tied scores get same rank, next rank skips', () { /* ... */ });
    test('Finance Hold flag propagates to output', () { /* ... */ });
    test('bilingual remark: avg >= 85 -> Outstanding / የላቀ ውጤት', () { /* ... */ });
    test('subject weight normalization: midterm 30%, final 50%', () { /* ... */ });
  });
}
```

---

## 🟡 P1 — After P0 is working

### TASK-07 · License & Monetization (`lib/services/license_service.dart`)
- Offline HMAC-SHA256 activation code verification
- Free tier: 100 scans/month tracked in SharedPreferences
- `lib/screens/settings/activation_screen.dart` — shows trial status + Telebirr payment instructions

### TASK-08 · Quick Enter screen (CA component entry)
- File: `lib/screens/assessment/quick_enter_screen.dart`
- Lists class roster, tap a cell to enter a number (0–100)
- Auto-advance to next student
- Saves as a non-scanned `Assessment` with type `'manual_ca'`
- For: homework (10pt), group project (10pt), attendance, lab marks

### TASK-09 · OMR engine improvements
- File: `lib/services/coordinate_map_omr_service.dart` (extend existing)
- **Blue ink chroma isolation:** convert to HSV, isolate blue-black hue range before thresholding
- **Scribble/erasure detection:** if a bubble area has density > threshold AND neighbor pixels are also dark → flag as "scribble, not answer"
- **X-mark detection:** detect X pattern inside bubble as valid answer (many Ethiopian students do this)

### TASK-10 · HoD Analytics Dashboard
- File: `lib/screens/analytics/hod_dashboard_screen.dart`
- Section comparison: Grade 10A avg vs 10B avg per subject
- Item Discrimination Index: flag questions where top-20% students got wrong but bottom-20% got right
- Export as PDF for HoD meeting

### TASK-11 · Dashboard redesign (`lib/screens/home/main_dashboard.dart`)
- Remove: cluttered action grid
- Add: Hero "Next Action" card (e.g., "10B Biology: 12 papers left → Resume")
- 3 big tiles: 📄 New Exam | 📷 Scan Papers | 🎓 Card Day
- Quick Enter + Settings → bottom nav

---

## 🔵 P2 — Later / Nice to Have

### TASK-12 · Answer Sheet Pads (pre-printed)
- Design artwork for printer-ready 2-per-A4 A5 sheets
- Corner anchors, contrast-optimized for Risograph/photocopier

### TASK-13 · CRC Demo mode
- "Demo school" mode: loads synthetic class of 40 students
- Scan fake papers to show at Woreda CRC presentation
- One-tap: "Export Cluster Rankings" for 5 demo schools

### TASK-14 · Student add/edit screen simplification
- File: `lib/screens/students/add_student_screen.dart`
- Required: Full Name + Roll Number only
- Optional (collapsed): gender, parent phone, section

---

## 🛠️ HOW TO RUN IN CODESPACE

```bash
# 1. Clone
git clone https://github.com/Mayademe1020/ethiograde.git
cd ethiograde

# 2. Set up Flutter (use Flutter 3.29.x)
flutter --version  # must show 3.29.x / Dart 3.7.x

# 3. Get packages
flutter pub get

# 4. Verify no errors
flutter analyze

# 5. Run tests
flutter test test/services/scoring_service_test.dart  # existing baseline
flutter test  # all tests once you've added TASK-06
```

> **OpenCode note:** If `flutter pub get` hangs, use `dart pub get --no-precompile` instead.

---

## 📂 Key File Map (for quick navigation in Codespace)

```
lib/
├── config/
│   ├── theme.dart              ← TASK-01 fix needed
│   └── routes.dart
├── models/
│   ├── proof_vault_entry.dart  ✅ Done
│   ├── homeroom_report.dart    ✅ Done
│   └── assessment.dart
├── services/
│   ├── homeroom_consolidation_service.dart  ✅ Done
│   ├── proof_vault_service.dart             ← TASK-03 TODO
│   ├── report_card_pdf_service.dart         ← TASK-04 TODO
│   ├── coordinate_map_omr_service.dart      ← TASK-09 extend
│   └── excel_service.dart                   ← extend for broadsheet
├── screens/
│   ├── homeroom/
│   │   └── homeroom_card_screen.dart        ← TASK-05 TODO
│   ├── assessment/
│   │   └── quick_enter_screen.dart          ← TASK-08 TODO
│   └── home/
│       └── main_dashboard.dart              ← TASK-11 redesign
assets/
└── fonts/
    ├── PlusJakartaSans-*.ttf   ✅ Bundled
    └── NotoSansEthiopic-Regular.ttf  ← TASK-02 download & add
test/
└── services/
    └── homeroom_consolidation_service_test.dart  ← TASK-06 TODO
```
