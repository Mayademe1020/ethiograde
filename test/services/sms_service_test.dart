import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:ethiograde/services/sms_service.dart';

/// Fake url_launcher platform that records launched URIs.
class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launched = <String>[];
  bool shouldSucceed = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return shouldSucceed;
  }
}

void main() {
  late Directory tempDir;
  late _FakeUrlLauncher fakeLauncher;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('sms_service_test_');
    Hive.init(tempDir.path);
  });

  setUp(() {
    fakeLauncher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = fakeLauncher;
  });

  tearDown(() async {
    for (final name in ['sms_history', 'sms_offline_queue']) {
      if (Hive.isBoxOpen(name)) {
        await Hive.box(name).clear();
        await Hive.box(name).close();
      }
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('SmsTemplate', () {
    test('renders English template with placeholders', () {
      final text = DefaultTemplates.resultNotification.render(
        studentName: 'Abebe',
        subject: 'Math',
        percentage: 85.0,
        schoolName: 'My School',
      );
      expect(text, 'Abebe scored 85.0% in Math. - My School');
    });

    test('renders Amharic template', () {
      final text = DefaultTemplates.resultNotification.render(
        studentName: 'አበበ',
        subject: 'ሂሳብ',
        percentage: 85.0,
        schoolName: 'ትምህርት ቤት',
        amharic: true,
      );
      expect(text, contains('አበበ'));
      expect(text, contains('85.0'));
      expect(text, contains('ትምህርት ቤት'));
    });
  });

  group('SmsService', () {
    test('rejects invalid phone numbers without launching', () async {
      final service = SmsService();
      final result = await service.sendSms(
        phoneNumber: 'abc',
        message: 'hello',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('Invalid phone'));
      expect(fakeLauncher.launched, isEmpty);
    });

    test('launches sms: URI for a valid number', () async {
      final service = SmsService();
      final result = await service.sendSms(
        phoneNumber: '0911 234 567',
        message: 'Hello from school',
        studentName: 'Abebe',
        templateName: 'Test',
      );

      expect(result.success, isTrue);
      expect(result.phoneNumber, '+251911234567');
      expect(fakeLauncher.launched, hasLength(1));
      final uri = Uri.parse(fakeLauncher.launched.single);
      expect(uri.scheme, 'sms');
      expect(uri.path, '+251911234567');
      expect(uri.queryParameters['body'], contains('Hello from school'));

      // Logged in history box
      final history = Hive.box('sms_history');
      expect(history.length, 1);
      final entry = history.getAt(0) as Map;
      expect(entry['success'], isTrue);
      expect(entry['studentName'], 'Abebe');
    });

    test('normalizes 09-prefixed numbers to +251', () async {
      final service = SmsService();
      await service.sendSms(phoneNumber: '0923456789', message: 'hi');

      expect(fakeLauncher.launched.single, startsWith('sms:+251923456789'));
    });

    test('queues message when launch fails', () async {
      fakeLauncher.shouldSucceed = false;
      final service = SmsService();
      final result = await service.sendSms(
        phoneNumber: '0911234567',
        message: 'queued message',
      );

      expect(result.success, isFalse);
      final queue = Hive.box('sms_offline_queue');
      expect(queue.length, 1);
      final entry = queue.getAt(0) as Map;
      expect(entry['message'], 'queued message');
      expect(entry['phoneNumber'], '+251911234567');
    });

    test('processQueue resends queued messages and clears them', () async {
      fakeLauncher.shouldSucceed = false;
      final service = SmsService();
      await service.sendSms(phoneNumber: '0911234567', message: 'queued 1');
      await service.sendSms(phoneNumber: '0923456789', message: 'queued 2');
      expect(Hive.box('sms_offline_queue').length, 2);

      fakeLauncher.shouldSucceed = true;
      final sent = await service.processQueue();

      expect(sent, 2);
      expect(Hive.box('sms_offline_queue').length, 0);
    });

    test('sendBulk sends all messages', () async {
      final service = SmsService();
      final results = await service.sendBulk(
        messages: [
          {'phone': '0911111111', 'message': 'm1', 'student': 'Abebe'},
          {'phone': '0922222222', 'message': 'm2', 'student': 'Sara'},
        ],
      );

      expect(results, hasLength(2));
      expect(results.every((r) => r.success), isTrue);
      expect(fakeLauncher.launched, hasLength(2));
    });
  });
}