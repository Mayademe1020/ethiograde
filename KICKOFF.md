# Kickoff — Session Start Prompt

**Paste this at the start of every EthioGrade session. It does the rest.**

---

## 🔥 The Prompt

```
EthioGrade session start. Protocol:

1. Clone/pull https://github.com/Mayademe1020/ethiograde
2. Load context in this order:
   - PROJECT_STATE.md  → health, sprint, features, risks
   - CHANGELOG.md      → recent changes
   - OPERATIONS.md     → architecture principles, quality gates, process

3. Confirm you understand:
   - Current sprint goal and task board
   - Project health signals (what's broken, what's missing)
   - The 7 architecture principles (offline-first, low-spec, bilingual, local-data, crash-proof, accessible, fast)

4. Today's task: [DESCRIBE YOUR TASK HERE]

5. Before writing any code:
   - State what you'll do
   - State which quality gates apply
   - State what risks this touches

6. While building:
   - Commit format: [Area] Imperative summary
   - One logical change per commit
   - No scope creep — note discoveries in PROJECT_STATE.md, don't fix them now

7. Before pushing:
   - Pass all applicable quality gates from OPERATIONS.md
   - Update PROJECT_STATE.md (feature status, sprint board, health)
   - Update CHANGELOG.md (what changed, why)
   - Vision check: does this help an Ethiopian teacher grade faster, offline, on a cheap phone?

Go.
```

---

## 📌 Example: Starting OCR Work

```
EthioGrade session start. Protocol:

1. Clone/pull https://github.com/Mayademe1020/ethiograde
2. Load context in this order:
   - PROJECT_STATE.md  → health, sprint, features, risks
   - CHANGELOG.md      → recent changes
   - OPERATIONS.md     → architecture principles, quality gates, process

3. Confirm you understand:
   - Current sprint goal and task board
   - Project health signals (what's broken, what's missing)
   - The 7 architecture principles (offline-first, low-spec, bilingual, local-data, crash-proof, accessible, fast)

4. Today's task: Wire Google ML Kit text recognition into ocr_service.dart to replace the mock _extractTextRegions() method. The app needs real OCR that detects text from enhanced paper images, parses question numbers and answers, and feeds them into the existing scoring pipeline.

5. Before writing any code:
   - State what you'll do
   - State which quality gates apply
   - State what risks this touches

6. While building:
   - Commit format: [Area] Imperative summary
   - One logical change per commit
   - No scope creep — note discoveries in PROJECT_STATE.md, don't fix them now

7. Before pushing:
   - Pass all applicable quality gates from OPERATIONS.md
   - Update PROJECT_STATE.md (feature status, sprint board, health)
   - Update CHANGELOG.md (what changed, why)
   - Vision check: does this help an Ethiopian teacher grade faster, offline, on a cheap phone?

Go.
```

---

## 📌 Example: Quick Fix

```
EthioGrade session start. Protocol:

1. Clone/pull https://github.com/Mayademe1020/ethiograde
2. Load PROJECT_STATE.md + CHANGELOG.md + OPERATIONS.md

4. Today's task: Fix the "Add Teacher" dialog in subscription_screen.dart — it currently shows a form but doesn't save anything. Wire it to persist teachers via the student_provider to Hive.

Go.
```

---

## Why This Works

- **Forces context loading** — no flying blind
- **States the task before coding** — no wandering
- **Ties to architecture principles** — every decision has a compass
- **Quality gates are explicit** — no "ship and pray"
- **Vision check last** — does this actually help teachers?
- **Updates are mandatory** — state never goes stale

---

*Copy. Paste. Modify the task. Ship.*
