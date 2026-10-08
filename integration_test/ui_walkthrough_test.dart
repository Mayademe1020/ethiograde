import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:ethiograde/main.dart' as app;
import 'package:ethiograde/config/routes.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/student.dart';
import 'package:ethiograde/models/class_info.dart';
import 'package:ethiograde/models/scan_result.dart';

import 'package:ethiograde/screens/onboarding/onboarding_screen.dart';
import 'package:ethiograde/screens/home/main_dashboard.dart';
import 'package:ethiograde/screens/assessment/exam_day_create_screen.dart';
import 'package:ethiograde/screens/assessment/answer_key_screen.dart';
import 'package:ethiograde/screens/assessment/answer_key_confirmation_screen.dart';
import 'package:ethiograde/screens/assessment/answer_key_photo_scan.dart';
import 'package:ethiograde/screens/assessment/answer_key_section_setup.dart';
import 'package:ethiograde/screens/scanning/camera_screen.dart';
import 'package:ethiograde/screens/scanning/batch_scan_screen.dart';
import 'package:ethiograde/screens/scanning/omr_calibration_screen.dart';
import 'package:ethiograde/screens/quick_grade/quick_grade_screen.dart';
import 'package:ethiograde/screens/quick_enter/quick_enter_screen.dart';
import 'package:ethiograde/screens/review/review_screen.dart';
import 'package:ethiograde/screens/review/grade_review_screen.dart';
import 'package:ethiograde/screens/analytics/analytics_screen.dart';
import 'package:ethiograde/screens/sms/sms_compose_screen.dart';
import 'package:ethiograde/screens/sms/sms_history_screen.dart';
import 'package:ethiograde/screens/students/import_excel_screen.dart';
import 'package:ethiograde/screens/students/add_student_screen.dart';
import 'package:ethiograde/screens/students/student_detail_screen.dart';
import 'package:ethiograde/screens/settings/grading_scale_editor_screen.dart';
import 'package:ethiograde/screens/classes/class_detail_screen.dart';

