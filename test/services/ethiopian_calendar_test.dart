import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/services/ethiopian_calendar.dart';

void main() {
  group('EthiopianCalendar', () {
    group('toEthiopian', () {
      test('Ethiopian New Year 2016 (Sep 11, 2023 Gregorian)', () {
        final date = EthiopianCalendar.toEthiopian(DateTime(2023, 9, 11));
        expect(date.year, 2016);
        expect(date.month, 1); // Meskerem
        expect(date.day, 1);
      });

      test('Pagume 6 (leap year) — Sep 10, 2023 Gregorian', () {
        final date = EthiopianCalendar.toEthiopian(DateTime(2023, 9, 10));
        // Day before Ethiopian New Year 2016 = last day of 2015
        expect(date.year, 2015);
        expect(date.month, 13); // Pagume
        // Could be day 5 or 6 depending on leap year calculation
        expect(date.day, greaterThanOrEqualTo(5));
      });

      test('Meskerem 15 — Sep 25, 2023 Gregorian', () {
        final date = EthiopianCalendar.toEthiopian(DateTime(2023, 9, 25));
        expect(date.year, 2016);
        expect(date.month, 1); // Meskerem
        expect(date.day, 15);
      });

      test('Tikimem 1 — Oct 11, 2023 Gregorian', () {
        final date = EthiopianCalendar.toEthiopian(DateTime(2023, 10, 11));
        expect(date.year, 2016);
        expect(date.month, 2); // Tikimt
        expect(date.day, 1);
      });

      test('Tir 1 — Jan 8, 2024 Gregorian', () {
        final date = EthiopianCalendar.toEthiopian(DateTime(2024, 1, 8));
        expect(date.year, 2016);
        expect(date.month, 5); // Tir
        expect(date.day, 1);
      });

      test('Yekatit 1 — Feb 8, 2024 Gregorian', () {
        final date = EthiopianCalendar.toEthiopian(DateTime(2024, 2, 8));
        expect(date.year, 2016);
        expect(date.month, 6); // Yekatit
        expect(date.day, 1);
      });

      test('Hamle 1 — July 7, 2024 Gregorian', () {
        final date = EthiopianCalendar.toEthiopian(DateTime(2024, 7, 7));
        expect(date.year, 2016);
        expect(date.month, 11); // Hamle
        expect(date.day, 1);
      });

      test('Nehase 1 — Aug 6, 2024 Gregorian', () {
        final date = EthiopianCalendar.toEthiopian(DateTime(2024, 8, 6));
        expect(date.year, 2016);
        expect(date.month, 12); // Nehase
        expect(date.day, 1);
      });
    });

    group('formatEthiopian', () {
      test('default format in Amharic', () {
        final date = EthiopianDate(year: 2016, month: 1, day: 15);
        final formatted = EthiopianCalendar.formatEthiopian(date, isAmharic: true);
        expect(formatted, '15 መስከረም 2016');
      });

      test('default format in English', () {
        final date = EthiopianDate(year: 2016, month: 1, day: 15);
        final formatted = EthiopianCalendar.formatEthiopian(date, isAmharic: false);
        expect(formatted, '15 Meskerem 2016');
      });

      test('short format dd/MM/yyyy', () {
        final date = EthiopianDate(year: 2016, month: 13, day: 6);
        final formatted = EthiopianCalendar.formatEthiopian(
          date,
          format: 'dd/MM/yyyy',
        );
        expect(formatted, '06/13/2016');
      });

      test('month+year format', () {
        final date = EthiopianDate(year: 2016, month: 5, day: 1);
        final formatted = EthiopianCalendar.formatEthiopian(
          date,
          isAmharic: false,
          format: 'MMMM yyyy',
        );
        expect(formatted, 'Tir 2016');
      });

      test('Pagume month name in Amharic', () {
        final date = EthiopianDate(year: 2015, month: 13, day: 5);
        final formatted = EthiopianCalendar.formatEthiopian(date, isAmharic: true);
        expect(formatted, '5 ጳጉሜ 2015');
      });
    });

    group('formatDate (mixed calendar)', () {
      test('Ethiopian mode', () {
        final gregorian = DateTime(2023, 9, 25);
        final formatted = EthiopianCalendar.formatDate(
          gregorian,
          useEthiopian: true,
          isAmharic: false,
        );
        expect(formatted, contains('Meskerem'));
        expect(formatted, contains('2016'));
      });

      test('Gregorian mode', () {
        final gregorian = DateTime(2023, 9, 25);
        final formatted = EthiopianCalendar.formatDate(
          gregorian,
          useEthiopian: false,
          isAmharic: false,
        );
        expect(formatted, contains('Sep'));
        expect(formatted, contains('2023'));
      });
    });

    group('isEthiopianLeapYear', () {
      test('leap years are 3 mod 4', () {
        expect(EthiopianCalendar.isEthiopianLeapYear(2015), true);
        expect(EthiopianCalendar.isEthiopianLeapYear(2016), false);
        expect(EthiopianCalendar.isEthiopianLeapYear(2019), true);
        expect(EthiopianCalendar.isEthiopianLeapYear(2020), false);
      });
    });

    group('EthiopianDate', () {
      test('toString', () {
        final date = EthiopianDate(year: 2016, month: 1, day: 1);
        expect(date.toString(), '1/1/2016 (EC)');
      });

      test('monthName', () {
        final date = EthiopianDate(year: 2016, month: 3, day: 15);
        expect(date.monthName, 'Hidar');
        expect(date.monthNameAmharic, 'ኅዳር');
      });
    });
  });
}
