import 'package:flutter/foundation.dart';

/// Centralized logging for EthioGrade.
///
/// Every log message follows one format:
/// ```
/// [ClassName] method — message
/// [ClassName] method — message: error
/// ```
///
/// Usage:
/// ```dart
/// AppLog.info(this, 'load', 'loaded ${items.length} items');
/// AppLog.error(this, 'save', error, stackTrace);
/// AppLog.warn(this, 'migrate', 'box was corrupt, recreated');
/// ```
class AppLog {
  AppLog._();

  // ── Log levels ──────────────────────────────────────────────────────

  static void info(Object context, String method, String message) {
    final tag = _tag(context);
    debugPrint('[$tag] $method — $message');
  }

  static void warn(Object context, String method, String message) {
    final tag = _tag(context);
    debugPrint('[WARN][$tag] $method — $message');
  }

  static void error(
    Object context,
    String method,
    Object error, [
    StackTrace? stackTrace,
  ]) {
    final tag = _tag(context);
    final st = stackTrace != null ? '\n$stackTrace' : '';
    debugPrint('[ERROR][$tag] $method — $error$st');
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  /// Extracts a short tag from the context object.
  /// `TeacherProvider` → `TeacherProvider`
  /// `_MyPrivateClass` → `MyPrivateClass`
  static String _tag(Object context) {
    final name = context.runtimeType.toString();
    return name.startsWith('_') ? name.substring(1) : name;
  }
}
