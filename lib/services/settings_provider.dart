import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/grading_scale.dart';

enum VoiceFeedbackMode { off, statusOnly, scoreOnly, gradeOnly, scoreAndGrade }

/// Manages app settings.
///
/// Non-sensitive settings (rubric, language, auto-enhance) → SharedPreferences.
/// PII (names, phone numbers, handles) → encrypted Hive box.
class SettingsProvider extends ChangeNotifier {
  static const String _piiBoxName = 'settings_pii';

  String _schoolName = '';
  String _teacherName = '';
  String _schoolLogoPath = '';
  String _defaultRubric = 'moe_national';
  bool _autoEnhanceImages = true;
  VoiceFeedbackMode _voiceFeedbackMode = VoiceFeedbackMode.scoreOnly;
  bool _darkMode = false;
  String _telegramHandle = '';
  String _whatsappNumber = '';
  bool _loaded = false;

  // Cloud OCR settings
  bool _cloudOcrEnabled = false;
  String _cloudOcrEndpoint = 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions';
  String _cloudOcrApiKey = '';
  String _cloudOcrModel = 'qwen-vl-plus';

  // Custom grading scales
  List<GradingScale> _customScales = [];
  List<GradingScale> get customScales => _customScales;

  String get schoolName => _schoolName;
  String get teacherName => _teacherName;
  String get schoolLogoPath => _schoolLogoPath;
  String get defaultRubric => _defaultRubric;
  bool get autoEnhanceImages => _autoEnhanceImages;
  bool get voiceFeedbackEnabled => _voiceFeedbackMode != VoiceFeedbackMode.off;
  VoiceFeedbackMode get voiceFeedbackMode => _voiceFeedbackMode;
  String get voiceFeedbackModeLabel => _voiceFeedbackLabel(_voiceFeedbackMode);
  String get voiceFeedbackModeDescription =>
      _voiceFeedbackDescription(_voiceFeedbackMode);
  bool get darkMode => _darkMode;
  String get telegramHandle => _telegramHandle;
  String get whatsappNumber => _whatsappNumber;
  bool get isLoaded => _loaded;

  // Cloud OCR getters
  bool get cloudOcrEnabled => _cloudOcrEnabled;
  String get cloudOcrEndpoint => _cloudOcrEndpoint;
  String get cloudOcrApiKey => _cloudOcrApiKey;
  String get cloudOcrModel => _cloudOcrModel;

  /// Explicit load — call from widget tree, not constructor.
  Future<void> loadSettings() async {
    if (_loaded) return;
    try {
      // Non-sensitive: SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      _defaultRubric = prefs.getString('default_rubric') ?? 'moe_national';
      _autoEnhanceImages = prefs.getBool('auto_enhance') ?? true;
      _voiceFeedbackMode = _parseVoiceFeedbackMode(
        prefs.getString('voice_feedback_mode'),
        legacyEnabled: prefs.getBool('voice_feedback') ?? true,
      );
      _darkMode = prefs.getBool('dark_mode') ?? false;
      _schoolLogoPath = prefs.getString('school_logo') ?? '';

      // PII: encrypted Hive box — must already be opened by main.dart with cipher
      if (!Hive.isBoxOpen(_piiBoxName)) {
        throw StateError(
          'PII box "$_piiBoxName" must be opened by main.dart with '
          'HiveAesCipher before SettingsProvider.loadSettings() is called.',
        );
      }
      final piiBox = Hive.box(_piiBoxName);
      _schoolName = (piiBox.get('school_name') as String?) ?? '';
      _teacherName = (piiBox.get('teacher_name') as String?) ?? '';
      _telegramHandle = (piiBox.get('telegram_handle') as String?) ?? '';
      _whatsappNumber = (piiBox.get('whatsapp_number') as String?) ?? '';

      // Cloud OCR settings (encrypted — API key is sensitive)
      _cloudOcrEnabled = piiBox.get('cloud_ocr_enabled') == true;
      _cloudOcrEndpoint = (piiBox.get('cloud_ocr_endpoint') as String?) ?? 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions';
      _cloudOcrApiKey = (piiBox.get('cloud_ocr_api_key') as String?) ?? '';
      _cloudOcrModel = (piiBox.get('cloud_ocr_model') as String?) ?? 'qwen-vl-plus';

      // Custom grading scales
      final scalesJson = prefs.getString('custom_grading_scales');
      if (scalesJson != null && scalesJson.isNotEmpty) {
        try {
          final List<dynamic> decoded = jsonDecode(scalesJson);
          _customScales = decoded.map((m) => GradingScale.fromMap(m)).toList();
        } catch (e) {
          debugPrint('[Settings] Failed to parse custom scales: $e');
          _customScales = [];
        }
      }

      _loaded = true;
    } catch (e) {
      debugPrint('[Settings] loadSettings failed: $e');
      _loaded = true; // Don't retry-loop on failure
    }
    notifyListeners();
  }

  Future<void> updateSchoolInfo({
    String? name,
    String? teacher,
    String? logoPath,
  }) async {
    final piiBox = await _getPiiBox();
    final prefs = await SharedPreferences.getInstance();
    if (name != null) {
      _schoolName = name;
      await piiBox.put('school_name', name);
    }
    if (teacher != null) {
      _teacherName = teacher;
      await piiBox.put('teacher_name', teacher);
    }
    if (logoPath != null) {
      _schoolLogoPath = logoPath;
      await prefs.setString('school_logo', logoPath);
    }
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
    _voiceFeedbackMode = voiceFeedbackEnabled
        ? VoiceFeedbackMode.off
        : VoiceFeedbackMode.scoreOnly;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('voice_feedback_mode', _voiceFeedbackMode.name);
    await prefs.setBool('voice_feedback', voiceFeedbackEnabled);
    notifyListeners();
  }

