package com.ethiograde.model

import kotlinx.serialization.Serializable
import java.security.MessageDigest
import java.util.UUID

@Serializable
enum class QuestionType(val label: String, val shortCode: String) {
    MCQ("Multiple Choice", "MCQ"),
    TRUE_FALSE("True / False", "T/F"),
    SHORT_ANSWER("Short Answer", "SHORT"),
    ESSAY("Essay", "ESSAY"),
    MATCHING("Matching", "MATCH"),
    MULTI_ANSWER("Multi-Answer", "MULTI");

    val isObjective: Boolean
        get() = this == MCQ || this == TRUE_FALSE || this == MATCHING || this == MULTI_ANSWER
}

@Serializable
data class AnswerKeySection(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val type: QuestionType,
    val start: Int,
    val end: Int,
    val pointsPerQuestion: Double = 1.0,
    val isLocked: Boolean = false
) {
    val count: Int get() = (end - start + 1).coerceAtLeast(0)
}

@Serializable
data class Question(
    val number: Int,
    val text: String = "",
    val type: QuestionType = QuestionType.MCQ,
    val correctAnswer: String = "",
    val acceptedAnswers: List<String> = emptyList(),
    val points: Double = 1.0,
    val options: List<String> = emptyList(),
    val keywords: List<String> = emptyList(),
    val isFlagged: Boolean = false
) {
    val isObjective: Boolean get() = type.isObjective
    val hasAnswer: Boolean get() = correctAnswer.isNotBlank() || acceptedAnswers.isNotEmpty()
    val effectiveAnswers: List<String>
        get() = if (acceptedAnswers.isNotEmpty()) acceptedAnswers
        else if (correctAnswer.isNotBlank()) listOf(correctAnswer)
        else emptyList()
}

enum class AssessmentOperationalState {
    NEEDS_SETUP,
    NEEDS_KEY,
    READY_TO_SCAN,
    IN_PROGRESS,
    NEEDS_REVIEW,
    COMPLETED
}

enum class AssessmentNextAction {
    FINISH_KEY,
    START_SCANNING,
    RESUME_SCANNING,
    REVIEW_PAPERS,
    VIEW_RESULTS
}

enum class ExamDayStartMode {
    CREATE_FORM,
    QUICK_SCAN,
    CA_FAST_ENTRY
}

@Serializable
data class Assessment(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val subject: String = "Mathematics",
    val classId: String = "",
    val className: String = "",
    val gradeLevel: Int = 5,
    val academicYear: String = "",
    val rubricType: String = "moe_national",
    val semester: String = "Semester 1",
    val category: String = "Quiz",
    val weightPercent: Double = 10.0,
    val questions: List<Question> = emptyList(),
    val sections: List<AnswerKeySection> = emptyList(),
    val isCompleted: Boolean = false,
    val isAnswerKeyConfirmed: Boolean = false,
    val answerKeyFingerprint: String = "",
    val answerKeyRevision: Int = 1,
    val createdAtMillis: Long = System.currentTimeMillis(),
    val updatedAtMillis: Long = System.currentTimeMillis()
) {
    val questionCount: Int get() = questions.size
    val maxScore: Double get() = questions.sumOf { it.points }.let { if (it <= 0.0) 1.0 else it }

    val answeredQuestionCount: Int get() = questions.count { it.hasAnswer }
    val hasCompleteAnswerKey: Boolean
        get() = questions.isNotEmpty() && questions.all { it.hasAnswer }

    val mcqCount: Int get() = questions.count { it.type == QuestionType.MCQ }
    val trueFalseCount: Int get() = questions.count { it.type == QuestionType.TRUE_FALSE }
    val shortAnswerCount: Int get() = questions.count { it.type == QuestionType.SHORT_ANSWER }
    val essayCount: Int get() = questions.count { it.type == QuestionType.ESSAY }
    val matchingCount: Int get() = questions.count { it.type == QuestionType.MATCHING }
    val multiAnswerCount: Int get() = questions.count { it.type == QuestionType.MULTI_ANSWER }

    fun computeAnswerKeyFingerprint(): String {
        val canonical = questions.sortedBy { it.number }.joinToString("|") { q ->
            "${q.number}:${q.type.name}:${q.correctAnswer.trim().uppercase()}:${q.points}"
        }
        val digest = MessageDigest.getInstance("SHA-256").digest(canonical.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }.take(16)
    }

    fun operationalState(results: List<ScanResult>): AssessmentOperationalState {
        if (questions.isEmpty()) return AssessmentOperationalState.NEEDS_SETUP
        if (!hasCompleteAnswerKey) return AssessmentOperationalState.NEEDS_KEY
        if (isCompleted) return AssessmentOperationalState.COMPLETED
        val needsAction = results.any { it.requiresTeacherAction(answerKeyFingerprint) }
        if (needsAction) return AssessmentOperationalState.NEEDS_REVIEW
        if (results.isNotEmpty()) return AssessmentOperationalState.IN_PROGRESS
        return AssessmentOperationalState.READY_TO_SCAN
    }

    fun nextAction(results: List<ScanResult>): AssessmentNextAction {
        return when (operationalState(results)) {
            AssessmentOperationalState.NEEDS_SETUP,
            AssessmentOperationalState.NEEDS_KEY -> AssessmentNextAction.FINISH_KEY
            AssessmentOperationalState.READY_TO_SCAN -> AssessmentNextAction.START_SCANNING
            AssessmentOperationalState.IN_PROGRESS -> AssessmentNextAction.RESUME_SCANNING
            AssessmentOperationalState.NEEDS_REVIEW -> AssessmentNextAction.REVIEW_PAPERS
            AssessmentOperationalState.COMPLETED -> AssessmentNextAction.VIEW_RESULTS
        }
    }
}
