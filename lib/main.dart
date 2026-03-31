import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'config/routes.dart';
import 'config/theme.dart';
import 'config/constants.dart';
import 'services/locale_provider.dart';
import 'services/assessment_provider.dart';
import 'services/student_provider.dart';
import 'services/analytics_provider.dart';
import 'services/settings_provider.dart';
import 'services/teacher_provider.dart';
import 'services/migration_service.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/home/main_dashboard.dart';

/// Names for encrypted Hive boxes.
class _BoxNames {
  static const String students = 'students';
  static const String assessments = 'assessments';
  static const String scanResults = 'scan_results';
  static const String teachers = 'teachers';
  static const String metadata = 'metadata';
}

/// Secure-storage key that holds the AES-256 Hive encryption key.
const String _hiveKeyStorageKey = 'hive_encryption_key';

/// Wrapper so [main] can report init errors to the UI.
enum _InitStatus { ok, fallback }

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _InitStatus status;

  try {
    status = await _initEncryptedHive();
  } catch (e, st) {
    debugPrint('[Hive] Unexpected init failure: $e\n$st');
    status = _InitStatus.fallback;
  }

  // isFirstLaunch is async — resolve before runApp so MaterialApp
  // can pick the correct initialRoute synchronously.
  final isFirstLaunch = await AppConstants.checkFirstLaunch();

  runApp(EthioGradeApp(
    initStatus: status,
    isFirstLaunch: isFirstLaunch,
  ));
}

/// Initialise Hive with AES-256 encryption.
///
/// 1. Derive or retrieve a 32-byte encryption key.
/// 2. Open three boxes with [HiveAesCipher]:
///    - `students` (regular)
///    - `assessments` (regular)
///    - `scan_results` (LAZY — expected to grow large)
/// 3. Compact each box to reclaim fragmented space.
///
/// On *any* failure the caller falls back to in-memory-only state;
/// the app always launches.
Future<_InitStatus> _initEncryptedHive() async {
  // ── 1. Hive init ──────────────────────────────────────────────────
  await Hive.initFlutter();

  // ── 2. Encryption key ─────────────────────────────────────────────
  final secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  Uint8List encryptionKey;

  final storedKey = await secureStorage.read(key: _hiveKeyStorageKey);
  if (storedKey != null && storedKey.isNotEmpty) {
    encryptionKey = base64Decode(storedKey);
    debugPrint('[Hive] Loaded existing encryption key');
  } else {
    encryptionKey = Uint8List.fromList(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    await secureStorage.write(
      key: _hiveKeyStorageKey,
      value: base64Encode(encryptionKey),
    );
    debugPrint('[Hive] Generated new AES-256 encryption key');
  }

  final cipher = HiveAesCipher(encryptionKey);

  // ── 3. Open boxes ─────────────────────────────────────────────────
  final students = await _openBoxSafe(
    _BoxNames.students,
    cipher: cipher,
  );
  final assessments = await _openBoxSafe(
    _BoxNames.assessments,
    cipher: cipher,
  );
  final scanResults = await _openLazyBoxSafe(
    _BoxNames.scanResults,
    cipher: cipher,
  );

  final teachers = await _openBoxSafe(
    _BoxNames.teachers,
    cipher: cipher,
  );

  // ── 4. Compact ────────────────────────────────────────────────────
  await students.compact();
  await assessments.compact();
  await scanResults.compact();
  await teachers.compact();

  // ── 5. Metadata box (for schema versioning) ───────────────────────
  final metadata = await _openBoxSafe(
    _BoxNames.metadata,
    cipher: cipher,
  );
  await metadata.compact();

  // ── 6. Run migrations ─────────────────────────────────────────────
  await MigrationService.runMigrations();

  debugPrint('[Hive] Boxes open — students: ${students.length}, '
      'assessments: ${assessments.length}, '
      'scan_results: ${scanResults.length}, '
      'teachers: ${teachers.length}');

  return _InitStatus.ok;
}

/// Open a regular [Box] with error recovery.
/// If the box is corrupt it is deleted and recreated.
Future<Box> _openBoxSafe(
  String name, {
  required HiveCipher cipher,
}) async {
  try {
    return await Hive.openBox(name, encryptionCipher: cipher);
  } catch (e) {
    debugPrint('[Hive] Box "$name" corrupt — deleting and recreating: $e');
    await Hive.deleteBoxFromDisk(name);
    return await Hive.openBox(name, encryptionCipher: cipher);
  }
}

/// Open a [LazyBox] with error recovery.
Future<LazyBox<List>> _openLazyBoxSafe(
  String name, {
  required HiveCipher cipher,
}) async {
  try {
    return await Hive.openLazyBox<List>(name, encryptionCipher: cipher);
  } catch (e) {
    debugPrint('[Hive] Lazy box "$name" corrupt — deleting and recreating: $e');
    await Hive.deleteBoxFromDisk(name);
    return await Hive.openLazyBox<List>(name, encryptionCipher: cipher);
  }
}

class EthioGradeApp extends StatelessWidget {
  final _InitStatus initStatus;
  final bool isFirstLaunch;

  const EthioGradeApp({
    super.key,
    required this.initStatus,
    required this.isFirstLaunch,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => AssessmentProvider()),
        ChangeNotifierProvider(create: (_) => StudentProvider()),
        ChangeNotifierProvider(create: (_) => AnalyticsProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => TeacherProvider()),
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
            initialRoute: isFirstLaunch
                ? AppRoutes.onboarding
                : AppRoutes.dashboard,
            onGenerateRoute: AppRoutes.onGenerateRoute,
            // Non-intrusive banner if Hive fell back to in-memory mode.
            builder: initStatus == _InitStatus.fallback
                ? (context, child) => _FallbackBanner(child: child)
                : null,
          );
        },
      ),
    );
  }
}

/// Thin banner that slides in when storage init failed.
class _FallbackBanner extends StatelessWidget {
  final Widget? child;
  const _FallbackBanner({this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
          MaterialBanner(
          content: const Text(
            'Storage unavailable — data will not be saved this session.',
          ),
          leading: const Icon(Icons.warning_amber_rounded),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          actions: [
            TextButton(
              onPressed: () => ScaffoldMessenger.of(context)
                  .hideCurrentMaterialBanner(),
              child: const Text('DISMISS'),
            ),
          ],
        ),
        Expanded(child: child ?? const SizedBox.shrink()),
      ],
    );
  }
}
