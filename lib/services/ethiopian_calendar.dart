/// Ethiopian calendar conversion utility.
///
/// Pure Dart — no dependencies, no heavy computation.
/// The Ethiopian calendar (Ge'ez calendar) has:
/// - 13 months: 12 months of 30 days + Pagume (5 or 6 days)
/// - Ethiopian new year: Meskerem 1 = September 11 (or 12 in Gregorian leap year)
/// - ~7-8 years behind Gregorian calendar
/// - Leap year every 4 years (same as Julian calendar)
///
/// Used by the app to display dates in Ethiopian format for teachers.
class EthiopianCalendar {
  EthiopianCalendar._();

  // Ethiopian month names
  static const List<String> monthNamesAm = [
    'መስከረም', 'ጥቅምት', 'ኅዳር', 'ታኅሣሥ', 'ጥር',
    'የካቲት', 'መጋቢት', 'ሚያዝያ', 'ግንቦት', 'ሰኔ',
    'ሐምሌ', 'ነሐሴ', 'ጳጉሜ',
  ];

  static const List<String> monthNamesEn = [
    'Meskerem', 'Tikimt', 'Hidar', 'Tahsas', 'Tir',
    'Yekatit', 'Megabit', 'Miazia', 'Ginbot', 'Sene',
    'Hamle', 'Nehase', 'Pagume',
  ];

  /// Convert a Gregorian [DateTime] to Ethiopian calendar.
  static EthiopianDate toEthiopian(DateTime gregorian) {
    // Algorithm based on the Ethiopian calendar's fixed relationship to Julian Day Number.
    // Reference: Ethiopian calendar epoch is JD 1724221 (August 29, 7 AD Julian)

    final y = gregorian.year;
    final m = gregorian.month;
    final d = gregorian.day;

    // Compute Julian Day Number (JDN) from Gregorian date
    final jdn = _gregorianToJdn(y, m, d);

    // Ethiopian calendar: 4-year cycle of 1461 days
    // JDN 1724221 = Ethiopian epoch (1/1/1 Ethiopian = August 29, 7 AD Gregorian)
    const ethEpoch = 1724221;

    final r = (jdn - ethEpoch) % 1461;
    final n = (r % 1461) ~/ 365; // year within 4-year cycle (0-3)

    var ethYear = ((jdn - ethEpoch) ~/ 1461) * 4 + n + 1; // 1-indexed
    var ethDayOfYear = (jdn - ethEpoch) % 1461;
    if (ethDayOfYear == 0) ethDayOfYear = 1461; // edge case

    // dayOfYear 1-30 → Meskerem, 31-60 → Tikimt, etc.
    // 360-365 → Pagume (5 or 6 days)
    final ethMonth = ((ethDayOfYear - 1) ~/ 30) + 1;
    final ethDay = ((ethDayOfYear - 1) % 30) + 1;

    // Handle Pagume (month 13) which has 5 days normally, 6 in leap year
    int finalMonth = ethMonth;
    int finalDay = ethDay;
    if (finalMonth > 13) {
      finalMonth = 13;
      finalDay = 6; // Pagume 6 (leap year)
    }

    // Ethiopian year adjustment
    // If Gregorian month is before September (1-8), Ethiopian year is 7 less
    // If Gregorian month is September or later, Ethiopian year is 8 less (approximately)
    // But we compute it from the JDN, so the year is already correct.
    // However, the Ethiopian calendar is typically ~7-8 years behind.
    // The JDN-based computation gives us the correct year directly.

    return EthiopianDate(
      year: ethYear,
      month: finalMonth,
      day: finalDay,
    );
  }

  /// Format an Ethiopian date as a string.
  ///
  /// [format]: 'd MMMM yyyy' (default), 'dd/MM/yyyy', 'MMMM yyyy'
  static String formatEthiopian(
    EthiopianDate date, {
    bool isAmharic = true,
    String format = 'd MMMM yyyy',
  }) {
    final monthNames = isAmharic ? monthNamesAm : monthNamesEn;

    switch (format) {
      case 'dd/MM/yyyy':
        return '${date.day.toString().padLeft(2, '0')}/'
            '${date.month.toString().padLeft(2, '0')}/'
            '${date.year}';
      case 'MMMM yyyy':
        return '${monthNames[date.month - 1]} ${date.year}';
      case 'd MMMM yyyy':
      default:
        return '${date.day} ${monthNames[date.month - 1]} ${date.year}';
    }
  }

  /// Format a Gregorian DateTime for display, respecting the user's
  /// calendar preference.
  ///
  /// If [useEthiopian] is true, converts to Ethiopian calendar and formats.
  /// Otherwise, formats as Gregorian.
  static String formatDate(
    DateTime date, {
    required bool useEthiopian,
    bool isAmharic = true,
    String ethFormat = 'd MMMM yyyy',
    String gregFormat = 'd MMM yyyy',
  }) {
    if (useEthiopian) {
      final ethDate = toEthiopian(date);
      return formatEthiopian(ethDate, isAmharic: isAmharic, format: ethFormat);
    }

    // Gregorian format
    final months = isAmharic
        ? ['ጃንዩ', 'ፌብሩ', 'ማርች', 'ኤፕሪ', 'ሜይ', 'ጁን',
           'ጁላይ', 'ኦገስ', 'ሴፕቴ', 'ኦክቶ', 'ኖቬም', 'ዲሴም']
        : ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
           'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    switch (gregFormat) {
      case 'dd/MM/yyyy':
        return '${date.day.toString().padLeft(2, '0')}/'
            '${date.month.toString().padLeft(2, '0')}/'
            '${date.year}';
      default:
        return '${date.day} ${months[date.month - 1]} ${date.year}';
    }
  }

  /// Compute Julian Day Number from Gregorian date.
  static int _gregorianToJdn(int year, int month, int day) {
    final a = (14 - month) ~/ 12;
    final y = year + 4800 - a;
    final m = month + 12 * a - 3;
    return day + ((153 * m + 2) ~/ 5) + 365 * y + (y ~/ 4) - (y ~/ 100) + (y ~/ 400) - 32045;
  }

  /// Check if an Ethiopian year is a leap year.
  static bool isEthiopianLeapYear(int ethYear) {
    return ethYear % 4 == 3; // Ethiopian leap years are 3 mod 4
  }
}

/// Represents a date in the Ethiopian calendar.
class EthiopianDate {
  final int year;
  final int month; // 1-13 (13 = Pagume)
  final int day;   // 1-30 (or 1-6 for Pagume)

  const EthiopianDate({
    required this.year,
    required this.month,
    required this.day,
  });

  String get monthName => EthiopianCalendar.monthNamesEn[month - 1];
  String get monthNameAmharic => EthiopianCalendar.monthNamesAm[month - 1];

  @override
  String toString() => '$day/$month/$year (EC)';
}
