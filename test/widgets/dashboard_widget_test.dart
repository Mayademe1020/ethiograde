import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ethiograde/screens/home/main_dashboard.dart';
import 'package:ethiograde/services/locale_provider.dart';
import 'package:ethiograde/services/assessment_provider.dart';
import 'package:ethiograde/services/student_provider.dart';
import 'package:ethiograde/services/settings_provider.dart';
import 'package:ethiograde/config/theme.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/student.dart';

void main() {
  late LocaleProvider localeProvider;
  late SettingsProvider settingsProvider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    localeProvider = LocaleProvider();
    settingsProvider = SettingsProvider();
  });

  /// Helper that wraps MainDashboard in full provider context.
  Widget buildDashboard({bool isAmharic = false}) {
    if (isAmharic) {
      localeProvider.setLocale('am');
    }

    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
          ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
          ChangeNotifierProvider<StudentProvider>(create: (_) => StudentProvider()),
          ChangeNotifierProvider<AssessmentProvider>(create: (_) => AssessmentProvider()),
        ],
        child: const MainDashboard(),
      ),
    );
  }

  group('MainDashboard — rendering', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      expect(find.byType(MainDashboard), findsOneWidget);
    });

    testWidgets('shows bottom navigation with 4 tabs', (tester) async {
      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      // NavigationBar with 4 destinations
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Assess'), findsOneWidget);
      expect(find.text('Students'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('shows Amharic tab labels when locale is Amharic', (tester) async {
      await tester.pumpWidget(buildDashboard(isAmharic: true));
      await tester.pumpAndSettle();

      expect(find.text('ዋና'), findsOneWidget);
      expect(find.text('ፈተና'), findsWidgets); // Appears in tab + elsewhere
      expect(find.text('ተማሪዎች'), findsWidgets);
      expect(find.text('ቅንብር'), findsOneWidget);
    });
  });

  group('MainDashboard — Home tab', () {
    testWidgets('shows welcome message', (tester) async {
      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      // Should show welcome text (may be "Welcome, " with empty name)
      expect(find.byType(SliverToBoxAdapter), findsWidgets);
    });

    testWidgets('shows stat cards for students, active, completed', (tester) async {
      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      // StatCard widgets should be present
      expect(find.text('Students'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
    });

    testWidgets('shows empty state when no assessments', (tester) async {
      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      // Empty state should show "No assessments yet"
      expect(find.text('No assessments yet'), findsOneWidget);
    });

    testWidgets('shows quick actions', (tester) async {
      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      expect(find.text('Scan'), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);
      expect(find.text('Analytics'), findsOneWidget);
      expect(find.text('Reports'), findsOneWidget);
    });

    testWidgets('shows Amharic quick actions', (tester) async {
      await tester.pumpWidget(buildDashboard(isAmharic: true));
      await tester.pumpAndSettle();

      expect(find.text('ማሰስ'), findsOneWidget);
      expect(find.text('Excel አስገባ'), findsOneWidget);
      expect(find.text('ትንተና'), findsOneWidget);
      expect(find.text('ሪፖርት'), findsOneWidget);
    });

    testWidgets('shows Recent Assessments section', (tester) async {
      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      expect(find.text('Recent Assessments'), findsOneWidget);
    });

    testWidgets('shows language toggle', (tester) async {
      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      expect(find.byType(Icon), findsWidgets);
    });
  });

  group('MainDashboard — navigation', () {
    testWidgets('tapping Assess tab shows assessments view', (tester) async {
      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      // Tap "Assess" tab
      await tester.tap(find.text('Assess'));
      await tester.pumpAndSettle();

      // Should show assessments tab header
      expect(find.text('No assessments'), findsOneWidget);
    });

    testWidgets('tapping Students tab shows students view', (tester) async {
      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Students'));
      await tester.pumpAndSettle();

      // Should show search bar and empty state
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('tapping Settings tab shows settings view', (tester) async {
      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsWidgets);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Preferences'), findsOneWidget);
    });
  });

  group('MainDashboard — empty states', () {
    testWidgets('home empty state is bilingual', (tester) async {
      // English
      await tester.pumpWidget(buildDashboard(isAmharic: false));
      await tester.pumpAndSettle();
      expect(find.text('No assessments yet'), findsOneWidget);

      // Reset and test Amharic
      SharedPreferences.setMockInitialValues({});
      localeProvider = LocaleProvider();
      await tester.pumpWidget(buildDashboard(isAmharic: true));
      await tester.pumpAndSettle();
      expect(find.text('ገና ምንም ፈተና የለም'), findsOneWidget);
    });

    testWidgets('students empty state shows import hint', (tester) async {
      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Students'));
      await tester.pumpAndSettle();

      expect(find.text('No students — Import Excel or add manually'), findsOneWidget);
    });

    testWidgets('students Amharic empty state', (tester) async {
      await tester.pumpWidget(buildDashboard(isAmharic: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ተማሪዎች'));
      await tester.pumpAndSettle();

      expect(find.text('ተማሪ የለም — Excel ይምጡ ወይም ያክሉ'), findsOneWidget);
    });
  });

  group('MainDashboard — FAB', () {
    testWidgets('FAB appears on home tab', (tester) async {
      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('New Assessment'), findsOneWidget);
    });

    testWidgets('FAB shows Amharic text', (tester) async {
      await tester.pumpWidget(buildDashboard(isAmharic: true));
      await tester.pumpAndSettle();

      expect(find.text('አዲስ ፈተና'), findsOneWidget);
    });

    testWidgets('FAB disappears on other tabs', (tester) async {
      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      // FAB visible on home
      expect(find.byType(FloatingActionButton), findsOneWidget);

      // Switch to Assess tab
      await tester.tap(find.text('Assess'));
      await tester.pumpAndSettle();

      // FAB should be gone
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });

  group('MainDashboard — settings tab', () {
    testWidgets('shows profile section with name and school', (tester) async {
      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('School'), findsOneWidget);
    });

    testWidgets('shows language toggle switch', (tester) async {
      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.byType(SwitchListTile), findsWidgets);
    });

    testWidgets('shows Ethiopian calendar toggle', (tester) async {
      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Ethiopian Calendar'), findsOneWidget);
    });

    testWidgets('shows subscription section', (tester) async {
      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Subscription'), findsOneWidget);
      expect(find.text('Individual Teacher'), findsOneWidget);
    });
  });
}
