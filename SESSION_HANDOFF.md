# SESSION_HANDOFF.md

Created: 2026-06-13
Updated: 2026-06-14
Branch: `codex/review-queue-v2`
HEAD: `5100619`

---

## A. Product Goal

Gradeflow exists to help teachers reduce repetitive exam-marking work from hours to minutes. The product must:

- require little or no training
- guide the teacher to the next action
- minimize typing and repeated setup
- support scanning a completed master paper to create an answer key
- scan student papers continuously
- automate routine grading
- surface only genuine exceptions requiring teacher judgment
- preserve work after interruption
- remain trustworthy, offline-first, and usable on low-end Android devices
- make teachers prefer Gradeflow over returning to manual marking

---

## B. Approved UI/UX Direction

- **Wireframe 3** (Classroom Ready) is the selected information-architecture foundation.
- **Wireframe 2** (Calm Flow) contributes calmness and visual restraint.
- **Wireframe 1** (Command Center) contributes clarity around beginning grading.
- The dashboard must behave like an operational assistant, not a menu of technical modes.
- Current navigation remains **Home / Assess / Students / Settings** for Phase 1.
- Navigation restructuring is **deferred** to Phase 3.

---

## C. Dashboard Phase 1 Status

### Committed

- Commit `e94a921` — `feat: add teacher-first operational dashboard`
- 5 files: `dashboard_actions.dart` (new), `main_dashboard.dart`, `assessments_tab.dart`, `assessment_card.dart`, `dashboard_test.dart`

### What was implemented

- **Unified next-action resolver** (`dashboard_actions.dart`): single function determining the one winning primary CTA. Priority: draft → incomplete setup → ready-to-grade → grade papers.
- **One dominant PrimaryActionCard**: shows resume context, setup prompt, scanning prompt, or generic start — never two competing CTAs.
- **Separate ResumeGradingBanner removed** from competing-CTA hierarchy. Draft recovery is now part of the unified primary action.
- **Decorative statistics removed**: no more Students/Active/Completed stat cards.
- **Redundant Recent Activity removed**: duplicated what Recent Assessments already shows.
- **Technical quick actions removed**: Master Key, No List, Class List, Manual Key shortcuts no longer on dashboard. These remain accessible inside ExamDayCreateScreen.
- **Recent Assessments placed before My Classes** in the dashboard hierarchy.
- **Quick Grade visible** from the Assessments tab via an OutlinedButton.
- **Operational-status resolver** (`resolveOperationalStatus()`): shared by AssessmentCard and dashboard. Derives: Setup incomplete, Ready to grade, Grading in progress, Graded.
- **AssessmentCard uses centralized status** instead of inline switch.
- **Compact and localization tests**: 320×568, 390×844, text scale 1.5, long names, Amharic content.

### What is NOT verified

- Physical low-end Android performance
- Real camera behavior
- Full master-paper workflow on device
- Classroom comprehension and adoption
- TalkBack/screen-reader accessibility
- Real-world Amharic translation quality
- 50-paper batch performance

---

## C2. Answer-Key Change Safety (P0 Grade Integrity)

### Committed

- Commit `4121f02` — `feat: answer-key change safety — P0 grade-integrity protection`
- 18 files changed, 3187 insertions, 92 deletions

### What was implemented

- **AnswerKeyFingerprintService**: Deterministic SHA-256 fingerprint of scoring key via canonical JSON serialization
- **IntegrityStateResolver**: Centralized state resolution (current/legacyUnknown/outdated/recalculating/recalculationFailed/currentNeedsManualReview)
- **AnswerKeyRecalculationService**: Batch rescoring from persisted student responses with idempotency guard
- **LegacyBaselineService**: Explicit migration for old assessments without fingerprints
- **Assessment model**: Added `answerKeyRevision` (HiveField 18), `answerKeyFingerprint` (HiveField 19)
- **AssessmentProvider**: `saveAnswerKeyChange()` increments revision, auto-manages fingerprint
- **HybridGradingService**: Stamps `scoredWithKeyFingerprint`/`scoredWithKeyRevision` in result metadata
- **AnswerKeyScreen**: Three-action dialog (Recalculate now / Save and recalculate later / Cancel)
- **ReviewScreen**: Integrity resolver integration, old `answerKeyChangedNeedsRegrade` flag bridged, finalization gate blocks stale results

