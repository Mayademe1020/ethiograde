import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/student.dart';
import '../models/assessment.dart';
import '../models/scan_result.dart';
import 'app_log.dart';
import 'error_handler.dart';
import 'hive_box_mixin.dart';
import 'validation_service.dart';

/// Import result with counts and error details.
class ImportResult {
  final int imported;
  final int skipped;
  final List<String> errors;

  const ImportResult({
    required this.imported,
    required this.skipped,
    required this.errors,
  });

  bool get hasErrors => errors.isNotEmpty;

  @override
  String toString() =>
      'ImportResult(imported: $imported, skipped: $skipped, errors: ${errors.length})';
}

/// Export / import / auto-backup for all EthioGrade data.
///
/// Manual exports are encrypted backup files. Imports validate every record
/// via [ValidationService] before writing.
class BackupService with HiveBoxMixin {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const ValidationService _validator = ValidationService();
  static const String _studentsBox = 'students';
  static const String _assessmentsBox = 'assessments';
  static const String _scanResultsBox = 'scan_results';
  static const String _metadataBox = 'metadata';
  static const String _autoBackupCountKey = 'auto_backup_scan_count';
  static const String _hiveKeyStorageKey = 'hive_encryption_key';

  static const int _autoBackupInterval = 10;
  static const int _maxAutoBackups = 3;

  // ── Export ─────────────────────────────────────────────────────────

  /// Export all data to an encrypted timestamped backup file.
  /// Uses the same AES-256 key as Hive storage.
  /// Returns the file path on success, null on failure.
  Future<String?> exportAllData() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final filePath = '${dir.path}/ethiograde_backup_$timestamp.enc';

      final data = await _collectAllData();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

      final encrypted = await _encryptData(jsonStr);
      if (encrypted == null) {
        AppLog.warn(this, 'exportAllData', 'encryption failed, aborting export');
        return null;
      }

