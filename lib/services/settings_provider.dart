import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  String _schoolName = '';
  String _teacherName = '';
  String _schoolLogoPath = '';
  String _subscriptionMode = 'individual'; // individual | school
  String _defaultRubric = 'moe_national';
  bool _autoEnhanceImages = true;
  bool _voiceFeedbackEnabled = true;
  bool _darkMode = false;
  bool _useEthiopianCalendar = true; // default: Ethiopian for Ethiopian teachers
  String _telegramHandle = '';
  String _whatsappNumber = '';

  String get schoolName => _schoolName;
  String get teacherName => _teacherName;
  String get schoolLogoPath => _schoolLogoPath;
  String get subscriptionMode => _subscriptionMode;
  bool get isSchoolMode => _subscriptionMode == 'school';
  String get defaultRubric => _defaultRubric;
  bool get autoEnhanceImages => _autoEnhanceImages;
  bool get voiceFeedbackEnabled => _voiceFeedbackEnabled;
  bool get darkMode => _darkMode;
  bool get useEthiopianCalendar => _useEthiopianCalendar;
  String get telegramHandle => _telegramHandle;
  String get whatsappNumber => _whatsappNumber;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _schoolName = prefs.getString('school_name') ?? '';
    _teacherName = prefs.getString('teacher_name') ?? '';
    _schoolLogoPath = prefs.getString('school_logo') ?? '';
    _subscriptionMode = prefs.getString('subscription_mode') ?? 'individual';
    _defaultRubric = prefs.getString('default_rubric') ?? 'moe_national';
    _autoEnhanceImages = prefs.getBool('auto_enhance') ?? true;
    _voiceFeedbackEnabled = prefs.getBool('voice_feedback') ?? true;
    _darkMode = prefs.getBool('dark_mode') ?? false;
    _useEthiopianCalendar = prefs.getBool('ethiopian_calendar') ?? true;
    _telegramHandle = prefs.getString('telegram_handle') ?? '';
    _whatsappNumber = prefs.getString('whatsapp_number') ?? '';
    notifyListeners();
  }

  Future<void> updateSchoolInfo({
    String? name,
    String? teacher,
    String? logoPath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (name != null) {
      _schoolName = name;
      await prefs.setString('school_name', name);
    }
    if (teacher != null) {
      _teacherName = teacher;
      await prefs.setString('teacher_name', teacher);
    }
    if (logoPath != null) {
      _schoolLogoPath = logoPath;
      await prefs.setString('school_logo', logoPath);
    }
    notifyListeners();
  }

  Future<void> setSubscriptionMode(String mode) async {
    _subscriptionMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('subscription_mode', mode);
    notifyListeners();
  }

  Future<void> setDefaultRubric(String rubric) async {
    _defaultRubric = rubric;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_rubric', rubric);
    notifyListeners();
  }

  Future<void> toggleAutoEnhance() async {
    _autoEnhanceImages = !_autoEnhanceImages;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_enhance', _autoEnhanceImages);
    notifyListeners();
  }

  Future<void> toggleVoiceFeedback() async {
    _voiceFeedbackEnabled = !_voiceFeedbackEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_feedback', _voiceFeedbackEnabled);
    notifyListeners();
  }

  Future<void> toggleDarkMode() async {
    _darkMode = !_darkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', _darkMode);
    notifyListeners();
  }

  Future<void> toggleEthiopianCalendar() async {
    _useEthiopianCalendar = !_useEthiopianCalendar;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ethiopian_calendar', _useEthiopianCalendar);
    notifyListeners();
  }

  Future<void> updateContactInfo({
    String? telegram,
    String? whatsapp,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (telegram != null) {
      _telegramHandle = telegram;
      await prefs.setString('telegram_handle', telegram);
    }
    if (whatsapp != null) {
      _whatsappNumber = whatsapp;
      await prefs.setString('whatsapp_number', whatsapp);
    }
    notifyListeners();
  }

  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _loadSettings();
  }
}
