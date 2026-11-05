# Answer-Key Change Safety — Architecture Confirmation

> **Status:** Pre-implementation review. No code changes.
> **Date:** 2026-06-14
> **Branch:** `codex/review-queue-v2`
> **HEAD:** `e94a921`

---

## State Verification

| Check | Status |
|-------|--------|
| Branch | `codex/review-queue-v2` |
| HEAD | `e94a921e5748083bfa2db5616641142d26877fdb` — matches expected |
| Dashboard Phase 1 intact | Yes — 5 files committed in `e94a921` |
| `SESSION_HANDOFF.md` | Untracked (expected) |
| `.project-os/DECISION_LOG.md` | Modified (expected — prior session) |
| Source code changes after checkpoint | **None** — only `DECISION_LOG.md` and untracked files |
| 29 pre-existing test failures | Identical at HEAD, no regressions |

---

## A. Canonical Key Schema

The answer key is **not a separate model**. It is the `List<Question>` on the `Assessment`, where each `Question` carries a `correctAnswer` field.

### Scoring-relevant fields that determine whether an answer key changed

| # | Field | Location | HiveField | Scoring impact |
|---|-------|----------|-----------|----------------|
| 1 | Question identity (id + number) | `Question.id`, `Question.number` | Q-0, Q-1 | Determines which detected answer maps to which key entry |
| 2 | Question type | `Question.type` | Q-2 | Determines which checkAnswer branch runs (MCQ/TF/matching/short/essay) |
| 3 | Correct answer | `Question.correctAnswer` | Q-7 | The actual answer compared against detected student response |
| 4 | Options list | `Question.options` | Q-6 | MCQ options — affects display, not scoring logic directly |
| 5 | Points / max score | `Question.points` | Q-5 | Directly multiplied into score when isCorrect |
| 6 | Keywords | `Question.keywords` | Q-10 | Short answer matching — list of accepted alternatives |
| 7 | Essay rubric weights | `Question.essayRubric` | Q-11 | Essay scoring weights (currently unused by auto-grader) |
| 8 | Topic tag | `Question.topicTag` | Q-9 | Affects weighted component assignment in `computeWeightedPercentage()` |
| 9 | Question order (list order) | Position in `Assessment.questions` | — | `scoreAnswers()` iterates assessment.questions in list order |
| 10 | Question text | `Question.text` | Q-3 | Display only — not used in scoring logic |
| 11 | Rubric type | `Assessment.rubricType` | A-6 | Determines letter grade mapping (moe_national, private_international, university, custom) |
| 12 | Grading scale | `Assessment.rubricType` + registered custom scales | A-6 | `ScoringService.calculateGrade()` reads this |
| 13 | Weighted scale | `Assessment.weightedScaleId` | A-16 | Links to `WeightedGradeScale` for component-weighted scoring |

### Canonical serialization strategy

**Deterministic canonical JSON + SHA-256 is the safest approach.**

The canonical form must serialize all scoring-relevant fields in a deterministic order:

```
{
  "questions": [
    {
      "id": "<question.id>",
      "number": <question.number>,
      "type": <question.type.index>,
      "correctAnswer": <normalized correctAnswer>,
      "points": <question.points>,
      "keywords": <question.keywords or null>,
      "essayRubric": <question.essayRubric or null>,
      "topicTag": <question.topicTag or null>
    },
    ...
  ],
  "rubricType": "<assessment.rubricType>",
  "weightedScaleId": "<assessment.weightedScaleId or null>"
}
```

Normalization rules for `correctAnswer`:
- MCQ/TF: uppercase trimmed string
- Matching: canonical `"MATCH:X-Y-Z"` format
- Short answer: if `List`, sort alphabetically; if `String`, trim and lowercase
- Essay: null (not scored automatically)

### Why NOT other approaches

| Approach | Risk |
|----------|------|
| Runtime Dart `hashCode` | Non-deterministic across isolates, Android versions, and cold starts. Cannot be reproduced or debugged. |
| Monotonic revision counter alone | Cannot detect whether the key actually changed (two edits that cancel out increment revision but fingerprint stays same). Cannot detect corruption. |
| Revision + fingerprint | Revision is useful for ordering and UI, but fingerprint is the correctness source. Revision without fingerprint is incomplete. |

**Recommendation:** Revision counter + SHA-256 fingerprint. The revision increments on every save. The fingerprint is the authoritative change-detection mechanism.

---

## B. Revision/Fingerprint Decision

### Chosen approach: `answerKeyRevision` (int) + `answerKeyFingerprint` (String)

Both stored on `Assessment`. The fingerprint is computed deterministically from the canonical serialization. The revision is a simple incrementing counter.

**Why both:**
- **Fingerprint** = correctness mechanism. Two assessments with the same fingerprint have identical scoring behavior. Two with different fingerprints will produce different scores for at least one student response.
- **Revision** = ordering and UI mechanism. "Your key is revision 5; this result was scored with revision 3." Also useful for display ("Key changed 2 times since last scoring").

### Computation