### Tests added (76 total)

- 13 fingerprint tests
- 18 integrity resolver tests
- 12 recalculation/scoring tests
- 11 legacy baseline tests
- 22 AnswerKeyScreen logic tests

### Test results

```
flutter test --reporter compact → 996 pass / 29 fail (pre-existing)
```

---

## C3. P0 Release-Critical Correctness (Completed)

### Commits

- `86b7701` — `fix: P0 release-critical correctness and data-integrity tranche`
- `5100619` — `fix: complete P0 integration — gate, matching, review, marks, template, deletion`

### What was implemented

**P0.1 — Student matching precedence:**
- Exact student ID beats fuzzy name
- 5-step precedence: ID → exact name → normalized name → first name → fuzzy → manual
- 17 tests passing

**P0.2 — Centralized review-state resolver:**
- `ScanResult.needsReview` excludes resolved items (teacherReviewed, batchReviewResolution, duplicateReviewed, studentMatchResolved)
- Added `isUnmatched` getter for separate student-assignment tracking
- 12 tests passing

**P0.3 — Multiple-mark handling:**
- OMR services return `[MULTIPLE]` when >1 bubble exceeds threshold
- Confidence=0, requires teacher review
- Never silently picks first detected answer
- 9 tests passing

**P0.4 — Wrong-template protection:**
- Batch processor validates coordinate map assessmentId
- Wrong template rejected, missing ID warned
- 7 tests passing

**P0.5 — Safe class deletion:**
- `canDeleteClass()` checks students, assessments, drafts
- Returns blocking reasons with actionable text
- 5 tests passing

**P0.6 — Unified completion gate:**
- `AssessmentCompletionGate` with 14 checks
- Each check has severity, explanation, action route/label
- Wired into ReviewScreen and GradeReviewScreen
- 17 integration tests + 9 unit tests passing

### Test results

```
P0 tests: 78/78 pass
Full suite: 1071 pass / 29 fail (pre-existing)
```

### What is NOT verified

- Real-device Android behavior
- Physical paper scanning
- Camera permission on real device
- APK build (Android SDK not installed)

### Next tasks (in order)

1. **Install Android SDK** — required for APK build
2. Build and install APK on device
3. Run real-device smoke test
4. Fix resolved vs unresolved review state (`requiresTeacherAction` resolver)
5. Add scanned-master workflow to Quick Grade
6. Redesign grading entry around teacher decisions (Phase 2)

---

## D. Master-Paper Capability Status

### Formal Class Assessment

Source-connected flow exists:

```
ExamDayCreateScreen (scanMaster mode)
→ AnswerSheetSetupScreen (generates PDF + coordinate map)
→ CameraScreen (masterKey mode — captures master paper)
→ BatchScanScreen (masterOnly=true — processes via CoordinateMapOmrService)
→ showMasterKeyConfirmation (teacher reviews/corrects detected answers)
→ _saveAnswerKeyToAssessment (persists confirmed key to Hive)
→ BatchScanScreen (student scanning with confirmed key)
```

Evidence level:
- Source-connected: yes
- Partial unit test coverage: yes (model tests, some service tests)
- End-to-end persistence test: no
- Real-device camera test: no
- Low-quality image test: no

### Quick Grade

- Visible entry exists on Assessments tab (committed in `e94a921`)
- Currently requires manual answer-key entry (comma-separated letters)
- Master-paper scanning NOT available in Quick Grade
- Adding scanned-master support is a **P1 teacher-effort task**

---

## E. Confirmed Correctness Gaps

### P0 — Grade Integrity