      await File(filePath).writeAsBytes(encrypted);
      AppLog.info(this, 'exportAllData', 'exported encrypted to $filePath');
      return filePath;
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'exportAllData', e, st);
      return null;
    }
  }

  /// Export and open the system share sheet.
  Future<void> exportAndShare() async {
    final filePath = await exportAllData();
    if (filePath == null) return;

    try {
      await Share.shareXFiles(
        [XFile(filePath)],
        subject: 'EthioGrade Backup',
        text: 'EthioGrade data backup',
      );
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'exportAndShare', e, st);
    }
  }

  // ── Import ─────────────────────────────────────────────────────────

  /// Import data from a JSON backup file.
  ///
  /// [replace] — if true, clears all existing data before importing.
  ///             if false, merges (skips duplicates by ID).
  Future<ImportResult> importData(
    String filePath, {
    bool replace = false,
  }) async {
    final errors = <String>[];
    int imported = 0;
    int skipped = 0;

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return ImportResult(
          imported: 0,
          skipped: 0,
          errors: ['File not found: $filePath'],
        );
      }

      late final String jsonStr;
      if (filePath.endsWith('.enc')) {
        final decrypted = await _decryptData(await file.readAsBytes());
        if (decrypted == null) {
          return const ImportResult(
            imported: 0,
            skipped: 0,
            errors: [
              'Failed to decrypt backup — wrong device or corrupted file',
            ],
          );
        }
        jsonStr = decrypted;
      } else {
        jsonStr = await file.readAsString();
      }

      final Map<String, dynamic> data;
      try {
        data = jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (e, st) {
        AppErrorHandler.catchError(this, 'importData/jsonDecode', e, st);
        return ImportResult(
          imported: 0,
          skipped: 0,
          errors: ['Invalid JSON: $e'],
        );
      }

      final version = data['version'] as int? ?? 0;
      if (version < 1) {
        return ImportResult(
          imported: 0,
          skipped: 0,
          errors: ['Unsupported backup version: $version'],
        );
      }

      if (replace) {
        await _clearAllBoxes();
      }

      final students = data['students'] as List? ?? [];
      for (final item in students) {
        try {
          final map = Map<String, dynamic>.from(item as Map);
          final student = Student.fromMap(map);
          final validation = _validator.validateStudent(student);
          if (!validation.isValid) {
            errors.add(
              'Student ${student.id}: ${validation.errors.join("; ")}',
            );
            skipped++;
            continue;
          }

          final box = await openBox(_studentsBox);
          if (!replace && box.containsKey(student.id)) {
            skipped++;
            continue;
          }
          await box.put(student.id, student.toMap());
          imported++;
        } catch (e, st) {
          AppErrorHandler.catchError(this, 'importData/student', e, st);
          errors.add('Student record: $e');
          skipped++;
        }
      }

      final assessments = data['assessments'] as List? ?? [];
      for (final item in assessments) {
        try {
          final map = Map<String, dynamic>.from(item as Map);
          final assessment = Assessment.fromMap(map);
          final validation = _validator.validateAssessment(assessment);
          if (!validation.isValid) {
            errors.add(
              'Assessment ${assessment.id}: ${validation.errors.join("; ")}',
            );
            skipped++;
            continue;
          }

          final box = await openBox(_assessmentsBox);
          if (!replace && box.containsKey(assessment.id)) {
            skipped++;
            continue;
          }
          await box.put(assessment.id, assessment.toMap());
          imported++;
        } catch (e, st) {
          AppErrorHandler.catchError(this, 'importData/assessment', e, st);
          errors.add('Assessment record: $e');
          skipped++;
        }
      }

      final scanResults = data['scanResults'] as List? ?? [];
      for (final item in scanResults) {
        try {
          final map = Map<String, dynamic>.from(item as Map);
          final scan = ScanResult.fromMap(map);
          final validation = _validator.validateScanResult(scan);
          if (!validation.isValid) {
            errors.add(
              'ScanResult ${scan.id}: ${validation.errors.join("; ")}',
            );
            skipped++;
            continue;
          }

          final box = await openBox(_scanResultsBox);
          if (!replace) {
            final existing = await box.get(scan.id);
            if (existing != null) {
              skipped++;
              continue;
            }
          }
          await box.put(scan.id, scan.toMap());
          imported++;
        } catch (e, st) {
          AppErrorHandler.catchError(this, 'importData/scanResult', e, st);
          errors.add('ScanResult record: $e');
          skipped++;
        }
      }

      AppLog.info(
        this,
        'importData',
        'import done: $imported imported, $skipped skipped, '
        '${errors.length} errors',
      );
      return ImportResult(imported: imported, skipped: skipped, errors: errors);
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'importData', e, st);
      return ImportResult(
        imported: 0,
        skipped: 0,
        errors: ['Import failed: $e'],
      );
    }
  }

  // ── Auto-backup ───────────────────────────────────────────────────

  /// Call after every scan. Auto-backs up every [_autoBackupInterval] scans.
  Future<void> recordScanAndMaybeBackup() async {
    try {
      final metaBox = await openBox(_metadataBox);
      final count =
          (metaBox.get(_autoBackupCountKey, defaultValue: 0) as int) + 1;

      if (count >= _autoBackupInterval) {
        await metaBox.put(_autoBackupCountKey, 0);
        await _autoBackup();
      } else {
        await metaBox.put(_autoBackupCountKey, count);
      }
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'recordScanAndMaybeBackup', e, st);
    }
  }

  /// Create a timestamped auto-backup and prune old ones.
  Future<void> _autoBackup() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final filePath = '${dir.path}/ethiograde_auto_$timestamp.enc';

      final data = await _collectAllData();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final encrypted = await _encryptData(jsonStr);
      if (encrypted == null) {
        AppLog.warn(this, '_autoBackup', 'encryption failed, aborting');
        return;
      }

      await File(filePath).writeAsBytes(encrypted);
      AppLog.info(this, '_autoBackup', 'saved to $filePath');

      final autoBackups =
          dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.contains('ethiograde_auto_'))
              .toList()
            ..sort((a, b) => b.path.compareTo(a.path));

      for (int i = _maxAutoBackups; i < autoBackups.length; i++) {
        try {
          await autoBackups[i].delete();
          AppLog.info(this, '_autoBackup', 'pruned old backup: ${autoBackups[i].path}');
        } catch (e, st) {
          AppErrorHandler.catchError(this, '_autoBackup/prune', e, st);
        }
      }
    } catch (e, st) {
      AppErrorHandler.catchError(this, '_autoBackup', e, st);
    }
  }

  // ── List backups ──────────────────────────────────────────────────

  /// List all backup files (manual + auto) with metadata.
  Future<List<BackupInfo>> listBackups() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final backups = <BackupInfo>[];

      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        if (!entity.path.contains('ethiograde_')) continue;
        if (!entity.path.endsWith('.json') && !entity.path.endsWith('.enc')) {
          continue;
        }

        try {
          final stat = await entity.stat();
          final name = entity.path.split(RegExp(r'[\\/]')).last;
          final isAuto = name.contains('_auto_');
          backups.add(
            BackupInfo(
              filePath: entity.path,
              fileName: name,
              date: stat.modified,
              sizeBytes: stat.size,
              isAutoBackup: isAuto,
            ),
          );
        } catch (e, st) {
          AppErrorHandler.catchError(this, 'listBackups/stat', e, st);
        }
      }

      backups.sort((a, b) => b.date.compareTo(a.date));
      return backups;
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'listBackups', e, st);
      return [];
    }
  }

  // ── Verify backup integrity ───────────────────────────────────────

  /// Verify a backup file's integrity without importing it.
  /// Returns null on success, or an error message on failure.
  Future<String?> verifyBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return 'File not found: $filePath';
      }

      final content = await file.readAsBytes();
      if (content.length < 17) {
        return 'File too small — not a valid backup';
      }

      final decrypted = await _decryptData(content);
      if (decrypted == null) {
        return 'Failed to decrypt — wrong device or corrupted file';
      }

      final data = jsonDecode(decrypted) as Map<String, dynamic>;

      final version = data['version'] as int? ?? 0;
      if (version < 1) {
        return 'Unsupported backup version: $version';
      }

      final checksum = data['checksum'] as String?;
      if (checksum != null) {
        final dataWithoutChecksum = Map<String, dynamic>.from(data)
          ..remove('checksum');
        final computedChecksum = _computeChecksum(dataWithoutChecksum);
        if (computedChecksum != checksum) {
          return 'Checksum mismatch — backup file has been corrupted';
        }
      }

      final requiredKeys = ['version', 'exportDate', 'students', 'assessments', 'scanResults'];
      for (final key in requiredKeys) {
        if (!data.containsKey(key)) {
          return 'Missing required key: $key';
        }
      }

      AppLog.info(this, 'verifyBackup', 'backup verified successfully: $filePath');
      return null;
    } catch (e, st) {
      AppErrorHandler.catchError(this, 'verifyBackup', e, st);
      return 'Verification failed: $e';
    }
  }

  // ── Encryption ─────────────────────────────────────────────────────

  /// Encrypt JSON string with AES-256-CBC using the Hive encryption key.
  /// Returns bytes: [16-byte IV][encrypted data].
  /// Returns null if key not available.
  Future<Uint8List?> _encryptData(String plainText) async {
    try {
      final keyBytes = await _getEncryptionKey();
      if (keyBytes == null) return null;

      final iv = enc.IV(
        Uint8List.fromList(
          List<int>.generate(16, (_) => Random.secure().nextInt(256)),
        ),
      );
      final encrypter = enc.Encrypter(
        enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc),
      );
      final encrypted = encrypter.encrypt(plainText, iv: iv);

      final result = Uint8List(16 + encrypted.bytes.length);
      result.setAll(0, iv.bytes);
      result.setAll(16, encrypted.bytes);
      return result;
    } catch (e, st) {
      AppErrorHandler.catchError(this, '_encryptData', e, st);
      return null;
    }
  }

  /// Decrypt AES-256-CBC bytes. Expects [16-byte IV][encrypted data].
  /// Returns JSON string or null on failure.
  Future<String?> _decryptData(Uint8List data) async {
    try {
      if (data.length < 17) return null;

      final keyBytes = await _getEncryptionKey();
      if (keyBytes == null) return null;

      final iv = enc.IV(data.sublist(0, 16));
      final encryptedBytes = data.sublist(16);
      final encrypter = enc.Encrypter(
        enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc),
      );
      return encrypter.decrypt64(base64Encode(encryptedBytes), iv: iv);
    } catch (e, st) {
      AppErrorHandler.catchError(this, '_decryptData', e, st);
      return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  /// Read the AES-256 key from secure storage (same as Hive uses).
  Future<Uint8List?> _getEncryptionKey() async {
    try {
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      final storedKey = await storage.read(key: _hiveKeyStorageKey);
      if (storedKey == null || storedKey.isEmpty) return null;
      return base64Decode(storedKey);
    } catch (e, st) {
      AppErrorHandler.catchError(this, '_getEncryptionKey', e, st);
      return null;
    }
  }

  /// Collect all data from all boxes into a single JSON-serialisable map.
  Future<Map<String, dynamic>> _collectAllData() async {
    final studentsBox = await openBox(_studentsBox);
    final assessmentsBox = await openBox(_assessmentsBox);
    final scanResultsBox = await openBox(_scanResultsBox);

    final students = studentsBox.values
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();

    final assessments = assessmentsBox.values
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();

    final scanResults = <Map<String, dynamic>>[];
    for (final key in scanResultsBox.keys) {
      final data = await scanResultsBox.get(key);
      if (data != null) {
        scanResults.add(Map<String, dynamic>.from(data as Map));
      }
    }

    final data = {
      'version': 1,
      'exportDate': DateTime.now().toIso8601String(),
      'students': students,
      'assessments': assessments,
      'scanResults': scanResults,
    };

    data['checksum'] = _computeChecksum(data);

    return data;
  }

  /// Compute SHA-256 checksum of the data map.
  String _computeChecksum(Map<String, dynamic> data) {
    final canonicalJson = jsonEncode(data);
    return sha256.convert(utf8.encode(canonicalJson)).toString();
  }

  /// Clear all data boxes (used in replace-mode import).
  Future<void> _clearAllBoxes() async {
    try {
      await (await openBox(_studentsBox)).clear();
      await (await openBox(_assessmentsBox)).clear();
      await (await openBox(_scanResultsBox)).clear();
      AppLog.info(this, '_clearAllBoxes', 'all boxes cleared for replace import');
    } catch (e, st) {
      AppErrorHandler.catchError(this, '_clearAllBoxes', e, st);
    }
  }
}

/// Metadata about a backup file.
class BackupInfo {
  final String filePath;
  final String fileName;
  final DateTime date;
  final int sizeBytes;
  final bool isAutoBackup;

  const BackupInfo({
    required this.filePath,
    required this.fileName,
    required this.date,
    required this.sizeBytes,
    required this.isAutoBackup,
  });

  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
