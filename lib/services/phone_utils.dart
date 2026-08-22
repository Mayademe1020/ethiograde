import 'package:flutter/services.dart';

/// Shared Ethiopian phone number utilities.
///
/// Standard across the platform:
/// - A number is exactly 9 digits (starting with 7 or 9) under the +251 prefix.
/// - Users type either `09...`, `7...`/`9...` (9 digits), or `+251...`.
/// - Everything is normalized to E.164 (`+251XXXXXXXXX`).
class PhoneUtils {
  PhoneUtils._();

  /// The country prefix prepended by default.
  static const String countryCode = '+251';

  /// Maximum characters a phone field may hold: `+251` + 9 digits = 13.
  static const int maxLength = 13;

  /// Matches the 9 local digits: must start with 7 or 9.
  static final RegExp _localRegex = RegExp(r'^[79]\d{8}$');

  /// Matches a full E.164 number: +251 followed by 9 digits starting with 7/9.
  static final RegExp _e164Regex = RegExp(r'^\+251[79]\d{8}$');

  /// Normalizes an Ethiopian phone number to E.164 (`+251...`) form.
  ///
  /// Strips spaces/dashes/parens, converts a leading `0`, and prepends
  /// `+251` when only the 9 local digits are given. Returns the input
  /// unchanged (trimmed) when it cannot be recognized.
  static String normalize(String phone) {
    final cleaned = phone.trim().replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
    if (cleaned.startsWith('0') && cleaned.length == 10) {
      return '$countryCode${cleaned.substring(1)}';
    }
    if (cleaned.startsWith('251') && cleaned.length == 12) {
      return '+$cleaned';
    }
    if (_localRegex.hasMatch(cleaned)) {
      return '$countryCode$cleaned';
    }
    if (_e164Regex.hasMatch(cleaned)) {
      return cleaned;
    }
    return cleaned;
  }

  /// Whether [phone] is a valid Ethiopian mobile number
  /// (`+251` + exactly 9 digits starting with 7 or 9).
  static bool isValid(String phone) {
    return _e164Regex.hasMatch(phone);
  }

  /// Whether the raw [phone] input (before normalization) is valid.
  static bool isValidRaw(String phone) {
    return isValid(normalize(phone));
  }

  /// The 9 local digits (e.g. `912345678`) or empty when invalid.
  static String localDigits(String phone) {
    final normalized = normalize(phone);
    if (!isValid(normalized)) return '';
    return normalized.substring(countryCode.length);
  }
}

/// Live input filter for Ethiopian phone fields.
///
/// Enforces the platform standard as the user types:
/// - only digits, plus an optional leading `+` (no other characters)
/// - at most [PhoneUtils.maxLength] characters (`+251` + 9 digits)
///
/// Semantic correctness (must start with 7 or 9, exactly 9 digits) is still
/// validated on submit via [PhoneUtils.isValidRaw].
class PhoneDigitsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final buffer = StringBuffer();
    var plusSeen = false;
    for (final ch in newValue.text.split('')) {
      if (ch == '+') {
        if (!plusSeen && buffer.isEmpty) {
          buffer.write('+');
          plusSeen = true;
        }
        continue;
      }
      if (ch.compareTo('0') >= 0 && ch.compareTo('9') <= 0) {
        buffer.write(ch);
      }
    }
    var text = buffer.toString();
    if (text.length > PhoneUtils.maxLength) {
      text = text.substring(0, PhoneUtils.maxLength);
    }
    return newValue.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}