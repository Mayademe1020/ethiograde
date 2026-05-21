/// Operation result — never throws, always returns a status.
///
/// Shared across all providers for consistent error handling.
class Result<T> {
  final bool success;
  final T? data;
  final String? error;

  const Result.success(this.data) : success = true, error = null;
  const Result.failure(this.error) : success = false, data = null;
}
