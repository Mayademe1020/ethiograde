package com.ethiograde.service

import com.ethiograde.model.*
import kotlin.math.abs
import kotlin.math.min

data class AnswerDuplicate(
    val indexA: Int,
    val indexB: Int,
    val similarity: Double
)

object ScoringService {

    private val numberWords = mapOf(
        "zero" to "0", "one" to "1", "two" to "2", "three" to "3", "four" to "4",
        "five" to "5", "six" to "6", "seven" to "7", "eight" to "8", "nine" to "9",
        "ten" to "10", "eleven" to "11", "twelve" to "12", "twenty" to "20",
        "thirty" to "30", "forty" to "40", "fifty" to "50", "hundred" to "100"
    )

    fun calculateGrade(
        percentage: Double,
        rubricType: String,
        customScales: List<GradingScale> = emptyList()
    ): String {
        if (rubricType.startsWith("custom:")) {
            val id = rubricType.removePrefix("custom:")
            customScales.firstOrNull { it.id == id }?.let { return it.gradeFor(percentage) }
        }
        return when (rubricType) {
            "private_international" -> GradingScale.privateInternational.gradeFor(percentage)
            "university" -> GradingScale.university.gradeFor(percentage)
            else -> GradingScale.moeNational.gradeFor(percentage)
        }
    }

    fun scoreAnswers(
        detected: List<DetectedAnswer>,
        assessment: Assessment
    ): List<AnswerMatch> {
        val detectedByQ = detected.associateBy { it.questionNumber }
        return assessment.questions.sortedBy { it.number }.map { q ->
            val det = detectedByQ[q.number]
            val rawAns = det?.answer ?: "[MISSING]"
            if (rawAns == "[MISSING]" || rawAns == "[MULTIPLE]") {
                AnswerMatch(
                    questionNumber = q.number,
                    detectedAnswer = rawAns,
                    correctAnswer = q.correctAnswer,
                    isCorrect = false,
                    score = 0.0,
                    maxScore = q.points,
                    confidence = det?.confidence ?: 0.0,
                    ocrRawText = det?.rawText
                )
            } else {
                val (isCorrect, score) = checkAnswer(rawAns, q)
                AnswerMatch(
                    questionNumber = q.number,
                    detectedAnswer = rawAns,
                    correctAnswer = q.correctAnswer,
                    isCorrect = isCorrect,
                    score = score,
                    maxScore = q.points,
                    confidence = det?.confidence ?: 0.0,
                    ocrRawText = det?.rawText
                )
            }
        }
    }

    fun checkAnswer(detected: String, question: Question): Pair<Boolean, Double> {
        val det = detected.trim()
        val maxPts = question.points
        if (det.isEmpty() || !question.hasAnswer) return false to 0.0

        return when (question.type) {
            QuestionType.MCQ -> {
                val normDet = det.uppercase().take(1)
                val normKey = question.correctAnswer.trim().uppercase().take(1)
                val ok = normDet.isNotEmpty() && normDet == normKey
                ok to if (ok) maxPts else 0.0
            }
            QuestionType.TRUE_FALSE -> {
                val d = normalizeTrueFalse(det)
                val k = normalizeTrueFalse(question.correctAnswer)
                val ok = d.isNotEmpty() && d == k
                ok to if (ok) maxPts else 0.0
            }
            QuestionType.MULTI_ANSWER -> {
                val detSet = det.uppercase().split(Regex("[,+\\s]+")).filter { it.isNotEmpty() }.toSet()
                val keySet = question.correctAnswer.uppercase().split(Regex("[,+\\s]+")).filter { it.isNotEmpty() }.toSet()
                if (keySet.isEmpty()) return false to 0.0
                if (detSet == keySet) return true to maxPts
                val hits = detSet.intersect(keySet).size
                val wrong = (detSet - keySet).size
                val partial = ((hits - wrong * 0.5).coerceAtLeast(0.0) / keySet.size) * maxPts
                false to partial
            }
            QuestionType.MATCHING -> {
                val d = det.uppercase().removePrefix("MATCH:").replace(Regex("[,\\s-]+"), "")
                val k = question.correctAnswer.uppercase().removePrefix("MATCH:").replace(Regex("[,\\s-]+"), "")
                val ok = d.isNotEmpty() && d == k
                ok to if (ok) maxPts else 0.0
            }
            QuestionType.SHORT_ANSWER -> {
                val matched = question.effectiveAnswers.any { target ->
                    isShortAnswerMatch(det, target)
                }
                matched to if (matched) maxPts else 0.0
            }
            QuestionType.ESSAY -> {
                if (question.keywords.isEmpty()) {
                    val matched = question.effectiveAnswers.any { isShortAnswerMatch(det, it) }
                    matched to if (matched) maxPts else 0.0
                } else {
                    val lower = det.lowercase()
                    val matchedKeywords = question.keywords.count { kw -> lower.contains(kw.lowercase()) }
                    val ratio = matchedKeywords.toDouble() / question.keywords.size
                    val pts = (ratio * maxPts).coerceIn(0.0, maxPts)
                    (ratio >= 0.7) to pts
                }
            }
        }
    }

