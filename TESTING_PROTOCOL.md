# Real Device Testing Protocol

> Before a teacher in Hawassa trusts this app, we test it ourselves.
> No shortcuts. No "it should work."

---

## Device Requirements

| Spec | Minimum | Ideal |
|------|---------|-------|
| RAM | 2GB | 4GB |
| Android | 8.0 (API 26) | 10+ |
| Camera | Rear, autofocus | Rear, autofocus, flash |
| Storage | 100MB free | 500MB free |
| Internet | NOT required | Airplane mode ON during test |

---

## Pre-Test Setup

1. Build debug APK: `flutter build apk --debug`
2. Install on device: `flutter install`
3. Enable airplane mode (proves offline-first)
4. Grant camera + storage permissions when prompted
5. Complete onboarding flow

---

## Test Scenarios

### T1: Clean MCQ Sheet (Happy Path)
**Input:** Printed answer sheet, 20 questions, A-E answers, good lighting
**Steps:**
1. Create assessment with 20 MCQ questions, correct answers: A,C,B,D,A,E,B,C,D,A,E,B,C,D,A,E,B,C,D,A
2. Open camera, scan the printed sheet
3. Check: enhancement completes in <2s
4. Check: all 20 answers detected
5. Check: score matches expected
6. Check: scan-to-result <5s total

**Pass criteria:** ≥19/20 correct detection, <5s total

---

### T2: Dim Classroom Lighting
**Input:** Same printed sheet, room lights off, window light only
**Steps:**
1. Repeat T1 in dim conditions
2. Check: confidence scores are lower but answers still correct
3. Check: no crash, no freeze

**Pass criteria:** ≥17/20 correct, app doesn't freeze

---

### T3: Handwritten Answers (Amharic)
**Input:** Student paper with handwritten ሀ, ለ, ሐ, መ answers
**Steps:**
1. Create assessment with 10 questions
2. Scan handwritten paper
3. Check: Amharic letters recognized or gracefully degraded
4. Check: teacher can manually correct via review screen

**Pass criteria:** No crash. Manual correction flow works. Amharic detection is bonus.

---

### T4: Rotated/Tilted Paper
**Input:** Paper scanned at ~15° angle
**Steps:**
1. Scan tilted paper
2. Check: skew detected and logged in metadata
3. Check: answers still partially correct
4. Check: no crash

**Pass criteria:** Skew detected, no crash, ≥50% answers correct

---

### T5: Paper Upside Down
**Input:** Paper scanned upside down (180°)
**Steps:**
1. Scan upside down
2. Check: EXIF rotation handled
3. Check: ML Kit still detects some text
4. Check: graceful failure if nothing detected

**Pass criteria:** No crash. Either detects or returns empty gracefully.

---

### T6: Batch Scan (10 Papers)
**Input:** 10 different answer sheets
**Steps:**
1. Use batch scan mode
2. Scan all 10 papers sequentially
3. Check: each scan completes in <5s
4. Check: total memory stays <150MB
5. Check: no lag in camera preview between scans
6. Check: all 10 results saved

**Pass criteria:** All 10 scanned, no OOM, no crash, <1min total

---

### T7: Low-End Device Stress
**Input:** 2GB RAM device, other apps open
**Steps:**
1. Open 3-4 other apps in background
2. Run T1 scan
3. Check: no OOM kill
4. Check: scan still completes

**Pass criteria:** App survives, scan completes

---

### T8: PDF Export After Scanning
**Input:** Completed batch scan results
**Steps:**
1. Go to Reports screen
2. Generate student PDF
3. Generate class PDF
4. Check: PDF opens correctly
5. Check: grades match scan results

**Pass criteria:** PDFs generate, grades are correct

---

### T9: Review Screen Manual Override
**Input:** A scan with some wrong detections
**Steps:**
1. Open review screen for a scan
2. Change a detected answer manually
3. Check: score recalculates
4. Check: change persists after navigating away and back

**Pass criteria:** Override works, persists

---

### T10: Crash Recovery
**Input:** Mid-scan
**Steps:**
1. Start a scan
2. Kill the app (swipe away) during enhancement
3. Reopen app
4. Check: previous completed scans still exist
5. Check: no data corruption

**Pass criteria:** Previous data intact, app reopens cleanly

---

## Performance Benchmarks

Record these during testing:

| Metric | Target | Actual |
|--------|--------|--------|
| Enhancement time | <1s | ___ |
| ML Kit recognition | <2s | ___ |
| Total scan-to-result | <5s | ___ |
| Memory peak (scan) | <100MB | ___ |
| Memory peak (batch 10) | <150MB | ___ |
| APK size | <50MB | ___ |
| Cold start time | <3s | ___ |

---

## Known Limitations (Not Failures)

- Amharic handwriting recognition may be low — ML Kit Latin script doesn't handle አማርኛ well
- Extreme skew (>25°) may produce garbage — teacher should re-scan
- Flash off in very dark rooms will fail — camera needs minimum light

---

## What to Report

For each test, record:
- Device model + Android version
- RAM available
- Test scenario ID
- Pass/Fail
- Actual performance numbers
- Screenshots of any failures
- Logcat output for crashes (`adb logcat | grep flutter`)

---

*This protocol exists because "it works on my machine" is not a standard.
A teacher's trust is earned in the first scan.*
