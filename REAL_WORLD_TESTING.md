# REAL_WORLD_TESTING.md — Accuracy Benchmark Protocol

**Purpose:** Measure EthioGrade's actual scanning accuracy on real printed answer sheets.
**No architecture. No features. Just field truth.**

---

## What To Record Per Paper

| Field | Required | Example |
|-------|----------|---------|
| Paper ID | Yes | P001 |
| Student name (or alias) | Yes | "Student A" |
| Device | Yes | "Tecno Spark 10 / Samsung A14" |
| Android version | Yes | "Android 13" |
| Paper condition | Yes | Clean / Folded / Smudged / Faded print |
| Lighting | Yes | Indoor daylight / Lamp / Outdoor shade |
| Sheet format | Yes | Full A4 / Half-sheet |
| Assessment ID | Yes | Link to the answer key used |
| Total questions | Yes | 40 |
| Expected answers | Yes | `A,B,C,D,A,B,C,D,...` (comma-separated) |
| Detected answers | Yes | `A,B,C,D,A,B,MISSING,D,...` (comma-separated) |
| Wrong detections | Yes | `"Q3: expected C, got B"` |
| Missed (MISSING) | Yes | `"Q7, Q22"` |
| Confidence scores | Optional | `"Q3: 0.45, Q7: 0.12"` |
| Scan time (seconds) | Optional | 4.2 |
| Notes | Optional | "Student erased Q7 heavily, paper tore" |

---

## Results Template

Copy this for each batch. One file per testing session.

```
# Test Session: [DATE]
## Device: [DEVICE MODEL]
## Lighting: [CONDITION]
## Sheet: [Full A4 / Half]

| Paper | Q#  | Expected | Detected | Correct? | Confidence | Notes           |
|-------|-----|----------|----------|----------|------------|-----------------|
| P001  | 1   | A        | A        | ✅       | 0.92       |                 |
| P001  | 2   | B        | B        | ✅       | 0.88       |                 |
| P001  | 3   | C        | B        | ❌       | 0.45       | Light pencil    |
| P001  | 4   | D        | MISSING  | ❌       | 0.12       | Smudged         |
| ...   | ... | ...      | ...      | ...      | ...        |                 |

### Summary: Paper P001
- Total: 40
- Correct: 37
- Wrong: 2 (Q3, Q15)
- Missed: 1 (Q4)
- Accuracy: 92.5%

### Summary: Session
- Papers scanned: [N]
- Total questions: [N * Q]
- Overall accuracy: [correct / total]%
- Worst failure mode: [e.g. "pencil marks below 0.5mm"]
```

---

## Minimum First Benchmark

**Do not skip these minimums. An honest pilot requires truth.**

| Dimension | Minimum | Why |
|-----------|---------|-----|
| Papers | 15 | Need enough data to spot patterns (5 clean, 5 folded/smudged, 5 faded/light pencil) |
| Devices | 2 | At least one low-end (2GB RAM) and one mid-range. Camera quality varies wildly. |
| Sheet formats | 2 | Both full A4 and half-sheet. Half-sheet anchors are tighter — more failure risk. |
| Lighting | 2 | Indoor daylight and lamp. Outdoor shade is a bonus. |
| Answer key variations | 2 | Different patterns (e.g. A-heavy vs mixed) to detect systematic bias. |

**Total scans: ~60 minimum** (15 papers × 2 formats × 2 lighting, or adjusted based on your access).

---

## How To Run A Session

1. **Print 15 answer sheets** using EthioGrade's PDF generator.
2. **Fill them by hand** with a real pencil (HB or 2B). Include:
   - 5 clean, well-filled papers (happy path)
   - 5 with light pencil, partial erasures, or smudges (stress test)
   - 5 with faded print, folded corners, or coffee stains (adversarial)
3. **Scan each paper** using Batch Scan. Record the device and lighting.
4. **Write down expected answers** before scanning (from your answer key).
5. **Compare detected vs expected** per question. Log every mismatch.
6. **Fill the results template** for each paper.
7. **Compute per-session accuracy** = correct / total.

---

## Decision Rules

After completing the minimum benchmark:

### ✅ Pilot-Ready
- Overall accuracy ≥ 95% on clean papers
- Overall accuracy ≥ 85% on stressed papers
- No systematic failure mode affecting > 20% of questions on any single paper
- Half-sheet accuracy within 5% of full-sheet accuracy
- App does not crash on any scan

### 🟡 Needs Tuning
- Overall accuracy 85–95% on clean papers
- Clear failure mode identified (e.g. "pencil < 0.3mm always missed")
- Half-sheet significantly worse than full-sheet
- Action: adjust fill threshold, anchor detection, or perspective correction

### 🔴 Not Ready
- Overall accuracy < 85% on clean papers
- Frequent crashes or hangs during batch scan
- Systematic bias (e.g. always reads B as D)
- Action: fundamental OMR rework needed before pilot

---

## Patterns To Watch For

These are the most common OMR failure modes. Log them specifically:

| Pattern | Symptom | Likely Cause |
|---------|---------|-------------|
| Light pencil missed | Q marked as MISSING but student filled it | Fill threshold too high (> 0.35) |
| Erasure detected as fill | Q shows answer but student erased | Fill threshold too low or no erasure detection |
| Wrong bubble selected | Adjacent option detected | Perspective correction error, anchor misalignment |
| Sheet not recognized | Entire scan fails | Corner anchors not detected (cropped, folded corner) |
| Half-sheet offset | All answers shifted by 1 position | Half-sheet coordinate map misaligned |

---

## What NOT To Do

- Do NOT test only with perfect clean papers — that's not reality
- Do NOT test only on your flagship phone — teachers use cheap devices
- Do NOT average away bad results — one bad paper matters if a teacher hits it
- Do NOT add features before completing the benchmark — measure first, build second
- Do NOT skip logging mismatches — every error is a clue

---

## After The Benchmark

1. Compute overall accuracy per device, per lighting, per sheet format
2. Identify top 3 failure modes by frequency
3. Decide: ✅ pilot, 🟡 tune, 🔴 rework
4. If 🟡: file specific bugs with reproduction steps (paper ID, Q#, expected, got)
5. If ✅: proceed to pilot with known limitations documented
6. Update this file with actual results — it becomes your baseline

---

_Last updated: 2026-04-17_