  Future<void> setVoiceFeedbackMode(VoiceFeedbackMode mode) async {
    _voiceFeedbackMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('voice_feedback_mode', mode.name);
    await prefs.setBool('voice_feedback', voiceFeedbackEnabled);
    notifyListeners();
  }

  Future<void> toggleDarkMode() async {
    _darkMode = !_darkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', _darkMode);
    notifyListeners();
  }

  Future<void> updateContactInfo({String? telegram, String? whatsapp}) async {
    final piiBox = await _getPiiBox();
    if (telegram != null) {
      _telegramHandle = telegram;
      await piiBox.put('telegram_handle', telegram);
    }
    if (whatsapp != null) {
      _whatsappNumber = whatsapp;
      await piiBox.put('whatsapp_number', whatsapp);
    }
    notifyListeners();
  }

  // ── Cloud OCR Settings ──

  Future<void> updateCloudOcr({
    bool? enabled,
    String? endpoint,
    String? apiKey,
    String? model,
  }) async {
    final piiBox = await _getPiiBox();
    if (enabled != null) {
      _cloudOcrEnabled = enabled;
      await piiBox.put('cloud_ocr_enabled', enabled);
    }
    if (endpoint != null) {
      _cloudOcrEndpoint = endpoint;
      await piiBox.put('cloud_ocr_endpoint', endpoint);
    }
    if (apiKey != null) {
      _cloudOcrApiKey = apiKey;
      await piiBox.put('cloud_ocr_api_key', apiKey);
    }
    if (model != null) {
      _cloudOcrModel = model;
      await piiBox.put('cloud_ocr_model', model);
    }
    notifyListeners();
  }

  // ── Custom Grading Scales ──

  Future<void> saveCustomScale(GradingScale scale) async {
    final idx = _customScales.indexWhere((s) => s.id == scale.id);
    if (idx >= 0) {
      _customScales[idx] = scale;
    } else {
      _customScales.add(scale);
    }
    await _persistCustomScales();
    notifyListeners();
  }

  Future<void> deleteCustomScale(String scaleId) async {
    _customScales.removeWhere((s) => s.id == scaleId);
    await _persistCustomScales();
    notifyListeners();
  }

  /// Look up a custom scale by its rubricKey (e.g. "custom:uuid").
  GradingScale? getCustomScaleByKey(String rubricKey) {
    if (!rubricKey.startsWith('custom:')) return null;
    final id = rubricKey.substring(7);
    return _customScales.cast<GradingScale?>().firstWhere(
      (s) => s?.id == id,
      orElse: () => null,
    );
  }

  Future<void> _persistCustomScales() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_customScales.map((s) => s.toMap()).toList());
    await prefs.setString('custom_grading_scales', encoded);
  }

  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('default_rubric');
    await prefs.remove('auto_enhance');
    await prefs.remove('voice_feedback');
    await prefs.remove('voice_feedback_mode');
    await prefs.remove('dark_mode');
    await prefs.remove('school_logo');
    await prefs.remove('custom_grading_scales');

    final piiBox = await _getPiiBox();
    await piiBox.clear();

    _schoolName = '';
    _teacherName = '';
    _telegramHandle = '';
    _whatsappNumber = '';
    _defaultRubric = 'moe_national';
    _autoEnhanceImages = true;
    _voiceFeedbackMode = VoiceFeedbackMode.scoreOnly;
    _darkMode = false;
    _schoolLogoPath = '';
    _customScales = [];
    notifyListeners();
  }

  Future<Box> _getPiiBox() async {
    if (Hive.isBoxOpen(_piiBoxName)) return Hive.box(_piiBoxName);
    return await Hive.openBox(_piiBoxName);
  }

  static VoiceFeedbackMode _parseVoiceFeedbackMode(
    String? value, {
    required bool legacyEnabled,
  }) {
    if (value == null || value.isEmpty) {
      return legacyEnabled
          ? VoiceFeedbackMode.scoreOnly
          : VoiceFeedbackMode.off;
    }
    return VoiceFeedbackMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () =>
          legacyEnabled ? VoiceFeedbackMode.scoreOnly : VoiceFeedbackMode.off,
    );
  }

  static String _voiceFeedbackLabel(VoiceFeedbackMode mode) {
    switch (mode) {
      case VoiceFeedbackMode.off:
        return 'Off';
      case VoiceFeedbackMode.statusOnly:
        return 'Status only';
      case VoiceFeedbackMode.scoreOnly:
        return 'Score only';
      case VoiceFeedbackMode.gradeOnly:
        return 'Grade only';
      case VoiceFeedbackMode.scoreAndGrade:
        return 'Score + grade';
    }
  }

  static String _voiceFeedbackDescription(VoiceFeedbackMode mode) {
    switch (mode) {
      case VoiceFeedbackMode.off:
        return 'No scan sound';
      case VoiceFeedbackMode.statusOnly:
        return 'Only tells scan status';
      case VoiceFeedbackMode.scoreOnly:
        return 'Says marks like 8';
      case VoiceFeedbackMode.gradeOnly:
        return 'Says grades like A';
      case VoiceFeedbackMode.scoreAndGrade:
        return 'Says mark and grade';
    }
  }
}
