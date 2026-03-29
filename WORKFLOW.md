# EthioGrade — Team Workflow Protocol

> **Purpose:** This document is the single source of truth for how we work.
> Read it at the start of every session. Follow it until the end.
> It simulates a 20-person dedicated team — every role, every check, every time.

---

## 🚀 Session Start Protocol (Mandatory — Every Time)

Before any code is written or any task begins, execute this sequence:

```
Step 1 → Read PROGRESS.md        (Where are we? What's done, what's left?)
Step 2 → Read CHANGELOG.md        (What changed recently? What broke? What improved?)
Step 3 → Read WORKFLOW.md         (This file — re-anchor on process)
Step 4 → Read the task brief      (What are we building today?)
Step 5 → Confirm alignment        (Does today's task match the Next Up list in PROGRESS.md?)
```

**If the task is NOT in PROGRESS.md → pause and add it before starting.**
**If PROGRESS.md is outdated → update it first, then proceed.**

---

## 👥 The 20 Roles (Simulated)

Every decision goes through these lenses. You don't need 20 people — you need 20 perspectives.

| # | Role | Responsibility | When They Speak |
|---|------|---------------|-----------------|
| 1 | **Product Manager** | Does this serve Ethiopian teachers? Is it in the roadmap? | Every task start |
| 2 | **Tech Lead / Architect** | Does this fit the architecture? Will it scale? | Every code change |
| 3 | **Flutter Developer** | Is this idiomatic Dart/Flutter? Provider + Hive patterns? | Every code change |
| 4 | **ML/AI Engineer** | Is the OCR/ML pipeline correct? Model integration sound? | OCR, scanning, AI tasks |
| 5 | **Backend Engineer** | Data persistence, offline-first, conflict resolution? | Data/storage tasks |
| 6 | **QA Engineer** | Can we test this? What breaks? Edge cases? | Every feature completion |
| 7 | **Security Engineer** | Any data leaks? Permission issues? Input validation? | Every external integration |
| 8 | **UX Designer** | Is this intuitive for a teacher in rural Ethiopia? | Every screen change |
| 9 | **UI Designer** | Does this match Ethiopian theme? Visual consistency? | Every visual change |
| 10 | **Accessibility** | Can teachers with low literacy use this? Color-blind safe? | Every UI component |
| 11 | **Performance** | Will this run on 2GB RAM? Is it jank-free at 60fps? | Image processing, lists, charts |
| 12 | **Localization (i18n)** | Is every string in both Amharic and English? | Every user-facing string |
| 13 | **DevOps** | Can we build, sign, and ship this? CI/CD ready? | Build/deploy tasks |
| 14 | **Data Scientist** | Are analytics meaningful? Charts accurate? | Analytics features |
| 15 | **Documentation** | Is README/PROGRESS/CHANGELOG up to date? | Every commit |
| 16 | **Mobile Platform** | Android API 26+ compatible? Permissions handled? | Android-specific code |
| 17 | **Integration** | Does this play well with other services? (PDF, Excel, Voice) | Cross-service work |
| 18 | **Project Manager** | Are we on schedule? Any blockers? What's next? | Every session end |
| 19 | **Teacher Advocate** | Would an Ethiopian teacher actually use this? Is it practical? | Every UX decision |
| 20 | **Code Reviewer** | Clean code? No hacks? Follows conventions? | Every PR/commit |

---

## 🔄 Development Cycle

### Before Starting a Task

1. **Read PROGRESS.md** — Find the task in the appropriate section
2. **Move it to 🔄 In Progress** — Update the file
3. **Understand scope** — Read the relevant code files
4. **Plan approach** — State what you'll do before doing it
5. **Check dependencies** — Does this task block or depend on another?

### While Working

1. **Small commits** — One logical change per commit
2. **Test as you go** — Don't write 500 lines then test
3. **Update code comments** — If the "why" isn't obvious, comment it
4. **No scope creep** — If you find something else broken, note it in PROGRESS.md, don't fix it now

### After Completing a Task

1. **Update PROGRESS.md:**
   - Move task from ❌ Not Done → ✅ Done
   - Update Overall Completion percentage
   - Update Next Up if priorities shifted
   - Add any new issues found to Technical Debt
2. **Update CHANGELOG.md:**
   - Add date + what was added/fixed/improved
   - Note any breaking changes
3. **Commit with clear message** — Format: `[Area] Short description`
4. **Push to GitHub**
5. **Session summary** — What was done, what's next

---

## ✅ Quality Gates (No Skipping)

Every piece of code must pass these checks before it's considered "done":

### Gate 1: Functionality
- [ ] It works for the happy path
- [ ] It handles empty/null/missing data gracefully
- [ ] It works in both Amharic and English modes
- [ ] It doesn't crash on back-button, minimize, or orientation change

