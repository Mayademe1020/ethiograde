import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'settings_provider.dart';

/// Voice service — TTS via flutter_tts for reading scores aloud.
///
/// STT, recording, and playback remain stubs (deferred to v0.3.0).
/// Only flutter_tts is re-enabled (~2MB APK delta, no native SDK bloat).
///
/// Design:
/// - Singleton (one TTS engine instance)
/// - English-only (Amharic removed from codebase)
/// - Safe for 2GB RAM: TTS engine is lightweight
/// - Never blocks UI: all speech is async with completion futures
class VoiceService {
  static final VoiceService _instance = VoiceService._();
  factory VoiceService() => _instance;
  VoiceService._();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _isSpeaking = false;
  bool _shouldStop = false;

  // Stub state (STT/recording/playback — not implemented)
  bool _isListening = false;
  bool _isRecording = false;
  bool _isPlaying = false;

  bool get isListening => _isListening;
  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
  bool get isSpeaking => _isSpeaking;

  /// Stub stream — emits false (not playing). STT/playback deferred.
  Stream<bool> get playingStateChanged => Stream.value(false);

  /// Whether the file at [path] exists and is non-empty.
  static bool fileExists(String path) {
    final f = File(path);
    return f.existsSync() && f.lengthSync() > 0;
  }

  /// Initialize TTS engine. Safe to call multiple times.
  Future<bool> initialize({String locale = 'en-US'}) async {
    if (_initialized) return true;
    try {
      await _tts.setLanguage(locale);
      await _tts.setSpeechRate(0.45); // Slower for clarity
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _initialized = true;
      debugPrint('[Voice] TTS initialized ($locale)');
      return true;
    } catch (e) {
      debugPrint('[Voice] TTS init failed: $e');
      return false;
    }
  }

  /// Change TTS locale (e.g., 'en-US', 'am-ET' if available on device).
  Future<void> setLocale(String locale) async {
    try {
      await _tts.setLanguage(locale);
    } catch (e) {
      debugPrint('[Voice] TTS locale change failed: $e');
    }
  }

  // ──── Speech to Text (stub) ────

  Future<void> startListening({
    required Function(String text) onResult,
    Function()? onDone,
    String? locale,
  }) async {
    debugPrint('[Voice] Stub: startListening ignored (STT deferred to v0.3.0)');
  }

  Future<void> stopListening() async {}

  Future<List<dynamic>> getAvailableLocales() async => [];

  // ──── Text to Speech (real) ────

  /// Speak [text] aloud. Completes when speech finishes or is stopped.
  Future<void> speak(String text, {String? locale}) async {
    await initialize();
    if (locale != null) await _tts.setLanguage(locale);
    _isSpeaking = true;
    _shouldStop = false;

    final completer = Completer<void>();
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      if (!completer.isCompleted) completer.complete();
    });
    _tts.setErrorHandler((msg) {
      _isSpeaking = false;
      debugPrint('[Voice] TTS error: $msg');
      if (!completer.isCompleted) completer.complete();
    });

    await _tts.speak(text);
    return completer.future;
  }

  /// Stop speaking immediately.
  Future<void> stopSpeaking() async {
    _shouldStop = true;
    _isSpeaking = false;
    await _tts.stop();
  }

  // ──── Audio Recording (stub) ────

  Future<void> startRecording() async {
    debugPrint(
      '[Voice] Stub: startRecording ignored (recording deferred to v0.3.0)',
    );
  }

  Future<String?> stopRecording() async => null;

  Future<double> getAmplitude() async => 0.0;

  // ──── Audio Playback (stub) ────

  Future<void> playRecording(String path) async {
    debugPrint(
      '[Voice] Stub: playRecording ignored (playback deferred to v0.3.0)',
    );
  }

  Future<void> stopPlayback() async {
    _isPlaying = false;
  }

  // ──── Convenience (real TTS) ────

  /// Read a single student's score aloud.
  Future<void> readScore({
    required String studentName,
    required double score,
    required double maxScore,
    required String grade,
    VoiceFeedbackMode mode = VoiceFeedbackMode.scoreOnly,
    bool needsReview = false,
  }) async {
    final text = scoreReadoutText(
      score: score,
      maxScore: maxScore,
      grade: grade,
      mode: mode,
      needsReview: needsReview,
    );
    if (text.isEmpty) return;
    await speak(text);
  }

  /// Read all students' scores sequentially.
  ///
  /// [onReadingIndex] fires before each student is spoken (0-based index).
  /// Call [stopSpeaking] to cancel mid-read.
  Future<void> readAllScores({
    required List<String> studentNames,
    required List<double> scores,
    required List<double> maxScores,
    required List<double> percentages,
    required List<String> grades,
    VoiceFeedbackMode mode = VoiceFeedbackMode.scoreOnly,
    List<bool>? needsReview,
    void Function(int index)? onReadingIndex,
  }) async {
    if (mode == VoiceFeedbackMode.off) return;
    await initialize();
    _shouldStop = false;

    for (int i = 0; i < studentNames.length; i++) {
      if (_shouldStop) break;

      onReadingIndex?.call(i);

      final score = scores[i];
      final maxScore = maxScores[i];
      final grade = grades[i];
      final text = scoreReadoutText(
        score: score,
        maxScore: maxScore,
        grade: grade,
        mode: mode,
        needsReview: needsReview != null && i < needsReview.length
            ? needsReview[i]
            : false,
      );
      if (text.isEmpty) continue;

      await speak(text);
      // Small pause between students for clarity
      if (!_shouldStop && i < studentNames.length - 1) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }

    _isSpeaking = false;
  }

  /// Dispose TTS engine.
  void dispose() {
    _tts.stop().catchError((e) {
      debugPrint('[Voice] TTS dispose stop failed: $e');
    });
    _initialized = false;
  }

  /// Builds safe classroom speech. It never includes student name or id.
  @visibleForTesting
  static String scoreReadoutText({
    required double score,
    required double maxScore,
    required String grade,
    required VoiceFeedbackMode mode,
    bool needsReview = false,
  }) {
    final statusText = needsReview ? 'needs review' : 'graded';
    final scoreText = _formatScore(score);
    final gradeText = grade.trim().isEmpty ? 'not graded' : grade.trim();

    switch (mode) {
      case VoiceFeedbackMode.off:
        return '';
      case VoiceFeedbackMode.statusOnly:
        return statusText;
      case VoiceFeedbackMode.scoreOnly:
        return needsReview ? '$scoreText, needs review' : scoreText;
      case VoiceFeedbackMode.gradeOnly:
        return needsReview ? '$gradeText, needs review' : gradeText;
      case VoiceFeedbackMode.scoreAndGrade:
        final text = '$scoreText, $gradeText';
        return needsReview ? '$text, needs review' : text;
    }
  }

  static String _formatScore(double score) {
    if (score == score.roundToDouble()) {
      return score.toInt().toString();
    }
    return score.toStringAsFixed(1);
  }
}