// Bounded settle — some screens (camera, calibration) animate forever, so pump
// a fixed number of frames instead of pumpAndSettle (which would hang ~10 min).
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Platform walkthrough — new user', (tester) async {
    // Swallow FlutterErrors into the report so a single screen error does not
    // abort the whole walkthrough before the checklist is printed.
    final recordedErrors = <String>{};

    app.main();
    await tester.pump(const Duration(seconds: 5));
    await _settle(tester);

    // Install AFTER app.main() so this handler overrides the app's own
    // FlutterError.onError (main.dart). Prints the full diagnostic, including
    // the offending widget's file:line, so overflows can be localized.
    FlutterError.onError = (details) {
      recordedErrors.add(details.exceptionAsString());
      debugPrint('FLUTTER_ERROR_DETAIL: ${details.toString()}');
    };

    final report = <String>[];

    // ── Checklist item: app launches & onboarding renders ──────────────
    if (find.byType(OnboardingScreen).evaluate().isNotEmpty) {
      report.add('PASS  launch + onboarding renders');
      var reachedDashboard = find.byType(MainDashboard).evaluate().isNotEmpty;
      final labels = [
        'Get Started',
        'Get started',
        'Continue',
        'Next',
        'Start',
        'Finish',
        'Done',
        'Skip'
      ];
      for (int i = 0; i < 8 && !reachedDashboard; i++) {
        var tappedThis = false;
        for (final label in labels) {
          final btn = find.widgetWithText(ElevatedButton, label);
          if (btn.evaluate().isNotEmpty) {
            await tester.tap(btn.first);
            tappedThis = true;
            break;
          }
          final btn2 = find.widgetWithText(TextButton, label);
          if (btn2.evaluate().isNotEmpty) {
            await tester.tap(btn2.first);
            tappedThis = true;
            break;
          }
        }
        await _settle(tester);
        reachedDashboard = find.byType(MainDashboard).evaluate().isNotEmpty;
        if (!tappedThis) break;
      }
      if (reachedDashboard) {
        report.add('PASS  onboarding completes -> dashboard');
      } else {
        report.add('WARN  onboarding shown but dashboard not reached');
      }
    } else if (find.byType(MainDashboard).evaluate().isNotEmpty) {
      report.add('PASS  launch (returning user) -> dashboard');
    } else {
      report.add('WARN  neither onboarding nor dashboard detected at launch');
    }

    // The root Navigator is the one MaterialApp uses for named routes.
    late final NavigatorState nav;
    try {
      final navFinder = find.byType(Navigator);
      nav = tester.state<NavigatorState>(navFinder.first);
    } catch (e) {
      report.add('FAIL  cannot obtain Navigator: $e');
      _printReport(report, recordedErrors);
      return;
    }

    final dummyAssessment = Assessment(title: 'Walkthrough', subject: 'Math');
    final dummyStudent = Student(studentId: 'S1', firstName: 'A', lastName: 'B');
    final dummyClass = ClassInfo(
      id: 'c1',
      name: 'Class',
      school: 'School',
      grade: 9,
      section: 'A',
      subject: 'Math',
      studentIds: const [],
      ownerId: 't1',
      createdAt: DateTime.now(),
    );

    final routes = <(String, Type, Object?)>[
      (AppRoutes.dashboard, MainDashboard, null),
      (AppRoutes.createAssessment, ExamDayCreateScreen, null),
      (AppRoutes.answerKey, AnswerKeyScreen, null),
      (AppRoutes.answerKeyConfirmation, AnswerKeyConfirmationScreen,
          dummyAssessment),
      (AppRoutes.answerKeyPhotoScan, AnswerKeyPhotoScanScreen, 5),
      (AppRoutes.answerKeySectionSetup, AnswerKeySectionSetup,
          dummyAssessment),
      (AppRoutes.camera, CameraScreen, null),
      (AppRoutes.batchScan, BatchScanScreen, null),
      (AppRoutes.omrCalibration, OmrCalibrationScreen, dummyAssessment),
      (AppRoutes.quickGrade, QuickGradeScreen, null),
      (AppRoutes.quickEnter, QuickEnterScreen, null),
      (AppRoutes.review, ReviewScreen, null),
      (AppRoutes.sideBySide, SideBySideReview, null),
      (AppRoutes.gradeReview, GradeReviewScreen, <String, Object?>{
        'assessment': dummyAssessment,
        'results': <ScanResult>[],
        'readOnly': false,
      }),
      (AppRoutes.analytics, AnalyticsScreen, null),
      (AppRoutes.smsCompose, SmsComposeScreen, null),
      (AppRoutes.smsHistory, SmsHistoryScreen, null),
      (AppRoutes.importExcel, ImportCsvScreen, null),
      (AppRoutes.addStudent, AddStudentScreen, null),
      (AppRoutes.studentDetail, StudentDetailScreen, dummyStudent),
      (AppRoutes.gradingScaleEditor, GradingScaleEditorScreen, null),
      (AppRoutes.classDetail, ClassDetailScreen, dummyClass),
    ];

    for (final (route, type, args) in routes) {
      final routeErrs = <String>[];
      debugPrint('>> PUSH $route');
      try {
        // Do NOT await pushNamed — it completes only when the route is popped,
        // which would block this loop forever.
        nav.pushNamed(route, arguments: args);
        await _settle(tester);
        routeErrs.addAll(_drain(tester));
        if (find.byType(type).evaluate().isEmpty) {
          report.add('WARN  $route :: screen type not found in tree');
          debugPrint('>> WARN $route');
        } else {
          report.add('PASS  $route');
          debugPrint('>> PASS $route');
        }
      } catch (e) {
        routeErrs.add(e.toString());
        report.add('FAIL  $route :: $e');
        debugPrint('>> FAIL $route :: $e');
      }
      // Pop back to a clean stack.
      try {
        int pops = 0;
        while (nav.canPop() && pops < 5) {
          nav.pop();
          pops++;
          await _settle(tester);
          routeErrs.addAll(_drain(tester));
        }
      } catch (_) {}
      if (routeErrs.isNotEmpty) {
        final joined = routeErrs.join(' || ');
        report.add('FAIL  $route :: $joined');
        debugPrint('>> RUNTIME-ERR $route :: $joined');
      }
    }

    _printReport(report, recordedErrors);

    expect(recordedErrors, isEmpty,
        reason: 'Walkthrough produced FlutterErrors:\n${recordedErrors.join('\n')}');
  });
}

List<String> _drain(WidgetTester tester) {
  final out = <String>[];
  try {
    dynamic e;
    while ((e = tester.takeException()) != null) {
      out.add(e.toString());
    }
  } catch (_) {}
  return out;
}

void _printReport(List<String> report, Set<String> errors) {
  debugPrint('===== ETHIOGRADE WALKTHROUGH REPORT =====');
  for (final r in report) {
    debugPrint(r);
  }
  debugPrint('=========================================');
  debugPrint('TOTAL: ${report.length} checks');
  debugPrint('PASS: ${report.where((r) => r.startsWith('PASS')).length}');
  debugPrint('WARN: ${report.where((r) => r.startsWith('WARN')).length}');
  debugPrint('FAIL: ${report.where((r) => r.startsWith('FAIL')).length}');
  if (errors.isNotEmpty) {
    debugPrint('---- distinct runtime errors captured ----');
    for (final e in errors) {
      debugPrint('ERR: $e');
    }
  }
}