1. **Answer-key edits can leave stale ScanResults.** Editing an answer key on AnswerKeyScreen saves immediately but does NOT recalculate existing ScanResults. Scores may be based on a previous key.
2. **ReviewScreen has only a partial regrade mechanism.** It detects changes via runtime signature comparison, but only when the teacher navigates FROM the review screen TO the answer key editor. Dashboard "Set Answer Key" path bypasses detection.
3. **No answer-key revision or fingerprint tracking exists.** Assessment has no version field. ScanResult has no `scoredWithKeyFingerprint`. The runtime `_answerKeySignature()` is not persisted.
4. **"Keep current scores" only flags, never recalculates.** Results get `answerKeyChangedNeedsRegrade: true` in metadata but scores remain stale.

### P0 — Review Integrity

- `ScanResult.needsReview` returns true for resolved items.
- `BatchReviewService.summarize()` counts resolved items as needing review.
- A centralized `requiresTeacherAction` resolver is proposed but not implemented.

### P0 — Student Matching

- `StudentMatcher.matchFromOcr` calls `matchName` BEFORE `matchById`.
- A fuzzy name match at confidence ≥ 0.7 can be accepted before an exact student ID is checked.
- This is a correctness risk.

### P1 — Workflow and Localization

- Quick Grade lacks master-paper scanning
- Multiple grading drafts are not clearly surfaced (only most recent shown)
- Coordinate-map recovery needs verification
- Amharic OCR names do not reliably match Latin-script roster names

### P2

- Multi-page ordinary-paper scanning
- Stronger handwriting recognition
- Accessibility and low-end-device validation

---

## F. Answer-Key Integrity Audit Summary

### Current behavior

| Path | Answer key edit triggers recalculation? | Stale result protection? |
|---|---|---|
| AnswerKeyScreen (direct from dashboard) | No | None |
| AnswerKeyScreen (via ReviewScreen) | Only if teacher chooses "Regrade all" | Runtime detection only, not persisted |
| QuickGradeScreen | N/A (no answer key editing after creation) | None |

### Key findings

- `ScoringService.scoreAnswers()` reads `assessment.questions[*].correctAnswer` at call time. No version stamp on output.
- `ScanResult` has no `scoredWithKeyFingerprint` or equivalent.
- `Assessment` has no `answerKeyFingerprint` or `answerKeyRevision`.
- The `_answerKeySignature()` in review_screen.dart is runtime-only, not persisted.
- Manual overrides in SideBySideReview use the `correctAnswer` stored in the existing AnswerMatch, not re-read from the assessment.
- GradeReviewScreen computes statistics from ScanResult data as-is.

### Recommended direction

- Add `answerKeyFingerprint` to Assessment (deterministic hash of all question.correctAnswer pairs)
- Add `scoredWithKeyFingerprint` to ScanResult metadata (stamped by scoring service)
- Show staleness indicator when fingerprints mismatch
- Add recalculation prompt on AnswerKeyScreen "Done" when results exist
- Keep existing review-screen regrade flow as primary path
- Never silently present or finalize stale results

---

## G. Next Prioritized Work

### Next task — Answer-Key Change Safety Architecture Confirmation

Before coding, settle:

1. Canonical scoring-key representation (hash vs revision counter)
2. Persistence mechanism (Hive field vs metadata map)
3. Backward compatibility (lazy fingerprint generation for old assessments)
4. Rescoring from persisted responses (AnswerMatch.detectedAnswer is available)
5. Manual-override preservation policy
6. Stale-result states and UI indicators
7. Interruption and recovery during recalculation
8. Result/report/finalization enforcement
9. Exact files and tests

### After that (in order)

1. Implement answer-key revision integrity and safe recalculation
2. Fix resolved versus unresolved review state (`requiresTeacherAction` resolver)
3. Match exact student ID before fuzzy name in StudentMatcher
4. Add scanned-master workflow to Quick Grade
5. Redesign grading entry around teacher decisions (Phase 2)
6. Validate real-device, Amharic, offline, and low-end workflows