```dart
// On Assessment:
int answerKeyRevision;          // HiveField(18) — new field
String answerKeyFingerprint;    // HiveField(19) — new field

// Computed via:
String computeAnswerKeyFingerprint(Assessment assessment) {
  // Canonical JSON serialization of scoring-relevant fields
  // SHA-256 hex digest
}
```

### When fingerprint is computed

1. **On assessment save** (AssessmentProvider.saveAssessment/updateAssessment) — if questions or rubricType changed
2. **On answer-key edit** (AnswerKeyScreen) — after each question answer changes
3. **On migration** (lazy, on first read of legacy assessment with no fingerprint)

---

## C. Exact Persistence Design

### Fields to add to Assessment

```dart
@HiveType(typeId: 2)
class Assessment {
  // ... existing fields through HiveField(17) ...

  @HiveField(18)
  final int answerKeyRevision;        // default: 0

  @HiveField(19)
  final String answerKeyFingerprint;  // default: ''
}
```

**HiveField numbers:** 18 and 19 are the next available on Assessment (current max is 17). No gaps exist at 18/19.

### Fields to add to ScanResult (via metadata map)

```dart
// In ScanResult.metadata:
'scoredWithKeyFingerprint': '<hex string>',   // fingerprint of the key at scoring time
'scoredWithKeyRevision': <int>,               // revision at scoring time
```

**Why metadata map, not typed fields:** ScanResult already has 19 typed fields (0-18). Adding typed fields would require a new HiveField number and adapter change. The metadata map is the existing extensibility mechanism and is used for all other contextual data. Using metadata avoids touching the ScanResult adapter.

**The fingerprint and revision in metadata are stamped by ScoringService.scoreAnswers() at scoring time.** This is the single point where the key version is recorded on the result.

### Where the stamp is added

In `ScoringService.scoreAnswers()`, after computing the answer matches:

```dart
// Existing return point (scoring_service.dart line 261):
return matches;

// New: the caller (HybridGradingService.gradePaper) stamps the result metadata
// with the key fingerprint and revision BEFORE constructing ScanResult.
```

The stamp happens in `HybridGradingService.gradePaper()` at lines 204-221, where the `ScanResult` is constructed. The metadata map is built at lines 172-186. Two new entries are added:

```dart
'metadata': {
  ...existing keys...,
  'scoredWithKeyFingerprint': assessment.answerKeyFingerprint,
  'scoredWithKeyRevision': assessment.answerKeyRevision,
}
```

### No migration required for new fields

- `answerKeyRevision` defaults to `0` when absent from Hive binary data (Hive returns `null` for missing fields; the model constructor defaults to `0`).
- `answerKeyFingerprint` defaults to `''` when absent.
- `metadata['scoredWithKeyFingerprint']` defaults to `null` when absent from existing ScanResults.
- Existing results without the metadata keys are treated as "legacy baseline" (see Section E).

---

## D. Migration and Legacy Strategy

### Legacy assessments (no fingerprint/revision)

**Behavior:** Lazy fingerprint generation on first read.

When an Assessment is loaded and `answerKeyFingerprint` is empty:
1. Compute the fingerprint from the current questions.
2. Set `answerKeyRevision = 0` (legacy baseline).
3. Persist the computed fingerprint back to Hive.
4. This is a one-time cost per assessment, triggered on first access after upgrade.

**Implementation:** Add a method to AssessmentProvider:

```dart
Future<void> ensureFingerprintCurrent(Assessment assessment) async {
  if (assessment.answerKeyFingerprint.isNotEmpty) return;
  final fp = computeAnswerKeyFingerprint(assessment);
  final updated = assessment.copyWith(
    answerKeyRevision: 0,
    answerKeyFingerprint: fp,
  );
  await updateAssessment(updated);
}
```

### Legacy scan results (no scoredWithKeyFingerprint)

**Behavior:** Treated as `scoredWithKeyFingerprint == assessment.answerKeyFingerprint` (i.e., assumed current).

**Rationale:** Legacy results were scored with whatever key existed at the time. If the current key's fingerprint matches, they are current. If the key has since changed, the comparison will fail because the legacy result has no fingerprint — this is handled by the "legacy baseline or unknown" integrity state (see Section E).

**Alternative considered:** Treating missing fingerprint as "unknown" (always stale). This is too aggressive — it would flag every existing result as stale on first upgrade, even if the key hasn't changed.

**Chosen approach:** Missing fingerprint + matching current key fingerprint = current. Missing fingerprint + non-matching or missing current fingerprint = legacy baseline (safe default: "treat as current but cannot verify").

### Migration sequence

1. App upgrade: new HiveField(18) and (19) on Assessment are absent → defaults to 0 and ''.
2. First access to any Assessment: `ensureFingerprintCurrent()` computes and persists.
3. First scoring after upgrade: `scoredWithKeyFingerprint` is stamped in metadata.
4. No box-level migration needed. No adapter rebuild needed (new fields have defaults).

---

## E. Per-Question-Type Rescoring Matrix

