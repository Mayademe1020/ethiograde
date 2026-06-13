import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethiograde/screens/review/grade_review_screen.dart';
import 'package:ethiograde/services/student_provider.dart';
import 'package:ethiograde/services/assessment_provider.dart';
import 'package:ethiograde/services/class_provider.dart';
import 'package:ethiograde/services/teacher_provider.dart';
import 'package:ethiograde/services/weighted_grade_provider.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'ethiograde_grade_review_test_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Hive.openBox('students');
    await Hive.openBox('assessments');
    await Hive.openBox('classes');
    await Hive.openBox('teachers');
    await Hive.openBox('settings_pii');
    await Hive.openBox('grading_drafts');
    await Hive.openBox('audit_trail');
    await Hive.openBox('weighted_scales');
    await Hive.openBox('scan_results');
  });

  tearDown(() async {
    for (final name in [
      'students',
      'assessments',
      'classes',
      'teachers',
      'settings_pii',
      'grading_drafts',
      'audit_trail',
      'weighted_scales',
      'scan_results',
    ]) {
      if (Hive.isBoxOpen(name)) {
        try {
          await Hive.box(name).clear();
          await Hive.box(name).close();
        } catch (_) {}
      }
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Assessment makeAssessment({String? weightedScaleId}) => Assessment(
        id: 'a1',
        title: 'Math Unit 1',
        subject: 'Math',
        status: AssessmentStatus.active,
        weightedScaleId: weightedScaleId);

  ScanResult makeResult({
    String id = 'r1',
    String name = 'Abebe Kebede',
    double totalScore = 7,
    double maxScore = 10,
    double percentage = 70,
    String grade = 'B',
  }) =>
      ScanResult(
        id: id,
        assessmentId: 'a1',
        studentId: 's1',
        studentName: name,
        imagePath: '/fake/path.png',
        totalScore: totalScore,
        maxScore: maxScore,
        percentage: percentage,
        grade: grade,
        confidence: 0.95,
        status: ScanStatus.graded);

  Widget wrapReview({
    required Assessment assessment,
    required List<ScanResult> results,
  }) {

    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => StudentProvider()),
          ChangeNotifierProvider(create: (_) => AssessmentProvider()),
          ChangeNotifierProvider(create: (_) => ClassProvider()),
          ChangeNotifierProvider(create: (_) => TeacherProvider()),
          ChangeNotifierProvider(create: (_) => WeightedGradeProvider()),
        ],
        child: GradeReviewScreen(assessment: assessment, results: results)));
  }

  group('GradeReviewScreen — empty state', () {
    testWidgets('shows empty state when no results', (tester) async {
      await tester.pumpWidget(
        wrapReview(assessment: makeAssessment(), results: []));
      await tester.pumpAndSettle();

      expect(find.text('No results to review'), findsOneWidget);
    });
  });
}
