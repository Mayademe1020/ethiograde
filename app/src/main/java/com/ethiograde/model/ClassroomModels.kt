package com.ethiograde.model

import kotlinx.serialization.Serializable
import java.security.MessageDigest
import java.util.UUID

@Serializable
enum class AttendanceStatus(val label: String, val shortCode: String) {
    PRESENT("Present", "P"),
    ABSENT("Absent", "A"),
    LATE("Late", "L"),
    EXCUSED("Excused", "E")
}

@Serializable
data class AttendanceRecord(
    val id: String = UUID.randomUUID().toString(),
    val classId: String,
    val dateIso: String, // YYYY-MM-DD
    val entries: Map<String, AttendanceStatus> = emptyMap(),
    val notes: String = "",
    val updatedAtMillis: Long = System.currentTimeMillis()
) {
    val presentCount: Int get() = entries.values.count { it == AttendanceStatus.PRESENT }
    val absentCount: Int get() = entries.values.count { it == AttendanceStatus.ABSENT }
    val lateCount: Int get() = entries.values.count { it == AttendanceStatus.LATE }
    val excusedCount: Int get() = entries.values.count { it == AttendanceStatus.EXCUSED }
}

@Serializable
data class ClassNote(
    val id: String = UUID.randomUUID().toString(),
    val classId: String,
    val dateIso: String,
    val title: String,
    val content: String,
    val category: String = "General",
    val createdAtMillis: Long = System.currentTimeMillis()
)

@Serializable
enum class AuditAction(val label: String) {
    CREATED("Graded"),
    SCORE_OVERRIDE("Score Overridden"),
    ANSWER_CORRECTED("Answer Corrected"),
    STUDENT_REASSIGNED("Student Reassigned"),
    MARKED_REVIEWED("Marked Reviewed"),
    REVERTED("Reverted"),
    KEY_RECALCULATED("Answer Key Updated")
}

@Serializable
data class AuditEntry(
    val id: String = UUID.randomUUID().toString(),
    val scanResultId: String,
    val assessmentId: String,
    val action: AuditAction,
    val previousScore: Double,
    val newScore: Double,
    val previousGrade: String,
    val newGrade: String,
    val reason: String = "",
    val changedBy: String = "Teacher",
    val timestampMillis: Long = System.currentTimeMillis()
)

@Serializable
data class ProofVaultEntry(
    val id: String = UUID.randomUUID().toString(),
    val assessmentId: String,
    val studentId: String,
    val studentName: String,
    val totalScore: Double,
    val maxScore: Double,
    val bubbleDensities: Map<Int, Map<String, Double>> = emptyMap(),
    val detectedAnswers: Map<Int, String> = emptyMap(),
    val integrityHash: String,
    val scannedAtMillis: Long = System.currentTimeMillis()
) {
    fun verifyIntegrity(): Boolean = computeHash() == integrityHash

    fun computeHash(): String = computeProofHash(
        assessmentId = assessmentId,
        studentId = studentId,
        totalScore = totalScore,
        bubbleDensities = bubbleDensities,
        detectedAnswers = detectedAnswers,
        scannedAtMillis = scannedAtMillis
    )

    companion object {
        fun computeProofHash(
            assessmentId: String,
            studentId: String,
            totalScore: Double,
            bubbleDensities: Map<Int, Map<String, Double>>,
            detectedAnswers: Map<Int, String>,
            scannedAtMillis: Long
        ): String {
            val densityPayload = bubbleDensities.entries.sortedBy { it.key }.joinToString(";") { (q, map) ->
                "$q:" + map.entries.sortedBy { it.key }.joinToString(",") { (opt, d) ->
                    "$opt=${"%.4f".format(d)}"
                }
            }
            val answerPayload = detectedAnswers.entries.sortedBy { it.key }.joinToString(";") { (q, ans) ->
                "$q=$ans"
            }
            val raw = "$assessmentId|$studentId|${"%.2f".format(totalScore)}|$scannedAtMillis|$densityPayload|$answerPayload"
            val digest = MessageDigest.getInstance("SHA-256").digest(raw.toByteArray())
            return digest.joinToString("") { "%02x".format(it) }
        }
    }
}

@Serializable
data class GradingDraft(
    val assessmentId: String,
    val classId: String = "",
    val completedCount: Int = 0,
    val currentStudentIndex: Int = 0,
    val savedAtMillis: Long = System.currentTimeMillis(),
    val mode: String = "quick_enter"
) {
    val ageMillis: Long get() = (System.currentTimeMillis() - savedAtMillis).coerceAtLeast(0L)
    val ageLabel: String
        get() {
            val mins = ageMillis / 60_000
            if (mins < 1) return "just now"
            if (mins < 60) return "${mins}m ago"
            val hours = mins / 60
            if (hours < 24) return "${hours}h ago"
            return "${hours / 24}d ago"
        }
}

@Serializable
data class SmsLogEntry(
    val id: String = UUID.randomUUID().toString(),
    val studentName: String,
    val phoneNumber: String,
    val message: String,
    val templateName: String = "",
    val success: Boolean = true,
    val errorMessage: String? = null,
    val sentAtMillis: Long = System.currentTimeMillis()
)
