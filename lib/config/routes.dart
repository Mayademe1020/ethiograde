import 'package:flutter/material.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/home/main_dashboard.dart';

class AppRoutes {
  static const String onboarding = '/onboarding';
  static const String dashboard = '/dashboard';
  static const String settings = '/settings';

  // Assessment
  static const String createAssessment = '/assessment/create';
  static const String questionList = '/assessment/questions';
  static const String answerKey = '/assessment/answer-key';
  static const String rubricSelector = '/assessment/rubric';

  // Scanning
  static const String camera = '/scanning/camera';
  static const String imagePreview = '/scanning/preview';
  static const String scanResults = '/scanning/results';
  static const String batchScan = '/scanning/batch';

  // Review
  static const String review = '/review';
  static const String sideBySide = '/review/side-by-side';

  // Students
  static const String studentList = '/students/list';
  static const String importExcel = '/students/import';
  static const String addStudent = '/students/add';

  // Analytics
  static const String analytics = '/analytics';
  static const String heatmap = '/analytics/heatmap';
  static const String essayAnalytics = '/analytics/essay';

  // Reports
  static const String reports = '/reports';
  static const String reportPreview = '/reports/preview';
  static const String shareReport = '/reports/share';

  // Subscription
  static const String subscription = '/subscription';
  static const String schoolAdmin = '/subscription/school-admin';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case onboarding:
        return _fade(const OnboardingScreen());
      case dashboard:
        return _fade(const MainDashboard());
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
