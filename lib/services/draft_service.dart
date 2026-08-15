import 'app_log.dart';
import 'error_handler.dart';
import 'hive_box_mixin.dart';

/// Auto-save service for grading drafts.
///
/// Handles the "phone dies mid-grading" edge case:
/// - Saves partial grading progress every few scans
/// - Recovers drafts on app restart
/// - Teacher can resume where they left off
///
/// Drafts are stored in the encrypted Hive `grading_drafts` box.
/// Each draft is keyed by assessmentId and contains the list of
/// completed scan results so far.
class DraftService with HiveBoxMixin {
  static final DraftService _instance = DraftService._();
  factory DraftService() => _instance;
  DraftService._();

  static const String _boxName = 'grading_drafts';

  /// Save a grading draft for an assessment.
  ///
  /// [completedResults] are the scan results graded so far.
  /// [currentStudentIndex] tracks where the teacher was in the batch.
  Future<void> saveDraft({
    required String assessmentId,
    required List<Map<String, dynamic>> completedResults,
    required int currentStudentIndex,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final box = await openBox(_boxName);
      await box.put(assessmentId, {
        'assessmentId': assessmentId,
        'completedResults': completedResults,
        'currentStudentIndex': currentStudentIndex,
        'savedAt': DateTime.now().toIso8601String(),
        'metadata': metadata ?? {},
      });
      AppLog.info(this, 'saveDraft', 'saved $assessmentId (${completedResults.length} results, index $currentStudentIndex)');
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'saveDraft', e, st);
      // Never crash on draft save failure
    }
  }

  /// Check if a draft exists for an assessment.
  Future<bool> hasDraft(String assessmentId) async {
    try {
      final box = await openBox(_boxName);
      return box.containsKey(assessmentId);
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'hasDraft', e, st);
      return false;
    }
  }

  /// Load a grading draft.
  ///
  /// Returns null if no draft exists.
  Future<GradingDraft?> loadDraft(String assessmentId) async {
    try {
      final box = await openBox(_boxName);
      final data = box.get(assessmentId);
      if (data == null) return null;

      final map = Map<String, dynamic>.from(data as Map);
      final meta = Map<String, dynamic>.from(map['metadata'] ?? {});
      return GradingDraft(
        assessmentId: map['assessmentId'] ?? '',
        classId: meta['classId'] ?? map['classId'] ?? '',
        completedResults: List<Map<String, dynamic>>.from(
          map['completedResults'] ?? [],
        ),
        currentStudentIndex: map['currentStudentIndex'] ?? 0,
        savedAt: DateTime.tryParse(map['savedAt'] ?? '') ?? DateTime.now(),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'loadDraft', e, st);
      return null;
    }
  }

  /// Delete a draft after grading is complete.
  Future<void> clearDraft(String assessmentId) async {
    try {
      final box = await openBox(_boxName);
      await box.delete(assessmentId);
      AppLog.info(this, 'clearDraft', 'cleared $assessmentId');
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'clearDraft', e, st);
    }
  }

  /// Get all draft assessments (for showing "resume grading" prompts).
  Future<List<GradingDraft>> getAllDrafts() async {
    try {
      final box = await openBox(_boxName);
      return box.values.map((data) {
        final map = Map<String, dynamic>.from(data as Map);
        final meta = Map<String, dynamic>.from(map['metadata'] ?? {});
        return GradingDraft(
          assessmentId: map['assessmentId'] ?? '',
          classId: meta['classId'] ?? map['classId'] ?? '',
          completedResults: List<Map<String, dynamic>>.from(
            map['completedResults'] ?? [],
          ),
          currentStudentIndex: map['currentStudentIndex'] ?? 0,
          savedAt: DateTime.tryParse(map['savedAt'] ?? '') ?? DateTime.now(),
          metadata: meta,
        );
      }).toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'getAllDrafts', e, st);
      return [];
    }
  }

  /// Clear all drafts (used in clear-all-data).
  Future<void> clearAll() async {
    try {
      final box = await openBox(_boxName);
      await box.clear();
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'clearAll', e, st);
    }
  }
}

/// A saved grading session draft.
class GradingDraft {
  final String assessmentId;
  final String classId;
  final List<Map<String, dynamic>> completedResults;
  final int currentStudentIndex;
  final DateTime savedAt;
  final Map<String, dynamic> metadata;

  const GradingDraft({
    required this.assessmentId,
    this.classId = '',
    required this.completedResults,
    required this.currentStudentIndex,
    required this.savedAt,
    this.metadata = const {},
  });

  /// Number of students graded so far.
  int get completedCount => completedResults.length;

  /// How long ago the draft was saved.
  Duration get age => DateTime.now().difference(savedAt);

  /// Human-readable age string.
  String get ageLabel {
    if (age.inMinutes < 1) return 'just now';
    if (age.inMinutes < 60) return '${age.inMinutes}m ago';
    if (age.inHours < 24) return '${age.inHours}h ago';
    return '${age.inDays}d ago';
  }
}
