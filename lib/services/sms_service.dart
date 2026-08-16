import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

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
///
/// Uses the platform's default SMS app via `url_launcher`'s `sms:` URI —
/// no restricted `SEND_SMS` permission required, works reliably across
/// devices, and is Play Store safe. The user confirms each message in
/// their SMS app before it is actually delivered.
class SmsService {
  final bool offlineQueue;

  static const String _queueBox = 'sms_offline_queue';

  SmsService({this.offlineQueue = true});

  /// Opens the default SMS app pre-filled with [message] to [phoneNumber].
  /// Returns success when the SMS app was launched; delivery is confirmed
  /// by the user inside that app.
  Future<SmsResult> sendSms({
    required String phoneNumber,
    required String message,
    String studentName = '',
    String templateName = '',
  }) async {
    final cleaned = _cleanPhoneNumber(phoneNumber);

    if (!_isValidPhone(cleaned)) {
      const error = 'Invalid phone number';
      await _logSms(
        studentName: studentName,
        phoneNumber: phoneNumber,
        message: message,
        templateName: templateName,
        success: false,
        errorMessage: error,
      );
      return SmsResult(
        success: false,
        phoneNumber: phoneNumber,
        errorMessage: error,
      );
    }

    // Build sms: URI with message body. The `?body=` form works on Android;
    // iOS uses the same sms: scheme. url_launcher resolves platform quirks.
    final uri = Uri(
      scheme: 'sms',
      path: cleaned,
      query: 'body=${Uri.encodeQueryComponent(message)}',
    );

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        throw StateError('No SMS app available to handle the request');
      }

      await _logSms(
        studentName: studentName,
        phoneNumber: cleaned,
        message: message,
        templateName: templateName,
        success: true,
      );

      return SmsResult(success: true, phoneNumber: cleaned);
    } catch (e) {
      await _logSms(
        studentName: studentName,
        phoneNumber: cleaned,
        message: message,
        templateName: templateName,
        success: false,
        errorMessage: e.toString(),
      );

      if (offlineQueue) {
        await _queueMessage(
          phoneNumber: cleaned,
          message: message,
          studentName: studentName,
          templateName: templateName,
        );
      }
      return SmsResult(
        success: false,
        phoneNumber: cleaned,
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

  /// Whether the app can launch an SMS handler (best-effort check).
  Future<bool> canSend() async {
    final uri = Uri.parse('sms:');
    return await canLaunchUrl(uri);
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
    String studentName = '',
    String templateName = '',
  }) async {
    try {
      final box = await Hive.openBox(_queueBox);
      final entry = {
        'id': const Uuid().v4(),
        'phoneNumber': phoneNumber,
        'message': message,
        'studentName': studentName,
        'templateName': templateName,
        'queuedAt': DateTime.now().toIso8601String(),
      };
      await box.put(entry['id'], entry);
    } catch (_) {
      // Queueing failure shouldn't break the caller.
    }
  }

  /// Retries sending all queued messages. Returns the number re-sent.
  Future<int> processQueue() async {
    final box = await Hive.openBox(_queueBox);
    final keys = box.keys.toList();
    var sent = 0;

    for (final key in keys) {
      final entry = Map<String, dynamic>.from(box.get(key) as Map);
      final result = await sendSms(
        phoneNumber: entry['phoneNumber'] ?? '',
        message: entry['message'] ?? '',
        studentName: entry['studentName'] ?? '',
        templateName: entry['templateName'] ?? '',
      );
      if (result.success) {
        await box.delete(key);
        sent++;
      }
    }

    return sent;
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