package com.ethiograde.model

import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
data class GradeRange(
    val grade: String,
    val minScore: Double,
    val maxScore: Double,
    val remark: String = ""
)

@Serializable
data class GradingScale(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val rubricKey: String = "custom:$id",
    val ranges: List<GradeRange>
) {
    fun gradeFor(percentage: Double): String {
        val clamped = percentage.coerceIn(0.0, 100.0)
        val sorted = ranges.sortedByDescending { it.minScore }
        for (r in sorted) {
            if (clamped >= r.minScore) return r.grade
        }
        return sorted.lastOrNull()?.grade ?: "F"
    }

    companion object {
        val moeNational = GradingScale(
            id = "moe_national",
            name = "Ethiopian MoE National",
            rubricKey = "moe_national",
            ranges = listOf(
                GradeRange("A", 90.0, 100.0, "Excellent"),
                GradeRange("B", 80.0, 89.99, "Very Good"),
                GradeRange("C", 60.0, 79.99, "Satisfactory"),
                GradeRange("D", 50.0, 59.99, "Fair"),
                GradeRange("F", 0.0, 49.99, "Fail")
            )
        )

        val privateInternational = GradingScale(
            id = "private_international",
            name = "Private / International",
            rubricKey = "private_international",
            ranges = listOf(
                GradeRange("A+", 95.0, 100.0, "Distinction"),
                GradeRange("A", 90.0, 94.99, "Excellent"),
                GradeRange("B+", 85.0, 89.99, "Very Good"),
                GradeRange("B", 80.0, 84.99, "Good"),
                GradeRange("C+", 75.0, 79.99, "Above Average"),
                GradeRange("C", 70.0, 74.99, "Average"),
                GradeRange("D", 60.0, 69.99, "Pass"),
                GradeRange("F", 0.0, 59.99, "Fail")
            )
        )

        val university = GradingScale(
            id = "university",
            name = "University / Higher Ed",
            rubricKey = "university",
            ranges = listOf(
                GradeRange("A+", 90.0, 100.0, "First Class"),
                GradeRange("A", 85.0, 89.99, "Excellent"),
                GradeRange("A-", 80.0, 84.99, "Very Good"),
                GradeRange("B+", 75.0, 79.99, "Good"),
                GradeRange("B", 70.0, 74.99, "Above Average"),
                GradeRange("B-", 65.0, 69.99, "Satisfactory"),
                GradeRange("C+", 60.0, 64.99, "Fair"),
                GradeRange("C", 50.0, 59.99, "Pass"),
                GradeRange("D", 40.0, 49.99, "Conditional"),
                GradeRange("F", 0.0, 39.99, "Fail")
            )
        )

        val builtInPresets: List<GradingScale> = listOf(moeNational, privateInternational, university)
    }
}

@Serializable
data class AssessmentComponent(
    val name: String,
    val weight: Double
)

@Serializable
data class WeightedGradeScale(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val rubricType: String = "moe_national",
    val components: List<AssessmentComponent> = emptyList()
)
