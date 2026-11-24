package com.ethiograde.service

import com.ethiograde.model.*
import kotlin.math.ceil

data class SubjectPerformance(
    val subject: String,
    val assessmentCount: Int,
    val resultCount: Int,
    val averagePercentage: Double,
    val passRate: Double,
    val highestScore: Double,
    val lowestScore: Double
)

data class AtRiskStudent(
    val student: Student,
    val averagePercentage: Double,
    val assessedCount: Int,
    val failingCount: Int
)

data class StudentTrendPoint(
    val assessmentTitle: String,
    val subject: String,
    val percentage: Double,
    val timestampMillis: Long
)

object AnalyticsService {
    fun computeBySubject(
        assessments: List<Assessment>,
        allResults: List<ScanResult>
    ): List<SubjectPerformance> {
        val bySubject = assessments.groupBy { it.subject }
        return bySubject.map { (subject, subAssessments) ->
            val ids = subAssessments.map { it.id }.toSet()
            val results = allResults.filter {
                it.assessmentId in ids && (it.status == ScanStatus.GRADED || it.status == ScanStatus.REVIEWED || it.status == ScanStatus.MANUAL_ENTRY)
            }
            val avg = if (results.isEmpty()) 0.0 else results.sumOf { it.percentage } / results.size
            val passCount = results.count { it.percentage >= 50.0 }
            val passRate = if (results.isEmpty()) 0.0 else passCount.toDouble() / results.size * 100.0
            SubjectPerformance(
                subject = subject,
                assessmentCount = subAssessments.size,
                resultCount = results.size,
                averagePercentage = avg,
                passRate = passRate,
                highestScore = results.maxOfOrNull { it.percentage } ?: 0.0,
                lowestScore = results.minOfOrNull { it.percentage } ?: 0.0
            )
        }.sortedByDescending { it.resultCount }
    }

    fun findAtRiskStudents(
        students: List<Student>,
        allResults: List<ScanResult>,
        threshold: Double = 55.0
    ): List<AtRiskStudent> {
        val byStudent = allResults.groupBy { it.studentId }
        return students.mapNotNull { st ->
            val res = byStudent[st.id].orEmpty()
            if (res.isEmpty()) return@mapNotNull null
            val avg = res.sumOf { it.percentage } / res.size
            val failing = res.count { it.percentage < 50.0 }
            if (avg < threshold || failing >= 2) {
                AtRiskStudent(st, avg, res.size, failing)
            } else null
        }.sortedBy { it.averagePercentage }
    }

    fun studentTrend(
        studentId: String,
        assessments: List<Assessment>,
        allResults: List<ScanResult>
    ): List<StudentTrendPoint> {
        val assessmentMap = assessments.associateBy { it.id }
        return allResults
            .filter { it.studentId == studentId }
            .sortedBy { it.scannedAtMillis }
            .map { r ->
                val a = assessmentMap[r.assessmentId]
                StudentTrendPoint(
                    assessmentTitle = a?.title ?: "Assessment",
                    subject = a?.subject ?: "",
                    percentage = r.percentage,
                    timestampMillis = r.scannedAtMillis
                )
            }
    }
}

object ItemAnalysisService {
    fun computeSummary(
        results: List<ScanResult>,
        assessment: Assessment
    ): ClassAnalysisSummary {
        val graded = results.filter {
            it.status == ScanStatus.GRADED || it.status == ScanStatus.REVIEWED || it.status == ScanStatus.MANUAL_ENTRY
        }
        if (graded.isEmpty()) {
            return ClassAnalysisSummary(0, 0.0, 0, 0, 0, 0, emptyList())
        }

        val sortedByScore = graded.sortedByDescending { it.totalScore }
        val groupSize = ceil(sortedByScore.size * 0.27).toInt().coerceAtLeast(1)
        val topGroup = sortedByScore.take(groupSize)
        val bottomGroup = sortedByScore.takeLast(groupSize)

        val stats = assessment.questions.sortedBy { it.number }.map { q ->
            val qMatches = graded.mapNotNull { res -> res.answers.firstOrNull { it.questionNumber == q.number } }
            val totalAttempts = qMatches.size
            val correctCount = qMatches.count { it.isCorrect }
            val difficulty = if (totalAttempts > 0) correctCount.toDouble() / totalAttempts else 0.0

            val topCorrect = topGroup.count { res -> res.answers.any { it.questionNumber == q.number && it.isCorrect } }
            val botCorrect = bottomGroup.count { res -> res.answers.any { it.questionNumber == q.number && it.isCorrect } }
            val discrimination = (topCorrect.toDouble() / topGroup.size) - (botCorrect.toDouble() / bottomGroup.size)

            val optionCounts = qMatches
                .groupBy { it.detectedAnswer.ifBlank { "[MISSING]" } }
                .mapValues { it.value.size }

            QuestionStats(
                questionNumber = q.number,
                questionText = q.text.ifBlank { "Question ${q.number}" },
                correctAnswer = q.correctAnswer,
                totalAttempts = totalAttempts,
                correctCount = correctCount,
                difficulty = difficulty,
                discrimination = discrimination,
                optionCounts = optionCounts
            )
        }

        val avgScore = graded.sumOf { it.percentage } / graded.size
        return ClassAnalysisSummary(
            totalStudents = graded.size,
            averageScore = avgScore,
            easyCount = stats.count { it.difficultyLevel == DifficultyLevel.EASY },
            mediumCount = stats.count { it.difficultyLevel == DifficultyLevel.MEDIUM },
            hardCount = stats.count { it.difficultyLevel == DifficultyLevel.HARD },
            lowDiscriminationCount = stats.count { it.isLowDiscrimination },
            questions = stats
        )
    }
}

