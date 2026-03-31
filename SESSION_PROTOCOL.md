# EthioGrade — Session Launcher v3

> Paste the block below into MIMO Claw. It figures out what to do from the project state.
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

DECIDE WHAT TO WORK ON:
- Look at the Sprint Board in PROJECT_STATE.md
- Find tasks marked 📋 Pending or 🟡 In Progress
- Skip anything marked ✅ Done — it's done, don't touch it
- If a task is blocked by a 🔴 risk, note it and pick the next available task
- Pick the task that reduces the most risk or unblocks the most downstream work
- If Sprint 1 is complete, look at Release Train for next version scope

BEFORE YOU CODE, TELL ME:
- "Current health: [from PROJECT_STATE.md]"
- "Last changes: [from CHANGELOG.md Unreleased section]"
- "I'm picking: [task name] — because [why]"
- "Principles at risk: [which of the 7 offline-first/low-spec/bilingual/local-data/crash-proof/accessible/fast]"
- "Plan: [what you'll do in 2-3 sentences]"

THEN BUILD IT:
- [Area] Imperative commit messages, one logical change per commit
- No scope creep — log discoveries in PROJECT_STATE.md, don't fix them now
- Follow OPERATIONS.md quality gates before pushing

WHEN DONE, UPDATE:
- PROJECT_STATE.md: feature status, sprint board, health signals, discovered items
- CHANGELOG.md: what changed and why under [Unreleased]

VISION CHECK (answer honestly):
- Does this help an Ethiopian teacher grade faster, offline, on a cheap phone?

REPORT FORMAT:
✅ Done: [completed]
🟡 WIP: [in progress]
📋 Next: [recommended next task]
⚠️ Found: [new risks or discoveries]

Go.
```

---

## How This Works

```
You paste → system reads PROJECT_STATE.md → finds pending task → builds it
                                    ↓
                          No hardcoded tasks
                          No "already built" questions
                          Always picks what's actually next
```

## 7 Architecture Principles (reference)

| # | Principle | One-liner |
|---|-----------|-----------|
| 1 | Offline-first | Zero network calls in core pipeline |
| 2 | Low-spec | 2GB RAM, Android 8, <150MB heap |
| 3 | Bilingual | Every string Amharic AND English |
| 4 | Local-data | Hive only, no cloud sync |
| 5 | Crash-proof | Auto-save, never lose data |
| 6 | Accessible | Beginner-friendly, WCAG AA |
| 7 | Fast | Scan → grade in <5 seconds |

---

*v3 | 2026-03-31 | Task-agnostic, state-driven, paste-and-go*
