package com.ethiograde.model

import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
enum class ScanStatus {
    GRADED,
    REVIEWED,
    NEEDS_RESCAN,
    MANUAL_ENTRY
}

@Serializable
data class AnswerMatch(
    val questionNumber: Int,
    val detectedAnswer: String,
    val correctAnswer: String,
    val isCorrect: Boolean,
    val score: Double,
    val maxScore: Double,
    val confidence: Double = 1.0,
    val ocrRawText: String? = null,
    val isOverridden: Boolean = false
)

@Serializable
data class ScanResult(
    val id: String = UUID.randomUUID().toString(),
    val assessmentId: String,
    val studentId: String = "",
    val studentName: String = "Student",
    val imagePath: String = "",
    val enhancedImagePath: String = "",
    val answers: List<AnswerMatch> = emptyList(),
    val totalScore: Double = 0.0,
    val maxScore: Double = 1.0,
    val percentage: Double = 0.0,
    val grade: String = "F",
    val status: ScanStatus = ScanStatus.GRADED,
    val confidence: Double = 1.0,
    val imageHash: String? = null,
    val paperLabel: String = "",
    val teacherNotes: String = "",
    val scannedAtMillis: Long = System.currentTimeMillis(),
    val uncertainQuestions: List<Int> = emptyList(),
    val detectedMethod: String = "manual",
    val scoredWithKeyFingerprint: String = "",
    val scoredWithKeyRevision: Int = 1,
    val weightedScoring: Boolean = false
) {
    val isMissingStudent: Boolean
        get() = studentId.isBlank() || studentName.equals("Unknown Student", ignoreCase = true)

    fun isOutdatedKey(currentFingerprint: String): Boolean {
        if (currentFingerprint.isBlank() || scoredWithKeyFingerprint.isBlank()) return false
        return currentFingerprint != scoredWithKeyFingerprint
    }

    fun requiresTeacherAction(currentFingerprint: String = ""): Boolean {
        if (status == ScanStatus.NEEDS_RESCAN) return true
        if (status == ScanStatus.REVIEWED) return false
        if (uncertainQuestions.isNotEmpty()) return true
        if (answers.any { it.detectedAnswer == "[MULTIPLE]" || it.detectedAnswer == "[MISSING]" }) {
            return true
        }
        if (isOutdatedKey(currentFingerprint)) return true
        if (isMissingStudent) return true
        return false
    }
}

data class DetectedAnswer(
    val questionNumber: Int,
    val answer: String,
    val confidence: Double = 1.0,
    val rawText: String = "",
    val needsReview: Boolean = false,
    val source: String = "ocr"
)
