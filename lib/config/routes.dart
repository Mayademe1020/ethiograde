import 'package:flutter/material.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/home/main_dashboard.dart';
import '../screens/assessment/exam_day_create_screen.dart';
import '../screens/assessment/answer_key_screen.dart';
import '../screens/assessment/answer_sheet_setup_screen.dart';
import '../screens/scanning/camera_screen.dart';
import '../screens/scanning/batch_scan_screen.dart';
import '../screens/quick_grade/quick_grade_screen.dart';
import '../screens/quick_enter/quick_enter_screen.dart';
import '../screens/review/review_screen.dart';
import '../screens/review/grade_review_screen.dart';
import '../screens/students/import_excel_screen.dart';
import '../screens/students/add_student_screen.dart';
import '../screens/settings/grading_scale_editor_screen.dart';
import '../models/student.dart';
import '../models/grading_scale.dart';
import '../models/assessment.dart';
import '../models/scan_result.dart';

class AppRoutes {
  static const String onboarding = '/onboarding';
  static const String dashboard = '/dashboard';

  // Assessment
  static const String createAssessment = '/assessment/create';
  static const String answerKey = '/assessment/answer-key';
  static const String answerSheetSetup = '/assessment/answer-sheet-setup';

  // Scanning
  static const String camera = '/scanning/camera';
  static const String batchScan = '/scanning/batch';
  static const String quickGrade = '/quick_grade';
  static const String quickEnter = '/quick_enter';

  // Review
  static const String review = '/review';
  static const String sideBySide = '/review/side-by-side';
  static const String gradeReview = '/review/grade-review';

  // Students
  static const String importExcel = '/students/import';
  static const String addStudent = '/students/add';

  // Classes

  // Settings
  static const String gradingScaleEditor = '/settings/grading-scale';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case onboarding:
        return _fade(const OnboardingScreen());
      case dashboard:
        return _fade(const MainDashboard());

      // Assessment
      case createAssessment:
        final args = settings.arguments;
        final mode = args is ExamDayStartMode ? args : null;
        return _fade(ExamDayCreateScreen(initialMode: mode));
      case answerKey:
        return _fade(const AnswerKeyScreen());
      case answerSheetSetup:
        final args = settings.arguments;
        final assessment = args is Assessment ? args : null;
        return _fade(AnswerSheetSetupScreen(assessment: assessment));

      // Scanning
      case camera:
        return _fade(const CameraScreen());
      case batchScan:
        return _fade(const BatchScanScreen());
      case quickGrade:
        return _fade(const QuickGradeScreen());
      case quickEnter:
        return _fade(const QuickEnterScreen());

      // Review
      case review:
        return _fade(const ReviewScreen());
      case sideBySide:
        return _fade(const SideBySideReview());
      case gradeReview:
        final args = settings.arguments as Map<String, dynamic>;
        return _fade(
          GradeReviewScreen(
            assessment: args['assessment'] as Assessment,
            results: (args['results'] as List<ScanResult>),
          ),
        );

      // Students
      case importExcel:
        final classId = settings.arguments as String?;
        return _fade(ImportCsvScreen(classId: classId));
      case addStudent:
        final args = settings.arguments;
        if (args is Student) {
          return _fade(AddStudentScreen(existingStudent: args));
        }
        final classId = args as String?;
        return _fade(AddStudentScreen(preselectedClassId: classId));

      // Settings
      case gradingScaleEditor:
        final existing = settings.arguments as GradingScale?;
        return _fade(GradingScaleEditorScreen(existingScale: existing));

      default:
        return _fade(const MainDashboard());
    }
  }

  static PageRouteBuilder<T> _fade<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 250),
    );
  }
}