object HomeroomConsolidationService {
    fun consolidate(
        classInfo: ClassInfo,
        students: List<Student>,
        assessments: List<Assessment>,
        allResults: List<ScanResult>,
        attendanceRecords: List<AttendanceRecord>,
        overrides: Map<String, HomeroomOverride>,
        semester: String,
        academicYear: String,
        homeroomTeacherName: String,
        customScales: List<GradingScale> = emptyList()
    ): HomeroomClassReport {
        val classStudents = students.filter { it.belongsToClass(classInfo.id, classInfo.displayName) }
        val classAssessments = assessments.filter { a ->
            (a.classId == classInfo.id || a.classId.isBlank()) &&
                (semester == "All" || a.semester.equals(semester, ignoreCase = true)) &&
                (academicYear.isBlank() || a.academicYear.isBlank() || a.academicYear == academicYear)
        }

        val subjectList = classAssessments.map { it.subject }.distinct().sorted()
        val absentByStudent = mutableMapOf<String, Int>()
        attendanceRecords.filter { it.classId == classInfo.id }.forEach { rec ->
            rec.entries.forEach { (sId, st) ->
                if (st == AttendanceStatus.ABSENT) {
                    absentByStudent[sId] = (absentByStudent[sId] ?: 0) + 1
                }
            }
        }

        val draftReports = classStudents.mapIndexed { idx, student ->
            val subjectsMap = mutableMapOf<String, SubjectConsolidation>()
            for (subject in subjectList) {
                val subAssessments = classAssessments.filter { it.subject == subject }
                var quizPts = 0.0
                var quizMax = 0.0
                var midPts = 0.0
                var midMax = 0.0
                var finPts = 0.0
                var finMax = 0.0
                var hitCount = 0

                for (a in subAssessments) {
                    val res = allResults.firstOrNull {
                        it.assessmentId == a.id &&
                            (it.studentId == student.id || it.studentName.equals(student.fullName, ignoreCase = true))
                    } ?: continue
                    hitCount++
                    when {
                        a.category.contains("mid", ignoreCase = true) || a.title.contains("mid", ignoreCase = true) -> {
                            midPts += res.totalScore
                            midMax += res.maxScore
                        }
                        a.category.contains("final", ignoreCase = true) || a.title.contains("final", ignoreCase = true) -> {
                            finPts += res.totalScore
                            finMax += res.maxScore
                        }
                        else -> {
                            quizPts += res.totalScore
                            quizMax += res.maxScore
                        }
                    }
                }

                if (hitCount > 0) {
                    val totalEarned = quizPts + midPts + finPts
                    val totalMax = (quizMax + midMax + finMax).coerceAtLeast(1.0)
                    val pct = (totalEarned / totalMax * 100.0).coerceIn(0.0, 100.0)
                    val grade = ScoringService.calculateGrade(pct, "moe_national", customScales)
                    subjectsMap[subject] = SubjectConsolidation(
                        subjectName = subject,
                        quizScore = quizPts,
                        midtermScore = midPts,
                        finalScore = finPts,
                        totalScore = pct,
                        maxPossible = 100.0,
                        percentage = pct,
                        letterGrade = grade,
                        assessmentCount = hitCount
                    )
                }
            }

            val grandTotal = subjectsMap.values.sumOf { it.totalScore }
            val avg = if (subjectsMap.isEmpty()) 0.0 else grandTotal / subjectsMap.size
            val ov = overrides["${classInfo.id}_${student.id}"]
            val (remarkEn, remarkAm) = generateRemarks(avg)

            HomeroomStudentReport(
                studentId = student.id,
                rollNumber = student.studentId.ifBlank { "${idx + 1}" },
                fullName = student.fullName,
                gender = student.gender.ifBlank { "—" },
                subjects = subjectsMap,
                grandTotal = grandTotal,
                semesterAverage = avg,
                classRank = 1,
                conduct = ov?.conduct ?: "A",
                absentDays = absentByStudent[student.id] ?: 0,
                hasFinanceHold = ov?.hasFinanceHold ?: false,
                remarkEn = remarkEn,
                remarkAm = remarkAm
            )
        }.sortedByDescending { it.semesterAverage }

        // Standard tied competition ranking (1, 1, 3...)
        var lastAvg = -1.0
        var lastRank = 1
        val ranked = draftReports.mapIndexed { index, r ->
            val rank = if (index > 0 && kotlin.math.abs(r.semesterAverage - lastAvg) < 0.01) {
                lastRank
            } else {
                index + 1
            }
            lastAvg = r.semesterAverage
            lastRank = rank
            r.copy(classRank = rank)
        }

        return HomeroomClassReport(
            classId = classInfo.id,
            className = classInfo.displayName,
            semester = semester,
            academicYear = academicYear,
            homeroomTeacherName = homeroomTeacherName,
            subjectList = subjectList,
            students = ranked
        )
    }

    private fun generateRemarks(avg: Double): Pair<String, String> = when {
        avg >= 90.0 -> "Excellent performance. Keep it up!" to "በጣም ጥሩ ውጤት! በዚህ ይቀጥሉ"
        avg >= 80.0 -> "Very good effort and progress." to "በጣም ጥሩ ጥረት እና መሻሻል"
        avg >= 60.0 -> "Satisfactory work. Aim higher next term." to "ጥሩ ውጤት፤ በሚቀጥለው የተሻለ ይስሩ"
        avg >= 50.0 -> "Passing grade. More practice advised." to "አላፊ ውጤት፤ ተጨማሪ ልምምድ ያስፈልጋል"
        else -> "Needs close academic follow-up." to "ልዩ ክትትል እና ድጋፍ ያስፈልጋል"
    }
}
