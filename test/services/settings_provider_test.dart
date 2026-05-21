import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ethiograde/services/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'ethiograde_settings_test_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Open PII box for SettingsProvider
    await Hive.openBox('settings_pii');
  });

  tearDown(() async {
    if (Hive.isBoxOpen('settings_pii')) {
      final box = Hive.box('settings_pii');
      await box.clear();
      await box.close();
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('SettingsProvider', () {
    test('loadSettings defaults', () async {
      final provider = SettingsProvider();
      await provider.loadSettings();

      expect(provider.isLoaded, isTrue);
      expect(provider.defaultRubric, 'moe_national');
      expect(provider.autoEnhanceImages, isTrue);
      expect(provider.voiceFeedbackEnabled, isTrue);
      expect(provider.darkMode, isFalse);
      expect(provider.schoolName, isEmpty);
      expect(provider.teacherName, isEmpty);
      expect(provider.telegramHandle, isEmpty);
      expect(provider.whatsappNumber, isEmpty);
    });

    test('loadSettings reads SharedPreferences values', () async {
      SharedPreferences.setMockInitialValues({
        'default_rubric': 'university',
        'auto_enhance': false,
        'voice_feedback': false,
        'dark_mode': true,
        'school_logo': '/path/to/logo.png',
      });
      final provider = SettingsProvider();
      await provider.loadSettings();

      expect(provider.defaultRubric, 'university');
      expect(provider.autoEnhanceImages, isFalse);
      expect(provider.voiceFeedbackEnabled, isFalse);
      expect(provider.darkMode, isTrue);
      expect(provider.schoolLogoPath, '/path/to/logo.png');
    });

    test('loadSettings reads PII from Hive', () async {
      final piiBox = Hive.box('settings_pii');
      await piiBox.put('school_name', 'Bole High School');
      await piiBox.put('teacher_name', 'Abebe Kebede');
      await piiBox.put('telegram_handle', '@abebe');
      await piiBox.put('whatsapp_number', '+251911222333');

      final provider = SettingsProvider();
      await provider.loadSettings();

      expect(provider.schoolName, 'Bole High School');
      expect(provider.teacherName, 'Abebe Kebede');
      expect(provider.telegramHandle, '@abebe');
      expect(provider.whatsappNumber, '+251911222333');
    });

    test('loadSettings is idempotent', () async {
      final provider = SettingsProvider();
      await provider.loadSettings();
      expect(provider.isLoaded, isTrue);

      // Second call should not reload
      SharedPreferences.setMockInitialValues({'default_rubric': 'university'});
      await provider.loadSettings();
      expect(provider.defaultRubric, 'moe_national'); // unchanged
    });

    test('updateSchoolInfo saves to Hive', () async {
      final provider = SettingsProvider();
      await provider.loadSettings();

      await provider.updateSchoolInfo(
        name: 'Arat Kilo School',
        teacher: 'Tigist Haile');

      expect(provider.schoolName, 'Arat Kilo School');
      expect(provider.teacherName, 'Tigist Haile');

      // Verify persisted in Hive
      final piiBox = Hive.box('settings_pii');
      expect(piiBox.get('school_name'), 'Arat Kilo School');
      expect(piiBox.get('teacher_name'), 'Tigist Haile');
    });

    test('updateSchoolInfo partial update', () async {
      final provider = SettingsProvider();
      await provider.loadSettings();

      await provider.updateSchoolInfo(name: 'Test School');
      expect(provider.schoolName, 'Test School');
      expect(provider.teacherName, isEmpty);

      await provider.updateSchoolInfo(teacher: 'Teacher Name');
      expect(provider.schoolName, 'Test School'); // unchanged
      expect(provider.teacherName, 'Teacher Name');
    });

    test('setDefaultRubric persists', () async {
      final provider = SettingsProvider();
      await provider.loadSettings();

      await provider.setDefaultRubric('university');
      expect(provider.defaultRubric, 'university');
    });

    test('toggleAutoEnhance flips value', () async {
      final provider = SettingsProvider();
      await provider.loadSettings();
      expect(provider.autoEnhanceImages, isTrue);

      await provider.toggleAutoEnhance();
      expect(provider.autoEnhanceImages, isFalse);

      await provider.toggleAutoEnhance();
      expect(provider.autoEnhanceImages, isTrue);
    });

    test('toggleVoiceFeedback flips value', () async {
      final provider = SettingsProvider();
      await provider.loadSettings();
      expect(provider.voiceFeedbackEnabled, isTrue);

      await provider.toggleVoiceFeedback();
      expect(provider.voiceFeedbackEnabled, isFalse);
    });

    test('toggleDarkMode flips value', () async {
      final provider = SettingsProvider();
      await provider.loadSettings();
      expect(provider.darkMode, isFalse);

      await provider.toggleDarkMode();
      expect(provider.darkMode, isTrue);
    });

    test('updateContactInfo saves to Hive', () async {
      final provider = SettingsProvider();
      await provider.loadSettings();

      await provider.updateContactInfo(
        telegram: '@teacher',
        whatsapp: '+251900000000');

      expect(provider.telegramHandle, '@teacher');
      expect(provider.whatsappNumber, '+251900000000');

      final piiBox = Hive.box('settings_pii');
      expect(piiBox.get('telegram_handle'), '@teacher');
      expect(piiBox.get('whatsapp_number'), '+251900000000');
    });

    test('updateContactInfo partial update', () async {
      final provider = SettingsProvider();
      await provider.loadSettings();

      await provider.updateContactInfo(telegram: '@tg');
      expect(provider.telegramHandle, '@tg');
      expect(provider.whatsappNumber, isEmpty);
    });

    test('resetAll clears everything', () async {
      final provider = SettingsProvider();
      await provider.loadSettings();

      // Set some values first
      await provider.updateSchoolInfo(name: 'Test', teacher: 'Teacher');
      await provider.updateContactInfo(telegram: '@tg', whatsapp: '+251');
      await provider.setDefaultRubric('university');
      await provider.toggleDarkMode();

      // Reset
      await provider.resetAll();

      expect(provider.schoolName, isEmpty);
      expect(provider.teacherName, isEmpty);
      expect(provider.telegramHandle, isEmpty);
      expect(provider.whatsappNumber, isEmpty);
      expect(provider.defaultRubric, 'moe_national');
      expect(provider.autoEnhanceImages, isTrue);
      expect(provider.voiceFeedbackEnabled, isTrue);
      expect(provider.darkMode, isFalse);
    });

    test('notifyListeners fires on load', () async {
      final provider = SettingsProvider();
      var fired = false;
      provider.addListener(() => fired = true);
      await provider.loadSettings();
      expect(fired, isTrue);
    });

    test('notifyListeners fires on toggle', () async {
      final provider = SettingsProvider();
      await provider.loadSettings();
      var count = 0;
      provider.addListener(() => count++);

      await provider.toggleDarkMode();
      expect(count, 1);
    });

    test('graceful failure on corrupt Hive', () async {
      // Close the box so _getPiiBox has to re-open it
      await Hive.box('settings_pii').close();

      final provider = SettingsProvider();
      await provider.loadSettings();

      // Should not throw, should load defaults
      expect(provider.isLoaded, isTrue);
      expect(provider.schoolName, isEmpty);
    });
  });
}
