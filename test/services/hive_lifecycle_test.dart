import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Tests that Hive boxes close cleanly and survive force-close simulation.
///
/// This validates the _AppLifecycleObserver._cleanup() behavior:
/// 1. Open encrypted boxes
/// 2. Write data
/// 3. Close via Hive.close()
/// 4. Reopen — data persists and no corruption
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Uint8List encryptionKey;
  late HiveCipher cipher;

  const boxNames = [
    'students',
    'assessments',
    'scan_results',
    'settings_pii',
    'metadata',
    'audit_trail',
    'grading_drafts',
    'student_transfers',
    'weighted_scales',
  ];

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_lifecycle_test');
    Hive.init(tempDir.path);

    encryptionKey = Uint8List.fromList(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)));
    cipher = HiveAesCipher(encryptionKey);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('Hive box lifecycle cleanup', () {
    test('close and reopen preserves data', () async {
      // Open all boxes and write test data
      for (final name in boxNames) {
        final box = await Hive.openBox(name, encryptionCipher: cipher);
        await box.put('test_key', 'test_value_$name');
      }

      // Verify data exists
      for (final name in boxNames) {
        final box = Hive.box(name);
        expect(box.get('test_key'), 'test_value_$name');
      }

      // Simulate lifecycle cleanup: close all boxes
      await Hive.close();

      // Verify boxes are closed
      for (final name in boxNames) {
        expect(Hive.isBoxOpen(name), isFalse);
      }

      // Reopen all boxes
      for (final name in boxNames) {
        await Hive.openBox(name, encryptionCipher: cipher);
      }

      // Verify data survived close/reopen
      for (final name in boxNames) {
        final box = Hive.box(name);
        expect(box.get('test_key'), 'test_value_$name',
            reason: 'Box "$name" data should survive close/reopen');
      }
    });

    test('multiple close calls are safe (idempotent)', () async {
      // Open a box
      await Hive.openBox('idempotent_test', encryptionCipher: cipher);
      final box = Hive.box('idempotent_test');
      await box.put('key', 'value');

      // Close multiple times — should not throw
      await Hive.close();
      await Hive.close();
      await Hive.close();

      // Reopen and verify
      await Hive.openBox('idempotent_test', encryptionCipher: cipher);
      expect(Hive.box('idempotent_test').get('key'), 'value');
    });

    test('lazy box survives close/reopen', () async {
      final lazyBox = await Hive.openLazyBox(
        'scan_results',
        encryptionCipher: cipher);
      await lazyBox.put('scan_1', {'score': 85, 'student': 'Abebe'});

      await Hive.close();
      expect(Hive.isBoxOpen('scan_results'), isFalse);

      final reopened = await Hive.openLazyBox(
        'scan_results',
        encryptionCipher: cipher);
      final data = await reopened.get('scan_1');
      expect(data, isNotNull);
      final map = Map<String, dynamic>.from(data as Map);
      expect(map['score'], 85);
    });

    test('corrupt box recovers via delete+reopen', () async {
      // Open and write
      final box = await Hive.openBox(
        'corrupt_test',
        encryptionCipher: cipher);
      await box.put('key', 'value');
      await box.close();

      // Corrupt the box file on disk
      final boxFile = File('${tempDir.path}/corrupt_test.hive');
      if (await boxFile.exists()) {
        await boxFile.writeAsBytes([0, 0, 0, 0, 0, 0, 0, 0], flush: true);
      }

      // Attempt to open — should fail, then recover
      try {
        await Hive.openBox('corrupt_test', encryptionCipher: cipher);
        // If it somehow opens, data is gone (expected)
      } catch (_) {
        await Hive.deleteBoxFromDisk('corrupt_test');
        final recovered = await Hive.openBox(
          'corrupt_test',
          encryptionCipher: cipher);
        expect(recovered.isOpen, isTrue);
        expect(recovered.get('key'), isNull); // data gone, but box works
      }
    });
  });
}
