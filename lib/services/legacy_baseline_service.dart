import 'package:hive/hive.dart';

import '../config/constants.dart';
import '../models/assessment.dart';
import 'answer_key_fingerprint_service.dart';

/// Detects and establishes baseline integrity state for legacy assessments
/// and results that lack fingerprint/revision metadata.
///
/// This service must be called explicitly at app startup or on first access
/// to a legacy assessment. It NEVER mutates storage as a side effect of
/// ordinary model reads.
class LegacyBaselineService {
  LegacyBaselineService({
    AnswerKeyFingerprintService? fingerprintService,
  }) : _fingerprintService = fingerprintService ?? const AnswerKeyFingerprintService();

  final AnswerKeyFingerprintService _fingerprintService;

  /// Establish baseline fingerprint and revision for a legacy assessment.
  ///
  /// Returns the updated assessment if changes were made, or the original
  /// if no update was needed.
  ///
  /// Safe to call multiple times — idempotent.
  Assessment ensureBaseline(Assessment assessment) {
    if (assessment.answerKeyFingerprint.isNotEmpty) {
      return assessment; // Already has fingerprint
    }

    final fingerprint = _fingerprintService.compute(assessment);
    return assessment.copyWith(
      answerKeyRevision: 1,
      answerKeyFingerprint: fingerprint,
    );
  }

  /// Batch-establish baselines for all assessments in the box.
  ///
  /// Returns the count of assessments that were updated.
  Future<int> ensureAllBaselines() async {
    final box = Hive.box(AppConstants.assessmentsBox);
    int updated = 0;

    for (final key in box.keys) {
      final data = box.get(key);
      if (data == null) continue;

      final map = Map<String, dynamic>.from(data as Map);
      final assessment = Assessment.fromMap(map);

      if (assessment.answerKeyFingerprint.isNotEmpty) continue;

      final baseline = ensureBaseline(assessment);
      await box.put(key, baseline.toMap());
      updated++;
    }

    return updated;
  }

  /// Determine if an assessment is a legacy assessment (no fingerprint).
  static bool isLegacy(Assessment assessment) {
    return assessment.answerKeyFingerprint.isEmpty;
  }
}
