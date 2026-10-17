import 'app_log.dart';

/// Centralized error handling for EthioGrade.
///
/// Every catch block in the app should use one of these methods.
/// This ensures consistent error logging and prevents silent failures.
///
/// Usage:
/// ```dart
/// try {
///   await _saveData();
/// } catch (e, st) {
///   AppErrorHandler.catchError(this, 'saveData', e, st);
/// }
/// ```
class AppErrorHandler {
  AppErrorHandler._();

  /// Handle a caught error — logs it and returns true (for use in catch blocks).
  ///
  /// Use this when you want to catch and continue:
  /// ```dart
  /// } catch (e, st) {
  ///   AppErrorHandler.catchError(this, 'methodName', e, st);
  /// }
  /// ```
  static bool catchError(
    Object context,
    String method,
    Object error,
    StackTrace? stackTrace,
  ) {
    AppLog.error(context, method, error, stackTrace);
    return true; // convenience: `} catch (e, st) { AppErrorHandler.catchError(...); }`
  }

  /// Handle a caught error with a fallback value.
  ///
  /// Use this when you want to return a default on error:
  /// ```dart
  /// } catch (e, st) {
  ///   return AppErrorHandler.catchAndReturn(this, 'methodName', e, st, <Student>[]);
  /// }
  /// ```
  static T catchAndReturn<T>(
    Object context,
    String method,
    Object error,
    StackTrace? stackTrace,
    T fallback,
  ) {
    AppLog.error(context, method, error, stackTrace);
    return fallback;
  }

  /// Handle a caught error and rethrow it as a [RuntimeException].
  ///
  /// Use this when the error should propagate but with better context:
  /// ```dart
  /// } catch (e, st) {
  ///   AppErrorHandler.catchAndRethrow(this, 'methodName', e, st);
  /// }
  /// ```
  static Never catchAndRethrow(
    Object context,
    String method,
    Object error,
    StackTrace? stackTrace,
  ) {
    AppLog.error(context, method, error, stackTrace);
    Error.throwWithStackTrace(
      RuntimeException('$method failed: $error', error),
      stackTrace ?? StackTrace.current,
    );
  }
}

/// Wraps an error with context for rethrowing.
class RuntimeException implements Exception {
  final String message;
  final Object? originalError;

  RuntimeException(this.message, [this.originalError]);

  @override
  String toString() => 'RuntimeException: $message';
}
