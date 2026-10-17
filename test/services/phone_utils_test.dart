import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/services/phone_utils.dart';

void main() {
  group('PhoneUtils.normalize', () {
    test('prepends +251 to bare 9-digit numbers', () {
      expect(PhoneUtils.normalize('912345678'), '+251912345678');
    });

    test('converts 09-prefixed numbers', () {
      expect(PhoneUtils.normalize('0912345678'), '+251912345678');
    });

    test('keeps valid +251 numbers unchanged', () {
      expect(PhoneUtils.normalize('+251912345678'), '+251912345678');
    });

    test('strips spaces, dashes, parens and dots', () {
      expect(PhoneUtils.normalize('+251 91 234 5678'), '+251912345678');
      expect(PhoneUtils.normalize('(091) 234-5678'), '+251912345678');
    });

    test('converts bare 251 form', () {
      expect(PhoneUtils.normalize('251912345678'), '+251912345678');
    });

    test('leaves unparseable input unchanged', () {
      expect(PhoneUtils.normalize('123456789'), '123456789');
    });
  });

  group('PhoneUtils.isValid', () {
    test('accepts 9 digits starting with 7', () {
      expect(PhoneUtils.isValid('+251712345678'), isTrue);
    });

    test('accepts 9 digits starting with 9', () {
      expect(PhoneUtils.isValid('+251912345678'), isTrue);
    });

    test('rejects numbers not starting with 7 or 9', () {
      expect(PhoneUtils.isValid('+251212345678'), isFalse);
      expect(PhoneUtils.isValid('+251612345678'), isFalse);
    });

    test('rejects wrong lengths', () {
      expect(PhoneUtils.isValid('+25191234567'), isFalse);
      expect(PhoneUtils.isValid('+2519123456789'), isFalse);
    });

    test('rejects missing +251 prefix', () {
      expect(PhoneUtils.isValid('912345678'), isFalse);
    });
  });

  group('PhoneUtils.isValidRaw', () {
    test('accepts 09-prefixed raw input', () {
      expect(PhoneUtils.isValidRaw('0912345678'), isTrue);
    });

    test('accepts bare 9-digit raw input', () {
      expect(PhoneUtils.isValidRaw('912345678'), isTrue);
    });

    test('accepts +251 raw input', () {
      expect(PhoneUtils.isValidRaw('+251912345678'), isTrue);
    });

    test('rejects bare +251 with no digits', () {
      expect(PhoneUtils.isValidRaw('+251'), isFalse);
    });

    test('rejects non-7/9 starts and short numbers', () {
      expect(PhoneUtils.isValidRaw('012345678'), isFalse);
      expect(PhoneUtils.isValidRaw('0912345'), isFalse);
    });
  });

  group('PhoneUtils.localDigits', () {
    test('extracts the 9 local digits', () {
      expect(PhoneUtils.localDigits('0912345678'), '912345678');
      expect(PhoneUtils.localDigits('+251712345678'), '712345678');
    });

    test('returns empty for invalid input', () {
      expect(PhoneUtils.localDigits('123456789'), isEmpty);
    });
  });
}