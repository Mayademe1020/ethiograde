import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/assessment.dart';

/// Minimal service for tracking an in-progress scan session.
///
/// Persisted to Hive so that if the app crashes or is killed during
/// scanning, the teacher can resume where they left off.
///
/// Session lifecycle:
/// 1. Teacher starts scanning → saveSession()
/// 2. Each capture → updateSession() (add image path)
/// 3. Batch processing starts → completeSession() (delete)
/// 4. App restart → getActiveSession() → show resume dialog
///
/// Stored in the `metadata` Hive box to avoid opening a new box.
/// Key: 'active_scan_session'
class SessionService {
  static final SessionService _instance = SessionService._();
  factory SessionService() => _instance;
  SessionService._();

  static const String _boxName = 'metadata';
  static const String _sessionKey = 'active_scan_session';

  /// Save or update the active scan session.
  ///
  /// [assessmentId] — which assessment this session belongs to
  /// [imagePaths] — all images captured so far
  /// [assessmentTitle] — display name for the resume dialog
  Future<void> saveSession({
    required String assessmentId,
    required String assessmentTitle,
    required List<String> imagePaths,
  }) async {
    try {
      final box = Hive.box(_boxName);
      final session = {
        'assessmentId': assessmentId,
        'assessmentTitle': assessmentTitle,
        'imagePaths': imagePaths,
        'capturedAt': DateTime.now().toIso8601String(),
        'completed': false,
      };
      await box.put(_sessionKey, session);
      debugPrint('Session: saved — ${imagePaths.length} images for "$assessmentTitle"');
    } catch (e, st) {
      debugPrint('Session: save failed ($e)\n$st');
    }
  }

  /// Mark the session as completed (batch processing started).
  /// This prevents the resume dialog from showing.
  Future<void> completeSession() async {
    try {
      final box = Hive.box(_boxName);
      await box.delete(_sessionKey);
      debugPrint('Session: completed and deleted');
    } catch (e) {
      debugPrint('Session: completeSession failed ($e)');
    }
  }

  /// Get the active (incomplete) scan session, if any.
  ///
  /// Returns null if:
  /// - No session exists
  /// - Session is marked completed
  /// - Session data is corrupt
  /// - All image files have been deleted (nothing to resume)
  Future<ScanSession?> getActiveSession() async {
    try {
      final box = Hive.box(_boxName);
      final data = box.get(_sessionKey);
      if (data == null) return null;

      final map = Map<String, dynamic>.from(data as Map);

      if (map['completed'] == true) return null;

      final imagePaths = List<String>.from(map['imagePaths'] ?? []);
      // Verify at least one image file still exists
      final existingPaths = <String>[];
      for (final path in imagePaths) {
        if (await File(path).exists()) {
          existingPaths.add(path);
        }
      }

      if (existingPaths.isEmpty) {
        // All images gone — clean up the stale session
        await completeSession();
        return null;
      }

      // Update paths if some images were cleaned up
      if (existingPaths.length < imagePaths.length) {
        debugPrint('Session: ${imagePaths.length - existingPaths.length} images missing, updating');
        await saveSession(
          assessmentId: map['assessmentId'] ?? '',
          assessmentTitle: map['assessmentTitle'] ?? '',
          imagePaths: existingPaths,
        );
      }

      return ScanSession(
        assessmentId: map['assessmentId'] ?? '',
        assessmentTitle: map['assessmentTitle'] ?? '',
        imagePaths: existingPaths,
        capturedAt: DateTime.tryParse(map['capturedAt'] ?? '') ?? DateTime.now(),
      );
    } catch (e, st) {
      debugPrint('Session: getActiveSession failed ($e)\n$st');
      return null;
    }
  }

  /// Discard the active session and clean up captured images.
  ///
  /// Called when the teacher chooses "Discard" on the resume dialog.
  /// Deletes image files and removes the session from Hive.
  Future<void> discardSession() async {
    try {
      final session = await getActiveSession();
      if (session != null) {
        // Clean up image files
        for (final path in session.imagePaths) {
          try {
            final file = File(path);
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
        debugPrint('Session: discarded ${session.imagePaths.length} images');
      }
      await completeSession();
    } catch (e) {
      debugPrint('Session: discardSession failed ($e)');
    }
  }
}

/// Represents an in-progress scan session that can be resumed.
class ScanSession {
  final String assessmentId;
  final String assessmentTitle;
  final List<String> imagePaths;
  final DateTime capturedAt;

  const ScanSession({
    required this.assessmentId,
    required this.assessmentTitle,
    required this.imagePaths,
    required this.capturedAt,
  });

  int get imageCount => imagePaths.length;
}
