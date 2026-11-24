package com.ethiograde.service

import com.ethiograde.model.AnswerKeySection
import com.ethiograde.model.DetectedAnswer
import com.ethiograde.model.QuestionType

data class TextRegionInput(
    val text: String,
    val confidence: Double,
    val x: Double = 0.0,
    val y: Double = 0.0
)

data class ParsedBulkItem(
    val number: Int,
    val answer: String,
    val type: QuestionType
)

object AnswerParser {
    private val amharicMcq = mapOf("ሀ" to "A", "ለ" to "B", "ሐ" to "C", "መ" to "D", "ሠ" to "E")

    fun parseQuestionAnswer(text: String): Pair<Int, String>? {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return null

        val ethRegex = Regex("^([a-eA-E]{1,2})\\s+(\\d+)\\s*[.\\-):]?\\s*(.+)$")
        ethRegex.find(trimmed)?.let { m ->
            val num = m.groupValues[2].toIntOrNull()
            if (num != null && num in 1..200) {
                val letters = m.groupValues[1].uppercase().toList().joinToString(",")
                if (letters.isNotEmpty()) return num to letters
            }
        }

        val patterns = listOf(
            Regex("^(\\d+)\\s*[.\\-):]\\s*(.+)$"),
            Regex("^(\\d+)([a-eA-E]|[tTfF]|true|false|True|False)$"),
            Regex("^(\\d+)\\s+(true|false|True|False|TRUE|FALSE)$"),
            Regex("^(\\d+)\\s{1,2}(\\S{1,2})$")
        )
        for (p in patterns) {
            val match = p.find(trimmed) ?: continue
            val num = match.groupValues[1].toIntOrNull() ?: continue
            if (num !in 1..200) continue
            val raw = match.groupValues.last().trim()
            val extracted = extractAnswerFromText(raw)
            val norm = normalizeAnswer(extracted)
            if (norm.isNotEmpty()) return num to norm
        }
        return null
    }

    private fun extractAnswerFromText(text: String): String {
        val words = text.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (words.isEmpty()) return text.trim()
        val last = words.last()
        val lastNorm = normalizeAnswer(last)
        if (lastNorm == "True" || lastNorm == "False") return last
        if (Regex("^[a-eA-E]$").matches(last)) return last
        amharicMcq[last]?.let { return it }
        if (last == "እውነት" || last == "ት") return "True"
        if (last == "ሐሰት") return "False"
        return text.trim()
    }

    fun normalizeAnswer(raw: String): String {
        if (raw.isBlank()) return ""
        val stripped = raw.trim().replace(Regex("\\s+"), " ").replace(Regex("[.,;:!?]+$"), "")
        if (stripped.isEmpty()) return ""
        val lower = stripped.lowercase()
        if (lower in listOf("true", "t", "yes", "y")) return "True"
        if (lower in listOf("false", "f", "no", "n")) return "False"
        if (stripped in listOf("እውነት", "ት")) return "True"
        if (stripped == "ሐሰት") return "False"
        amharicMcq[stripped]?.let { return it }
        if (Regex("^[a-e]$").matches(lower)) return lower.uppercase()
        if (stripped.length <= 5 && Regex("^[a-zA-Z0-9]+$").matches(stripped)) return stripped
        if (stripped.length in 2..80 && Regex("[a-zA-Z0-9\\u1200-\\u137F]").containsMatchIn(stripped)) {
            return stripped
        }
        return ""
    }

