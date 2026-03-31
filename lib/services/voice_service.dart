import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

class VoiceService {
  static final VoiceService _instance = VoiceService._();
  factory VoiceService() => _instance;
  VoiceService._();

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  bool _isListening = false;
  bool _isRecording = false;
  bool _isPlaying = false;
  String _currentLocale = 'en_US';
  String? _currentPlayingPath;

  bool get isListening => _isListening;
  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
  String? get currentPlayingPath => _currentPlayingPath;

  /// Stream of playback state changes (true = playing, false = stopped).
  Stream<bool> get playingStateStream => _player.playerStateStream.map(
        (state) => state.playing,
      );

  /// Whether audio playback is supported on this device.
  bool get isPlaybackSupported => true;

  /// Initialize voice services
  Future<bool> initialize({String locale = 'en_US'}) async {
    _currentLocale = locale;

    // Init speech recognition
    final available = await _speech.initialize(
      onError: (error) => debugPrint('Speech error: $error'),
      onStatus: (status) => debugPrint('Speech status: $status'),
    );

    // Init TTS
    await _tts.setLanguage(locale == 'am_ET' ? 'am-ET' : 'en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    return available;
  }

  /// Set locale for speech recognition and TTS
  Future<void> setLocale(String locale) async {
    _currentLocale = locale;
    await _tts.setLanguage(locale == 'am_ET' ? 'am-ET' : 'en-US');
  }

  // ──── Speech to Text ────

  /// Start listening for speech input
  Future<void> startListening({
    required Function(String text) onResult,
    Function()? onDone,
    String? locale,
  }) async {
    if (_isListening) return;

    _isListening = true;
    await _speech.listen(
      onResult: (result) {
        onResult(result.recognizedWords);
        if (result.finalResult) {
          _isListening = false;
          onDone?.call();
        }
      },
      localeId: locale ?? _currentLocale,
      listenMode: stt.ListenMode.confirmation,
      cancelOnError: true,
    );
  }

  /// Stop listening
  Future<void> stopListening() async {
    _isListening = false;
    await _speech.stop();
  }

  /// Get available locales for speech recognition
  Future<List<stt.LocaleName>> getAvailableLocales() async {
    return await _speech.locales();
  }

  // ──── Text to Speech ────

  /// Speak text aloud
  Future<void> speak(String text, {String? locale}) async {
    if (locale != null) {
      await _tts.setLanguage(locale == 'am_ET' ? 'am-ET' : 'en-US');
    }
    await _tts.speak(text);
  }

  /// Stop speaking
  Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  // ──── Audio Recording ────

  /// Start recording voice note
  Future<void> startRecording() async {
    if (_isRecording) return;

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${dir.path}/voice_note_$timestamp.m4a';

    if (await _recorder.hasPermission()) {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );
      _isRecording = true;
    }
  }

  /// Stop recording and return file path
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    _isRecording = false;
    final path = await _recorder.stop();
    return path;
  }

  /// Get recording amplitude for waveform display
  Future<double> getAmplitude() async {
    final amplitude = await _recorder.getAmplitude();
    return amplitude.current;
  }

  /// Play a recorded voice note.
  /// Returns a Future that completes when playback starts, or throws on error.
  Future<void> playRecording(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw VoicePlaybackException('Voice note file not found');
    }

    // Stop any current playback first.
    if (_isPlaying) {
      await stopPlayback();
    }

    try {
      _currentPlayingPath = path;
      _isPlaying = true;
      await _player.setFilePath(path);
      await _player.play();

      // Listen for completion to reset state.
      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _isPlaying = false;
          _currentPlayingPath = null;
        }
      });
    } catch (e) {
      _isPlaying = false;
      _currentPlayingPath = null;
      debugPrint('[Voice] Playback error: $e');
      rethrow;
    }
  }

  /// Stop current playback.
  Future<void> stopPlayback() async {
    _isPlaying = false;
    _currentPlayingPath = null;
    await _player.stop();
  }

  /// Pause current playback.
  Future<void> pausePlayback() async {
    _isPlaying = false;
    await _player.pause();
  }

  /// Resume paused playback.
  Future<void> resumePlayback() async {
    _isPlaying = true;
    await _player.play();
  }

  /// Get playback duration of a voice note file.
  Future<Duration?> getRecordingDuration(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      final source = AudioSource.uri(Uri.file(path));
      await _player.setAudioSource(source);
      final duration = _player.duration;
      await _player.stop();
      return duration;
    } catch (e) {
      debugPrint('[Voice] Duration query error: $e');
      return null;
    }
  }

  // ──── Convenience ────

  /// Read score aloud to teacher
  Future<void> readScore({
    required String studentName,
    required double score,
    required double maxScore,
    required String grade,
    bool isAmharic = false,
  }) async {
    final percentage = (score / maxScore * 100).toStringAsFixed(0);
    String text;

    if (isAmharic) {
      text = '$studentName ውጤት: $score ከ $maxScore. '
          'ፐርሰንት $percentage%. ደረጃ $grade.';
    } else {
      text = '$studentName scored $score out of $maxScore. '
          'Percentage $percentage%. Grade $grade.';
    }

    await speak(text);
  }

  /// Dispose resources
  void dispose() {
    _speech.cancel();
    _tts.stop();
    _recorder.dispose();
    _player.dispose();
  }
}

/// Exception thrown when voice playback fails.
class VoicePlaybackException implements Exception {
  final String message;
  VoicePlaybackException(this.message);

  @override
  String toString() => 'VoicePlaybackException: $message';
}
