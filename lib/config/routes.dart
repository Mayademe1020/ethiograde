import 'package:flutter/material.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/home/main_dashboard.dart';
import '../screens/assessment/exam_day_create_screen.dart';
import '../screens/assessment/answer_key_screen.dart';
import '../screens/assessment/answer_key_confirmation_screen.dart';
import '../screens/scanning/camera_screen.dart';
import '../screens/scanning/batch_scan_screen.dart';
import '../screens/scanning/uploaded_papers_review_screen.dart';
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
  static const String answerKeyConfirmation = '/assessment/answer-key-confirmation';

  // Scanning
  static const String camera = '/scanning/camera';
  static const String batchScan = '/scanning/batch';
  static const String uploadedPapersReview = '/scanning/uploaded-papers-review';
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

      // Scanning
      case camera:
        return _fade(const CameraScreen(), settings);
      case batchScan:
        return _fade(const BatchScanScreen(), settings);
      case uploadedPapersReview:
        final args = settings.arguments as UploadedPapersReviewArgs;
        return _fade(UploadedPapersReviewScreen(args: args), settings);
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
          ),
          settings,
        );

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

      // Settings
      case gradingScaleEditor:
        final existing = settings.arguments as GradingScale?;
        return _fade(
          GradingScaleEditorScreen(existingScale: existing),
          settings,
        );

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
