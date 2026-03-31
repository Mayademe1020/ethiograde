import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ethiograde/services/session_service.dart';

void main() {
  late Box metadataBox;
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('session_test');
    Hive.init(tempDir.path);
    metadataBox = await Hive.openBox('metadata');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await metadataBox.clear();
  });

  group('SessionService', () {
    test('saveSession persists to Hive', () async {
      await SessionService().saveSession(
        assessmentId: 'test-123',
        assessmentTitle: 'Math Final',
        imagePaths: ['/tmp/img1.jpg', '/tmp/img2.jpg'],
      );

      final data = metadataBox.get('active_scan_session');
      expect(data, isNotNull);
      final map = Map<String, dynamic>.from(data as Map);
      expect(map['assessmentId'], 'test-123');
      expect(map['assessmentTitle'], 'Math Final');
      expect(map['imagePaths'], ['/tmp/img1.jpg', '/tmp/img2.jpg']);
      expect(map['completed'], false);
    });

    test('completeSession deletes session from Hive', () async {
      await SessionService().saveSession(
        assessmentId: 'test-123',
        assessmentTitle: 'Math Final',
        imagePaths: ['/tmp/img1.jpg'],
      );
      await SessionService().completeSession();

      final data = metadataBox.get('active_scan_session');
      expect(data, isNull);
    });

    test('getActiveSession returns null when no session', () async {
      final session = await SessionService().getActiveSession();
      expect(session, isNull);
    });

    test('getActiveSession returns null for completed session', () async {
      await metadataBox.put('active_scan_session', {
        'assessmentId': 'test-123',
        'assessmentTitle': 'Math',
        'imagePaths': ['/tmp/img1.jpg'],
        'completed': true,
      });

      final session = await SessionService().getActiveSession();
      expect(session, isNull);
    });

    test('getActiveSession returns session with existing images', () async {
      // Create a real temp file
      final tmpFile = File('${tempDir.path}/test_img.jpg');
      await tmpFile.writeAsBytes([0xFF, 0xD8, 0xFF]); // JPEG header

      await SessionService().saveSession(
        assessmentId: 'test-456',
        assessmentTitle: 'English Quiz',
        imagePaths: [tmpFile.path],
      );

      final session = await SessionService().getActiveSession();
      expect(session, isNotNull);
      expect(session!.assessmentId, 'test-456');
      expect(session.imageCount, 1);
      expect(session.imagePaths.first, tmpFile.path);

      // Cleanup
      await tmpFile.delete();
    });

    test('getActiveSession filters out missing image files', () async {
      final existingFile = File('${tempDir.path}/exists.jpg');
      await existingFile.writeAsBytes([0xFF, 0xD8]);
      final missingPath = '${tempDir.path}/does_not_exist.jpg';

      await SessionService().saveSession(
        assessmentId: 'test-789',
        assessmentTitle: 'Science',
        imagePaths: [existingFile.path, missingPath],
      );

      final session = await SessionService().getActiveSession();
      expect(session, isNotNull);
      expect(session!.imageCount, 1);
      expect(session.imagePaths.first, existingFile.path);

      await existingFile.delete();
    });

    test('getActiveSession returns null when all images are gone', () async {
      await SessionService().saveSession(
        assessmentId: 'test-gone',
        assessmentTitle: 'History',
        imagePaths: ['/tmp/gone1.jpg', '/tmp/gone2.jpg'],
      );

      final session = await SessionService().getActiveSession();
      expect(session, isNull);
      // Session should be cleaned up
      expect(metadataBox.get('active_scan_session'), isNull);
    });

    test('discardSession cleans up images and deletes session', () async {
      final tmpFile = File('${tempDir.path}/discard_test.jpg');
      await tmpFile.writeAsBytes([0x00]);

      await SessionService().saveSession(
        assessmentId: 'test-discard',
        assessmentTitle: 'Art',
        imagePaths: [tmpFile.path],
      );

      await SessionService().discardSession();

      expect(await tmpFile.exists(), false);
      expect(metadataBox.get('active_scan_session'), isNull);
    });
  });
}
