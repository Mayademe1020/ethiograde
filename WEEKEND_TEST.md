# WEEKEND_TEST.md — One-Day Accuracy Sprint

**Goal:** 10 papers, 1 phone, 1 teacher, 3 hours. Get real numbers, not theories.

---

## 1. Minimum Materials

| Item | Notes |
|------|-------|
| Your phone | The one you'd actually use in class. Not a borrowed flagship. |
| 10 printed answer sheets | Use EthioGrade's PDF generator. Full A4. |
| HB or 2B pencil | The pencil your students actually use. Not pen. |
| 1 answer key | A single assessment with ~20-30 MCQ questions. |
| A table near a window | Daylight. No flash needed. |
| This logging sheet | Printed or on a second screen. |

That's it. No second phone. No special lighting rig. No folded/smudged papers yet — those come in round 2 if round 1 looks good.

---

## 2. One-Day Schedule (3 hours after work)

| Time | Duration | What |
|------|----------|------|
| 0:00 | 15 min | Print 10 sheets + 1 answer key. Fill answer key in app. |
| 0:15 | 30 min | Fill all 10 sheets by hand with pencil. 5 clean, 5 with light marks (press lightly on purpose for 2 of them). |
| 0:45 | 60 min | Scan all 10 sheets. One at a time. Log each result immediately. |
| 1:45 | 30 min | Compare detected vs expected. Count errors. |
| 2:15 | 15 min | Compute accuracy. Make the decision. |
| 2:30 | done | You have your answer. |

**Critical:** Log as you scan. Do not scan all 10 then try to remember what happened.

---

## 3. Simplified Logging Sheet

Print this 10 times (or copy into a notebook). One per paper.

```
Paper #: ____
Time: ____

Expected answers: A,B,C,D,A,B,C,D,A,B,C,D,A,B,C,D,A,B,C,D  (write yours)
Detected answers: ___________________________________________

Errors:
  Q#__ expected __ got __  (type: wrong / missed)
  Q#__ expected __ got __
  Q#__ expected __ got __

Total questions: ____
Correct: ____
Wrong: ____
Missed (MISSING): ____

Accuracy: ____%   (= correct ÷ total × 100)

Notes: (light pencil? smudge? fold? camera shake?)
__________________________________________________
```

**Do not skip the Notes field.** A 60% on a heavily erased paper is different from a 60% on a clean one.

---

## 4. How To Score Accuracy Quickly

After scanning all 10 papers:

```
Paper 01: 18/20 = 90%
Paper 02: 17/20 = 85%
Paper 03: 20/20 = 100%
Paper 04: 15/20 = 75%   ← light pencil
Paper 05: 19/20 = 95%
Paper 06: 20/20 = 100%
Paper 07: 14/20 = 70%   ← light pencil
Paper 08: 18/20 = 90%
Paper 09: 19/20 = 95%
Paper 10: 16/20 = 80%   ← light pencil

─────────────────────────────
TOTAL:     176/200 = 88%
Clean avg: 170/180 = 94.4%   (papers without light pencil)
Light avg:  45/60  = 75.0%   (light pencil papers)
```

**Two numbers matter:**
- **Overall:** correct ÷ total across all 10 papers
- **Clean-only:** correct ÷ total on the 5 clean papers

If clean papers score well but light-pencil papers tank, that's a known threshold issue — fixable, not fatal.

---

## 5. Decision Rules

### ✅ Go to pilot
- Clean paper accuracy ≥ 90%
- Overall accuracy ≥ 85%
- Zero crashes during scanning
- No systematic pattern (e.g., always misreads D as B)

### 🟡 Tune and retest
- Clean paper accuracy 75–90%
- Clear failure mode you can name: "light pencil always missed" or "erased answers read as filled"
- Action: adjust fill threshold or perspective correction. Retest next weekend with same 10 papers.

### 🔴 Stop and rethink
- Clean paper accuracy < 75%
- Crashes or hangs on >2 papers
- Systematic wrong reads (consistently swaps two answers)
- Action: the OMR pipeline has a fundamental issue. Do not ship to teachers.

**One exception:** If only 1-2 papers are bad and they have obvious physical damage (torn, coffee-stained), exclude them and recompute. Reality includes damaged papers, but one coffee stain shouldn't sink the whole benchmark.

---

## 6. Common Mistakes To Avoid

| Mistake | Why it kills your data |
|---------|----------------------|
| Testing in a dark room | OCR/OMR needs contrast. Low light = useless results. Use a window. |
| Using a pen instead of pencil | Your OMR is tuned for pencil fill. Pen changes the darkness profile entirely. |
| Filling bubbles too perfectly | Real students scribble. Fill like a real student would — messy, partial, sometimes outside the circle. |
| Scanning with flash on | Flash creates hot spots and reflections. Natural light or a lamp from the side. |
| Holding the phone too close | Camera needs to see the whole sheet. ~30cm above, centered. |
| Moving the phone mid-scan | Motion blur kills detection. Hold still. Tap to focus. Wait. Then capture. |
| Only testing with your own answer pattern | If your key is A,A,A,A... it masks systematic bias. Use a mixed pattern: A,B,C,D,B,A,C,D... |
| Not logging failures immediately | You will forget which paper had the smudge. Log it NOW. |
| Retrying failed scans | If a scan fails, log it as a failure. Do not rescan the same paper 3 times and take the best — that's cheating the benchmark. |
| Testing on WiFi-connected phone with notifications popping up | Notifications interrupt camera. Airplane mode during scanning. |

---

## 7. If You Only Have 1 Teacher And 1 Phone

**That's fine.** 10 papers from 1 device is more honest than 60 papers from 3 devices you don't actually have.

Here's how to still get useful evidence:

### Use the same 10 papers twice (different lighting)
- Morning: scan all 10 near a window (daylight)
- Evening: scan all 10 under a desk lamp (artificial)
- Compare: same papers, same phone, different light
- This gives you a lighting sensitivity baseline without needing a second device

### Use the same 10 papers for half-sheet too
- If you printed full A4, cut 5 of them in half (or print 5 half-sheets)
- Scan the half-sheets on the same phone
- Compare: same answers, same teacher, different format

### What 1 teacher × 1 phone × 10 papers actually tells you
- Whether the app works AT ALL on real hardware with real handwriting
- Whether the fill threshold is in the right ballpark
- Whether perspective correction handles your phone's camera
- What the worst-case accuracy looks like (light pencil)

### What it does NOT tell you
- Whether it works on other phone models (camera quality varies)
- Whether it works with left-handed writers (different smudge pattern)
- Whether Ethiopian student handwriting is harder than yours

**That's OK.** The point of round 1 is: does this work on ONE real phone with ONE real teacher? If yes, round 2 adds variation. If no, you saved yourself from building features on a broken foundation.

---

## Scoring Cheat Sheet

After all 10 papers, fill this in:

```
Date:           ___________
Device:         ___________   (model + Android version)
Total papers:   10
Total questions per paper: ____

Clean papers (5):
  Correct: ___ / ___
  Accuracy: ____%

Light-pencil papers (5):
  Correct: ___ / ___
  Accuracy: ____%

Overall:
  Correct: ___ / ___
  Accuracy: ____%

Crashes:        ___  (list paper #s)
Systematic errors: ___  (e.g., "D always read as C")
Worst paper:    ___  (paper #, accuracy %, why)

DECISION:  ✅ Pilot   🟡 Tune   🔴 Stop
Reason: ___________________________________________
```

---

_Last updated: 2026-04-17_
_Derived from: REAL_WORLD_TESTING.md (full protocol)_
