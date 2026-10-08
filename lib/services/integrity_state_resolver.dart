import '../config/integrity_metadata_keys.dart';
import '../models/assessment.dart';
import '../models/scan_result.dart';

/// Integrity state of a scan result relative to its assessment's answer key.
enum IntegrityState {
  /// Fingerprint matches current key. Scores are trustworthy.
  current,

  /// Fingerprint missing on result (legacy) but assessment has a baseline.
  /// Cannot verify correctness — treat with caution.
  legacyUnknown,

  /// Fingerprint on result does not match current assessment key.
  /// Scores are outdated and must be recalculated.
  outdated,

  /// Recalculation is in progress for this assessment.
  recalculating,

  /// Recalculation failed for this assessment.
  recalculationFailed,

  /// Auto-rescored but contains teacher-overridden answers that were preserved.
  currentNeedsManualReview,
}

/// Centralized resolver for scan-result integrity state.
///
/// All integrity checks MUST go through this resolver.
/// No widget or screen should compute fingerprint comparisons directly.
class IntegrityStateResolver {
  const IntegrityStateResolver();

  /// Resolve the integrity state of a single result against its assessment.
  IntegrityState resolve({
    required ScanResult result,
    required Assessment assessment,
  }) {
    // Check assessment-level recalculation state first
    final assessmentMeta = assessment.settings;
    if (assessmentMeta[IntegrityMetadataKeys.recalculationInProgress] == true) {
      return IntegrityState.recalculating;
    }
    if (assessmentMeta[IntegrityMetadataKeys.recalculationFailed] == true) {
      return IntegrityState.recalculationFailed;
    }

    final resultFp = result.metadata[IntegrityMetadataKeys.scoredWithKeyFingerprint] as String?;
    final keyFp = assessment.answerKeyFingerprint;

    // No fingerprint on result → legacy
    if (resultFp == null || resultFp.isEmpty) {
      if (keyFp.isNotEmpty) {
        return IntegrityState.legacyUnknown;
      }
      // Both missing — legacy baseline, trust current
      return IntegrityState.current;
    }

    // Fingerprint matches → current
    if (resultFp == keyFp) {
      // Check if any answers were teacher-overridden
      if (_hasManualOverrides(result)) {
        return IntegrityState.currentNeedsManualReview;
      }
      return IntegrityState.current;
    }

    // Fingerprint mismatch → outdated
    return IntegrityState.outdated;
  }

  /// Check if any answers in this result have manual overrides.
  bool _hasManualOverrides(ScanResult result) {
    if (result.metadata[IntegrityMetadataKeys.hasManualOverrides] == true) {
      return true;
    }
    if (result.isManualEntry) return true;
    if (result.metadata[IntegrityMetadataKeys.finalScoreManuallySet] == true) {
      return true;
    }
    return false;
  }

  /// Check if a result is eligible for automatic recalculation.
  ///
  /// A result is eligible if:
  /// - It is not a manual entry
  /// - It has no teacher-overridden answers
  /// - It has an imagePath (or is objective with clean detected answers)
  bool isEligibleForRecalculation(ScanResult result) {
    if (result.isManualEntry) return false;
    if (result.metadata[IntegrityMetadataKeys.hasManualOverrides] == true) {
      return false;
    }
    if (result.metadata[IntegrityMetadataKeys.finalScoreManuallySet] == true) {
      return false;
    }
    // Check per-answer overrides
    final overrideTypes = result.metadata[IntegrityMetadataKeys.answerOverrideTypes];
    if (overrideTypes is Map) {
      for (final entry in overrideTypes.entries) {
        final type = entry.value?.toString();
        if (type != null && type != AnswerOverrideType.auto) {
          return false;
        }
      }
    }
    return true;
  }

  /// Check if all results for an assessment are current (no outdated).
  bool allCurrent({
    required List<ScanResult> results,
    required Assessment assessment,
  }) {
    for (final result in results) {
      final state = resolve(result: result, assessment: assessment);
      if (state == IntegrityState.outdated ||
          state == IntegrityState.recalculating ||
          state == IntegrityState.recalculationFailed) {
        return false;
      }
    }
    return true;
  }

  /// Count results in each state.
  Map<IntegrityState, int> countByState({
    required List<ScanResult> results,
    required Assessment assessment,
  }) {
    final counts = <IntegrityState, int>{};
    for (final result in results) {
      final state = resolve(result: result, assessment: assessment);
      counts[state] = (counts[state] ?? 0) + 1;
    }
    return counts;
  }
}
