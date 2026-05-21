import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/services/voice_service.dart';

void main() {
  group('VoiceService.fileExists', () {
    test('returns false for non-existent file', () {
      expect(
        VoiceService.fileExists('/tmp/nonexistent_voice_note.m4a'),
        isFalse);
    });

    test('returns false for empty file', () {
      final tmpFile = File('${Directory.systemTemp.path}/empty_note.m4a');
      tmpFile.createSync();
      try {
        expect(VoiceService.fileExists(tmpFile.path), isFalse);
      } finally {
        tmpFile.deleteSync();
      }
    });

    test('returns true for non-empty file', () {
      final tmpFile = File('${Directory.systemTemp.path}/valid_note.m4a');
      tmpFile.writeAsBytesSync([0x00, 0x01, 0x02, 0x03]);
      try {
        expect(VoiceService.fileExists(tmpFile.path), isTrue);
      } finally {
        tmpFile.deleteSync();
      }
    });
  });

  group('VoiceService singleton', () {
    test('returns same instance', () {
      final a = VoiceService();
      final b = VoiceService();
      expect(identical(a, b), isTrue);
    });

    test('initial state is not speaking', () {
      final voice = VoiceService();
      expect(voice.isSpeaking, isFalse);
      expect(voice.isListening, isFalse);
      expect(voice.isRecording, isFalse);
      expect(voice.isPlaying, isFalse);
    });
  });

  group('VoiceService stub methods', () {
    test('startListening is safe no-op', () async {
      final voice = VoiceService();
      // Should not throw
      await voice.startListening(onResult: (_) {});
      expect(voice.isListening, isFalse);
    });

    test('stopListening is safe no-op', () async {
      final voice = VoiceService();
      await voice.stopListening();
    });

    test('getAvailableLocales returns empty', () async {
      final voice = VoiceService();
      final locales = await voice.getAvailableLocales();
      expect(locales, isEmpty);
    });

    test('startRecording is safe no-op', () async {
      final voice = VoiceService();
      await voice.startRecording();
      expect(voice.isRecording, isFalse);
    });

    test('stopRecording returns null', () async {
      final voice = VoiceService();
      final path = await voice.stopRecording();
      expect(path, isNull);
    });

    test('getAmplitude returns 0', () async {
      final voice = VoiceService();
      final amp = await voice.getAmplitude();
      expect(amp, 0.0);
    });

    test('playRecording is safe no-op', () async {
      final voice = VoiceService();
      await voice.playRecording('/tmp/fake.m4a');
    });

    test('stopPlayback sets isPlaying false', () async {
      final voice = VoiceService();
      await voice.stopPlayback();
      expect(voice.isPlaying, isFalse);
    });

    test('dispose is safe no-op', () {
      final voice = VoiceService();
      voice.dispose();
    });

    test('setLocale is safe no-op', () async {
      final voice = VoiceService();
      await voice.setLocale('am-ET');
    });
  });

  group('VoiceService playingStateChanged stream', () {
    test('emits false', () async {
      final voice = VoiceService();
      final events = await voice.playingStateChanged.toList();
      expect(events, [false]);
    });
  });
}
