# EthioGrade Production Readiness Audit

Date: 2026-05-20
Checkout reviewed: `D:\ethiograde_fresh`, branch `main`
Audience: product, design, engineering, QA, and pilot operations

## Executive Verdict

EthioGrade is not a feature-empty app. It has a serious offline grading engine:
local encrypted storage, class/student management, assessment creation, answer
keys, camera scanning, OCR, OMR, batch grading, review, Quick Grade, Quick
Enter, audit trail, draft recovery, backup/restore, custom scales, weighted
grading, answer-sheet PDF generation, and half-sheet OMR support.

The production gap is not raw capability. The production gap is product shape.
The backend is stronger than the teacher-facing experience. Many powerful
features exist, but the UI does not yet consistently guide a teacher from a
real classroom problem to the correct next action in one or two taps.

Production readiness status: not ready for broad teacher release.

Pilot readiness status: possible only after a focused teacher-journey rebuild
and real Android field validation.

## Product Thesis

EthioGrade should not be judged as an "AI grading app." It should be judged as:

> A calm, offline-first Android grading assistant that helps Ethiopian teachers
> turn paper exams into trusted grades, with review and export, on low-end
> phones and under classroom pressure.

Every screen, service, and future feature must answer one of these teacher jobs:

- Set up my class quickly.
- Add or import students without typing too much.
- Create an assessment quickly.
- Add, scan, or confirm a master answer sheet.
- Scan student papers.
- Understand which papers need review.
- See which expected students are missing from the scan batch.
- Detect when the same student/paper was scanned twice.
- Correct mistakes fast.
- Save final grades safely.
- Export or share usable results.
- Recover from crashes, phone death, storage problems, or interrupted grading.

## 360-Degree Readiness Scorecard

| Area | Current Status | Production Risk | Release Decision |
|---|---|---|---|
| Core grading engine | Strong but needs field proof | OMR/OCR accuracy unknown on real teacher phones | Pilot only after benchmark |
| Teacher workflow clarity | Weak | Too many equal actions; next step is not obvious | Must fix before pilot |
| One-hand mobile UX | Inconsistent | Small/icon-only actions, long steppers, horizontal tables | Must fix before pilot |
| Student/class setup | Functional but too much typing | Add Student asks too much; import/scan paths not dominant enough | Must simplify |
| Assessment setup | Functional but too complex | Stepper exposes rubric/weighted setup too early | Must simplify |
| Scan/review trust | Backend exists; UX partial | Confidence/review logic not presented as teacher control everywhere | Must improve |
| Master answer-sheet scan | Partly exists in OMR pipeline | Not visible enough as a primary teacher workflow | Must make first-class |
| Anonymous/no-roster grading | Partly possible through Quick Grade | Not clearly designed as a supported mode | Must define |
| Missing/duplicate student handling | Backend pieces exist | Batch-level teacher review is not strong enough | Must improve |
| Mixed question types | Backend supports MCQ/T/F/short/essay/matching | Teacher setup/review flow is too complex | Must simplify |
| Results/export value | Weak after Reports removal | Teachers need final usable output | Must restore minimal results/export |
| Offline/privacy | Strong | Needs plain-language proof in workflow, not only settings | Improve |
| Data safety | Strong direction | Must verify backup/restore and corruption flows on device | Validate |
| Android packaging | Build artifacts exist locally; release signing not production-ready | Debug signing, SDK 36 dependency, arm64-only choice | Fix before store/wide release |
| Performance | Not production-proven | Camera/scan flow can be heavy on low-end devices | Must profile |
| Accessibility | Not production-proven | TalkBack, font scale, contrast, tap targets unverified | Must audit |
| Documentation | Useful but stale/conflicting | PROJECT_STATE says many things are done while current UI disagrees | Must reconcile |
| Deferred features | Valuable but not integrated | Live grading/product components parked in `.deferred/` | Review later, do not merge blindly |

## What Exists Today

### Teacher-facing screens

