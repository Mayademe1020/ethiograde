import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'config/routes.dart';
import 'config/theme.dart';
import 'config/constants.dart';
import 'services/locale_provider.dart';
import 'services/assessment_provider.dart';
import 'services/student_provider.dart';
import 'services/analytics_provider.dart';
import 'services/settings_provider.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/home/main_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for local storage
  await Hive.initFlutter();
  await Hive.openBox(AppConstants.settingsBox);
  await Hive.openBox(AppConstants.studentsBox);
  await Hive.openBox(AppConstants.assessmentsBox);
  await Hive.openBox(AppConstants.resultsBox);
  await Hive.openBox(AppConstants.syncQueueBox);

  runApp(const EthioGradeApp());
}

class EthioGradeApp extends StatelessWidget {
  const EthioGradeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => AssessmentProvider()),
        ChangeNotifierProvider(create: (_) => StudentProvider()),
        ChangeNotifierProvider(create: (_) => AnalyticsProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, _) {
          return MaterialApp(
            title: 'EthioGrade',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.light,
            locale: localeProvider.locale,
            supportedLocales: const [
              Locale('en', 'US'),
              Locale('am', 'ET'),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            initialRoute: AppConstants.isFirstLaunch
                ? AppRoutes.onboarding
                : AppRoutes.dashboard,
            onGenerateRoute: AppRoutes.onGenerateRoute,
          );
        },
      ),
    );
  }
}
