# EthioGrade — Session Launcher v6

> Paste the block below into any AI agent. It reads the project state, finds the next task, and builds it.
> No hardcoded tasks. No re-asking about built features. Just paste and go.

---

```
You are the EthioGrade dev team. Load the project, find what needs work, do it.

cd /root/.openclaw/workspace/ethiograde
git pull --rebase origin main 2>&1

NOW READ THESE FILES IN ORDER:
1. PROJECT_STATE.md — health, sprint board, feature matrix, risk register
2. CHANGELOG.md (first 60 lines) — what changed recently
3. OPERATIONS.md — architecture principles, quality gates, commit format

THEN MAP THE REALITY:
ls lib/ && ls test/ — verify the code matches the plan, not just the docs

DECIDE WHAT TO WORK ON:
- Look at the Sprint Board in PROJECT_STATE.md
- Find tasks marked 📋 Pending or 🟡 In Progress
- Skip anything marked ✅ Done — it's done, don't touch it
- If a task is blocked by a 🔴 risk, note it and pick the next available task
- Pick the task that reduces the most risk or unblocks the most downstream work
- If Sprint is complete, look at Release Train for next version scope
  and create a new sprint with tasks from the Feature Matrix

BEFORE YOU CODE, TELL ME:
- "Current health: [from PROJECT_STATE.md]"
- "Last changes: [from CHANGELOG.md Unreleased section]"
- "I'm picking: [task name] — because [why]"
- "Principles at risk: [which of the 7: offline-first/low-spec/bilingual/local-data/crash-proof/accessible/fast]"
- "Plan: [what you'll do in 2-3 sentences]"

THEN BUILD IT:
- [Area] Imperative commit messages, one logical change per commit
- No scope creep — log discoveries in PROJECT_STATE.md, don't fix them now
- Run lint/analyze before committing (if dart/flutter available)
- Follow OPERATIONS.md quality gates before pushing
- Write tests for new functionality (test/services/ or test/widgets/)

WHEN DONE, UPDATE:
- PROJECT_STATE.md: feature status, sprint board, health signals, discovered items
- CHANGELOG.md: what changed and why under [Unreleased]
- git add -A && git commit -m "[Area] description" && git push origin main

VISION CHECK (answer honestly):
- Does this help an Ethiopian teacher grade faster, offline, on a cheap phone?

REPORT FORMAT:
✅ Done: [completed]
🟡 WIP: [in progress]
📋 Next: [recommended next task]
⚠️ Found: [new risks or discoveries]
```

---

## How This Works

```
You paste → read 3 .mds → ls to verify reality → find pending task → report plan → build → update docs → push
              ↓                ↓                      ↓
         Context from      Drift detection      No surprises
          last session      (docs ≠ code?)
```

## Quick Reference Card

Keep this open during sessions. Saves re-reading OPERATIONS.md every time.

### 7 Architecture Principles (non-negotiable)

| # | Principle | One-liner | How to verify |
|---|-----------|-----------|---------------|
| 1 | Offline-first | Zero network calls in core pipeline | grep for http/dio in lib/ — should find nothing outside Telebirr stub |
| 2 | Low-spec | 2GB RAM, Android 8, <150MB heap | Profile on low-end device; no synchronous heavy ops on UI thread |
| 3 | Bilingual | Every string Amharic AND English | Search for hardcoded English in widgets — all should have `isAm ? am : en` |
| 4 | Local-data | Hive only, no cloud sync | No Firebase/REST in individual mode |
| 5 | Crash-proof | Auto-save, never lose data | Kill app during scan → reopen → data survives |
| 6 | Accessible | Beginner-friendly, WCAG AA | Touch targets ≥48dp, screen reader labels, no tiny text |
| 7 | Fast | Scan → grade in <5 seconds | Time the pipeline on 2GB device |

### Commit Area Tags

`[OCR]` `[Camera]` `[PDF]` `[Voice]` `[Analytics]` `[UI]` `[i18n]` `[Data]` `[Build]` `[Docs]` `[Test]` `[Security]` `[Perf]` `[UX]`

Format: `[Area] Imperative short summary (≤72 chars)`

### File Map

```
lib/
├── config/       → routes, theme, constants
├── models/       → student, teacher, assessment, scan_result
├── services/     → OCR, scoring, persistence, voice, analytics, validation
├── screens/
│   ├── onboarding/
│   ├── home/           → main_dashboard
│   ├── scanning/       → camera_screen, batch_scan_screen
│   ├── review/         → review_screen
│   ├── reports/        → reports_screen
│   └── subscription/   → subscription_screen (school mode, teacher mgmt)
└── widgets/      → reusable (stat_card, language_toggle, paper_guide_overlay, etc.)

test/
├── services/     → unit tests for each service
├── widgets/      → widget tests
└── integration/  → E2E flow tests

Key docs:
├── PROJECT_STATE.md     → sprint board, feature matrix, risk register (SINGLE SOURCE OF TRUTH)
├── CHANGELOG.md         → what changed and why
├── OPERATIONS.md        → architecture principles, quality gates, release process
├── SESSION_PROTOCOL.md  → this file — how to start a session
└── TESTING_PROTOCOL.md  → testing strategy
```

### What To Do When Stuck

| Situation | Action |
|-----------|--------|
| All sprint tasks done | Check Release Train → create next sprint from Feature Matrix |
| Blocked by 🔴 risk | Document in Risk Register, pick next unblocked task |
| Discover new bug | Add to PROJECT_STATE.md Risk Register or Technical Debt, don't fix now |
| Tests can't run (no Flutter SDK) | Write tests anyway, CI will catch issues on push |
| Unsure which task to pick | Pick the one that unblocks the most downstream work |

---

*v6 | 2026-04-01 | Merges v4 structure (phases, quick reference, ls check) with v5 flow (cleaner, explicit push)*
