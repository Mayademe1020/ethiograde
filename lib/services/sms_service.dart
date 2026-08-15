import 'package:telephony/telephony.dart';
import 'package:uuid/uuid.dart';
import 'package:hive/hive.dart';

/// Result of an SMS send attempt.
class SmsResult {
  final bool success;
  final String? errorMessage;
  final String phoneNumber;

  const SmsResult({
    required this.success,
    required this.phoneNumber,
    this.errorMessage,
  });
}

/// SMS template with placeholders.
class SmsTemplate {
  final String name;
  final String englishTemplate;
  final String amharicTemplate;

  const SmsTemplate({
    required this.name,
    required this.englishTemplate,
    required this.amharicTemplate,
  });

  String render({
    required String studentName,
    required String subject,
    required double percentage,
    required String schoolName,
    bool amharic = false,
  }) {
    final template = amharic ? amharicTemplate : englishTemplate;
    return template
        .replaceAll('{student}', studentName)
        .replaceAll('{subject}', subject)
        .replaceAll('{percentage}', percentage.toStringAsFixed(1))
        .replaceAll('{school}', schoolName);
  }
}

/// Default templates for common use cases.
class DefaultTemplates {
  static const resultNotification = SmsTemplate(
    name: 'Result Notification',
    englishTemplate:
        '{student} scored {percentage}% in {subject}. - {school}',
    amharicTemplate: '{student} በ{subject} {percentage}% ተኸቷል። - {school}',
  );

  static const atRiskWarning = SmsTemplate(
    name: 'At-Risk Warning',
    englishTemplate:
        'Warning: {student} is struggling ({percentage}% avg). Please follow up. - {school}',
    amharicTemplate: 'ማስጠንቀቂያ: {student} እየተቸገረ ነው (አማካይ {percentage}%)። እባክዎን ይከታተሉ። - {school}',
  );

  static const all = [resultNotification, atRiskWarning];
}

/// Sends SMS messages to parents.
class SmsService {
  final Telephony telephony;
  final bool offlineQueue;

  SmsService({Telephony? telephony, this.offlineQueue = true})
      : telephony = telephony ?? Telephony.instance;

  Future<SmsResult> sendSms({
    required String phoneNumber,
    required String message,
    String studentName = '',
    String templateName = '',
  }) async {
    try {
      final cleaned = _cleanPhoneNumber(phoneNumber);

      if (!_isValidPhone(cleaned)) {
        return SmsResult(
          success: false,
          phoneNumber: phoneNumber,
          errorMessage: 'Invalid phone number',
        );
      }

      await telephony.sendSms(
        to: cleaned,
        message: message,
      );

      // Log successful send
      await _logSms(
        studentName: studentName,
        phoneNumber: cleaned,
        message: message,
        templateName: templateName,
        success: true,
      );

      return SmsResult(success: true, phoneNumber: cleaned);
    } catch (e) {
      // Log failed send
      await _logSms(
        studentName: studentName,
        phoneNumber: phoneNumber,
        message: message,
        templateName: templateName,
        success: false,
        errorMessage: e.toString(),
      );

      if (offlineQueue) {
        await _queueMessage(phoneNumber: phoneNumber, message: message);
      }
      return SmsResult(
        success: false,
        phoneNumber: phoneNumber,
        errorMessage: e.toString(),
      );
    }
  }

  Future<List<SmsResult>> sendBulk({
    required List<Map<String, String>> messages,
    String? template,
    bool useAmharic = false,
  }) async {
    final results = <SmsResult>[];

    for (final msg in messages) {
      final result = await sendSms(
        phoneNumber: msg['phone'] ?? '',
        message: msg['message'] ?? '',
        studentName: msg['student'] ?? '',
        templateName: template ?? '',
      );
      results.add(result);
    }

    return results;
  }

  Future<bool> requestPermission() async {
    final granted = await telephony.requestSmsPermissions;
    return granted ?? false;
  }

  String _cleanPhoneNumber(String phone) {
    var cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleaned.startsWith('0')) {
      cleaned = '+251${cleaned.substring(1)}';
    } else if (!cleaned.startsWith('+251') && cleaned.length == 9) {
      cleaned = '+251$cleaned';
    }
    return cleaned;
  }

  bool _isValidPhone(String phone) {
    final regex = RegExp(r'^\+251\d{9}$');
    return regex.hasMatch(phone);
  }

  Future<void> _queueMessage({
    required String phoneNumber,
    required String message,
  }) async {
  }

  Future<void> processQueue() async {
  }

  Future<void> _logSms({
    required String studentName,
    required String phoneNumber,
    required String message,
    required String templateName,
    required bool success,
    String? errorMessage,
  }) async {
    try {
      final box = await Hive.openBox('sms_history');
      final entry = {
        'id': const Uuid().v4(),
        'studentName': studentName,
        'phoneNumber': phoneNumber,
        'message': message,
        'templateName': templateName,
        'success': success,
        'errorMessage': errorMessage,
        'sentAt': DateTime.now().toIso8601String(),
      };
      await box.put(entry['id'], entry);
    } catch (_) {
      // Logging failure shouldn't break SMS flow
    }
  }
}