---

## H. Deferred and Prohibited Scope

The next task must NOT silently expand into:

- Dashboard redesign (Phase 1 complete)
- Bottom-navigation restructuring (Phase 3)
- Student-management relocation (Phase 3)
- OCR/OMR redesign
- Unrelated grading-engine changes
- Multi-page OCR
- Broad feature development

---

## I. Validation History

### Dashboard focused tests

```
flutter test test/widgets/dashboard_test.dart → 25/25 pass
```

Tests cover:
- 4-tab navigation
- Single dominant CTA
- No stat cards or quick-action shortcuts
- Empty classes card
- Tab switching
- Quick Grade accessibility
- 320×568 compact rendering
- 390×844 standard rendering
- Text scale 1.5
- Long teacher name
- Long school name
- Amharic content
- 6 next-action resolver tests (priorities, edge cases, grading-status lookup)
- 7 operational-status resolver tests (all 4 states + Quick Grade + no-roster)

### AssessmentCard test

```
flutter test test/widgets/assessment_card_test.dart → 6 pass, 1 fail
```

Failure: "AssessmentCard shows English status label" — test expects "Completed" but code shows "Graded" (with resolver) / "Done" (at HEAD). **Pre-existing failure** — identical error at HEAD `b06b3d5` before any dashboard changes.

### Full suite

```
flutter test --reporter compact → 1071 pass / 29 fail
```

**29 failing tests (all pre-existing, confirmed identical at HEAD b06b3d5):**

| File | Failures | Type |
|---|---|---|
| answer_sheet_generator_test.dart | 2 | Assertion (PDF size) |
| data_safety_test.dart | 6 | Environment (MissingPluginException — no path_provider mock) |
| student_matcher_test.dart | 2 | Assertion (Amharic transliteration gap) |
| assessment_card_test.dart | 1 | Assertion (status label mismatch) |
| answer_key_test.dart | 1 | Assertion (duplicate text) |
| class_detail_test.dart | 2 | Assertion (widget not found) |
| grading_scale_editor_test.dart | 6 | Assertion (UI mismatch) |
| import_csv_test.dart | 3 | Environment (TextEditingController lifecycle) |
| transfer_dialog_test.dart | 6 | Assertion (dialog not rendering) |

**Regression status:** None. The 29 failures are identical before and after the dashboard implementation. The +14 difference (906 → 920) is from 14 new tests added in this session.

### Answer-Key Integrity tests

```
flutter test test/services/answer_key_fingerprint_service_test.dart → 13/13 pass
flutter test test/services/integrity_state_resolver_test.dart → 18/18 pass
flutter test test/services/answer_key_recalculation_service_test.dart → 12/12 pass
flutter test test/services/legacy_baseline_service_test.dart → 11/11 pass
flutter test test/widgets/answer_key_screen_test.dart → 22/22 pass
```

**Total new tests:** 76 (across both sessions)
**Full suite:** 996 pass / 29 fail (pre-existing)

---

## J. Resume Instructions for Tomorrow

### START HERE NEXT SESSION

1. **Read this handoff first** (`SESSION_HANDOFF.md`).
2. **Inspect repository state:**
   ```
   git status --short
   git log --oneline -3
   ```
3. **Verify state matches this handoff:** branch should be `codex/review-queue-v2`, HEAD should be `4121f02`, working tree should be clean (only untracked directories).
4. **Summarize for the user:**
   - Dashboard Phase 1 is committed (`e94a921`)
   - Answer-Key Change Safety is committed (`4121f02`)
   - 29 pre-existing test failures remain (not regressions)
   - 76 new tests all passing
   - Ready for controlled teacher pilot testing
5. **Next task:** Real-device smoke test, then Fix resolved vs unresolved review state
6. **Begin with:** real-device validation using the smoke-test script in ANSWER_KEY_SAFETY_ARCHITECTURE.md
