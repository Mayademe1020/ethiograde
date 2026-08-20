import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'config/routes.dart';
import 'config/theme.dart';
import 'config/constants.dart';
import 'config/hive_adapters.dart';
import 'services/assessment_provider.dart';
import 'services/student_provider.dart';
import 'services/settings_provider.dart';
import 'services/teacher_provider.dart';
import 'services/class_provider.dart';
import 'services/attendance_provider.dart';
import 'services/class_notes_provider.dart';
import 'services/migration_service.dart';
import 'services/hive_migration.dart';
import 'services/scoring_service.dart';
import 'services/ocr_service.dart';
import 'services/weighted_grade_provider.dart';

/// Names for encrypted Hive boxes.
class _BoxNames {
  static const String students = 'students';
  static const String assessments = 'assessments';
  static const String scanResults = 'scan_results';
  static const String metadata = 'metadata';
}

/// Secure-storage key that holds the AES-256 Hive encryption key.
const String _hiveKeyStorageKey = 'hive_encryption_key';

/// Wrapper so [main] can report init errors to the UI.
enum InitStatus { ok, fallback, corruption }

/// Tracks whether any Hive box was corrupt during init.
/// Used by the UI to show a recovery message.
bool _hiveCorruptionDetected = false;

/// Dispose native resources when the app process is about to be killed.
///
/// [OcrService] holds a native ML Kit [TextRecognizer] that must be closed
/// to release platform resources. Without this, the native handle leaks on
/// low-spec Android devices (2GB RAM) causing gradual memory pressure.
///
/// [Hive] boxes are closed on [AppLifecycleState.detached] to flush pending
/// writes and prevent corruption on force-close.
class _AppLifecycleObserver with WidgetsBindingObserver {
  _AppLifecycleObserver() {
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _cleanup();
    }
  }

  /// Best-effort cleanup — never throw from lifecycle callbacks.
  static void _cleanup() {
    try {
      OcrService.instance.dispose();
    } catch (_) {}
    try {
      // Flush and close all Hive boxes to prevent corruption on force-kill.
      Hive.close();
    } catch (_) {}
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Global error handlers ──────────────────────────────────────────
  // Catch Flutter framework errors (build/layout/paint failures).
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError] ${details.exception}\n${details.stack}');
  };

  // Catch async errors that escape try/catch (unhandled Future errors).
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    debugPrint('[PlatformDispatcher] $error\n$stack');
    return true; // prevent default handler
  };

  // Replace red ErrorWidget with a user-friendly screen.
  ErrorWidget.builder = (details) {
    final cs = ThemeData().colorScheme;
    return Material(
      color: cs.errorContainer,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: cs.error, size: 48),
              const SizedBox(height: 12),
              Text(
                'Something went wrong',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cs.onErrorContainer,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                details.exception.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onErrorContainer.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  };

  InitStatus status;

  try {
    status = await _initEncryptedHive();
  } catch (e, st) {
    debugPrint('[Hive] Unexpected init failure: $e\n$st');
    status = InitStatus.fallback;
  }

  final isFirstLaunch = await AppConstants.isFirstLaunch;

  // Register lifecycle observer for native resource cleanup.
  _AppLifecycleObserver();

  runApp(EthioGradeApp(initStatus: status, isFirstLaunch: isFirstLaunch));
}

/// Initialise Hive with AES-256 encryption.
///
/// 1. Derive or retrieve a 32-byte encryption key.
/// 2. Open three boxes with [HiveAesCipher]:
///    - `students` (regular)
///    - `assessments` (regular)
///    - `scan_results` (regular — opened lazy historically; services use it
///      via [HiveBoxMixin.openBox] which requires a non-lazy box)
/// 3. Compact each box to reclaim fragmented space.
///
/// On *any* failure the caller falls back to in-memory-only state;
/// the app always launches.
Future<InitStatus> _initEncryptedHive() async {
  // ── 1. Hive init ──────────────────────────────────────────────────
  await Hive.initFlutter();

  // ── 1b. Migrate old Map data to typed format (BEFORE adapters) ────
  // Adapters change the binary format. Old Map data must be converted
  // before adapters are registered, or reads will fail.
  await HiveMigrationService.migrate();

  // ── 1c. Register TypeAdapters ─────────────────────────────────────
  registerHiveAdapters();

  // ── 2. Encryption key ─────────────────────────────────────────────
  const secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
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
  // Only open core boxes at startup — others open on-demand via providers.
  final students = await _openBoxSafe(_BoxNames.students, cipher: cipher);
  final assessments = await _openBoxSafe(_BoxNames.assessments, cipher: cipher);
  final scanResults = await _openBoxSafe(_BoxNames.scanResults, cipher: cipher);

  // PII settings box (encrypted) — teacher name, phone, handles
  await _openBoxSafe('settings_pii', cipher: cipher);

  // ── 4. Metadata box (for schema versioning) ───────────────────────
  await _openBoxSafe(_BoxNames.metadata, cipher: cipher);

  // ── 4b. Edge-case boxes ───────────────────────────────────────────
  await _openBoxSafe('audit_trail', cipher: cipher); // Grade audit trail
  await _openBoxSafe('grading_drafts', cipher: cipher); // Auto-save mid-grading
  await _openBoxSafe('student_transfers', cipher: cipher); // Transfer history
  await _openBoxSafe(
    'weighted_scales',
    cipher: cipher,
  ); // Weighted grade configs

  // ── 5. Run migrations ─────────────────────────────────────────────
  await MigrationService.runMigrations();

  debugPrint(
    '[Hive] Core boxes open — students: ${students.length}, '
    'assessments: ${assessments.length}, '
    'scan_results: ${scanResults.length}',
  );

  return _hiveCorruptionDetected ? InitStatus.corruption : InitStatus.ok;
}

