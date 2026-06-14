import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../config/constants.dart';
import '../config/integrity_metadata_keys.dart';
import '../models/assessment.dart';
import '../models/scan_result.dart';
import 'integrity_state_resolver.dart';
import 'scoring_service.dart';

/// Result of a batch recalculation operation.
class RecalculationResult {
  final List<ScanResult> updatedResults;
  final int recalculated;
  final int preserved;
  final int failed;
  final int scoresChanged;
  final int scoresUnchanged;

  const RecalculationResult({
    required this.updatedResults,
    required this.recalculated,
    required this.preserved,
    required this.failed,
    required this.scoresChanged,
    required this.scoresUnchanged,
  });

  int get total => recalculated + preserved + failed;
  bool get allSucceeded => failed == 0;
}

/// Recalculates scan results against a new answer key using persisted
/// student responses. Does NOT require original images.
///
/// Safety guarantees:
/// - Assessment remains outdated/recalculating until ALL results complete
/// - Partial recalculation is resumable
/// - Manual overrides are preserved
/// - Each result is independently stamped with the new key fingerprint
class AnswerKeyRecalculationService {
  AnswerKeyRecalculationService({
    IntegrityStateResolver? integrityResolver,
  })  : _integrityResolver = integrityResolver ?? const IntegrityStateResolver();

  final IntegrityStateResolver _integrityResolver;
  final ScoringService _scoring = const ScoringService();

  /// Recalculate all eligible results for an assessment with a new answer key.
  ///
  /// Steps:
  /// 1. Mark assessment as recalculating
  /// 2. For each result: check eligibility, rescore or preserve
  /// 3. Stamp each recalculated result with new fingerprint/revision
  /// 4. Persist each result individually
  /// 5. Mark assessment as current on completion
  Future<RecalculationResult> recalculateAll({
    required Assessment assessment,
    required List<ScanResult> results,
    void Function(int processed, int total)? onProgress,
  }) async {
    final updatedResults = <ScanResult>[];
    int recalculated = 0;
    int preserved = 0;
    int failed = 0;
    int scoresChanged = 0;
    int scoresUnchanged = 0;

    // Mark assessment as recalculating
    await _setRecalculationState(assessment, inProgress: true, processed: 0, total: results.length);

    final box = Hive.lazyBox('scan_results');

    for (int i = 0; i < results.length; i++) {
      final result = results[i];

      // Idempotency guard: skip results already stamped with current fingerprint
      final resultFp = result.metadata[IntegrityMetadataKeys.scoredWithKeyFingerprint] as String?;
      if (resultFp != null && resultFp.isNotEmpty && resultFp == assessment.answerKeyFingerprint) {
        updatedResults.add(result);
        preserved++;
        await _setRecalculationState(assessment, inProgress: true, processed: i + 1, total: results.length);
        onProgress?.call(i + 1, results.length);
        continue;
      }

      if (_integrityResolver.isEligibleForRecalculation(result)) {
        try {
          final newResult = _recalculateSingle(result, assessment);

          // Check if score actually changed
          if ((newResult.totalScore - result.totalScore).abs() > 0.001) {
            scoresChanged++;
          } else {
            scoresUnchanged++;
          }

          updatedResults.add(newResult);
          recalculated++;

          // Persist individually
          await box.put(newResult.id, newResult.toMap());
        } catch (e) {
          debugPrint('[Recalculation] Failed for ${result.id}: $e');
          updatedResults.add(result); // Preserve original on failure
          failed++;
        }
      } else {
        // Preserve — manual entry or teacher overrides
        updatedResults.add(result);
        preserved++;
      }

      // Update checkpoint
      await _setRecalculationState(assessment, inProgress: true, processed: i + 1, total: results.length);
      onProgress?.call(i + 1, results.length);
    }

    // Mark complete
    await _setRecalculationState(assessment, inProgress: false, processed: results.length, total: results.length);

    return RecalculationResult(
      updatedResults: updatedResults,
      recalculated: recalculated,
      preserved: preserved,
      failed: failed,
      scoresChanged: scoresChanged,
      scoresUnchanged: scoresUnchanged,
    );
  }

