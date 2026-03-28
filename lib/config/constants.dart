import 'package:shared_preferences/shared_preferences.dart';

class AppConstants {
  // App Info
  static const String appName = 'EthioGrade';
  static const String appVersion = '1.0.0';
  static const String companyName = 'EthioGrade Education Technology';

  // Hive Box Names
  static const String settingsBox = 'settings';
  static const String studentsBox = 'students';
  static const String assessmentsBox = 'assessments';
  static const String resultsBox = 'results';
  static const String syncQueueBox = 'sync_queue';

  // Shared Pref Keys
  static const String prefFirstLaunch = 'first_launch';
  static const String prefLanguage = 'language';
  static const String prefSchoolName = 'school_name';
  static const String prefTeacherName = 'teacher_name';
  static const String prefSubscriptionMode = 'subscription_mode';
  static const String prefSchoolLogo = 'school_logo_path';

  // Rubric Types
  static const String rubricMoE = 'moe_national';
  static const String rubricPrivate = 'private_international';
  static const String rubricUniversity = 'university';

  // Grading Scales
  static const Map<String, Map<String, dynamic>> gradingScales = {
    'moe_national': {
      'pass_mark': 50,
      'grades': {
        'A+': [95, 100],
        'A':  [90, 94],
        'A-': [85, 89],
        'B+': [80, 84],
        'B':  [75, 79],
        'B-': [70, 74],
        'C+': [65, 69],
        'C':  [60, 64],
        'C-': [55, 59],
        'D':  [50, 54],
        'F':  [0, 49],
      },
    },
    'private_international': {
      'pass_mark': 60,
      'grades': {
        'A*': [90, 100],
        'A':  [80, 89],
        'B':  [70, 79],
        'C':  [60, 69],
        'D':  [50, 59],
        'F':  [0, 49],
      },
    },
    'university': {
      'pass_mark': 50,
      'grades': {
        'A':  [90, 100],
        'A-': [85, 89],
        'B+': [80, 84],
        'B':  [75, 79],
        'B-': [70, 74],
        'C+': [65, 69],
        'C':  [60, 64],
        'C-': [55, 59],
        'D':  [50, 54],
        'F':  [0, 49],
      },
    },
  };

  // Check first launch
  static bool get isFirstLaunch {
    return SharedPreferences.getInstance().then(
      (prefs) => prefs.getBool(prefFirstLaunch) ?? true,
    ) as bool;
  }

  // Supported languages
  static const List<Map<String, String>> supportedLanguages = [
    {'code': 'en', 'name': 'English', 'native': 'English'},
    {'code': 'am', 'name': 'Amharic', 'native': 'አማርኛ'},
  ];

  // Question type labels (bilingual)
  static const Map<String, Map<String, String>> questionTypeLabels = {
    'mcq': {'en': 'Multiple Choice', 'am': 'ብዙ ምርጫ'},
    'true_false': {'en': 'True/False', 'am': 'እውነት/ሐሰት'},
    'short_answer': {'en': 'Short Answer', 'am': 'አጭር መልስ'},
    'essay': {'en': 'Essay', 'am': 'ግጥም ጽሑፍ'},
  };

  // Notification messages (bilingual)
  static const Map<String, Map<String, String>> messages = {
    'scan_complete': {
      'en': 'Scanning complete!',
      'am': 'ማሰስ ተጠናቋል!',
    },
    'grading_complete': {
      'en': 'Grading complete!',
      'am': 'ውጤት መስጠት ተጠናቋል!',
    },
    'report_ready': {
      'en': 'Report is ready',
      'am': 'ሪፖርት ዝግጁ ነው',
    },
    'no_students': {
      'en': 'No students added yet',
      'am': 'ተማሪዎች ገና አልተመዘገቡም',
    },
  };
}
