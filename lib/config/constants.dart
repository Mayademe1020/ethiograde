import 'package:shared_preferences/shared_preferences.dart';

class AppConstants {
  // App Info
  static const String appName = 'EthioGrade';
  static const String appVersion = '0.1.0';
  static const String companyName = 'EthioGrade Education Technology';

  // Hive Box Names
  static const String settingsBox = 'settings';
  static const String studentsBox = 'students';
  static const String assessmentsBox = 'assessments';

  // Shared Pref Keys
  static const String prefFirstLaunch = 'first_launch';
  static const String prefLanguage = 'language';

  // Rubric types: built-in keys are moe_national, private_international, university.
  // Custom scales use "custom:<uuid>" format. See ScoringService.gradingScales.

  // Grading scales: single source of truth is ScoringService.gradingScales
  // (lib/services/scoring_service.dart). Do not duplicate here.

  // Check first launch
  static Future<bool> get isFirstLaunch async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefFirstLaunch) ?? true;
  }

  static const List<Map<String, String>> supportedLanguages = [
    {'code': 'en', 'name': 'English', 'native': 'English'},
  ];

  // Question type labels
  static const Map<String, String> questionTypeLabels = {
    'mcq': 'Multiple Choice',
    'true_false': 'True/False',
    'short_answer': 'Short Answer',
    'essay': 'Essay',
  };

  // Notification messages
  static const Map<String, String> messages = {
    'scan_complete': 'Scanning complete!',
    'grading_complete': 'Grading complete!',
    'report_ready': 'Report is ready',
    'no_students': 'No students added yet',
  };

  // ── Subject classification for flow hints ──

  /// Subjects where OCR scanning works well (MCQ/T-F heavy).
  static const List<String> scanFriendlySubjects = [
    'Biology', 'Civics', 'English', 'History', 'Geography',
    'Social Studies', 'Economics', 'Political Science',
    'Chemistry', 'Physics', // theory sections
    'ICT', 'General Science', 'Aptitude',
  ];

  /// Subjects where manual score entry is recommended (work shown, subjective).
  static const List<String> manualEntrySubjects = [
    'Mathematics', 'Math', 'Physics', // calculation-heavy
    'Essay', 'Composition', 'Creative Writing', 'Literature',
  ];

  /// Suggestion for scan-friendly subjects.
  static const String scanSuggestionEn = 'Scanning works well for this subject';

  /// Suggestion for manual entry subjects.
  static const String manualSuggestionEn =
      'Manual score entry is recommended for this subject';
}
