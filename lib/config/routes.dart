import 'package:flutter/material.dart';
import '../screens/analytics/analytics_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/sms/sms_compose_screen.dart';
import '../screens/sms/sms_history_screen.dart';
import '../screens/home/main_dashboard.dart';
import '../screens/assessment/exam_day_create_screen.dart';
import '../screens/assessment/answer_key_screen.dart';
import '../screens/assessment/answer_key_confirmation_screen.dart';
import '../screens/assessment/answer_key_photo_scan.dart';
import '../screens/assessment/answer_key_section_setup.dart';
import '../screens/scanning/camera_screen.dart';
import '../screens/scanning/batch_scan_screen.dart';
import '../screens/scanning/omr_calibration_screen.dart';
import '../screens/quick_grade/quick_grade_screen.dart';
import '../screens/quick_enter/quick_enter_screen.dart';
import '../screens/review/review_screen.dart';
import '../screens/review/grade_review_screen.dart';
import '../screens/students/import_excel_screen.dart';
import '../screens/students/add_student_screen.dart';
import '../screens/students/student_detail_screen.dart';
import '../screens/settings/grading_scale_editor_screen.dart';
import '../screens/classes/class_detail_screen.dart';
import '../models/student.dart';
import '../models/class_info.dart';
import '../models/grading_scale.dart';
import '../models/assessment.dart';
import '../models/scan_result.dart';

class AppRoutes {
  static const String onboarding = '/onboarding';
  static const String dashboard = '/dashboard';

  // Assessment
  static const String createAssessment = '/assessment/create';
  static const String answerKey = '/assessment/answer-key';
  static const String answerKeyConfirmation =
      '/assessment/answer-key-confirmation';
  static const String answerKeyPhotoScan = '/assessment/answer-key-photo-scan';
  static const String answerKeySectionSetup =
      '/assessment/answer-key-section-setup';

  // Scanning
  static const String camera = '/scanning/camera';
  static const String batchScan = '/scanning/batch';
  static const String omrCalibration = '/scanning/omr-calibration';
  static const String quickGrade = '/quick_grade';
  static const String quickEnter = '/quick_enter';

  // Review
  static const String review = '/review';
  static const String sideBySide = '/review/side-by-side';
  static const String gradeReview = '/review/grade-review';
  static const String analytics = '/analytics';
  static const String smsCompose = '/sms/compose';
  static const String smsHistory = '/sms/history';

  // Students
  static const String importExcel = '/students/import';
  static const String addStudent = '/students/add';
  static const String studentDetail = '/students/detail';

  // Classes

  // Settings
  static const String gradingScaleEditor = '/settings/grading-scale';
  static const String classDetail = '/class/detail';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case onboarding:
        return _fade(const OnboardingScreen(), settings);
      case dashboard:
        return _fade(const MainDashboard(), settings);

      // Assessment
      case createAssessment:
        final args = settings.arguments;
        final mode = args is ExamDayStartMode ? args : null;
        return _fade(ExamDayCreateScreen(initialMode: mode), settings);
      case answerKey:
        return _fade(const AnswerKeyScreen(), settings);
      case answerKeyConfirmation:
        final args = settings.arguments as Assessment;
        return _fade(AnswerKeyConfirmationScreen(assessment: args), settings);
      case answerKeyPhotoScan:
        final args = settings.arguments as int;
        return _fade(AnswerKeyPhotoScanScreen(questionCount: args), settings);
      case answerKeySectionSetup:
        final args = settings.arguments as Assessment;
        return _fade(AnswerKeySectionSetup(assessment: args), settings);

      // Scanning
      case camera:
        return _fade(const CameraScreen(), settings);
      case batchScan:
        return _fade(const BatchScanScreen(), settings);
      case omrCalibration:
        final args = settings.arguments as Assessment;
        return _fade(OmrCalibrationScreen(assessment: args), settings);
      case quickGrade:
        return _fade(const QuickGradeScreen(), settings);
      case quickEnter:
        return _fade(const QuickEnterScreen(), settings);

      // Review
      case review:
        return _fade(const ReviewScreen(), settings);
      case sideBySide:
        return _fade(const SideBySideReview(), settings);
      case gradeReview:
        final args = settings.arguments as Map<String, dynamic>;
        return _fade(
          GradeReviewScreen(
            assessment: args['assessment'] as Assessment,
            results: (args['results'] as List<ScanResult>),
            readOnly: args['readOnly'] as bool? ?? false,
          ),
          settings,
        );

      // Analytics
      case analytics:
        return _fade(const AnalyticsScreen(), settings);

      // SMS
      case smsCompose:
        final args = settings.arguments as Map<String, dynamic>?;
        return _fade(
          SmsComposeScreen(
            initialMessages: args?['messages'] as List<Map<String, String>>?,
            assessmentName: args?['assessmentName'] as String?,
          ),
          settings,
        );
      case smsHistory:
        return _fade(const SmsHistoryScreen(), settings);

      // Students
      case importExcel:
        final classId = settings.arguments as String?;
        return _fade(ImportCsvScreen(classId: classId), settings);
      case addStudent:
        final args = settings.arguments;
        if (args is Student) {
          return _fade(AddStudentScreen(existingStudent: args), settings);
        }
        final classId = args as String?;
        return _fade(AddStudentScreen(preselectedClassId: classId), settings);
      case studentDetail:
        final student = settings.arguments as Student;
        return _fade(StudentDetailScreen(student: student), settings);

      // Settings
      case gradingScaleEditor:
        final existing = settings.arguments as GradingScale?;
        return _fade(
          GradingScaleEditorScreen(existingScale: existing),
          settings,
        );

      // Classes
      case classDetail:
        final classInfo = settings.arguments as ClassInfo;
        return _fade(ClassDetailScreen(classInfo: classInfo), settings);

      default:
        return _fade(const MainDashboard(), settings);
    }
  }

  static PageRouteBuilder<T> _fade<T>(Widget page, [RouteSettings? settings]) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 250),
    );
  }
}