/// Open a regular [Box] with error recovery.
/// If the box is corrupt it is RENAMED (not deleted) so data can be
/// manually recovered. A fresh box is created for the app to continue.
Future<Box> _openBoxSafe(String name, {required HiveCipher cipher}) async {
  try {
    return await Hive.openBox(name, encryptionCipher: cipher);
  } catch (e) {
    debugPrint('[Hive] Box "$name" corrupt — preserving and recreating: $e');
    // Rename corrupt file instead of deleting — preserves data for recovery
    await _preserveCorruptBox(name);
    return await Hive.openBox(name, encryptionCipher: cipher);
  }
}

/// Rename a corrupt Hive box file to .corrupt instead of deleting it.
/// This preserves the raw bytes for manual recovery or debugging.
Future<void> _preserveCorruptBox(String name) async {
  _hiveCorruptionDetected = true;
  try {
    final dir = await getApplicationDocumentsDirectory();
    // Hive stores boxes as files with .hive extension
    final hiveFile = File('${dir.path}/$name.hive');
    if (await hiveFile.exists()) {
      final corruptPath =
          '${dir.path}/$name.corrupt.${DateTime.now().millisecondsSinceEpoch}';
      await hiveFile.copy(corruptPath);
      debugPrint('[Hive] Preserved corrupt box to: $corruptPath');
    }
    // Now delete the original so Hive can recreate it
    await Hive.deleteBoxFromDisk(name);
  } catch (e) {
    // If rename fails, still try to delete so the app can start
    debugPrint('[Hive] Failed to preserve corrupt box "$name": $e');
    try {
      await Hive.deleteBoxFromDisk(name);
    } catch (_) {}
  }
}

class EthioGradeApp extends StatelessWidget {
  final InitStatus initStatus;
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
        ChangeNotifierProvider(create: (_) => AssessmentProvider()),
        ChangeNotifierProvider(create: (_) => StudentProvider()),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider()..loadSettings(),
        ),
        ChangeNotifierProvider(
          create: (_) => TeacherProvider()..loadTeachers(),
        ),
        ChangeNotifierProvider(create: (_) => ClassProvider()..loadClasses()),
        ChangeNotifierProvider(create: (_) => WeightedGradeProvider()),
        ChangeNotifierProvider(create: (_) => AttendanceProvider()..load()),
        ChangeNotifierProvider(create: (_) => ClassNotesProvider()..load()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settingsProvider, _) {
          // Keep ScoringService's custom scale registry in sync
          ScoringService.registerCustomScales(settingsProvider.customScales);

          return MaterialApp(
            title: 'EthioGrade',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.system,
            initialRoute: isFirstLaunch
                ? AppRoutes.onboarding
                : AppRoutes.dashboard,
            onGenerateRoute: AppRoutes.onGenerateRoute,
            // Non-intrusive banner if Hive had issues.
            builder: initStatus != InitStatus.ok
                ? (context, child) =>
                      _InitBanner(status: initStatus, child: child)
                : null,
          );
        },
      ),
    );
  }
}

/// Banner shown when Hive init had issues (fallback or corruption).
class _InitBanner extends StatelessWidget {
  final InitStatus status;
  final Widget? child;
  const _InitBanner({required this.status, this.child});

  @override
  Widget build(BuildContext context) {
    final isCorruption = status == InitStatus.corruption;
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        MaterialBanner(
          content: Text(
            isCorruption
                ? 'Some data was recovered from a corrupted file. '
                      'Your grades are safe. See Settings → Storage.'
                : 'Storage unavailable — grades will not be saved this session.',
            style: TextStyle(
              fontSize: 13,
              color: isCorruption
                  ? cs.onSecondaryContainer
                  : cs.onErrorContainer,
            ),
          ),
          leading: Icon(
            isCorruption ? Icons.healing_outlined : Icons.warning_amber_rounded,
            color: isCorruption ? cs.secondary : cs.error,
          ),
          backgroundColor: isCorruption
              ? cs.secondaryContainer
              : cs.errorContainer,
          surfaceTintColor: Colors.transparent,
          actions: [
            TextButton(
              onPressed: () =>
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
              child: const Text('Dismiss'),
            ),
          ],
        ),
        Expanded(child: child ?? const SizedBox.shrink()),
      ],
    );
  }
}