- Onboarding: `lib/screens/onboarding/onboarding_screen.dart`
- Home/dashboard: `lib/screens/home/main_dashboard.dart`
- Class detail: `lib/screens/classes/class_detail_screen.dart`
- Create class sheet: `lib/screens/classes/create_class_sheet.dart`
- Add student: `lib/screens/students/add_student_screen.dart`
- Import CSV/roster: `lib/screens/students/import_excel_screen.dart`
- Transfer student: `lib/screens/students/transfer_dialog.dart`
- Create assessment: `lib/screens/assessment/create_assessment_screen.dart`
- Answer key: `lib/screens/assessment/answer_key_screen.dart`
- Answer sheet setup/PDF: `lib/screens/assessment/answer_sheet_setup_screen.dart`
- Weighted grade setup: `lib/screens/assessment/weighted_grade_setup_sheet.dart`
- Camera scan: `lib/screens/scanning/camera_screen.dart`
- Batch scan: `lib/screens/scanning/batch_scan_screen.dart`
- Roster scan: `lib/screens/scanning/roster_scan_screen.dart`
- Quick Grade: `lib/screens/quick_grade/quick_grade_screen.dart`
- Quick Enter: `lib/screens/quick_enter/quick_enter_screen.dart`
- Review: `lib/screens/review/review_screen.dart`
- Grade review: `lib/screens/review/grade_review_screen.dart`
- Audit trail: `lib/screens/review/audit_trail_sheet.dart`
- Grading scale editor: `lib/screens/settings/grading_scale_editor_screen.dart`

### Core backend/services

- Assessment persistence and filters: `lib/services/assessment_provider.dart`
- Student/class providers: `lib/services/student_provider.dart`, `lib/services/class_provider.dart`
- Teacher profile: `lib/services/teacher_provider.dart`
- OCR: `lib/services/ocr_service.dart`
- OMR: `lib/services/omr_service.dart`, `lib/services/coordinate_map_omr_service.dart`
- Hybrid grading: `lib/services/hybrid_grading_service.dart`
- Scoring: `lib/services/scoring_service.dart`
- Answer parsing: `lib/services/answer_parser.dart`
- Answer sheet generation: `lib/services/answer_sheet_generator.dart`
- PDF service: `lib/services/answer_sheet_pdf_service.dart`
- Draft recovery: `lib/services/draft_service.dart`
- Audit trail: `lib/services/audit_service.dart`
- Backup/restore: `lib/services/backup_service.dart`
- Image hashing/duplicates: `lib/services/image_hash_service.dart`
- Roster parsing: `lib/services/roster_parser.dart`
- Student matching: `lib/services/student_matcher.dart`
- Transfer history: `lib/services/student_transfer_service.dart`
- Validation: `lib/services/validation_service.dart`
- Voice/TTS: `lib/services/voice_service.dart`
- Weighted grading: `lib/services/weighted_grade_provider.dart`, `lib/services/weighted_grade_service.dart`

## Backend Capability vs Frontend Exposure