    fun isShortAnswerMatch(detected: String, correct: String): Boolean {
        val a = normalizeText(detected)
        val b = normalizeText(correct)
        if (a.isEmpty() || b.isEmpty()) return false
        if (a == b) return true
        // Numeric tolerance
        val numA = a.toDoubleOrNull()
        val numB = b.toDoubleOrNull()
        if (numA != null && numB != null && abs(numA - numB) < 0.01) return true
        // Levenshtein tolerance <= 2 for longer words
        if (b.length >= 4 && levenshtein(a, b) <= if (b.length >= 7) 2 else 1) return true
        return false
    }

    fun isFuzzyOnlyMatch(detected: String, correct: String): Boolean {
        val a = normalizeText(detected)
        val b = normalizeText(correct)
        if (a == b) return false
        return isShortAnswerMatch(detected, correct)
    }

    private fun normalizeText(s: String): String {
        val words = s.lowercase()
            .trim()
            .replace(Regex("[^a-z0-9\\u1200-\\u137F\\s.]"), " ")
            .split(Regex("\\s+"))
            .filter { it.isNotEmpty() }
            .map { numberWords[it] ?: it }
            .map { if (it.length > 4 && it.endsWith("s")) it.dropLast(1) else it }
        return words.joinToString(" ")
    }

    private fun normalizeTrueFalse(s: String): String {
        return when (s.trim().lowercase()) {
            "t", "true", "yes", "y", "እውነት" -> "TRUE"
            "f", "false", "no", "n", "ሐሰት" -> "FALSE"
            else -> ""
        }
    }

    fun deduplicateAnswers(answers: List<DetectedAnswer>): List<DetectedAnswer> {
        val best = mutableMapOf<Int, DetectedAnswer>()
        for (a in answers) {
            val prev = best[a.questionNumber]
            if (prev == null || a.confidence > prev.confidence) {
                best[a.questionNumber] = a
            }
        }
        return best.values.sortedBy { it.questionNumber }
    }

    fun levenshtein(a: String, b: String): Int {
        if (a.isEmpty()) return b.length
        if (b.isEmpty()) return a.length
        val dp = Array(a.length + 1) { IntArray(b.length + 1) }
        for (i in 0..a.length) dp[i][0] = i
        for (j in 0..b.length) dp[0][j] = j
        for (i in 1..a.length) {
            for (j in 1..b.length) {
                val cost = if (a[i - 1] == b[j - 1]) 0 else 1
                dp[i][j] = min(
                    min(dp[i - 1][j] + 1, dp[i][j - 1] + 1),
                    dp[i - 1][j - 1] + cost
                )
            }
        }
        return dp[a.length][b.length]
    }

    fun detectAnswerDuplicates(results: List<ScanResult>): List<AnswerDuplicate> {
        if (results.size < 2) return emptyList()
        val duplicates = mutableListOf<AnswerDuplicate>()
        for (i in results.indices) {
            for (j in (i + 1) until results.size) {
                val mapA = results[i].answers.associate { it.questionNumber to it.detectedAnswer }
                val mapB = results[j].answers.associate { it.questionNumber to it.detectedAnswer }
                val commonKeys = mapA.keys.intersect(mapB.keys).filter {
                    val v = mapA[it]
                    v != "[MISSING]" && v != "[MULTIPLE]"
                }
                if (commonKeys.size < 5) continue
                val same = commonKeys.count { mapA[it] == mapB[it] }
                val sim = same.toDouble() / commonKeys.size
                if (sim >= 0.90) {
                    duplicates.add(AnswerDuplicate(i, j, sim))
                }
            }
        }
        return duplicates
    }

    fun recalculateForUpdatedKey(
        assessment: Assessment,
        existingResults: List<ScanResult>,
        customScales: List<GradingScale> = emptyList()
    ): List<ScanResult> {
        val fingerprint = assessment.answerKeyFingerprint.ifEmpty { assessment.computeAnswerKeyFingerprint() }
        val qMap = assessment.questions.associateBy { it.number }
        return existingResults.map { res ->
            val rescoredMatches = res.answers.map { m ->
                val q = qMap[m.questionNumber] ?: return@map m
                if (m.isOverridden) return@map m
                if (m.detectedAnswer == "[MISSING]" || m.detectedAnswer == "[MULTIPLE]") {
                    return@map m.copy(correctAnswer = q.correctAnswer, maxScore = q.points, score = 0.0, isCorrect = false)
                }
                val (ok, pts) = checkAnswer(m.detectedAnswer, q)
                m.copy(correctAnswer = q.correctAnswer, isCorrect = ok, score = pts, maxScore = q.points)
            }
            val newTotal = rescoredMatches.sumOf { it.score }
            val newMax = assessment.maxScore
            val newPct = if (newMax > 0) (newTotal / newMax * 100.0).coerceIn(0.0, 100.0) else 0.0
            res.copy(
                answers = rescoredMatches,
                totalScore = newTotal,
                maxScore = newMax,
                percentage = newPct,
                grade = calculateGrade(newPct, assessment.rubricType, customScales),
                scoredWithKeyFingerprint = fingerprint,
                scoredWithKeyRevision = assessment.answerKeyRevision
            )
        }
    }
}
