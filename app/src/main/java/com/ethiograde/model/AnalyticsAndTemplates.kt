package com.ethiograde.model

import kotlinx.serialization.Serializable

data class SubjectConsolidation(
    val subjectName: String,
    val quizScore: Double = 0.0,
    val midtermScore: Double = 0.0,
    val finalScore: Double = 0.0,
    val totalScore: Double = 0.0,
    val maxPossible: Double = 100.0,
    val percentage: Double = 0.0,
    val letterGrade: String = "F",
    val assessmentCount: Int = 0
)

data class HomeroomStudentReport(
    val studentId: String,
    val rollNumber: String,
    val fullName: String,
    val gender: String,
    val subjects: Map<String, SubjectConsolidation>,
    val grandTotal: Double,
    val semesterAverage: Double,
    val classRank: Int,
    val conduct: String = "A",
    val absentDays: Int = 0,
    val hasFinanceHold: Boolean = false,
    val remarkEn: String = "",
    val remarkAm: String = ""
)

data class HomeroomClassReport(
    val classId: String,
    val className: String,
    val semester: String,
    val academicYear: String,
    val homeroomTeacherName: String,
    val subjectList: List<String>,
    val students: List<HomeroomStudentReport>
)

@Serializable
data class HomeroomOverride(
    val id: String, // "${classId}_${studentId}"
    val classId: String,
    val studentId: String,
    val conduct: String = "A",
    val hasFinanceHold: Boolean = false
)

enum class DifficultyLevel(val label: String) {
    EASY("Easy"),
    MEDIUM("Medium"),
    HARD("Hard")
}

data class QuestionStats(
    val questionNumber: Int,
    val questionText: String,
    val correctAnswer: String,
    val totalAttempts: Int,
    val correctCount: Int,
    val difficulty: Double,
    val discrimination: Double,
    val optionCounts: Map<String, Int>
) {
    val difficultyLevel: DifficultyLevel
        get() = when {
            difficulty >= 0.7 -> DifficultyLevel.EASY
            difficulty >= 0.4 -> DifficultyLevel.MEDIUM
            else -> DifficultyLevel.HARD
        }

    val isLowDiscrimination: Boolean get() = totalAttempts >= 4 && discrimination < 0.2
}

data class ClassAnalysisSummary(
    val totalStudents: Int,
    val averageScore: Double,
    val easyCount: Int,
    val mediumCount: Int,
    val hardCount: Int,
    val lowDiscriminationCount: Int,
    val questions: List<QuestionStats>
)

@Serializable
data class BubbleTemplate(
    val name: String,
    val questionCount: Int,
    val options: List<String> = listOf("A", "B", "C", "D", "E"),
    val startX: Double,
    val startY: Double,
    val columnSpacing: Double,
    val rowSpacing: Double,
    val bubbleRadius: Double = 8.0,
    val fillThreshold: Double = 0.30
) {
    fun bubbleCenter(questionIndex: Int, optionIndex: Int): Pair<Double, Double> {
        return Pair(startX + optionIndex * columnSpacing, startY + questionIndex * rowSpacing)
    }

    val optionCount: Int get() = options.size
}

object StandardTemplates {
    val moe20x5 = BubbleTemplate("MoE 20×5", 20, listOf("A", "B", "C", "D", "E"), 280.0, 290.0, 110.0, 30.0, 8.0, 0.30)
    val moe30x5 = BubbleTemplate("MoE 30×5", 30, listOf("A", "B", "C", "D", "E"), 280.0, 260.0, 110.0, 27.0, 7.0, 0.30)
    val tf10 = BubbleTemplate("True/False 10", 10, listOf("True", "False"), 350.0, 290.0, 200.0, 30.0, 8.0, 0.30)
    val tf20 = BubbleTemplate("True/False 20", 20, listOf("True", "False"), 350.0, 270.0, 200.0, 27.0, 7.0, 0.30)
    val uni50x4 = BubbleTemplate("University 50×4", 50, listOf("A", "B", "C", "D"), 300.0, 220.0, 130.0, 22.0, 6.0, 0.30)
    val moe100x5 = BubbleTemplate("MoE 100×5", 100, listOf("A", "B", "C", "D", "E"), 180.0, 180.0, 110.0, 26.0, 7.0, 0.30)
    val moe120x5 = BubbleTemplate("MoE 120×5 (National)", 120, listOf("A", "B", "C", "D", "E"), 120.0, 150.0, 130.0, 24.0, 6.0, 0.30)

    val all = listOf(moe20x5, moe30x5, tf10, tf20, uni50x4, moe100x5, moe120x5)

    fun matchAssessment(questionCount: Int, isTrueFalse: Boolean): BubbleTemplate {
        if (isTrueFalse) return if (questionCount <= 10) tf10 else tf20
        return when {
            questionCount <= 20 -> moe20x5
            questionCount <= 30 -> moe30x5
            questionCount <= 50 -> uni50x4
            questionCount <= 100 -> moe100x5
            else -> moe120x5
        }
    }
}

data class CalibrationResult(
    val detectedCount: Int,
    val expectedCount: Int,
    val averageFill: Double,
    val fillMatrix: Map<Int, Map<String, Double>>
) {
    val isGoodAlignment: Boolean get() = expectedCount > 0 && detectedCount >= (expectedCount * 0.6).toInt()
}