| Capability | Backend Status | Frontend Status | Gap |
|---|---|---|---|
| Offline encrypted data | Exists | Settings mentions it | Trust should appear at key risk moments: first launch, scan, export, backup |
| Class setup | Exists | Home and class screens expose it | Needs stronger "first step" guidance |
| Student import | Exists | Students tab and class detail expose it | Should be a primary setup action, not just an icon |
| Roster scan | Exists | Exposed from class detail only | Too hidden for a major typing-reduction feature |
| Add one student | Exists | Exposed | Form is too heavy; full name + roll number should be first-class |
| Assessment create | Exists | Exposed | Stepper is too complex for first-time and one-hand use |
| Answer key completeness | Exists | Assessment card chip exists | Needs next-action copy on cards: "Finish answer key" |
| Master scan answer key | Exists through answer-key checkbox / answer sheet OMR path | Not promoted as a simple setup path | Teacher should scan a filled master sheet, preview it, confirm it, then use it as the exam key |
| Scan papers | Exists | Home scan action exists | Needs a visible assessment-level scan action |
| Scan master key / answer key checkbox | Exists in OMR pipeline | Not clearly surfaced from Assessments | Must be visible before pilot |
| Batch scanning | Exists | Exposed through camera/batch flow | Needs field validation and clearer progress/recovery |
| Duplicate detection | Exists | Partly in batch flow | Needs teacher-friendly explanation and undo path |
| Missing expected students | Student roster exists | Needs batch completion comparison | Teacher should see "not scanned yet" students before final save |
| No-roster / anonymous grading | Quick Grade can create temporary assessment | Needs explicit mode and labels | Useful when teacher does not want to register students |
| Review uncertain results | Exists | Review screens exist | Needs clearer "why this needs review" language |
| MISSING answer recovery | Exists | Exists in review flow | Should be optimized for thumb tapping and auto-advance |
| Reassign student | Exists | Review UI exposes action | Needs real flow validation |
| Audit trail | Exists | Audit sheet exists | Good trust feature; needs discoverability from result detail |
| Draft resume | Exists | Resume banner exists | Should drive Home primary action when active |
| Quick Grade | Exists | Home quick action | Needs clearer positioning: "I just need to grade now" |
| Quick Enter | Exists | Home quick action | Needs clearer positioning: "manual score entry" |
| Voice/read scores | Exists according to docs | Need current UI verification | Useful for accessibility and classroom checking |
| Backup/restore | Exists | Settings exposes it | Must be tested on device with real files |
| Results/reporting | Partial after Reports removal | Weak | Need minimal teacher-grade output before pilot |
| Analytics/topic mastery | Removed/deferred | Not exposed | Do not prioritize before core trust flow |
| Attendance | Removed | Not exposed | Keep out unless teacher interviews prove need |
| Telebirr/subscription | Deferred/removed | Not exposed | Keep out until product value is proven |
| Live grading/progressive setup | Deferred | Not in main | Valuable concept; must be redesigned and tested before merge |

## Major Product Gaps

### 1. The app has tools, but not enough guidance

Current Home exposes several options: New Assessment, Quick Grade, Quick Enter,
Scan, Import, classes, recent assessments, settings. These are useful, but they
are not arranged around the teacher's next job.

Production requirement:

- Home must choose one dominant next action.
- It should say "Continue grading", "Finish answer key", "Scan papers", "Create assessment", or "Add students first".
- Secondary tools should remain available, but visually quieter.

### 2. Create Assessment is too complex

The current stepper asks the teacher to move through basic info, rubric,
weighted setup, and questions. That is powerful, but too heavy for a teacher
who wants to grade today's exam.

Production requirement:

- Default flow: title, class, subject, question count, answer key, save.
- Use presets: 10, 20, 30, 50, 100.
- Default to MCQ, 1 point, current grading scale.
- Move weighted grading, custom scales, essay/short-answer complexity behind "Advanced".
- Provide a sticky primary action.

### 3. Add Student is not minimal enough

Current Add Student still has separate first/last name, additional names, and
required gender. This does not match the teacher-first design contract.

Production requirement:

- Required: Full name, Student ID/Roll No.
- Optional: class, gender, parent phone.
- Auto-select class when opened from class detail or when only one class exists.
- Put Import Roster and Scan Roster near this flow.

### 4. Assessments page is not a grading command center

Assessments should be where a teacher sees what is ready, what is blocked, and
what to do next. Right now it is mostly a list with filters and an icon add
button.

Production requirement:

- Each assessment card should show a next action:
  - "Add answer key"
  - "Generate answer sheet"
  - "Scan master key"
  - "Scan student papers"
  - "Review results"
  - "Completed"
- Scan should be visible here, not only on Home.

### 5. Master scan is not treated as a primary workflow

One of the most important teacher-saving ideas is this:

1. The teacher fills one answer sheet as the master.
2. The teacher scans that master sheet.
3. The app extracts the answer key.
4. The teacher previews and confirms the detected key.
5. The app uses that scanned master as the grading key for student papers.

This avoids forcing teachers to tap and record every correct answer manually.
It is especially important for long exams and for teachers using the app in a
real classroom, where manual entry is slow and error-prone.

Current state:

- The OMR pipeline includes answer key checkbox detection and answer key save
  from scan.
- The audit found this capability in docs and services, but the current UI does
  not make it obvious enough as the default teacher workflow.

Production requirement:

- "Scan master answer sheet" must be a first-class action on assessment setup.
- After master scan, show a preview: question number, detected answer,
  confidence, and missing/ambiguous answers.
- Teacher must confirm before the key becomes active.
- If master scan is weak, teacher should correct only the weak/missing answers,
  not re-enter the whole key.

