/// Centralized constants for ScanResult.metadata and Assessment.metadata keys
/// related to answer-key integrity and manual overrides.
///
/// All metadata key access MUST use these constants. No string literals.
class IntegrityMetadataKeys {
  IntegrityMetadataKeys._();

  // ── Answer-key integrity (on ScanResult.metadata) ──

  /// The answer-key fingerprint at the time this result was scored.
  static const String scoredWithKeyFingerprint = 'ik_scoredWithKeyFingerprint';

  /// The answer-key revision at the time this result was scored.
  static const String scoredWithKeyRevision = 'ik_scoredWithKeyRevision';

  // ── Manual override tracking (on ScanResult.metadata) ──

  /// true if this result contains any teacher-overridden answers.
  static const String hasManualOverrides = 'ik_hasManualOverrides';

  /// true if this result was manually entered (not scanned).
  static const String isManualEntry = 'ik_isManualEntry';

  /// true if this result's final score was manually set by the teacher,
  /// bypassing question-level scoring.
  static const String finalScoreManuallySet = 'ik_finalScoreManuallySet';

  // ── Per-answer override tracking (on AnswerMatch, stored in metadata) ──

  /// Map<int, String> — questionNumber → override type.
  /// Override types: 'auto', 'teacher_corrected', 'force_override',
  ///                 'partial_credit', 'essay_manual'.
  static const String answerOverrideTypes = 'ik_answerOverrideTypes';

  // ── Recalculation state (on Assessment.metadata) ──

  /// true while recalculation is in progress.
  static const String recalculationInProgress = 'ik_recalculationInProgress';

  /// Number of results processed so far during recalculation.
  static const String recalculationProcessedCount = 'ik_recalculationProcessedCount';

  /// Total number of results to process during recalculation.
  static const String recalculationTotalCount = 'ik_recalculationTotalCount';

  /// true when recalculation completed successfully.
  static const String recalculationComplete = 'ik_recalculationComplete';

  /// true when recalculation failed.
  static const String recalculationFailed = 'ik_recalculationFailed';

  /// Timestamp of last successful recalculation.
  static const String recalculationCompletedAt = 'ik_recalculationCompletedAt';

  // ── Legacy compatibility (on Assessment.metadata) ──

  /// true if this assessment has been baseline-migrated (fingerprint computed).
  static const String legacyBaselineApplied = 'ik_legacyBaselineApplied';
}

/// Override types for individual answer matches.
class AnswerOverrideType {
  AnswerOverrideType._();

  static const String auto = 'auto';
  static const String teacherCorrected = 'teacher_corrected';
  static const String forceOverride = 'force_override';
  static const String partialCredit = 'partial_credit';
  static const String essayManual = 'essay_manual';
}
