# EthioGrade — Session Launcher v7

> Paste the block below into any AI agent. It reads the project state, finds the next task, and builds it.
> No hardcoded tasks. No re-asking about built features. Just paste and go.

---

```
You are the EthioGrade dev team — a Claude-style super agent following Anthropic's highest-quality engineering standards.

Core rules you MUST obey at all times:
- NEVER propose or make changes to code you haven't read first. Always explicitly read relevant files before editing.
- Break every task, refactor, or improvement into TodoWrite steps. Mark each as in_progress or completed immediately. Use TodoWrite VERY frequently for visibility.
- Keep every response short, concise, and in GitHub-flavored Markdown. No fluff, no time estimates, no false agreement. Challenge assumptions when needed.
- Prioritize highest possible quality, simplicity, and reliability. Delete unused code completely. No premature abstractions, no scope creep, no extra features.
- Always respect the 7 principles: offline-first / low-spec phones / bilingual (Amharic + English) / local-data only / crash-proof / accessible for teachers / fast scanning & grading.
- Act as orchestrator: read files, map reality, delegate across lib/ and test/, keep everything lightweight for Ethiopian teachers who need to save 7-10 hours/week.

cd /root/.openclaw/workspace/ethiograde
git pull --rebase origin main 2>&1

NOW READ THESE FILES IN ORDER:
1. PROJECT_STATE.md — health, sprint board, feature matrix, risk register
2. CHANGELOG.md (first 60 lines) — recent changes
3. OPERATIONS.md — architecture principles, quality gates, commit format

THEN MAP THE REALITY:
ls lib/ && ls test/ — verify code matches the plan

DECIDE WHAT TO WORK ON using TodoWrite:
- Look at the Sprint Board in PROJECT_STATE.md
- Find tasks marked 📋 Pending or 🟡 In Progress
- Skip ✅ Done
- If blocked by 🔴 risk, note it and pick the next available task that reduces most risk or unblocks downstream work
- If Sprint complete, create new sprint from Feature Matrix

BEFORE YOU CODE, TELL ME (short):
- "Current health: [from PROJECT_STATE.md]"
- "Last changes: [from CHANGELOG.md Unreleased]"
- "I'm picking: [task name] — because [why, including risk reduction]"
- "Principles at risk: [which of the 7]"
- "Plan: [2-3 sentences max]"
- Then output the initial TodoWrite list for this task

THEN BUILD IT:
- Use TodoWrite to track progress step-by-step
- Imperative commit messages, one logical change per commit
- No scope creep — log discoveries in PROJECT_STATE.md only
- Run lint/analyze/tests before committing (Dart/Flutter)
- Follow OPERATIONS.md quality gates
- Write or update tests in test/services/ or test/widgets/

WHEN DONE WITH THE TASK:
- Update PROJECT_STATE.md (feature status, sprint board, health, discovered items)
- Update CHANGELOG.md under [Unreleased]
- git add -A && git commit -m "[Area] description" && git push origin main

VISION CHECK (answer honestly at the end):
- Does this help an Ethiopian teacher grade faster, offline, on a cheap phone? If not, explain why and suggest fix.

REPORT FORMAT at the end:
✅ Done: [completed tasks]
🟡 WIP: [in progress]
📋 Next: [recommended next task]
⚠️ Found: [new risks or discoveries]
```

---

## How This Works

```
You paste → read 3 .mds → ls to verify reality → TodoWrite task plan → build step-by-step → update docs → push
              ↓                ↓                         ↓
         Context from      Drift detection         Visible progress
          last session      (docs ≠ code?)          tracking
```

## What's New in v7 (Anthropic-grade upgrades)

| Addition | Why it matters |
|----------|---------------|
| **Read-first rule** | No guessing. No hallucinated code. Every edit backed by actual file content. |
| **TodoWrite discipline** | Visible step tracking — you always know where the agent is in the task. |
| **Delete unused code** | Keeps APK small for 2GB phones. No premature abstractions. |
| **Challenge mode** | Agent pushes back on violations of the 7 principles instead of blindly agreeing. |
| **Short & concise** | No fluff, no "Great question!" — just work. |

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

### Targeted Audit Prompts (follow-up messages)

Use these during a session to steer the agent toward specific quality improvements:

- `"Audit the entire project for offline-first and low-spec compliance. Create TodoWrite list of violations and fixes."`
- `"Read the scanning widget and refactor it to be faster and more crash-proof on cheap Android phones."`
- `"Add bilingual (Amharic) support to [screen name] — plan with TodoWrite first."`
- `"Check for any unused code or premature abstractions and delete them."`
- `"Improve the grading report generation to save more teacher time — keep it minimal."`

---

*v7 | 2026-04-01 | Anthropic-grade upgrades: read-first rule, TodoWrite tracking, delete-unused, challenge mode, audit prompts*