### 6. No-roster grading needs to be intentional

Some teachers may not want to register students in the system, especially during
first use, exam-day pressure, a demo, or a one-time class. The app should still
give value.

Supported product mode:

- Teacher creates or scans an answer key.
- Teacher scans papers without registering students.
- App grades each paper as Paper 1, Paper 2, Paper 3, or by detected written
  name/ID when available.
- Teacher can optionally assign names later.
- Results can still be exported.

Production requirement:

- Make this an explicit mode: "Grade without student list" or "Quick batch".
- Do not force class/student setup before value is proven.
- If students are later added, allow matching results to students.

### 7. Missing and duplicate student handling must be a batch-level review

In a real classroom, a student may be absent, a paper may be skipped, a teacher
may scan the same paper twice, or papers may be out of order. This is not an
edge case; it is normal classroom mess.

Production requirement:

- If an assessment has a roster, the final review must show:
  - scanned students
  - missing/not scanned students
  - duplicate scans
  - unassigned papers
  - low-confidence student matches
- Duplicate detection should explain the reason: same image, same student ID,
  or same answer pattern.
- Teacher should be able to keep, replace, merge, or discard duplicates.
- Missing students should not silently become zero unless the teacher chooses
  that policy.

### 8. Short answer and mixed question types need a clearer promise

The app supports more than MCQ and T/F in the model and parsing logic, including
short answer, essay, and matching. But production UX must be honest about what
can be auto-graded and what needs teacher review.

Production requirement:

- During setup, teacher chooses question type simply:
  - MCQ
  - True/False
  - Short answer
  - Matching
  - Essay/manual
- For short answer:
  - teacher can enter expected answer or keywords
  - app can detect text where possible
  - uncertain answers go to review
  - teacher remains final authority
- For essay/manual:
  - app should not pretend to auto-grade deeply
  - use Quick Enter/manual scoring path
- Mixed exams should show a clear review queue by question type.

### 9. Results/reporting value is underbuilt

Reports and analytics were removed, but teachers still need final grade output.
Without this, the app grades papers but does not fully close the teacher's job.

Production requirement:

- Minimal Results screen or grade review export path:
  - class/assessment/date
  - students, scores, grades
  - missing/ungraded students
  - edits/audit indication
  - export/share CSV/PDF/text
- Do not restore old analytics wholesale. Restore the teacher value first.

### 10. Field truth is missing

Docs define real-world benchmark rules, but there is no current evidence in the
repo that the minimum real-device benchmark has passed.

Production requirement:

- Run at least `WEEKEND_TEST.md` before pilot.
- Run `REAL_WORLD_TESTING.md` before broader release.
- Log accuracy by device, lighting, paper condition, and sheet format.

## Features That Solve Real Problems

| Teacher Problem | Feature Built or Planned | Status | Product Note |
|---|---|---|---|
| Grading takes too long | OMR/OCR scan, Batch Scan, Quick Grade | Built | Needs field accuracy proof |
| Answer key entry takes too long | Master answer-sheet scan | Partly built | Must become first-class and preview-confirmed |
| Teacher does not want setup | No-roster grading / Quick Grade | Partly built | Needs explicit "grade without student list" mode |
| Teacher distrusts AI result | Review, confidence, raw OCR, audit trail, reassign, rescan | Built | UX must show why review is needed |
| Setup takes too long | Import CSV, roster scan, demo data, class setup | Built | Frontend needs simplification |
| Student absent or skipped | Missing student batch review | Partial | Must appear before final save |
| Same paper scanned twice | Duplicate detection and undo | Built/partial UI | Needs batch-level keep/replace/discard UX |
| Short-answer exams are common | Short answer / matching / manual review | Built/partial | Needs honest mixed-mode setup and review |
| Paper answer sheets cost money | Half-sheet layout | Built | Great adoption feature; must validate accuracy |
| Phone dies mid-grading | Draft resume | Built | Must be Home primary action when present |
| Student transferred classes | Student transfer service/dialog | Built | Good school-reality feature |
| School uses custom rubrics | Custom grading scales, weighted grades | Built | Should be advanced, not default setup friction |
| Teacher needs to explain grade changes | Audit trail | Built | Strong trust feature |
| Teacher has no internet | Offline-only storage, no internet permission | Built | Strong differentiator |
| Teacher fears data loss | Backup/restore, auto-backup | Built | Needs plain workflow and validation |
| Teacher wants hands-free checking | Voice read scores | Built/partly needs verification | Helpful, but not core before scan flow |
| Teacher wants live session flow | Deferred live grading + progressive setup | Deferred | Valuable later; do not merge until core app is stable |
| Teacher needs class insights | Reports/analytics removed | Missing | Restore minimal results first, analytics later |