  /// Recalculate a single result against the current assessment key.
  ScanResult _recalculateSingle(ScanResult result, Assessment assessment) {
    final newMatches = <AnswerMatch>[];
    final overrideTypes = <int, String>{};

    for (final oldMatch in result.answers) {
      // Find the corresponding question in the new key
      final question = assessment.questions.where(
        (q) => q.number == oldMatch.questionNumber,
      ).firstOrNull;

      if (question == null) {
        // Question removed from key — preserve original match
        newMatches.add(oldMatch);
        continue;
      }

      final newCorrect = question.correctAnswer?.toString() ?? '';
      final isCorrect = _scoring.checkAnswer(
        detected: oldMatch.detectedAnswer,
        correct: question.correctAnswer,
        type: question.type,
      );

      final newScore = isCorrect ? question.points : 0.0;

      newMatches.add(AnswerMatch(
        questionNumber: oldMatch.questionNumber,
        detectedAnswer: oldMatch.detectedAnswer,
        correctAnswer: newCorrect,
        isCorrect: isCorrect,
        score: newScore,
        maxScore: question.points,
        confidence: oldMatch.confidence,
        ocrRawText: oldMatch.ocrRawText,
        boundingBox: oldMatch.boundingBox,
      ));

      // Track override type
      overrideTypes[oldMatch.questionNumber] = AnswerOverrideType.auto;
    }

    final newTotal = newMatches.fold(0.0, (s, a) => s + a.score);
    final maxScore = assessment.maxScore;
    final percentage = maxScore > 0 ? (newTotal / maxScore) * 100 : 0.0;
    final grade = _scoring.calculateGrade(percentage, assessment.rubricType);

    // Build new metadata with integrity stamps
    final newMetadata = Map<String, dynamic>.from(result.metadata);
    newMetadata[IntegrityMetadataKeys.scoredWithKeyFingerprint] = assessment.answerKeyFingerprint;
    newMetadata[IntegrityMetadataKeys.scoredWithKeyRevision] = assessment.answerKeyRevision;
    newMetadata['ik_recalculatedAt'] = DateTime.now().toIso8601String();
    newMetadata['ik_recalculatedFromRevision'] = result.metadata[IntegrityMetadataKeys.scoredWithKeyRevision];
    newMetadata[IntegrityMetadataKeys.answerOverrideTypes] = overrideTypes;

    return result.copyWith(
      answers: newMatches,
      totalScore: newTotal,
      maxScore: maxScore,
      percentage: percentage,
      grade: grade,
      metadata: newMetadata,
    );
  }

  /// Update assessment metadata to reflect recalculation state.
  Future<void> _setRecalculationState(
    Assessment assessment, {
    required bool inProgress,
    required int processed,
    required int total,
  }) async {
    final box = Hive.box(AppConstants.assessmentsBox);
    final newSettings = Map<String, dynamic>.from(assessment.settings);
    newSettings[IntegrityMetadataKeys.recalculationInProgress] = inProgress;
    newSettings[IntegrityMetadataKeys.recalculationProcessedCount] = processed;
    newSettings[IntegrityMetadataKeys.recalculationTotalCount] = total;
    if (!inProgress) {
      newSettings[IntegrityMetadataKeys.recalculationComplete] = true;
      newSettings[IntegrityMetadataKeys.recalculationCompletedAt] = DateTime.now().toIso8601String();
      newSettings.remove(IntegrityMetadataKeys.recalculationFailed);
    }

    final updated = assessment.copyWith(settings: newSettings);
    await box.put(assessment.id, updated.toMap());
  }

  /// Check if a recalculation was interrupted (assessment marked as in-progress
  /// but not complete).
  static bool isInterrupted(Assessment assessment) {
    return assessment.settings[IntegrityMetadataKeys.recalculationInProgress] == true;
  }

  /// Get recalculation progress for an assessment.
  static ({int processed, int total, bool inProgress}) getProgress(Assessment assessment) {
    final inProgress = assessment.settings[IntegrityMetadataKeys.recalculationInProgress] == true;
    final processed = assessment.settings[IntegrityMetadataKeys.recalculationProcessedCount] as int? ?? 0;
    final total = assessment.settings[IntegrityMetadataKeys.recalculationTotalCount] as int? ?? 0;
    return (processed: processed, total: total, inProgress: inProgress);
  }
}
