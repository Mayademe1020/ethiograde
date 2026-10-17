# PROJECT_CONTEXT.md

> Project memory for EthioGrade. Read this context before important work.

---

## 1. Product Vision

EthioGrade is a calm, offline-first teacher workspace for Ethiopian classrooms. It allows teachers to quickly scan, grade, and review student assessments using on-device ML/OMR with no internet required. The design focuses on practicality, speed, and clear next-action directions on low-end mobile devices.

---

## 2. Primary Users

- **Users:** Ethiopian teachers (Grades 1-12 & Universities).
- **Devices:** Low-end Android phones (2GB RAM, small screens, older Android versions).
- **Language:** English-only (Amharic support has been removed).
- **Connectivity:** Offline-first. Zero network requests or internet dependency.
- **Time pressure:** High. Grading must be fast, smooth, and easily recoverable.
- **Environment:** Bright classrooms requiring high contrast and readability.

---

## 3. Core Workflows

1. **Class/Student Roster Management:** Add students, import CSVs, and transfer students between classes.
2. **Assessment & Answer Key Setup:** Create MCQ, T/F, or matching assessments, setup grading rubrics (MOE National, etc.), and generate A4 or half-sheet templates.
3. **Paper Scanning:** OCR + coordinate-map OMR parallel hybrid grading.
4. **Grading Review & Fixes:** Side-by-side verification, confidence indicators, and step-through recovery for wrong/missing answers.
5. **Data Management:** Encrypted Hive database auto-saves, audit trails, and encrypted JSON backup/restore.

---

## 4. Hard Constraints

- **Do not add:** New external native dependencies without approval.
- **Do not add:** Any internet-facing or cloud sync features (the app must remain 100% local).
- **Do not restore:** Amharic localization keys (the app is strictly English-only).
- **Must preserve:** Draft auto-saving, audit trails (revert-to-this), and automatic local backup integrity.

---

## 5. Quality Bar

- Works flawlessly on 320px mobile viewport widths (no visual layout overflows).
- Implements theme-adaptive UI (Light & Dark) matching the refreshed color scheme.
- High contrast readable text matching `DESIGN.md` guidelines.
- Always handles loading/empty/error states using `SkeletonBox` and `AppEmptyState`.
- Retains TalkBack accessibility support using `Semantics` wrappers.

---

## 6. Risk Zones

- **Data Safety:** Corrupt Hive box recovery and file-deletion safety must not be compromised.
- **Calculations:** Weighted scoring and grade scale recalculations must match exactly.
- **Layout:** UI on small/inexpensive screens must not truncate action buttons or key details.

---

## 7. Decision Log

| Date | Area | Decision | Why | Consequence | Revisit when |
|---|---|---|---|---|---|
| 2026-04-14 | Localization | English-only | Simplified maintenance & codebase footprint | Removed all Amharic keys and LocaleProvider | Never |
| 2026-04-15 | Design | Plus Jakarta Sans | Modern, premium typography | Google Fonts package configured and cached | |
| 2026-04-15 | Design | Bottom Navigation | Restyled using Material 3 NavigationBar | Clean navigation interface | |
| 2026-06-10 | Architecture | Project Context | Created PROJECT_CONTEXT.md | Align with AI Director OS | |

---

## 8. Technical Stack

- **Frontend:** Flutter & Dart (>=3.8.0)
- **Database:** Hive (encrypted via AES-256) + SharedPreferences
- **OCR:** ML Kit TextRecognizer (on-device)
- **OMR:** Pure-Dart pixel sampling
- **State:** Provider (ChangeNotifier)
- **Testing:** flutter_test, integration_test

---

## 9. AI Working Rules

Always:
- Read this context before important work.
- State scope before changing files.
- Prefer the smallest useful change.
- Handle loading, empty, and error states.

Never:
- Overbuild simple requests.
- Touch unrelated files or paths.
- Add dependencies silently.