## Deferred or Removed Ideas

### Deferred and still valuable

- Live grading session flow under `.deferred/live_grading`.
- Progressive setup coordinator that walks teacher through class, students,
  assessment, and answer key readiness.
- Product UI components under `.deferred/live_grading/lib/widgets/product_components.dart`.
- Voice/TTS as accessibility and classroom read-back support.
- Camera mock and integration test infrastructure.
- Android performance and battery testing.

### Removed and should not be restored blindly

- Attendance.
- Analytics dashboard.
- Full reports screen as it existed before.
- Exam scheduling.
- Telebirr/subscription.
- Amharic UI mode.

These may become useful later, but they should not compete with the core grading
flow until the app proves adoption.

## UI/UX Production Audit

### One-hand use

Current risk:

- Too many top/right icon-only actions.
- Some workflows require careful text entry.
- Long steppers and horizontal score tables can be tiring on small phones.
- Some important actions are not near the thumb zone.

Required standard:

- Primary action near lower half or sticky bottom.
- Minimum practical tap target: 48dp.
- Avoid icon-only controls for core teacher actions.
- Use bottom sheets for choices, not deep navigation when possible.
- Reduce keyboard time.
- Prefer scan/preview/confirm over manual tapping for long answer keys.
- Let teachers finish common tasks while holding papers in the other hand.

### Friendliness and empathy

Current risk:

- The app sometimes sounds like a system: assessment, rubric, weighted setup,
  coordinate maps, confidence.
- Teachers need task language: "Scan papers", "Fix answer key", "Review 3 papers".

Required standard:

- Use teacher job language.
- Explain risk only where needed.
- Make recovery calm: "Nothing was saved yet", "You can review before saving",
  "Data stays on this phone".

### Adaptability

Current strengths:

- Manual Quick Enter for non-scan subjects.
- Quick Grade for one-off use.
- Custom scales and weighted grades.
- Import and scan roster.
- Backup/restore.

Current risk:

- These options are not organized by situation.

Required standard:

- Let teacher pick a mode by intent:
  - "I have answer sheets"
  - "I want to scan the master key"
  - "I do not want to register students"
  - "I want to enter scores manually"
  - "I need a quick one-time grade"
  - "I need to set up a class"

### Classroom and phone context

The app must be designed for the physical environment, not only the screen.

Real conditions to design for:

- Low-end Android phones with weaker cameras.
- 2GB RAM devices.
- Small screens.
- Bright classrooms and outdoor shade.
- Dim staff rooms or evening marking under a lamp.
- Shaky hands while holding a stack of papers.
- Teachers using one hand while sorting papers with the other.
- Students using light pencil, partial erasures, smudges, folded paper, and
  imperfect bubble fills.
- Interruptions: calls, notifications, students asking questions, phone battery
  running low.

Design implications:

- Camera UI must guide distance, alignment, and lighting.
- Scan failure copy must be practical: "Move closer", "Use brighter light",
  "Keep all four corners visible".
- Batch scan must save progress continuously.
- Review must be resumable and forgiving.
- Buttons must be large enough for one-hand use.
- The app must not require perfect paper or perfect classroom conditions.

### Trust

Current strengths:

- Review, audit trail, raw OCR, confidence, reassign, rescan, backup.

Current risk:

- Trust features are not consistently foregrounded.

Required standard:

- Never imply automatic grading is final.
- Always show review before final save when confidence is uncertain.
- Make audit history accessible from final results.

## Android Production Audit

### Manifest and permissions

Current state:

- Camera permission is declared.
- Internet permission is intentionally absent.
- Legacy read/write external storage permissions remain.
- Camera hardware is required.

