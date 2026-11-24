package com.ethiograde.service

import java.time.LocalDate

data class EthiopicDate(val year: Int, val month: Int, val day: Int) {
    val monthNameEn: String get() = EthiopianCalendarService.MONTHS_EN.getOrElse(month - 1) { "" }
    val monthNameAm: String get() = EthiopianCalendarService.MONTHS_AM.getOrElse(month - 1) { "" }

    fun formatted(): String = "$monthNameEn $day, $year E.C."
    fun formattedBilingual(): String = "$monthNameAm ($monthNameEn) $day, $year"
}

object EthiopianCalendarService {
    val MONTHS_EN = listOf(
        "Meskerem", "Tikimt", "Hidar", "Tahsas", "Tir", "Yekatit",
        "Megabit", "Miazia", "Ginbot", "Sene", "Hamle", "Nehase", "Pagume"
    )
    val MONTHS_AM = listOf(
        "መስከረም", "ጥቅምት", "ህዳር", "ታህሳስ", "ጥር", "የካቲት",
        "መጋቢት", "ሚያዝያ", "ግንቦት", "ሰኔ", "ሐምሌ", "ነሐሴ", "ጳጉሜ"
    )

    private const val JD_EPOCH_OFFSET_ETHIOPIC = 1723856

    fun toEthiopic(date: LocalDate = LocalDate.now()): EthiopicDate {
        val jdn = gregorianToJdn(date.year, date.monthValue, date.dayOfMonth)
        val r = (jdn - JD_EPOCH_OFFSET_ETHIOPIC).mod(1461)
        val n = (r % 365) + 365 * (r / 1460)
        val year = 4 * ((jdn - JD_EPOCH_OFFSET_ETHIOPIC) / 1461) + r / 365 - r / 1460
        val month = n / 30 + 1
        val day = (n % 30) + 1
        return EthiopicDate(year, month, day)
    }

    private fun gregorianToJdn(year: Int, month: Int, day: Int): Int {
        val a = (14 - month) / 12
        val y = year + 4800 - a
        val m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }
}
