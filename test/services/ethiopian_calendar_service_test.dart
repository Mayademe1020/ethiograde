import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/services/ethiopian_calendar_service.dart';

void main() {
  group('EthiopianCalendarService Tests', () {
    final service = EthiopianCalendarService();

    test('Converts Ethiopian New Year accurately', () {
      // Sept 11, 2024 is Meskerem 1, 2017 E.C.
      final gDate = DateTime(2024, 9, 11);
      final etDate = service.fromGregorian(gDate);

      expect(etDate.year, equals(2017));
      expect(etDate.month, equals(1)); // Meskerem
      expect(etDate.day, equals(1));
      expect(etDate.monthNameAm, equals('መስከረም'));
    });

    test('Formats Ethiopian Date with Amharic Fidel', () {
      final etDate = const EtDate(year: 2017, month: 2, day: 15);
      expect(etDate.formatAmharic(), equals('ጥቅምት 15, 2017 ዓ.ም.'));
      expect(etDate.formatEnglish(), equals('Tikimt 15, 2017 E.C.'));
    });

    test('Bidirectional conversion consistency', () {
      final original = DateTime(2026, 11, 23);
      final etDate = service.fromGregorian(original);
      final backToGregorian = service.toGregorian(etDate);

      expect(backToGregorian.year, equals(original.year));
      expect(backToGregorian.month, equals(original.month));
      expect(backToGregorian.day, equals(original.day));
    });
  });
}
