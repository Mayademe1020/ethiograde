package com.ethiograde.service

import com.ethiograde.model.Student
import kotlin.math.max

data class StudentMatchResult(
    val matchedStudent: Student? = null,
    val scannedName: String = "",
    val confidence: Double = 0.0,
    val similarStudents: List<Student> = emptyList(),
    val isAmbiguous: Boolean = false
) {
    val hasMatch: Boolean get() = matchedStudent != null
}

object StudentMatcher {
    fun similarity(a: String, b: String): Double {
        val la = a.lowercase().trim()
        val lb = b.lowercase().trim()
        if (la.isEmpty() && lb.isEmpty()) return 1.0
        if (la.isEmpty() || lb.isEmpty()) return 0.0
        val maxLen = max(la.length, lb.length)
        return 1.0 - (ScoringService.levenshtein(la, lb).toDouble() / maxLen)
    }

    fun matchName(scannedName: String, students: List<Student>): StudentMatchResult {
        val trimmed = scannedName.trim()
        if (trimmed.isEmpty() || students.isEmpty()) {
            return StudentMatchResult(scannedName = scannedName)
        }
        val norm = trimmed.lowercase().replace(Regex("\\s+"), " ")

        val exact = students.filter { it.fullName.lowercase().trim() == norm }
        if (exact.size == 1) return StudentMatchResult(exact.first(), trimmed, 1.0)
        if (exact.size > 1) return StudentMatchResult(null, trimmed, 1.0, exact, isAmbiguous = true)

        val firstWord = norm.split(" ").first()
        val firstMatches = students.filter { it.firstName.lowercase().trim() == firstWord }
        if (firstMatches.size == 1) return StudentMatchResult(firstMatches.first(), trimmed, 0.85)

        val scored = students
            .map { it to similarity(norm, it.fullName) }
            .filter { it.second > 0.5 }
            .sortedByDescending { it.second }

        if (scored.isEmpty()) return StudentMatchResult(scannedName = trimmed)
        val top = scored.first()
        if (top.second >= 0.7) {
            val ambig = scored.size > 1 && scored[1].second >= 0.7 && (top.second - scored[1].second) < 0.1
            return StudentMatchResult(
                matchedStudent = if (ambig) null else top.first,
                scannedName = trimmed,
                confidence = top.second,
                similarStudents = scored.take(3).map { it.first },
                isAmbiguous = ambig
            )
        }
        return StudentMatchResult(
            scannedName = trimmed,
            confidence = top.second,
            similarStudents = scored.take(3).map { it.first }
        )
    }

    fun matchFromOcr(ocrText: String, classStudents: List<Student>): StudentMatchResult {
        if (ocrText.isBlank() || classStudents.isEmpty()) return StudentMatchResult()
        val lines = ocrText.lines().map { it.trim() }.filter { it.isNotEmpty() }.take(8)
        for (line in lines) {
            // Check ID match
            val idMatch = classStudents.firstOrNull { s ->
                s.studentId.isNotBlank() && line.contains(s.studentId, ignoreCase = true)
            }
            if (idMatch != null) {
                return StudentMatchResult(idMatch, idMatch.fullName, 1.0)
            }
            val cleaned = line.replace(Regex("^(name|student|id)\\s*[:\\-]?\\s*", RegexOption.IGNORE_CASE), "").trim()
            if (cleaned.length >= 3 && !cleaned.first().isDigit()) {
                val res = matchName(cleaned, classStudents)
                if (res.hasMatch) return res
            }
        }
        return StudentMatchResult()
    }
}