    fun parseAnswersWithPosition(
        regions: List<TextRegionInput>,
        maxGap: Double = 20.0,
        maxGapBelow: Double = 90.0
    ): List<DetectedAnswer> {
        val out = mutableListOf<DetectedAnswer>()
        val answered = mutableSetOf<Int>()
        val sorted = regions.sortedBy { it.y }
        val consumed = mutableSetOf<Int>()

        sorted.forEachIndexed { idx, r ->
            parseQuestionAnswer(r.text)?.let { (q, ans) ->
                if (answered.add(q)) {
                    out.add(DetectedAnswer(q, ans, r.confidence, r.text, needsReview = r.confidence < 0.35, source = "ocr"))
                }
                consumed.add(idx)
            }
        }

        // Spatial horizontal association
        val lines = mutableListOf<MutableList<Int>>()
        sorted.forEachIndexed { idx, r ->
            val last = lines.lastOrNull()
            if (last == null || kotlin.math.abs(r.y - sorted[last.first()].y) > maxGap) {
                lines.add(mutableListOf(idx))
            } else {
                last.add(idx)
            }
        }
        for (line in lines) {
            if (line.size < 2) continue
            val byX = line.sortedBy { sorted[it].x }
            val qMatch = Regex("^(\\d+)\\s*[.\\-):]?$").find(sorted[byX.first()].text.trim()) ?: continue
            val qNum = qMatch.groupValues[1].toIntOrNull() ?: continue
            if (qNum !in 1..200 || answered.contains(qNum)) continue
            for (j in 1 until byX.size) {
                val cIdx = byX[j]
                if (consumed.contains(cIdx)) continue
                val norm = normalizeAnswer(sorted[cIdx].text)
                if (norm.isNotEmpty()) {
                    answered.add(qNum)
                    consumed.add(cIdx)
                    out.add(DetectedAnswer(qNum, norm, sorted[cIdx].confidence, sorted[cIdx].text, needsReview = true, source = "ocr-spatial"))
                    break
                }
            }
        }

        // Vertical association below bare question number
        sorted.forEachIndexed { i, anchor ->
            if (consumed.contains(i)) return@forEachIndexed
            val qMatch = Regex("^(\\d{1,3})\\s*[.\\-):]?$").find(anchor.text.trim()) ?: return@forEachIndexed
            val qNum = qMatch.groupValues[1].toIntOrNull() ?: return@forEachIndexed
            if (qNum !in 1..200 || answered.contains(qNum)) return@forEachIndexed

            var bestIdx: Int? = null
            var bestDy = Double.MAX_VALUE
            sorted.forEachIndexed { j, cand ->
                if (i == j || consumed.contains(j)) return@forEachIndexed
                val dy = cand.y - anchor.y
                if (dy <= 0 || dy > maxGapBelow) return@forEachIndexed
                if (kotlin.math.abs(cand.x - anchor.x) > 320.0) return@forEachIndexed
                if (parseQuestionAnswer(cand.text) != null) return@forEachIndexed
                val norm = normalizeAnswer(cand.text)
                if (norm.isEmpty()) return@forEachIndexed
                if (dy < bestDy) {
                    bestDy = dy
                    bestIdx = j
                }
            }
            bestIdx?.let { pick ->
                val chosen = sorted[pick]
                answered.add(qNum)
                consumed.add(pick)
                out.add(DetectedAnswer(qNum, normalizeAnswer(chosen.text), chosen.confidence, chosen.text, needsReview = true, source = "ocr-spatial"))
            }
        }
        return out
    }
}

object AnswerKeyParser {
    fun parseSectionBulkPaste(raw: String, section: AnswerKeySection): List<ParsedBulkItem> {
        if (raw.isBlank()) return emptyList()
        val parts = raw.split(Regex("[,\\s]+")).map { it.trim() }.filter { it.isNotEmpty() }
        return parts.mapIndexedNotNull { idx, value ->
            val qNum = section.start + idx
            if (qNum > section.end) null
            else ParsedBulkItem(qNum, normalizeForType(value, section.type), section.type)
        }
    }

    fun parseBulkPaste(raw: String): List<ParsedBulkItem> {
        if (raw.isBlank()) return emptyList()
        val parts = raw.split(",").map { it.trim() }.filter { it.isNotEmpty() }
        return parts.mapIndexedNotNull { idx, part ->
            val qNum = idx + 1
            if (part == "—" || part == "-") return@mapIndexedNotNull null
            val upper = part.uppercase()
            when {
                upper in listOf("T", "TRUE", "F", "FALSE") ->
                    ParsedBulkItem(qNum, if (upper.startsWith("T")) "True" else "False", QuestionType.TRUE_FALSE)
                Regex("^[A-E]$").matches(upper) ->
                    ParsedBulkItem(qNum, upper, QuestionType.MCQ)
                part.contains("+") && Regex("^[A-Ea-e]+(\\+[A-Ea-e]+)+$").matches(part) ->
                    ParsedBulkItem(qNum, upper, QuestionType.MULTI_ANSWER)
                else ->
                    ParsedBulkItem(qNum, part.removeSurrounding("\""), QuestionType.SHORT_ANSWER)
            }
        }
    }

    private fun normalizeForType(value: String, type: QuestionType): String {
        return when (type) {
            QuestionType.MCQ -> value.uppercase().take(1)
            QuestionType.TRUE_FALSE -> if (value.uppercase().startsWith("T")) "True" else "False"
            QuestionType.MULTI_ANSWER -> value.uppercase()
            else -> value
        }
    }
}
