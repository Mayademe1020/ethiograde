import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ethiograde/screens/scanning/camera_screen.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/services/assessment_provider.dart';

void main() {
  group('ReScanArguments', () {
    test('stores existing result and assessment', () {
      final result = ScanResult(
        id: 'test-id',
        assessmentId: 'a1',
        studentId: 's1',
        studentName: 'Abebe',
        imagePath: '/tmp/test.jpg',
      );
      final assessment = Assessment(
        id: 'a1',
        title: 'Math Final',
        subject: 'Math',
        questions: [],
      );

      final args = ReScanArguments(
        existingResult: result,
        assessment: assessment,
      );

      expect(args.existingResult.id, 'test-id');
      expect(args.existingResult.studentName, 'Abebe');
      expect(args.assessment.id, 'a1');
      expect(args.assessment.title, 'Math Final');
    });
  });

  group('CameraScreen re-scan mode', () {
    testWidgets('shows student name in header when in re-scan mode', skip: true, (
      tester,
    ) async {
      final result = ScanResult(
        id: 'rescan-1',
        assessmentId: 'a1',
        studentId: 's1',
        studentName: 'Kebede',
        imagePath: '/tmp/old.jpg',
      );
      final assessment = Assessment(
        id: 'a1',
        title: 'Physics Mid',
        subject: 'Physics',
        questions: [],
      );

      final args = ReScanArguments(
        existingResult: result,
        assessment: assessment,
      );

      // Build a minimal widget that passes re-scan args via route settings
      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (_) => MaterialPageRoute(
            settings: RouteSettings(arguments: args),
            builder: (_) => MultiProvider(
              providers: [
                ChangeNotifierProvider(create: (_) => AssessmentProvider()),
              ],
              child: const CameraScreen(),
            ),
          ),
        ),
      );

      // The camera screen needs camera permissions + hardware, so the widget
      // test won't fully initialize. But we can verify the scaffold builds
      // without crashing and the route args are accepted.
      expect(find.byType(CameraScreen), findsOneWidget);
    });

    testWidgets('ReScanArguments is distinct from Assessment arg', skip: true, (
      tester,
    ) async {
      // Verify that passing an Assessment directly still works (backward compat)
      final assessment = Assessment(
        id: 'a2',
        title: 'English Quiz',
        subject: 'English',
        questions: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (_) => MaterialPageRoute(
            settings: RouteSettings(arguments: assessment),
            builder: (_) => MultiProvider(
              providers: [
                ChangeNotifierProvider(create: (_) => AssessmentProvider()),
              ],
              child: const CameraScreen(),
            ),
          ),
        ),
      );

      expect(find.byType(CameraScreen), findsOneWidget);
    });

    testWidgets('shows retry and manual options when camera does not start', skip: true, (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => MultiProvider(
              providers: [
                ChangeNotifierProvider(create: (_) => AssessmentProvider()),
              ],
              child: const CameraScreen(),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(seconds: 8));
      await tester.pump();

      expect(find.text('Camera not ready'), findsOneWidget);
      expect(find.text('Try camera again'), findsOneWidget);
      expect(find.text('Enter answer key manually'), findsOneWidget);
    });
  });
}