Risks:

- Requiring camera hardware is fine for this app, but it excludes devices
  without camera support.
- Legacy storage permissions may be unnecessary on modern Android and should be
  reviewed for Play policy and Android 13+ behavior.

### Build configuration

Current state:

- `compileSdk` and `targetSdk` are 36.
- `minSdk` is 26.
- Release currently uses debug signing.
- ABI is restricted to `arm64-v8a`.
- Release minify and resource shrinking are enabled.

Risks:

- Debug signing is not production release signing.
- SDK 36 may complicate local builds.
- Arm64-only is probably reasonable for size, but needs a device-coverage
  decision for the target teacher population.

### Android validation required

Before pilot:

- Install debug/release build on at least one low-end Android device.
- Complete the full teacher flow.
- Capture screenshots for Home, Students, Create Assessment, Answer Key, Scan,
  Review, Results/Grade Review, Settings.
- Run logcat during scan/review.
- Confirm no crash during 10-paper scan.

Before production:

- Use release-signed APK/AAB.
- Confirm permissions behavior on Android 10, 12, 13, and 14+ if available.
- Run frame/memory checks on batch scan.
- Confirm backup/export/share works with Android file sharing.

## Performance Readiness

Known target from operations docs:

- Scan a paper in under 5 seconds.
- Grade 30 papers in under 3 minutes.
- Target low-spec 2GB RAM Android phones.

Current risk:

- These targets are stated but not proven in current audit evidence.

Required evidence:

- Batch scan timing on low-end hardware.
- Memory use during 30-paper scan.
- No thermal or battery collapse during extended scan.
- No UI freeze during image processing.
- APK size audit, with target under 20-25MB depending final ML/TTS cost.

## Privacy and Data Safety

Current strengths:

- No internet permission.
- Local Hive storage.
- AES-256 encrypted boxes.
- FlutterSecureStorage key storage.
- Backup/restore.
- Corrupt file preservation according to docs.
- Auto-backup on scan save according to docs.

Production gaps:

- Backup restore needs real Android file validation.
- Corruption banner/recovery needs UI validation.
- Privacy copy needs to be simple and present at moments of risk.
- Need a clear "delete all data" confirmation and backup suggestion before destructive actions.

## Accessibility Readiness

Current status: not proven.

Required before production:

- TalkBack labels for camera, scan, review, save, export, reassign, rescan.
- Font scale test at 1.3x and 1.5x.
- Contrast check in bright classroom conditions.
- No text overlap on small screens.
- Voice read scores tested as accessibility support, not a novelty.

## Test Readiness

Current strengths:

- Many service tests exist.
- Many widget tests exist.
- Integration tests exist for synthetic scan/grade flows.
- Real-world testing docs exist.

Current gaps:

- PROJECT_STATE and current checkout may be stale relative to actual UI.
- Real device camera flow is not proven in this audit.
- No captured current run of `flutter analyze`, `flutter test`, or Android install during this audit.
- CameraScreen hardware flow is not fully covered by widget tests.

Minimum release gates:

1. `flutter analyze`
2. `flutter test`
3. `flutter build apk --release`
4. Android install and smoke test
5. 10-paper weekend test
6. 60-scan real-world benchmark before wider rollout

## Documentation Readiness

Current issue:

- `PROJECT_STATE.md` is useful but overconfident. It marks many items done
  while current UI still has adoption-level gaps.
- `KNOWN_ISSUES.md` says no open medium bugs, but UX discoverability and
  product readiness gaps remain.
- `DESIGN.md` and `.project-os/` are absent from current `main`, though present
  in another branch/history.

Required:

- Restore or recreate `DESIGN.md`.
- Restore or recreate `.project-os/` operating rules.
- Update `PROJECT_STATE.md` to separate:
  - implemented
  - exposed in UI
  - tested locally
  - tested on Android
  - field-proven
- Update `KNOWN_ISSUES.md` with current production-readiness gaps.

## Priority Plan

### P0: Make the core teacher journey obvious

Goal: a teacher opens the app and knows the next action without explanation.

Scope:

