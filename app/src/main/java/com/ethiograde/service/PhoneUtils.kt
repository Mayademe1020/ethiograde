package com.ethiograde.service

object PhoneUtils {
    const val COUNTRY_CODE = "+251"
    const val MAX_LENGTH = 13

    private val localRegex = Regex("^[79]\\d{8}$")
    private val e164Regex = Regex("^\\+251[79]\\d{8}$")

    fun normalize(phone: String): String {
        val cleaned = phone.trim().replace(Regex("[\\s\\-().]"), "")
        if (cleaned.startsWith("0") && cleaned.length == 10) {
            return "$COUNTRY_CODE${cleaned.substring(1)}"
        }
        if (cleaned.startsWith("251") && cleaned.length == 12) {
            return "+$cleaned"
        }
        if (localRegex.matches(cleaned)) {
            return "$COUNTRY_CODE$cleaned"
        }
        if (e164Regex.matches(cleaned)) {
            return cleaned
        }
        return cleaned
    }

    fun isValid(phone: String): Boolean = e164Regex.matches(phone)
    fun isValidRaw(phone: String): Boolean = isValid(normalize(phone))
    fun filterInput(raw: String): String {
        val sb = StringBuilder()
        var plusSeen = false
        for (ch in raw) {
            if (ch == '+') {
                if (!plusSeen && sb.isEmpty()) {
                    sb.append('+')
                    plusSeen = true
                }
            } else if (ch in '0'..'9') {
                sb.append(ch)
            }
        }
        return sb.toString().take(MAX_LENGTH)
    }
}
