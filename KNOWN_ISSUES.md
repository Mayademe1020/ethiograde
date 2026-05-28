# KNOWN_ISSUES.md — Single Source of Truth

**Last updated:** 2026-04-17
**Rule:** Every session reads this FIRST. Every bug found goes here. Every fix removes it from here. No re-discovery.

---

## 🟡 Medium (UX friction / discoverability)

_(No open medium bugs.)_

---

## 🟢 Polish (pre-pilot nice-to-haves)

### BUG-008: No sample data on first launch
- **Fixed:** 2026-04-15
- **Fix:** DemoDataService seeds a demo class (Grade 5A Math) with 5 students (Ethiopian names, bilingual) and 1 assessment (10 MCQ/TF questions) on first launch. Idempotent — skips if already seeded. Called from OnboardingScreen._completeSetup().

### BUG-010: Dashboard lacks recent activity summary
- **Fixed:** 2026-04-15
- **Fix:** Added _RecentActivityCard to dashboard. Shows last completed assessment + in-progress assessments ready to scan. Displays assessment title, question count, and answer key status. Auto-hides when no activity exists.
- **Status:** ✅ Fixed

### BUG-011: Weighted setup button placement is confusing
- **Fixed:** 2026-04-15
- **Fix:** Promoted "Weighted Setup" from a buried OutlinedButton inside the Rubric step to its own dedicated Step (index 2) in the create assessment flow. Step title shows configured weights summary. Includes edit/skip options + bilingual labels. Questions moved to Step 4.
- **Status:** ✅ Fixed

---

## ✅ Fixed (keep for reference)

### BUG-015: Dashboard truncated mid-expression
- **Fixed:** 2026-04-17
- **Fix:** `main_dashboard.dart` was missing ~124 lines after `_showPrivacyPolicy` declaration — `_confirmClearData`, `_clearAllData`, `_SettingsSection`, `_SettingsTile` all deleted during Amharic removal scripts. Restored English-only versions. Verified all 74 lib files brace-balanced.

### BUG-014: Roster preview SnackBar broken
- **Fixed:** 2026-04-17
- **Fix:** `_saveAll()` in `roster_preview_screen.dart` had truncated ternary string from Amharic removal: `"$saved saved${failed > 0 ? "`. Completed with else branch `' ($failed failed)'` and closing paren.

### BUG-013: Onboarding language page broken
- **Fixed:** 2026-04-17
- **Fix:** Amharic removal left "language" `_OnboardingPage` with `descEn` assigned a `_OnboardingPage` constructor instead of String. Duplicate offline pages. Extra closing brace. Replaced with 4 accurate feature pages (Scan & Grade, Offline, Quick Enter, Track Grades). Verified all onboarding pages have titleEn + descEn.

### BUG-007: No "undo last scan" in batch mode
- **Fixed:** 2026-04-14
- **Fix:** "Undo Last" button in batch scan bottom actions. Removes last scan result, updates progress count, recomputes duplicates, updates crash-recovery draft. Bilingual snackbar confirmation.

### BUG-009: No printable answer sheet template
- **Fixed:** 2026-04-15
- **Fix:** Full 4-phase OMR pipeline: (1) AnswerSheetGenerator creates A4 PDF + CoordinateMap JSON with mm positions, corner anchors, MCQ/T/F rows. (2) AnswerSheetSetupScreen with type breakdown, header, student mode, answer key status. (3) Assessment model answer key completeness getters + scan button gates. (4) CoordinateMapOmrService scans filled sheets using anchor-based perspective correction + coordinate map bubble sampling.

### BUG-006: Audit trail is view-only (no revert)
- **Fixed:** 2026-04-14
- **Fix:** "Revert to this" button on each historical audit entry (except latest). Restores previous score/grade/percentage and records a new audit entry with revert reason. Bilingual.

### BUG-004: Long-press transfer has no visual hint
- **Fixed:** 2026-04-14
- **Fix:** Replaced remove-only IconButton with PopupMenuButton exposing "Transfer" and "Remove" options with icons and bilingual labels.

### BUG-003: Student reassignment is undiscoverable
- **Fixed:** 2026-04-14
- **Fix:** Visible "Reassign" ActionChip with swap icon + bilingual label on each student result card. Large tap target, Amharic label "ተማሪ ቀይር".

### BUG-005: VoiceService stubs may crash at runtime
- **Fixed:** 2026-04-14
- **Fix:** Audited — all VoiceService methods are safe no-ops returning void futures or empty values. No exceptions thrown. Voice buttons exist in UI but service handles gracefully. Deferred to v0.2.0.

### BUG-002: Transfer history not persisted to student metadata
- **Fixed:** 2026-04-14
- **Fix:** Transfer dialog now updates ClassProvider rosters via `removeStudentFromClass` + `addStudentToClass` after student transfer. `_undoTransfer` now accepts the current student state instead of using stale `widget.student`.

### BUG-001: Weighted scale not linked to assessment on save
- **Fixed:** 2026-04-14
- **Fix:** (1) `_saveAssessment()` now populates `assessmentIds` on each component with the assessment ID, so `computeForExam()` can find scan results. (2) `HybridGradingService.gradePaper()` now accepts `weightedScale` parameter and applies weighted scoring per-paper via `ScoringService.computeWeightedPercentage()`. (3) Removed redundant `saveForExam` call in `WeightedGradeSetupSheet._save()`. (4) All callers (batch_scan_screen, camera_screen) updated to pass weighted scale.