### Gate 2: Security
- [ ] No sensitive data in logs or error messages
- [ ] File paths validated (no path traversal)
- [ ] User input sanitized
- [ ] Permissions requested only when needed, with explanation

### Gate 3: Performance
- [ ] No synchronous heavy computation on UI thread
- [ ] Image processing runs in isolates if >100ms
- [ ] Lists use builders (not loading all items at once)
- [ ] No memory leaks (controllers disposed, listeners removed)

### Gate 4: UX/UI
- [ ] Follows Ethiopian theme (green/yellow/red palette)
- [ ] Loading states shown for async operations
- [ ] Error states have actionable messages
- [ ] Touch targets ≥ 48dp
- [ ] Text readable at default size (no hardcoded tiny fonts)

### Gate 5: Code Quality
- [ ] No `// TODO` left without a tracking entry in PROGRESS.md
- [ ] No hardcoded magic numbers (use constants)
- [ ] Functions < 50 lines (break up if larger)
- [ ] Named parameters for functions with >2 arguments

### Gate 6: Documentation
- [ ] PROGRESS.md updated
- [ ] CHANGELOG.md updated
- [ ] New public methods have doc comments

---

## 📋 Commit Message Format

```
[Area] Short description

- Detail 1
- Detail 2
- Closes #issue (if applicable)
```

**Areas:** `[OCR]` `[Camera]` `[PDF]` `[Voice]` `[Analytics]` `[UI]` `[i18n]` `[Data]` `[Build]` `[Docs]` `[Test]` `[Security]` `[Perf]`

**Examples:**
```
[OCR] Wire Google ML Kit text recognition to replace mock extractor

- Replaced _extractTextRegions() with real ML Kit pipeline
- Added image rotation handling for camera photos
- Updated answer parser confidence thresholds
- Closes #1
```

```
[UI] Add loading spinner to batch scan processing

- Shows progress during multi-page OCR
- Disables capture button while processing
```

---

## 🛡️ Security Rules (Non-Negotiable)

1. **Never commit** API keys, tokens, or secrets to the repo
2. **Never log** student PII (names, scores) in debug output
3. **Always validate** file paths from external sources (Excel import, image picker)
4. **Offline-first** — no data leaves the device unless explicitly in School Cloud mode
5. **Encrypt at rest** if storing sensitive assessment data (future: use `flutter_secure_storage`)

---

## 📊 Performance Budgets

| Metric | Target | Device |
|--------|--------|--------|
| App cold start | < 3s | 2GB RAM, Android 8 |
| Single paper scan + OCR | < 5s | Same |
| Batch scan (10 papers) | < 30s | Same |
| PDF report generation | < 3s | Same |
| Screen transition | < 300ms | Same |
| Memory usage | < 150MB | Peak |
| APK size | < 50MB | Release |

---

## 🎯 Vision Checkpoint

Before shipping any feature, ask these five questions:

1. **Does this help an Ethiopian teacher grade faster?** — If no, why are we building it?
2. **Does it work offline?** — Internet is a luxury, not a guarantee.
3. **Is it usable by someone with basic phone skills?** — Not everyone is tech-savvy.
4. **Does it respect the teacher's data?** — Their students' scores are private.
5. **Would we be proud to show this to a real teacher?** — If not, polish it.

---

## 📁 File Ownership (Who Touches What)

| File(s) | Owner Role | Notes |
|---------|-----------|-------|
| `lib/services/ocr_service.dart` | ML Engineer + Flutter Dev | Core differentiator |
| `lib/screens/*` | Flutter Dev + UX Designer | Every screen change needs UX sign-off |
| `lib/models/*` | Tech Lead | Schema changes affect everything |
| `lib/config/theme.dart` | UI Designer | Don't touch without design review |
| `lib/services/*_provider.dart` | Flutter Dev + Tech Lead | State management patterns |
| `assets/*` | UI Designer + ML Engineer | Fonts, images, models |
| `android/*` | Mobile Platform + DevOps | Build config |
| `pubspec.yaml` | Tech Lead | Dependency changes need justification |
| `PROGRESS.md` | Project Manager | Updated with every session |
| `CHANGELOG.md` | Documentation | Updated with every commit |
| `README.md` | Documentation + PM | Updated on milestones |

---

## 🔁 Session End Protocol

Before closing:

1. **Commit all work** — No uncommitted changes left behind
2. **Push to GitHub** — `git push origin main`
3. **Update PROGRESS.md** — Move tasks, update percentages
4. **Update CHANGELOG.md** — Log what was done today
5. **Note blockers** — Anything preventing progress tomorrow?
6. **State what's next** — So the next session starts fast

---

*This document evolves with the project. If a process isn't working, update this file.*
*Last Updated: 2026-03-29*
