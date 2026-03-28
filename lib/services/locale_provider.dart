import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('en', 'US');
  bool _isAmharic = false;

  Locale get locale => _locale;
  bool get isAmharic => _isAmharic;
  String get languageCode => _locale.languageCode;

  LocaleProvider() {
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('language') ?? 'en';
    _isAmharic = code == 'am';
    _locale = code == 'am'
        ? const Locale('am', 'ET')
        : const Locale('en', 'US');
    notifyListeners();
  }

  Future<void> toggleLocale() async {
    _isAmharic = !_isAmharic;
    _locale = _isAmharic
        ? const Locale('am', 'ET')
        : const Locale('en', 'US');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', _locale.languageCode);
    notifyListeners();
  }

  Future<void> setLocale(String code) async {
    _isAmharic = code == 'am';
    _locale = code == 'am'
        ? const Locale('am', 'ET')
        : const Locale('en', 'US');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', code);
    notifyListeners();
  }

  /// Get bilingual text based on current locale
  String t(String en, String am) => _isAmharic ? am : en;
}

/// Convenience function for bilingual text
String tr(LocaleProvider locale, String en, String am) {
  return locale.isAmharic ? am : en;
}
