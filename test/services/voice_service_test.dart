import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/services/voice_service.dart';

void main() {
  group('VoicePlaybackException', () {
    test('stores message correctly', () {
      final exception = VoicePlaybackException('File not found');
      expect(exception.message, 'File not found');
    });

    test('toString includes message', () {
      final exception = VoicePlaybackException('Test error');
      expect(exception.toString(), contains('Test error'));
      expect(exception.toString(), contains('VoicePlaybackException'));
    });
  });

  group('VoiceService singleton', () {
    test('returns same instance', () {
      final a = VoiceService();
      final b = VoiceService();
      expect(identical(a, b), isTrue);
    });
  });

  group('VoiceService properties', () {
    test('initial state is not listening or recording', () {
      final service = VoiceService();
      expect(service.isListening, isFalse);
      expect(service.isRecording, isFalse);
      expect(service.isPlaying, isFalse);
      expect(service.currentPlayingPath, isNull);
    });

    test('isPlaybackSupported returns true', () {
      final service = VoiceService();
      expect(service.isPlaybackSupported, isTrue);
    });
  });

  group('VoiceService playRecording', () {
    test('throws VoicePlaybackException for missing file', () async {
      final service = VoiceService();
      expect(
        () => service.playRecording('/nonexistent/path/note.m4a'),
        throwsA(isA<VoicePlaybackException>()),
      );
    });
  });
}