- Home primary action logic.
- Assessment cards with next action.
- Assessments page as grading command center.
- Restore/rebuild design components.
- Restore design/governance docs.
- Add explicit teacher modes: registered class grading, no-roster grading,
  Quick Grade, Quick Enter.

### P0: Simplify assessment setup

Goal: create a normal exam in under 1 minute.

Scope:

- Replace heavy Stepper with compact task flow.
- Keep advanced settings collapsed.
- Add question count presets.
- Direct answer-key entry or scan-master-key path.
- Make "Scan master answer sheet" a primary setup option.
- Add master-key preview and confirm.

### P0: Simplify student setup

Goal: add/import students with minimal typing.

Scope:

- Full name + roll number required.
- Gender optional.
- Class auto-select.
- Import roster and scan roster visible.

### P0: Prove scan accuracy

Goal: know whether OMR/OCR is real enough for pilot.

Scope:

- Run `WEEKEND_TEST.md`.
- Log every mismatch.
- Decide pilot/tune/rework.
- Include master-sheet scan, student-sheet scan, half-sheet scan, low light,
  and low-end phone conditions.

### P0: Make batch completion trustworthy

Goal: teacher knows whether all intended papers were handled.

Scope:

- Missing/not scanned students.
- Duplicate scans.
- Unassigned papers.
- Low-confidence student matches.
- Keep/replace/discard duplicate decisions.
- "Save final grades" only after teacher confirms these issues.

### P1: Restore minimum results/export

Goal: teacher can use final grades outside the app.

Scope:

- Simple final results table.
- Missing/ungraded students.
- Export/share CSV or PDF/text.
- Audit history access.

### P1: Clarify mixed question support

Goal: support common exams without overpromising automation.

Scope:

- MCQ/T/F as strongest automatic path.
- Short answer as detect-and-review path.
- Essay/manual as teacher-scored path.
- Matching as exact/partial review path.
- Review queue grouped by uncertainty and question type.

### P1: Android hardening

Goal: app runs smoothly on real target phones.

Scope:

- Low-end device install.
- Batch scan performance.
- Memory/battery check.
- Permission review.
- Release signing plan.

### P1: Trust and recovery polish

Goal: teachers feel safe.

Scope:

- Backup prompts.
- Offline/privacy copy at key moments.
- Draft resume prominence.
- Clear scan failure recovery.

### P2: Helpful later features

Only after core flow is proven:

- Live grading session mode.
- Voice-first review/readback improvements.
- Teacher-friendly insights/analytics.
- Attendance or school operations tools if interviews prove demand.
- Payments/subscription.
- Amharic UI return, if user research proves it increases adoption.

## Production Release Definition

EthioGrade is production-ready only when all are true:

- A new teacher can complete the main grading flow without coaching.
- First assessment setup takes under 1 minute for a normal MCQ/T/F exam.
- A teacher can create the answer key by scanning a master answer sheet,
  previewing it, correcting weak/missing answers, and confirming it.
- A teacher can grade papers without registering students first.
- Every core action is reachable within 1-2 taps from the relevant screen.
- Home always shows the best next action.
- Assessment cards tell the teacher what to do next.
- Add Student does not require unnecessary fields.
- Batch review clearly shows missing students, duplicate scans, unassigned
  papers, and low-confidence matches.
- Short-answer/mixed exams are honestly represented: automatic where possible,
  teacher review where needed.
- Scan/review/save flow is proven on real Android hardware.
- Clean paper OMR accuracy meets the benchmark.
- Stressed paper accuracy and limitations are documented.
- Master-sheet scan accuracy is separately measured.
- Low-end phone and difficult room-light conditions are tested.
- No crash during benchmark scanning.
- Backup/export/restore works on real Android.
- Results can be exported/shared.
- TalkBack, font scale, and small-screen checks are acceptable.
- Release signing and package output are ready.
- Known limitations are written in teacher language.

## Final Product Judgment

EthioGrade has enough technical substance to become useful. It does not need a
large new feature expansion before pilot. It needs disciplined product shaping.

The next successful version should feel less like a collection of grading tools
and more like a teacher companion that says:

1. Here is what you need to do next.
2. I will not lose your data.
3. I will not silently trust uncertain scans.
4. You can correct mistakes quickly.
5. You can leave with usable grades.

That is the adoption threshold.