Rescoring uses `AnswerMatch.detectedAnswer` (the student's persisted response) against the new `Question.correctAnswer` from the updated assessment key.

| Question Type | detectedAnswer available? | correctAnswer from key? | Rescore possible? | Method | Notes |
|---------------|--------------------------|------------------------|-------------------|--------|-------|
| **MCQ** | Yes — `"A"`, `"B"`, etc. | Yes — single letter | **Yes** | `checkAnswer(detected, correct, mcq)` | Binary: full points or zero. Normalize case + whitespace. |
| **True/False** | Yes — `"True"` / `"False"` | Yes — `"True"` / `"False"` | **Yes** | `checkAnswer(detected, correct, trueFalse)` | Binary. Normalize case + whitespace. |
| **Short Answer** | Yes — free text | Yes — String or List\<String\> | **Yes** | `checkAnswer(detected, correct, shortAnswer)` | Binary. Whitespace-normalized. If correctAnswer is List, any match counts. |
| **Fill in the Blank** | Same as short answer | Same as short answer | **Yes** | Same as short answer | No distinction in current codebase. |
| **Matching** | Yes — `"MATCH:G-D-E"` | Yes — same format | **Yes** | `checkAnswer(detected, correct, matching)` | Binary. Exact letter-sequence match. |
| **Essay** | Yes — raw OCR text or `"(manual: ...)"` | Usually null | **No auto-rescore** | — | Essay is manually graded. Teacher score is final. Raw text preserved for re-reading but no auto-re-score. |
| **Manual Entry** | Yes — `"(manual entry)"` | From key | **No** | — | `isManualEntry: true` — teacher entered scores directly. Scores are final. |

### Key observations

1. **MCQ, TF, Short Answer, Matching: full rescoring from persisted data.** The `detectedAnswer` is the canonical student response. The new `correctAnswer` comes from the updated assessment. Re-running `ScoringService.checkAnswer()` + computing totals produces the new score.

2. **Essay: no auto-rescore.** Essay scores are teacher-assigned. The raw text in `detectedAnswer` (or `ocrRawText`) is preserved for the teacher to re-read, but automated rescoring is not possible. **Policy: preserve teacher judgment** (see Section F).

3. **Manual entry: no rescoring.** Results with `isManualEntry: true` are teacher-entered. Their scores reflect direct teacher judgment. **Policy: preserve teacher judgment.**

4. **Weighted scoring:** If the assessment uses a `WeightedGradeScale`, the weighted percentage is recomputed from the new per-question scores. The rubric type for grade lookup may differ.

5. **Where original images are genuinely required:** Only for essay questions where the teacher wants to re-read the student's handwritten response. For all objective types, the persisted `detectedAnswer` is sufficient. For essay, the `detectedAnswer` contains OCR text which may be lossy — the original image provides the ground truth. However, essay rescoring is manual, not automated.

---

## F. Manual-Override Policy

| Override type | Current storage | Recalculation behavior | Rationale |
|---------------|----------------|----------------------|-----------|
| **Corrected detected answer** (`_applyAnswerChange`) | `AnswerMatch.detectedAnswer` replaced, `ocrRawText` set to `"(manual: <answer>)"` | **Recalculate.** The corrected answer is the new student response. Compare against new key. | Teacher explicitly changed what the student answered. The corrected answer is authoritative. |
| **Forced correct/incorrect** (`_applyOverride`) | `AnswerMatch.isCorrect` toggled, `score` set to 0 or maxScore | **Preserve.** Do not recalculate. The teacher's judgment overrides auto-scoring. | Teacher explicitly decided this answer is correct/wrong regardless of what the key says. |
| **Manually awarded partial credit** (via quick-enter or review) | `AnswerMatch.score` set to arbitrary value between 0 and maxScore | **Preserve.** Do not recalculate. | Teacher judged the partial quality. Key change should not override this. |
| **Essay/rubric marks** | `AnswerMatch.score` set by teacher, `detectedAnswer` may be `"(manual: ...)"` | **Preserve.** Do not recalculate. | Essay scoring is inherently manual. Teacher's grade stands. |
| **Manually entered final scores** (Quick Grade) | `ScanResult` with `isManualEntry: true` | **Preserve.** Do not recalculate. | Teacher typed the score directly. It is their judgment. |
| **ReviewScreen answer-key edits** (via `_openAnswerKeyEditor`) | Assessment updated, existing results flagged | **Recalculate** (existing flow). | This is the primary change scenario. |

### Decision rules

A result should be **recalculated** if and only if ALL of the following are true:
1. The result has a non-empty `imagePath` (original image exists) OR the `detectedAnswer` is a clean objective answer (MCQ/TF/matching/short-answer).
2. The result does NOT have `isManualEntry: true`.
3. No individual `AnswerMatch` in the result has been teacher-overridden (i.e., `ocrRawText` does not contain `"(manual:"` for that answer AND the answer was not force-toggled via `_applyOverride`).

A result should be **preserved** (not recalculated) if ANY of the following are true:
1. `isManualEntry == true`
2. Any answer has been teacher-overridden (detected by `ocrRawText` containing `"(manual:"`)
3. Any answer has been force-toggled (detected by checking if the original auto-score differs from current score AND the answer is not a manual correction)

### Implementation tracking

Each `AnswerMatch` needs a flag indicating whether it has been teacher-overloaded. This can be added to the metadata map:

```dart
// In AnswerMatch, add to metadata or ocrRawText convention:
// ocrRawText starts with "(manual:" → teacher-corrected answer
// ocrRawText is null and score != 0/1 of maxScore → partial credit
// score == maxScore or score == 0 and ocrRawText is null → auto-scored
```

**Detection heuristic (no new fields needed):**

```dart
bool _isAutoScored(AnswerMatch answer) {
  // Auto-scored answers have ocrRawText that does NOT start with "(manual:"
  // AND score is either 0 or maxScore (binary auto-grading)
  if (answer.ocrRawText != null && answer.ocrRawText!.startsWith('(manual:')) return false;
  if (answer.score != 0 && answer.score != answer.maxScore) return false;
  return true;
}
```

A result is eligible for recalculation if ALL its answers are auto-scored AND `isManualEntry == false`.

---

## G. Integrity-State Model

### States

| State | Meaning | Display behavior |
|-------|---------|-----------------|
| **current** | `scoredWithKeyFingerprint == assessment.answerKeyFingerprint` | Normal display. Green indicator. Ready for finalization. |
| **legacy_baseline** | `scoredWithKeyFingerprint` is missing (old result) AND assessment fingerprint exists and matches current key | Treated as current. No visual distinction. One-time migration stamps the fingerprint on next save. |
| **unknown** | `scoredWithKeyFingerprint` is missing AND assessment fingerprint is missing or key has changed since legacy | Amber indicator: "Scored with previous key version." Cannot verify correctness. |
| **outdated** | `scoredWithKeyFingerprint != assessment.answerKeyFingerprint` AND fingerprint is not null | Red indicator: "Scores may be outdated." Requires recalculation. |
| **recalculating** | Recalculation in progress | Progress indicator. Scores shown as "Recalculating..." |
| **recalculation_failed** | Recalculation encountered an error | Red indicator: "Recalculation failed." Retry option. Manual review needed. |
| **current_but_needs_manual_review** | Auto-rescored but contains teacher-overridden answers that were preserved | Amber indicator: "Rescored, but some answers were teacher-reviewed." |

### State resolution function

```dart
enum IntegrityState {
  current,
  legacyBaseline,
  unknown,
  outdated,
  recalculating,
  recalculationFailed,
  currentButNeedsManualReview,
}

IntegrityState resolveIntegrityState({
  required ScanResult result,
  required Assessment assessment,
  bool isRecalculating = false,
  bool recalculationFailed = false,
}) {
  if (isRecalculating) return IntegrityState.recalculating;
  if (recalculationFailed) return IntegrityState.recalculationFailed;

  final resultFp = result.metadata['scoredWithKeyFingerprint'] as String?;
  final keyFp = assessment.answerKeyFingerprint;

  // No fingerprint on result → legacy
  if (resultFp == null || resultFp.isEmpty) {
    if (keyFp.isNotEmpty) {
      return IntegrityState.unknown; // Cannot verify
    }
    return IntegrityState.legacyBaseline; // Both missing, trust current
  }

  // Fingerprint matches → current
  if (resultFp == keyFp) {
    // Check if any answers were teacher-overridden
    final hasOverrides = result.answers.any((a) =>
      a.ocrRawText != null && a.ocrRawText!.startsWith('(manual:'));
    if (hasOverrides) return IntegrityState.currentButNeedsManualReview;
    return IntegrityState.current;
  }

  // Fingerprint mismatch → outdated
  return IntegrityState.outdated;
}
```

### Where integrity state is enforced

| Location | Enforcement |
|----------|------------|
| **Results display** (ReviewScreen, GradeReviewScreen) | Show integrity badge on each result card. Outdated results show amber/red indicator. |
| **Reports and averages** (GradeReviewScreen stats) | If any results are `outdated`, show warning: "Class average may be inaccurate — N papers have outdated scores." |
| **Assessment cards** (Dashboard, AssessmentCard) | Show "Scores outdated" badge if any results for this assessment are outdated. |
| **Dashboard status** | Assessment operational status resolver adds an "Outdated" state when key-changed results exist. |
| **Finalization gate** | `_confirmFinalSaveIfNeeded()` checks for `outdated` results. Cannot final-save while outdated results exist (block, not warn). |
| **Export / publishing** | CSV export includes an "Integrity" column. Outdated results are flagged. Export is blocked if any results are outdated (unless teacher explicitly overrides). |

### Stale results must never appear as fully current

The integrity state is checked at display time, not at load time. Every render of a result card, score row, or statistic recalculates the integrity state against the current assessment fingerprint. This ensures that the moment the answer key changes, all displayed results immediately reflect the outdated state — no caching, no delayed detection.

---

## H. Recalculation Transaction and Recovery Design

### Recalculation flow

```
1. Teacher changes answer key → new fingerprint computed → Assessment saved
2. Teacher taps "Recalculate now" OR navigates away and returns later
3. System loads all ScanResults for this assessment
4. For each result:
   a. Check eligibility (auto-scored, not manual entry)
   b. If eligible: re-run checkAnswer() with stored detectedAnswer + new key
   c. Compute new totals, percentage, grade
   d. Stamp new scoredWithKeyFingerprint in metadata
   e. Persist updated ScanResult to Hive
   f. Record audit trail entry
5. When all results processed: mark assessment as "recalculation complete"
```

### Transaction model

**There is no atomic transaction across Hive.** Each `box.put()` is independent. The design must handle partial failure.

**Strategy: checkpoint-based progressive persistence.**

1. Before starting: set `assessment.metadata['recalculationInProgress'] = true` and persist.
2. Process results one at a time. After each successful save, increment `assessment.metadata['recalculationProcessedCount']`.
3. After each save, update `assessment.metadata['recalculationProcessedCount']` and persist assessment.
4. On completion: set `recalculationInProgress = false`, `recalculationComplete = true`, clear count.
5. On failure: `recalculationInProgress` remains true, `recalculationProcessedCount` indicates how far we got.

### Interruption scenarios

| Scenario | State after interruption | Recovery behavior |
|----------|------------------------|-------------------|
| **App closes after new key saved, before recalculation begins** | Key saved, no results updated. Assessment has `answerKeyFingerprint` set. Results have old/no fingerprint. | On next review screen open: `outdated` state detected. "Recalculate" prompt shown. |
| **App closes halfway through recalculation** | Some results have new fingerprint, some have old. Assessment has `recalculationInProgress: true`, `recalculationProcessedCount: N`. | On next launch: detect `recalculationInProgress`. Resume from `recalculationProcessedCount`. Re-process remaining results. Already-processed results have new fingerprint and are skipped. |
| **App closes after only some results written** | Same as halfway — partial completion. | Same recovery: resume from checkpoint. |
| **Providers or reports refreshing during recalculation** | Results list may show mixed states (some current, some outdated). | Integrity state is computed per-result at display time. Each result shows its own state. No "partial recalculation appears complete" because each result's state is independent. |

### Critical invariant

**A partial recalculation must never appear complete.**

This is guaranteed by:
1. Each result's integrity state is computed independently from its `scoredWithKeyFingerprint` vs the assessment's current fingerprint.
2. Results that haven't been recalculated still have the old fingerprint → `outdated` state.
3. The "recalculation complete" flag on the assessment is only set when ALL results have been processed.
4. The review queue's `_issueFor()` function classifies `outdated` results as `_ReviewIssue.answerKey` (regrade needed).

### Recalculation implementation

```dart
class AnswerKeyRecalculationService {
  /// Recalculate all eligible results for an assessment with a new answer key.
  ///
  /// Returns a summary of what was recalculated, preserved, and skipped.
  Future<RecalculationResult> recalculateAll({
    required Assessment assessment,
    required List<ScanResult> results,
    void Function(int processed, int total)? onProgress,
  }) async {
    final updatedResults = <ScanResult>[];
    int recalculated = 0;
    int preserved = 0;
    int skipped = 0;
    int failed = 0;

    // Checkpoint: mark in-progress
    await _setRecalculationInProgress(assessment, true, 0);

    for (int i = 0; i < results.length; i++) {
      final result = results[i];

      if (!result.isManualEntry && _isFullyAutoScored(result)) {
        // Recalculate
        try {
          final newResult = _recalculateSingle(result, assessment);
          updatedResults.add(newResult);
          recalculated++;
        } catch (e) {
          updatedResults.add(result); // Preserve original on failure
          failed++;
        }
      } else {
        // Preserve — manual entry or teacher overrides
        updatedResults.add(result);
        preserved++;
      }

      // Checkpoint
      await _setRecalculationInProgress(assessment, true, i + 1);
      onProgress?.call(i + 1, results.length);
    }

    // Checkpoint: mark complete
    await _setRecalculationInProgress(assessment, false, results.length);

    return RecalculationResult(
      updatedResults: updatedResults,
      recalculated: recalculated,
      preserved: preserved,
      skipped: skipped,
      failed: failed,
    );
  }

  ScanResult _recalculateSingle(ScanResult result, Assessment assessment) {
    // Re-score using stored detectedAnswer against new key
    final newMatches = <AnswerMatch>[];
    for (final oldMatch in result.answers) {
      final question = assessment.questions.firstWhere(
        (q) => q.number == oldMatch.questionNumber,
        orElse: () => Question(number: oldMatch.questionNumber, type: QuestionType.mcq),
      );

      final newCorrect = question.correctAnswer?.toString() ?? '';
      final isCorrect = const ScoringService().checkAnswer(
        detected: oldMatch.detectedAnswer,
        correct: question.correctAnswer,
        type: question.type,
      );

      newMatches.add(AnswerMatch(
        questionNumber: oldMatch.questionNumber,
        detectedAnswer: oldMatch.detectedAnswer,
        correctAnswer: newCorrect,
        isCorrect: isCorrect,
        score: isCorrect ? question.points : 0,
        maxScore: question.points,
        confidence: oldMatch.confidence,
        ocrRawText: oldMatch.ocrRawText,
        boundingBox: oldMatch.boundingBox,
      ));
    }

    final newTotal = newMatches.fold(0.0, (s, a) => s + a.score);
    final maxScore = assessment.maxScore;
    final percentage = maxScore > 0 ? (newTotal / maxScore) * 100 : 0.0;
    final grade = const ScoringService().calculateGrade(percentage, assessment.rubricType);

    return result.copyWith(
      answers: newMatches,
      totalScore: newTotal,
      maxScore: maxScore,
      percentage: percentage,
      grade: grade,
      metadata: {
        ...result.metadata,
        'scoredWithKeyFingerprint': assessment.answerKeyFingerprint,
        'scoredWithKeyRevision': assessment.answerKeyRevision,
        'recalculatedAt': DateTime.now().toIso8601String(),
        'recalculatedFromRevision': result.metadata['scoredWithKeyRevision'],
      },
    );
  }
}
```

---

## I. Teacher-Facing UI Behavior

### When no results exist

**Save the changed answer key normally.** No recalculation prompt needed. The teacher is setting up the key before scanning.

### When results exist

After the teacher edits the answer key and taps "Done" on AnswerKeyScreen:

**Step 1: Fingerprint comparison.**

Compare the pre-edit fingerprint (captured before opening the editor) with the post-edit fingerprint. If identical → "Answer key unchanged" snackbar, no further action.

**Step 2: If fingerprints differ, show dialog:**

```
Title: "Answer key changed"

Content:
"{N} papers were graded using the previous answer key.
Their scores must be recalculated."

Actions:
  [Recalculate now]    [Save and recalculate later]    [Cancel]
```

**Step 3: Action behavior:**

| Action | Behavior |
|--------|----------|
| **Recalculate now** | 1. Save the updated assessment (new fingerprint + incremented revision). 2. Immediately run `AnswerKeyRecalculationService.recalculateAll()`. 3. Show progress indicator during recalculation. 4. On completion: show "N papers recalculated" snackbar. 5. Navigate to ReviewScreen with updated results. |
| **Save and recalculate later** | 1. Save the updated assessment (new fingerprint + incremented revision). 2. Mark all existing results with `answerKeyChangedNeedsRegrade: true` in metadata (existing behavior). 3. Navigate to dashboard or previous screen. 4. Next time the teacher opens ReviewScreen for this assessment, the `_issueFor()` resolver will show `_ReviewIssue.answerKey` for all outdated results, and the queue header will show "Do first: regrade answer-key change" action. |
| **Cancel** | 1. Revert the assessment to its pre-edit state (restore original questions). 2. Navigate back without saving. 3. No results affected. |

### From ReviewScreen (existing path)

The existing `_openAnswerKeyEditor()` → `_showAnswerKeyChangedPrompt()` flow is preserved. It already offers "Keep current" and "Regrade all". The new architecture adds:

- "Keep current" now also stamps the new fingerprint on results (instead of just flagging `answerKeyChangedNeedsRegrade`).
- "Regrade all" now uses the `AnswerKeyRecalculationService` instead of re-running the full image pipeline.

### Integrity indicators on result cards

Each result card in ReviewScreen shows:
- **Current:** No indicator (normal)
- **Outdated:** Red chip: "Scores outdated"
- **Unknown (legacy):** Amber chip: "Previous key version"
- **Recalculating:** Spinner chip: "Recalculating..."
- **Recalculation failed:** Red chip: "Recalculation failed" with retry button

### Finalization gate

`_confirmFinalSaveIfNeeded()` is extended to check for `outdated` results:

```dart
final outdatedCount = results.where((r) =>
  resolveIntegrityState(result: r, assessment: assessment) == IntegrityState.outdated
).length;

if (outdatedCount > 0) {
  // Block final save — show dialog:
  // "N papers have outdated scores from a previous answer key.
  //  Recalculate before final save."
  // Only "Recalculate now" and "Review remaining" actions. No "Final save anyway."
}
```

---

## J. Central Service/API Design

### New services

| Service | Responsibility |
|---------|---------------|
| `AnswerKeyFingerprintService` | Computes deterministic fingerprint from Assessment. Pure function, no state. |
| `AnswerKeyRecalculationService` | Orchestrates batch recalculation with checkpointing, progress, and error recovery. |
| `IntegrityStateResolver` | Determines integrity state of a ScanResult given its Assessment. Pure function. |

### Modified services

| Service | Change |
|---------|--------|
| `ScoringService.scoreAnswers()` | No change to signature. Caller stamps fingerprint in metadata. |
| `HybridGradingService.gradePaper()` | Stamps `scoredWithKeyFingerprint` and `scoredWithKeyRevision` in result metadata at lines 172-186. |
| `AssessmentProvider.saveAssessment()` | Increments `answerKeyRevision` and recomputes `answerKeyFingerprint` when questions or rubricType change. |
| `AssessmentProvider` | Adds `ensureFingerprintCurrent()` for lazy legacy migration. |
| `ReviewScreen._issueFor()` | Uses `IntegrityStateResolver` instead of raw metadata check. |
| `ReviewScreen._confirmFinalSaveIfNeeded()` | Blocks final save when `outdated` results exist. |
| `AnswerKeyScreen` | Captures pre-edit fingerprint. After save, compares and shows recalculation dialog. |
| `ReviewScreen._openAnswerKeyEditor()` | Updated to use new recalculation service. |

### No changes to

- `BatchReviewService` — operates on results, not keys
- `StudentMatcher` — unrelated
- `AuditService` — already records score changes
- `DraftService` — stores drafts, not affected
- `BackupService` — serialization format unchanged (new metadata keys are just map entries)

---

## K. Exact Files to Change

### New files

| File | Purpose |
|------|---------|
| `lib/services/answer_key_fingerprint_service.dart` | Canonical fingerprint computation |
| `lib/services/answer_key_recalculation_service.dart` | Batch recalculation with checkpointing |
| `lib/services/integrity_state_resolver.dart` | Per-result integrity state determination |
| `test/services/answer_key_fingerprint_service_test.dart` | Fingerprint computation tests |
| `test/services/answer_key_recalculation_service_test.dart` | Recalculation tests |
| `test/services/integrity_state_resolver_test.dart` | Integrity state tests |

### Modified files

| File | Change |
|------|--------|
| `lib/models/assessment.dart` | Add `answerKeyRevision` (HiveField 18), `answerKeyFingerprint` (HiveField 19) fields. Update constructor, copyWith, toMap, fromMap. |
| `lib/models/assessment.g.dart` | **Regenerated** — add fields 18, 19 to adapter. |
| `lib/services/scoring_service.dart` | No change to core logic. Possibly add helper for re-scoring a single result from persisted data. |
| `lib/services/hybrid_grading_service.dart` | Stamp `scoredWithKeyFingerprint` and `scoredWithKeyRevision` in metadata (lines 172-186). |
| `lib/services/assessment_provider.dart` | Add `ensureFingerprintCurrent()`. Increment revision in `saveAssessment()`/`updateAssessment()` when key changes. |
| `lib/screens/assessment/answer_key_screen.dart` | Capture pre-edit fingerprint. After save, compare fingerprints and show recalculation dialog when results exist. |
| `lib/screens/review/review_screen.dart` | Update `_issueFor()` to use `IntegrityStateResolver`. Update `_confirmFinalSaveIfNeeded()` to block on outdated results. Update `_openAnswerKeyEditor()` to use recalculation service. Update result card to show integrity badges. |
| `lib/config/hive_adapters.dart` | No change needed — AssessmentAdapter is generated from annotations. |

### Files that do NOT change

- `lib/models/scan_result.dart` — no new typed fields (uses metadata map)
- `lib/models/scan_result.g.dart` — no change
- `lib/services/batch_review_service.dart` — no change
- `lib/services/student_matcher.dart` — no change
- `lib/services/audit_service.dart` — no change (already records overrides)
- `lib/services/backup_service.dart` — no change (serialization format compatible)
- `lib/config/routes.dart` — no change

---

## L. Tests Required

### Unit tests

| Test file | Tests |
|-----------|-------|
| `answer_key_fingerprint_service_test.dart` | 1. Deterministic: same assessment → same fingerprint. 2. Different correctAnswer → different fingerprint. 3. Different question order → different fingerprint. 4. Different rubricType → different fingerprint. 5. Different points → different fingerprint. 6. MCQ normalization (case, whitespace). 7. Matching canonical form. 8. Short answer list ordering. 9. Empty key → consistent fingerprint. 10. Legacy assessment (empty fingerprint) → computed on demand. |
| `answer_key_recalculation_service_test.dart` | 1. Recalculate MCQ results with new key. 2. Recalculate TF results. 3. Recalculate short answer results. 4. Recalculate matching results. 5. Preserve manual entry results. 6. Preserve teacher-overridden answers. 7. Preserve force-toggled correct/incorrect. 8. Partial credit preserved. 9. Essay results preserved. 10. Checkpoint: resume from midpoint after interruption. 11. Failed individual result: skip and continue. 12. Empty results list: no-op. 13. Results with missing questions: graceful handling. 14. Weighted scoring recalculated correctly. 15. Grade recalculated with correct rubric. |
| `integrity_state_resolver_test.dart` | 1. Matching fingerprint → current. 2. Missing fingerprint on result → unknown. 3. Mismatched fingerprint → outdated. 4. Manual entry → current (not recalculated). 5. Teacher-overridden answer → current_but_needs_manual_review. 6. Recalculating state. 7. Recalculation failed state. 8. Legacy baseline (both missing). |

### Widget tests

| Test file | Tests |
|-----------|-------|
| `answer_key_screen_test.dart` (new or extended) | 1. Pre-edit fingerprint captured. 2. Post-edit comparison triggers dialog. 3. "Recalculate now" action. 4. "Save and recalculate later" action. 5. "Cancel" reverts changes. 6. No dialog when no results exist. 7. No dialog when fingerprint unchanged. |
| `review_screen_test.dart` (extended) | 1. Outdated results show red badge. 2. Current results show no badge. 3. Final save blocked when outdated results exist. 4. Recalculation progress shown. 5. Queue header shows "regrade" action when outdated. |

### Integration tests

| Test | Description |
|------|-------------|
| Full recalculation flow | Create assessment → grade 3 papers → edit answer key → recalculate → verify all scores updated → verify integrity states → verify audit trail |
| Interruption recovery | Start recalculation → force close mid-way → restart → verify remaining results recalculated |
| Legacy migration | Load assessment with no fingerprint → verify fingerprint computed → verify results treated as current |

---

## M. Safest Implementation Sequence

### Slice 1: Fingerprint computation and persistence (no behavioral change)

1. Add `answerKeyRevision` and `answerKeyFingerprint` to Assessment model.
2. Regenerate Hive adapter.
3. Implement `AnswerKeyFingerprintService.compute()`.
4. Add `ensureFingerprintCurrent()` to AssessmentProvider.
5. Stamp fingerprint on assessment save (AssessmentProvider).
6. **Tests:** Fingerprint computation, Assessment persistence, lazy migration.
7. **Validation:** `flutter test` — no regressions.

### Slice 2: Result fingerprint stamping (no behavioral change)

1. Stamp `scoredWithKeyFingerprint` and `scoredWithKeyRevision` in HybridGradingService.gradePaper() metadata.
2. **Tests:** Metadata stamping on new results.
3. **Validation:** `flutter test` — no regressions.

### Slice 3: Integrity state resolver (no behavioral change)

1. Implement `IntegrityStateResolver.resolve()`.
2. Add integrity state checks to ReviewScreen result cards (display only).
3. **Tests:** All integrity state scenarios.
4. **Validation:** `flutter test` — no regressions.

### Slice 4: Answer-key change detection and dialog (behavioral change)

1. Update AnswerKeyScreen to capture pre-edit fingerprint.
2. After save, compare fingerprints and show recalculation dialog.
3. Implement "Recalculate now" and "Save and recalculate later" actions.
4. **Tests:** Dialog shown/hidden correctly, cancel reverts, actions execute.
5. **Validation:** `flutter test` — no regressions.

### Slice 5: Recalculation service (behavioral change)

1. Implement `AnswerKeyRecalculationService.recalculateAll()`.
2. Wire "Recalculate now" to the service.
3. Add progress indicator.
4. Add checkpoint-based recovery.
5. **Tests:** Full recalculation, partial failure, interruption recovery.
6. **Validation:** `flutter test` — no regressions.

### Slice 6: Finalization gate (behavioral change)

1. Update `_confirmFinalSaveIfNeeded()` to block on outdated results.
2. Update queue header to show recalculation action.
3. **Tests:** Final save blocked when outdated, allowed when current.
4. **Validation:** `flutter test` — no regressions.

### Slice 7: ReviewScreen integration (behavioral change)

1. Update `_openAnswerKeyEditor()` to use recalculation service.
2. Update `_issueFor()` to use IntegrityStateResolver.
3. Add integrity badges to result cards.
4. **Tests:** All review screen scenarios.
5. **Validation:** `flutter test` — no regressions. Full suite: 920+ pass.

---

## N. Remaining Uncertainties

1. **Essay rescoring with deleted images.** If temporary paper images were deleted after initial save, essay questions cannot be re-read by the teacher. The `detectedAnswer` may contain lossy OCR text. This is an existing limitation — the architecture cannot fix it without requiring image retention. **Recommendation:** Document this limitation. Consider requiring image retention for assessments with essay questions.

2. **Weighted scoring interaction.** The `computeWeightedPercentage()` method distributes questions to components by `topicTag`. If a question's `topicTag` changes alongside the answer key, the weighted distribution changes. The current architecture recomputes weighted scoring during recalculation, which handles this correctly. However, if the `WeightedGradeScale` itself changes (different component weights), that is a separate operation not covered by answer-key recalculation.

3. **Concurrent edits.** If the teacher edits the answer key on one device while another device has stale results, the architecture handles this correctly (fingerprint mismatch → outdated). But there is no real-time sync — this is offline-first. The uncertainty is: when would the second device learn about the change? Answer: only when it loads the assessment from Hive, which is the same device. Multi-device is deferred to a future cloud-sync phase.

4. **Custom grading scale changes.** If the teacher changes the grading scale (rubricType) alongside the answer key, the recalculation uses the new scale. This is correct behavior — the rubric is part of the scoring key. But if the teacher changes ONLY the rubric (not the answers), the fingerprint changes (rubricType is included in canonical form), triggering recalculation. This is the desired behavior.

5. **AnswerKeyScreen essayRubric drop.** The current `AnswerKeyScreen.onChanged` callback (line 138-148) constructs a new `Question(...)` without passing `essayRubric`. This silently drops essay rubric data when any answer is edited. This is a pre-existing bug unrelated to this architecture, but it affects fingerprint correctness for essay questions. **Must be fixed as part of Slice 1.**

6. **Performance on large batches.** Recalculating 50+ results involves 50+ Hive writes. On low-end Android devices, this could take several seconds. The checkpoint-based approach ensures progress is visible and resumable, but the UI must not block the main isolate. Consider using `compute()` or `Isolate.run()` for the pure scoring computation, with Hive writes on the main isolate.

7. **ScanResult.answers list immutability.** The recalculation service creates new `AnswerMatch` objects for each question. This is correct but means the entire `answers` list is rebuilt. For 40-question assessments with 50 papers, this is 2000 AnswerMatch objects created. This is negligible in Dart but worth noting for memory profiling.
