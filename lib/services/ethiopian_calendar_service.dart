/// Represents a date in the Ethiopian Calendar (ዓመተ ምሕረት / ዓ.ም.)
class EtDate {
  final int year;
  final int month; // 1 to 13
  final int day; // 1 to 30 (1 to 5 or 6 for Pagume)

  const EtDate({
    required this.year,
    required this.month,
    required this.day,
  });

  static const List<String> amharicMonths = [
    'መስከረም', // Meskerem (1)
    'ጥቅምት', // Tikimt (2)
    'ኅዳር', // Hidar (3)
    'ታኅሣሥ', // Tahsas (4)
    'ጥር', // Tir (5)
    'የካቲት', // Yekatit (6)
    'መጋቢት', // Megabit (7)
    'ሚያዝያ', // Miyazya (8)
    'ግንቦት', // Ginbot (9)
    'ሰኔ', // Sene (10)
    'ሐምሌ', // Hamle (11)
    'ነሐሴ', // Nehase (12)
    'ጳጉሜ', // Pagume (13)
  ];

  static const List<String> englishMonths = [
    'Meskerem',
    'Tikimt',
    'Hidar',
    'Tahsas',
    'Tir',
    'Yekatit',
    'Megabit',
    'Miyazya',
    'Ginbot',
    'Sene',
    'Hamle',
    'Nehase',
    'Pagume',
  ];

  String get monthNameAm => (month >= 1 && month <= 13) ? amharicMonths[month - 1] : '';
  String get monthNameEn => (month >= 1 && month <= 13) ? englishMonths[month - 1] : '';

  /// Formats date in Amharic: e.g. `ጥቅምት 15, 2017 ዓ.ም.`
  String formatAmharic() => '$monthNameAm $day, $year ዓ.ም.';

  /// Formats date in English: e.g. `Tikimt 15, 2017 E.C.`
  String formatEnglish() => '$monthNameEn $day, $year E.C.';

  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} E.C.';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EtDate &&
          runtimeType == other.runtimeType &&
          year == other.year &&
          month == other.month &&
          day == other.day;

  @override
  int get hashCode => year.hashCode ^ month.hashCode ^ day.hashCode;
}

/// Service providing conversions between Gregorian (DateTime) and Ethiopian Calendar dates.
class EthiopianCalendarService {
  static const EthiopianCalendarService _instance = EthiopianCalendarService._();
  factory EthiopianCalendarService() => _instance;
  const EthiopianCalendarService._();

  /// Ethiopian epoch in Julian Day Number (Aug 29, 8 C.E. Julian = JDN 1723856)
  static const int _ethiopianEpoch = 1723856;

  /// Converts a Julian Day Number (JDN) to an Ethiopian date.
  EtDate jdnToEthiopic(int jdn) {
    final r = (jdn - _ethiopianEpoch) % 1461;
    final n = (r % 365) + 365 * (r ~/ 1460);
    final year = 4 * ((jdn - _ethiopianEpoch) ~/ 1461) + (r ~/ 365) - (r ~/ 1460);
    final month = (n ~/ 30) + 1;
    final day = (n % 30) + 1;
    return EtDate(year: year, month: month, day: day);
  }

  /// Converts an Ethiopian date to a Julian Day Number (JDN).
  int ethiopicToJdn(EtDate date) {
    return (_ethiopianEpoch +
            365 * (date.year - 1) +
            (date.year ~/ 4) +
            30 * (date.month - 1) +
            date.day -
            1);
  }

  /// Converts Gregorian [DateTime] to [EtDate].
  EtDate fromGregorian(DateTime date) {
    final a = (14 - date.month) ~/ 12;
    final y = date.year + 4800 - a;
    final m = date.month + 12 * a - 3;

    final jdn = date.day +
        ((153 * m + 2) ~/ 5) +
        365 * y +
        (y ~/ 4) -
        (y ~/ 100) +
        (y ~/ 400) -
        32045;

    return jdnToEthiopic(jdn);
  }

  /// Converts [EtDate] to Gregorian [DateTime].
  DateTime toGregorian(EtDate date) {
    final jdn = ethiopicToJdn(date);
    final l = jdn + 68569;
    final n = (4 * l) ~/ 146097;
    final l1 = l - ((146097 * n + 3) ~/ 4);
    final i = (4000 * (l1 + 1)) ~/ 1461001;
    final l2 = l1 - ((1461 * i) ~/ 4) + 31;
    final j = (80 * l2) ~/ 2447;
    final day = l2 - ((2447 * j) ~/ 80);
    final l3 = j ~/ 11;
    final month = j + 2 - (12 * l3);
    final year = 100 * (n - 49) + i + l3;

    return DateTime(year, month, day);
  }

  /// Returns today's date in Ethiopian Calendar.
  EtDate today() => fromGregorian(DateTime.now());

  /// Returns the current Ethiopian academic year string, e.g. "2017 ዓ.ም."
  String currentAcademicYear() {
    final now = today();
    return '${now.year} ዓ.ም.';
  }
}
