/// Baked-in cloud grading configuration.
///
/// The proxy URL lives here rather than in teacher-facing settings because it
/// is not a secret. Every shipped build already contains it, so hiding it
/// behind a paste-in field only creates support burden: one toggle, zero
/// configuration, nothing for a teacher to mistype.
///
/// The Gemini API key is deliberately NOT here. It stays in the proxy's
/// Script Properties and never reaches the device.
///
/// Usage is bounded by the proxy's own per-IP rate limit and hard monthly
/// budget ceiling, so an open endpoint cannot produce an unbounded bill.
///
/// To point the app at a different deployment, change [proxyUrl] and rebuild.
/// Keep the `script.googleusercontent.com` host: the `script.google.com` form
/// redirects, and a redirect on a POST drops the request body so scans arrive
/// empty.
class CloudGradingConfig {
  const CloudGradingConfig._();

  /// Apps Script web app URL that fronts the Gemini API.
  ///
  /// Format:
  ///   https://script.googleusercontent.com/macros/s/<DEPLOYMENT_ID>/exec
  static const String proxyUrl = '';

  /// Whether cloud grading is offered in the UI at all.
  ///
  /// False keeps the app fully offline: ML Kit does the OCR and no settings
  /// are shown. Flip to true once [proxyUrl] is filled in and deployed.
  static const bool available = false;

  /// True when [proxyUrl] looks like a usable Apps Script endpoint.
  static bool get isConfigured => isConfiguredFor(proxyUrl);

  /// Same check against an arbitrary candidate URL, so callers (and tests) can
  /// validate an override without mutating the baked constant.
  ///
  /// Only HTTPS Apps Script URLs are accepted: the proxy fronts a paid API,
  /// so it must not be reachable over plaintext, and redirecting from
  /// `script.google.com` would drop the POST body.
  static bool isConfiguredFor(String candidate) {
    if (candidate.isEmpty) return false;
    final uri = Uri.tryParse(candidate);
    if (uri == null || !uri.isAbsolute) return false;
    return uri.scheme == 'https' &&
        uri.host.endsWith('script.googleusercontent.com');
  }
}