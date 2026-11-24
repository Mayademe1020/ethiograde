package com.ethiograde.viewmodel

import android.app.Application
import android.graphics.Bitmap
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.ethiograde.EthioGradeApp
import com.ethiograde.data.AppSettings
import com.ethiograde.data.VoiceFeedbackMode
import com.ethiograde.model.*
import com.ethiograde.service.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

sealed class DashboardPrimaryAction {
    data class ResumeDraft(val assessment: Assessment, val draft: GradingDraft) : DashboardPrimaryAction()
    data class FinishAnswerKey(val assessment: Assessment) : DashboardPrimaryAction()
    data class ReviewPapers(val assessment: Assessment, val count: Int) : DashboardPrimaryAction()
    data class StartScanning(val assessment: Assessment) : DashboardPrimaryAction()
    data object DefaultGradePapers : DashboardPrimaryAction()
}

data class EthioGradeUiState(
    val settings: AppSettings = AppSettings(),
    val classes: List<ClassInfo> = emptyList(),
    val students: List<Student> = emptyList(),
    val assessments: List<Assessment> = emptyList(),
    val scanResults: List<ScanResult> = emptyList(),
    val teachers: List<Teacher> = emptyList(),
    val attendanceRecords: List<AttendanceRecord> = emptyList(),
    val classNotes: List<ClassNote> = emptyList(),
    val auditEntries: List<AuditEntry> = emptyList(),
    val proofVaultEntries: List<ProofVaultEntry> = emptyList(),
    val drafts: List<GradingDraft> = emptyList(),
    val smsLogs: List<SmsLogEntry> = emptyList(),
    val homeroomOverrides: Map<String, HomeroomOverride> = emptyMap(),
    val activeAssessmentId: String? = null,
    val isScanning: Boolean = false,
    val statusBanner: String? = null,
    val settingsLoaded: Boolean = false
) {
    val activeAssessment: Assessment?
        get() = assessments.firstOrNull { it.id == activeAssessmentId } ?: assessments.firstOrNull()

    fun resultsForAssessment(assessmentId: String): List<ScanResult> =
        scanResults.filter { it.assessmentId == assessmentId }.sortedByDescending { it.totalScore }

    fun studentsInClass(classId: String): List<Student> {
        val cls = classes.firstOrNull { it.id == classId }
        return students.filter { it.belongsToClass(classId, cls?.displayName.orEmpty()) }
    }

    fun resolveDashboardAction(): DashboardPrimaryAction {
        val recentDraft = drafts.firstOrNull { it.ageMillis < 7L * 24 * 60 * 60 * 1000 }
        if (recentDraft != null) {
            assessments.firstOrNull { it.id == recentDraft.assessmentId }?.let {
                return DashboardPrimaryAction.ResumeDraft(it, recentDraft)
            }
        }
        val unkeyed = assessments.firstOrNull { !it.isCompleted && !it.hasCompleteAnswerKey }
        if (unkeyed != null) return DashboardPrimaryAction.FinishAnswerKey(unkeyed)

        for (a in assessments) {
            if (a.isCompleted) continue
            val res = resultsForAssessment(a.id)
            val actionCount = res.count { it.requiresTeacherAction(a.answerKeyFingerprint) }
            if (actionCount > 0) return DashboardPrimaryAction.ReviewPapers(a, actionCount)
        }

        val ready = assessments.firstOrNull {
            !it.isCompleted && it.hasCompleteAnswerKey && resultsForAssessment(it.id).isEmpty()
        }
        if (ready != null) return DashboardPrimaryAction.StartScanning(ready)

        return DashboardPrimaryAction.DefaultGradePapers
    }
}

private data class CoreCollections(
    val settings: AppSettings,
    val classes: List<ClassInfo>,
    val students: List<Student>,
    val assessments: List<Assessment>,
    val scanResults: List<ScanResult>
)

private data class SecondaryCollections(
    val teachers: List<Teacher>,
    val attendance: List<AttendanceRecord>,
    val notes: List<ClassNote>,
    val audits: List<AuditEntry>,
    val proofs: List<ProofVaultEntry>
)

private data class TertiaryCollections(
    val drafts: List<GradingDraft>,
    val smsLogs: List<SmsLogEntry>,
    val overrides: List<HomeroomOverride>
)

class EthioGradeViewModel(application: Application) : AndroidViewModel(application) {
    private val app = application as EthioGradeApp
    private val repo = app.repository
    private val voiceManager = VoiceFeedbackManager(application)

    private val activeAssessmentIdFlow = MutableStateFlow<String?>(null)
    private val isScanningFlow = MutableStateFlow(false)
    private val statusBannerFlow = MutableStateFlow<String?>(null)

    private val coreFlow = combine(
        repo.settings.settingsFlow,
        repo.classes,
        repo.students,
        repo.assessments,
        repo.scanResults
    ) { settings, classes, students, assessments, results ->
        CoreCollections(settings, classes, students, assessments, results)
    }

    private val secondaryFlow = combine(
        repo.teachers,
        repo.attendanceRecords,
        repo.classNotes,
        repo.auditEntries,
        repo.proofVaultEntries
    ) { teachers, attendance, notes, audits, proofs ->
        SecondaryCollections(teachers, attendance, notes, audits, proofs)
    }

    private val tertiaryFlow = combine(
        repo.drafts,
        repo.smsLogs,
        repo.homeroomOverrides
    ) { drafts, sms, overrides ->
        TertiaryCollections(drafts, sms, overrides)
    }

    val uiState: StateFlow<EthioGradeUiState> = combine(
        coreFlow,
        secondaryFlow,
        tertiaryFlow,
        activeAssessmentIdFlow,
        isScanningFlow,
        statusBannerFlow
    ) { arr ->
        val core = arr[0] as CoreCollections
        val sec = arr[1] as SecondaryCollections
        val tert = arr[2] as TertiaryCollections
        val activeId = arr[3] as String?
        val scanning = arr[4] as Boolean
        val banner = arr[5] as String?
        EthioGradeUiState(
            settings = core.settings,
            classes = core.classes,
            students = core.students,
            assessments = core.assessments,
            scanResults = core.scanResults,
            teachers = sec.teachers,
            attendanceRecords = sec.attendance,
            classNotes = sec.notes,
            auditEntries = sec.audits,
            proofVaultEntries = sec.proofs,
            drafts = tert.drafts,
            smsLogs = tert.smsLogs,
            homeroomOverrides = tert.overrides.associateBy { it.id },
            activeAssessmentId = activeId,
            isScanning = scanning,
            statusBanner = banner,
            settingsLoaded = true
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = EthioGradeUiState()
    )

    fun clearBanner() {
        statusBannerFlow.value = null
    }

    fun selectActiveAssessment(assessmentId: String) {
        activeAssessmentIdFlow.value = assessmentId
    }

    // ── Onboarding & Demo Seeding ────────────────────────────────────────

    fun completeOnboarding(
        teacherName: String,
        schoolName: String,
        academicYear: String,
        gradeLevels: List<Int>,
        subjects: List<String>,
        seedDemo: Boolean = true
    ) {
        viewModelScope.launch {
            val cleanName = teacherName.trim().ifEmpty { "Teacher" }
            val cleanSchool = schoolName.trim()
            repo.settings.completeOnboarding(cleanName, cleanSchool, academicYear)
            if (subjects.isNotEmpty()) {
                repo.settings.saveSubjects((uiState.value.settings.subjects + subjects).distinct().sorted())
            }
            val teacher = Teacher(
                name = cleanName,
                schoolName = cleanSchool,
                gradeLevels = gradeLevels,
                subjects = subjects,
                isActive = true
            )
            repo.upsertTeacher(teacher)

            if (seedDemo && uiState.value.classes.isEmpty()) {
                val demo = DemoDataService.buildDemoData(academicYear)
                repo.seedAll(demo.classes, demo.students, demo.assessments, demo.scanResults)
            } else if (gradeLevels.isNotEmpty() && uiState.value.classes.isEmpty()) {
                val g = gradeLevels.first()
                val subj = subjects.firstOrNull() ?: "Mathematics"
                repo.upsertClass(
                    ClassInfo(
                        name = "Grade ${g}A — $subj",
                        grade = g,
                        section = "A",
                        subject = subj,
                        academicYear = academicYear,
                        isHomeroom = true
                    )
                )
            }
        }
    }

    fun loadDemoData() {
        viewModelScope.launch {
            val demo = DemoDataService.buildDemoData(uiState.value.settings.currentAcademicYear)
            repo.seedAll(demo.classes, demo.students, demo.assessments, demo.scanResults)
            statusBannerFlow.value = "Sample classroom data loaded"
        }
    }

    // ── Class CRUD ───────────────────────────────────────────────────────

    fun saveClass(classInfo: ClassInfo) {
        viewModelScope.launch {
            val year = classInfo.academicYear.ifBlank { uiState.value.settings.currentAcademicYear }
            repo.upsertClass(classInfo.copy(academicYear = year))
        }
    }

    fun canDeleteClass(classId: String): Pair<Boolean, String?> {
        val studentCount = uiState.value.studentsInClass(classId).size
        val assessmentCount = uiState.value.assessments.count { it.classId == classId }
        if (studentCount > 0 || assessmentCount > 0) {
            return false to "Remove or transfer $studentCount student(s) and $assessmentCount assessment(s) before deleting this class."
        }
        return true to null
    }

    fun deleteClass(classId: String) {
        viewModelScope.launch { repo.deleteClass(classId) }
    }

    // ── Student CRUD & Import ────────────────────────────────────────────

    fun saveStudent(student: Student) {
        viewModelScope.launch {
            repo.upsertStudent(student)
        }
    }

    fun importStudents(students: List<Student>) {
        viewModelScope.launch {
            repo.upsertStudents(students)
            statusBannerFlow.value = "Imported ${students.size} students"
        }
    }

    fun transferStudent(student: Student, targetClass: ClassInfo) {
        viewModelScope.launch {
            val updated = student.copy(
                classIds = listOf(targetClass.id),
                className = targetClass.displayName,
                grade = targetClass.grade,
                section = targetClass.section
            )
            repo.upsertStudent(updated)
            statusBannerFlow.value = "Transferred ${student.fullName} to ${targetClass.displayName}"
        }
    }

    fun deleteStudent(studentId: String) {
        viewModelScope.launch { repo.deleteStudent(studentId) }
    }

    // ── Attendance & Notes ───────────────────────────────────────────────

    fun saveAttendance(record: AttendanceRecord) {
        viewModelScope.launch { repo.upsertAttendance(record) }
    }

    fun saveClassNote(note: ClassNote) {
        viewModelScope.launch { repo.upsertClassNote(note) }
    }

    fun deleteClassNote(id: String) {
        viewModelScope.launch { repo.deleteClassNote(id) }
    }

    // ── Assessment & Answer Key ──────────────────────────────────────────

    fun createAssessment(
        title: String,
        subject: String,
        classInfo: ClassInfo?,
        questionCount: Int,
        category: String = "Quiz",
        semester: String = "Semester 1",
        onCreated: (Assessment) -> Unit
    ) {
        viewModelScope.launch {
            val questions = (1..questionCount.coerceIn(1, 200)).map { num ->
                Question(number = num, text = "Question $num", type = QuestionType.MCQ, correctAnswer = "", points = 1.0)
            }
            val sections = listOf(
                AnswerKeySection(
                    title = "Part I — Multiple Choice",
                    type = QuestionType.MCQ,
                    start = 1,
                    end = questions.size
                )
            )
            val created = Assessment(
                title = title.trim().ifBlank { "$subject Assessment" },
                subject = subject,
                classId = classInfo?.id ?: "",
                className = classInfo?.displayName ?: "",
                gradeLevel = classInfo?.grade ?: 5,
                academicYear = uiState.value.settings.currentAcademicYear,
                rubricType = uiState.value.settings.defaultRubric,
                semester = semester,
                category = category,
                questions = questions,
                sections = sections
            )
            repo.upsertAssessment(created)
            activeAssessmentIdFlow.value = created.id
            onCreated(created)
        }
    }

    fun saveAssessmentWithRecalculation(updated: Assessment) {
        viewModelScope.launch {
            val old = uiState.value.assessments.firstOrNull { it.id == updated.id }
            val newFp = updated.computeAnswerKeyFingerprint()
            val keyChanged = old != null && old.answerKeyFingerprint.isNotEmpty() && old.answerKeyFingerprint != newFp
            val stamped = updated.copy(
                answerKeyFingerprint = newFp,
                answerKeyRevision = if (keyChanged) old.answerKeyRevision + 1 else updated.answerKeyRevision,
                updatedAtMillis = System.currentTimeMillis()
            )
            repo.upsertAssessment(stamped)

            if (keyChanged) {
                val existingResults = uiState.value.resultsForAssessment(stamped.id)
                if (existingResults.isNotEmpty()) {
                    val rescored = ScoringService.recalculateForUpdatedKey(
                        assessment = stamped,
                        existingResults = existingResults,
                        customScales = uiState.value.settings.customScales
                    )
                    repo.upsertScanResults(rescored)
                    existingResults.zip(rescored).forEach { (prev, next) ->
                        if (prev.totalScore != next.totalScore) {
                            repo.insertAuditEntry(
                                AuditEntry(
                                    scanResultId = next.id,
                                    assessmentId = stamped.id,
                                    action = AuditAction.KEY_RECALCULATED,
                                    previousScore = prev.totalScore,
                                    newScore = next.totalScore,
                                    previousGrade = prev.grade,
                                    newGrade = next.grade,
                                    reason = "Answer key updated (rev ${stamped.answerKeyRevision})"
                                )
                            )
                        }
                    }
                    statusBannerFlow.value = "Recalculated ${rescored.size} student papers for updated key"
                }
            }
        }
    }

    fun setAssessmentCompleted(assessment: Assessment, completed: Boolean) {
        viewModelScope.launch {
            repo.upsertAssessment(assessment.copy(isCompleted = completed, updatedAtMillis = System.currentTimeMillis()))
        }
    }

    fun deleteAssessment(id: String) {
        viewModelScope.launch { repo.deleteAssessment(id) }
    }

    // ── Quick Grade ──────────────────────────────────────────────────────

    fun createQuickGradeAssessment(answers: List<String>, onReady: (Assessment) -> Unit) {
        viewModelScope.launch {
            repo.settings.saveQuickTemplate(answers)
            val questions = answers.mapIndexed { idx, ans ->
                val upper = ans.trim().uppercase()
                val type = if (upper == "TRUE" || upper == "FALSE" || upper == "T" || upper == "F") {
                    QuestionType.TRUE_FALSE
                } else QuestionType.MCQ
                Question(
                    number = idx + 1,
                    text = "Q${idx + 1}",
                    type = type,
                    correctAnswer = if (type == QuestionType.TRUE_FALSE) {
                        if (upper.startsWith("T")) "True" else "False"
                    } else upper.take(1),
                    points = 1.0
                )
            }
            val assessment = Assessment(
                title = "Quick Grade (${questions.size}Q)",
                subject = uiState.value.settings.subjects.firstOrNull() ?: "General",
                academicYear = uiState.value.settings.currentAcademicYear,
                rubricType = uiState.value.settings.defaultRubric,
                questions = questions,
                isAnswerKeyConfirmed = true
            ).let { it.copy(answerKeyFingerprint = it.computeAnswerKeyFingerprint()) }
            repo.upsertAssessment(assessment)
            activeAssessmentIdFlow.value = assessment.id
            onReady(assessment)
        }
    }

    // ── Scanning & Grading ───────────────────────────────────────────────

    fun gradeBitmap(
        bmp: Bitmap,
        assessment: Assessment,
        preferredStudent: Student? = null,
        onComplete: (ScanResult, String?) -> Unit = { _, _ -> }
    ) {
        viewModelScope.launch {
            isScanningFlow.value = true
            val classStudents = if (assessment.classId.isNotBlank()) {
                uiState.value.studentsInClass(assessment.classId)
            } else uiState.value.students
            val tpl = repo.loadOmrCalibration(assessment.id)
            val out = OmrAndOcrService.gradePaperBitmap(
                context = app,
                bmp = bmp,
                assessment = assessment,
                classStudents = classStudents,
                preferredStudent = preferredStudent,
                template = tpl,
                customScales = uiState.value.settings.customScales
            )

            // Check image dHash duplicate
            val existing = uiState.value.resultsForAssessment(assessment.id)
            val dupMsg = existing.firstOrNull {
                it.imageHash != null && it.imageHash == out.scanResult.imageHash
            }?.let { "Possible duplicate scan of ${it.studentName}'s sheet" }

            repo.upsertScanResult(out.scanResult)
            repo.upsertProofVault(out.proofVaultEntry)
            repo.insertAuditEntry(
                AuditEntry(
                    scanResultId = out.scanResult.id,
                    assessmentId = assessment.id,
                    action = AuditAction.CREATED,
                    previousScore = 0.0,
                    newScore = out.scanResult.totalScore,
                    previousGrade = "—",
                    newGrade = out.scanResult.grade,
                    reason = "Scanned (${out.scanResult.detectedMethod})"
                )
            )
            voiceManager.speakResult(out.scanResult, uiState.value.settings.voiceFeedbackMode)
            isScanningFlow.value = false
            onComplete(out.scanResult, dupMsg)
        }
    }

    fun gradePhotoUri(
        uri: Uri,
        assessment: Assessment,
        preferredStudent: Student? = null,
        onComplete: (ScanResult?, String?) -> Unit = { _, _ -> }
    ) {
        viewModelScope.launch {
            isScanningFlow.value = true
            val bmp = OmrAndOcrService.loadOrientedBitmapAsync(app, uri)
            if (bmp == null) {
                isScanningFlow.value = false
                onComplete(null, "Could not decode selected image")
                return@launch
            }
            gradeBitmap(bmp, assessment, preferredStudent) { res, dup -> onComplete(res, dup) }
        }
    }

    fun gradeCapturedFile(
        filePath: String,
        deleteSourceAfterDecode: Boolean = true,
        assessment: Assessment,
        preferredStudent: Student? = null,
        onComplete: (ScanResult?, String?) -> Unit = { _, _ -> }
    ) {
        viewModelScope.launch {
            isScanningFlow.value = true
            val bmp = try {
                OmrAndOcrService.loadOrientedBitmapFromFileAsync(filePath)
            } finally {
                if (deleteSourceAfterDecode) {
                    withContext(Dispatchers.IO) { runCatching { File(filePath).delete() } }
                }
            }
            if (bmp == null) {
                isScanningFlow.value = false
                onComplete(null, "Could not decode captured photo")
                return@launch
            }
            gradeBitmap(bmp, assessment, preferredStudent) { res, dup -> onComplete(res, dup) }
        }
    }

    suspend fun loadOmrCalibration(assessmentId: String): BubbleTemplate? =
        repo.loadOmrCalibration(assessmentId)

    fun saveOmrCalibration(assessmentId: String, template: BubbleTemplate) {
        viewModelScope.launch {
            repo.saveOmrCalibration(assessmentId, template)
            statusBannerFlow.value = "OMR calibration saved (${template.name})"
        }
    }

    // ── Manual Entry / Quick Enter / CA Fast Entry ───────────────────────

    fun saveManualQuestionEntry(
        assessment: Assessment,
        student: Student,
        answersMap: Map<Int, String>
    ) {
        viewModelScope.launch {
            val existing = uiState.value.resultsForAssessment(assessment.id)
                .firstOrNull { it.studentId == student.id }
            val matches = assessment.questions.map { q ->
                val raw = answersMap[q.number]?.trim().orEmpty()
                if (raw.isBlank()) {
                    AnswerMatch(q.number, "[MISSING]", q.correctAnswer, false, 0.0, q.points, 1.0)
                } else {
                    val (ok, pts) = ScoringService.checkAnswer(raw, q)
                    AnswerMatch(q.number, raw, q.correctAnswer, ok, pts, q.points, 1.0)
                }
            }
            val total = matches.sumOf { it.score }
            val pct = if (assessment.maxScore > 0) (total / assessment.maxScore * 100.0).coerceIn(0.0, 100.0) else 0.0
            val result = (existing ?: ScanResult(
                assessmentId = assessment.id,
                studentId = student.id,
                studentName = student.fullName
            )).copy(
                answers = matches,
                totalScore = total,
                maxScore = assessment.maxScore,
                percentage = pct,
                grade = ScoringService.calculateGrade(pct, assessment.rubricType, uiState.value.settings.customScales),
                status = ScanStatus.MANUAL_ENTRY,
                confidence = 1.0,
                detectedMethod = "manual",
                scoredWithKeyFingerprint = assessment.answerKeyFingerprint,
                scannedAtMillis = System.currentTimeMillis()
            )
            repo.upsertScanResult(result)
            val count = uiState.value.resultsForAssessment(assessment.id).size
            repo.saveDraft(GradingDraft(assessment.id, assessment.classId, count, 0, mode = "quick_enter"))
        }
    }

    fun saveFastCaScore(assessment: Assessment, student: Student, score: Double) {
        viewModelScope.launch {
            val max = assessment.maxScore
            val clamped = score.coerceIn(0.0, max)
            val pct = if (max > 0) (clamped / max * 100.0).coerceIn(0.0, 100.0) else 0.0
            val existing = uiState.value.resultsForAssessment(assessment.id)
                .firstOrNull { it.studentId == student.id }
            val res = (existing ?: ScanResult(
                assessmentId = assessment.id,
                studentId = student.id,
                studentName = student.fullName
            )).copy(
                totalScore = clamped,
                maxScore = max,
                percentage = pct,
                grade = ScoringService.calculateGrade(pct, assessment.rubricType, uiState.value.settings.customScales),
                status = ScanStatus.REVIEWED,
                confidence = 1.0,
                detectedMethod = "fast_ca",
                scannedAtMillis = System.currentTimeMillis()
            )
            repo.upsertScanResult(res)
        }
    }

    fun clearDraft(assessmentId: String) {
        viewModelScope.launch { repo.deleteDraft(assessmentId) }
    }

    // ── Review & Audit Actions ───────────────────────────────────────────

    fun toggleAnswerOverride(result: ScanResult, questionNumber: Int, customScore: Double? = null, customAnswer: String? = null) {
        viewModelScope.launch {
            val updatedAnswers = result.answers.map { m ->
                if (m.questionNumber != questionNumber) m
                else {
                    val nextCorrect = if (customScore != null) customScore >= m.maxScore * 0.5 else !m.isCorrect
                    val nextScore = customScore ?: if (nextCorrect) m.maxScore else 0.0
                    m.copy(
                        detectedAnswer = customAnswer ?: m.detectedAnswer,
                        isCorrect = nextCorrect,
                        score = nextScore,
                        isOverridden = true
                    )
                }
            }
            val newTotal = updatedAnswers.sumOf { it.score }
            val newPct = if (result.maxScore > 0) (newTotal / result.maxScore * 100.0).coerceIn(0.0, 100.0) else 0.0
            val assessment = uiState.value.assessments.firstOrNull { it.id == result.assessmentId }
            val rubric = assessment?.rubricType ?: uiState.value.settings.defaultRubric
            val newGrade = ScoringService.calculateGrade(newPct, rubric, uiState.value.settings.customScales)
            val updated = result.copy(
                answers = updatedAnswers,
                totalScore = newTotal,
                percentage = newPct,
                grade = newGrade,
                uncertainQuestions = result.uncertainQuestions.filterNot { it == questionNumber },
                status = ScanStatus.REVIEWED
            )
            repo.upsertScanResult(updated)
            repo.insertAuditEntry(
                AuditEntry(
                    scanResultId = result.id,
                    assessmentId = result.assessmentId,
                    action = AuditAction.ANSWER_CORRECTED,
                    previousScore = result.totalScore,
                    newScore = newTotal,
                    previousGrade = result.grade,
                    newGrade = newGrade,
                    reason = "Q$questionNumber adjusted by teacher"
                )
            )
        }
    }

    fun overrideTotalScore(result: ScanResult, newScore: Double, reason: String) {
        viewModelScope.launch {
            val clamped = newScore.coerceIn(0.0, result.maxScore)
            val newPct = if (result.maxScore > 0) (clamped / result.maxScore * 100.0).coerceIn(0.0, 100.0) else 0.0
            val assessment = uiState.value.assessments.firstOrNull { it.id == result.assessmentId }
            val rubric = assessment?.rubricType ?: uiState.value.settings.defaultRubric
            val newGrade = ScoringService.calculateGrade(newPct, rubric, uiState.value.settings.customScales)
            val updated = result.copy(
                totalScore = clamped,
                percentage = newPct,
                grade = newGrade,
                status = ScanStatus.REVIEWED
            )
            repo.upsertScanResult(updated)
            repo.insertAuditEntry(
                AuditEntry(
                    scanResultId = result.id,
                    assessmentId = result.assessmentId,
                    action = AuditAction.SCORE_OVERRIDE,
                    previousScore = result.totalScore,
                    newScore = clamped,
                    previousGrade = result.grade,
                    newGrade = newGrade,
                    reason = reason.ifBlank { "Manual score override" }
                )
            )
        }
    }

    fun markResultReviewed(result: ScanResult) {
        viewModelScope.launch {
            repo.upsertScanResult(result.copy(status = ScanStatus.REVIEWED, uncertainQuestions = emptyList()))
            repo.insertAuditEntry(
                AuditEntry(
                    scanResultId = result.id,
                    assessmentId = result.assessmentId,
                    action = AuditAction.MARKED_REVIEWED,
                    previousScore = result.totalScore,
                    newScore = result.totalScore,
                    previousGrade = result.grade,
                    newGrade = result.grade,
                    reason = "Confirmed by teacher"
                )
            )
        }
    }

    fun reassignStudent(result: ScanResult, student: Student) {
        viewModelScope.launch {
            repo.upsertScanResult(result.copy(studentId = student.id, studentName = student.fullName))
            repo.insertAuditEntry(
                AuditEntry(
                    scanResultId = result.id,
                    assessmentId = result.assessmentId,
                    action = AuditAction.STUDENT_REASSIGNED,
                    previousScore = result.totalScore,
                    newScore = result.totalScore,
                    previousGrade = result.grade,
                    newGrade = result.grade,
                    reason = "Assigned to ${student.fullName}"
                )
            )
        }
    }

    fun revertAuditEntry(result: ScanResult, entry: AuditEntry) {
        viewModelScope.launch {
            val pct = if (result.maxScore > 0) (entry.previousScore / result.maxScore * 100.0).coerceIn(0.0, 100.0) else 0.0
            repo.upsertScanResult(
                result.copy(
                    totalScore = entry.previousScore,
                    percentage = pct,
                    grade = entry.previousGrade
                )
            )
            repo.insertAuditEntry(
                AuditEntry(
                    scanResultId = result.id,
                    assessmentId = result.assessmentId,
                    action = AuditAction.REVERTED,
                    previousScore = result.totalScore,
                    newScore = entry.previousScore,
                    previousGrade = result.grade,
                    newGrade = entry.previousGrade,
                    reason = "Reverted change from ${entry.action.label}"
                )
            )
        }
    }

    fun deleteScanResult(id: String) {
        viewModelScope.launch { repo.deleteScanResult(id) }
    }

    // ── Homeroom & SMS ───────────────────────────────────────────────────

    fun updateHomeroomOverride(classId: String, studentId: String, conduct: String, hasFinanceHold: Boolean) {
        viewModelScope.launch {
            repo.upsertHomeroomOverride(
                HomeroomOverride(
                    id = "${classId}_${studentId}",
                    classId = classId,
                    studentId = studentId,
                    conduct = conduct,
                    hasFinanceHold = hasFinanceHold
                )
            )
        }
    }

    fun logSms(entry: SmsLogEntry) {
        viewModelScope.launch { repo.insertSmsLog(entry) }
    }

    // ── Settings, Scales, Subjects, Backup ───────────────────────────────

    fun updateProfile(teacherName: String, schoolName: String, phone: String, telegram: String = "", whatsapp: String = "") {
        viewModelScope.launch {
            val normalizedPhone = if (phone.isBlank()) "" else PhoneUtils.normalize(phone)
            repo.settings.updateProfile(teacherName, schoolName, normalizedPhone, telegram, whatsapp)
            val currentTeacher = uiState.value.teachers.firstOrNull { it.isActive }
            if (currentTeacher != null) {
                repo.upsertTeacher(currentTeacher.copy(name = teacherName, schoolName = schoolName, phone = normalizedPhone))
            }
        }
    }

    fun addOrSwitchTeacher(teacher: Teacher) {
        viewModelScope.launch {
            uiState.value.teachers.forEach { t ->
                if (t.isActive && t.id != teacher.id) repo.upsertTeacher(t.copy(isActive = false))
            }
            repo.upsertTeacher(teacher.copy(isActive = true))
            repo.settings.updateProfile(teacher.name, teacher.schoolName, teacher.phone)
        }
    }

    fun setDefaultRubric(key: String) = viewModelScope.launch { repo.settings.setDefaultRubric(key) }
    fun toggleDarkMode() = viewModelScope.launch { repo.settings.toggleDarkMode() }
    fun toggleAutoEnhance() = viewModelScope.launch { repo.settings.toggleAutoEnhance() }
    fun setVoiceFeedbackMode(mode: VoiceFeedbackMode) = viewModelScope.launch { repo.settings.setVoiceFeedbackMode(mode) }
    fun setAcademicYear(year: String) = viewModelScope.launch { repo.settings.setAcademicYear(year) }
    fun saveSubjects(subjects: List<String>) = viewModelScope.launch { repo.settings.saveSubjects(subjects) }
    fun saveCustomScale(scale: GradingScale) = viewModelScope.launch { repo.settings.saveCustomScale(scale) }
    fun deleteCustomScale(id: String) = viewModelScope.launch { repo.settings.deleteCustomScale(id) }

    suspend fun exportEncryptedBackupBytes(passphrase: String = ""): ByteArray {
        val s = uiState.value
        val key = repo.settings.getOrCreateAesKey()
        return withContext(Dispatchers.Default) {
            if (passphrase.isNotBlank()) {
                BackupService.createPassphraseBackup(
                    passphrase = passphrase,
                    students = s.students,
                    classes = s.classes,
                    assessments = s.assessments,
                    scanResults = s.scanResults
                )
            } else {
                BackupService.createEncryptedBackup(key, s.students, s.classes, s.assessments, s.scanResults)
            }
        }
    }

    fun importBackupBytes(
        bytes: ByteArray,
        passphrase: String? = null,
        replace: Boolean = false,
        onResult: (String) -> Unit
    ) {
        viewModelScope.launch {
            val key = repo.settings.getOrCreateAesKey()
            val decoded = withContext(Dispatchers.Default) {
                BackupService.decryptBackup(bytes = bytes, passphrase = passphrase, fallbackDeviceAesKey = key)
            }
            decoded.fold(
                onSuccess = { payload ->
                    if (replace) repo.clearAllDatabaseTables()
                    repo.seedAll(payload.classes, payload.students, payload.assessments, payload.scanResults)
                    val msg = "Imported ${payload.students.size} students, ${payload.assessments.size} assessments"
                    statusBannerFlow.value = msg
                    onResult(msg)
                },
                onFailure = { err ->
                    onResult("Backup restore failed: ${err.message ?: "Invalid or corrupt file"}")
                }
            )
        }
    }

    fun clearAllData() {
        viewModelScope.launch {
            repo.clearAllDatabaseTables()
            repo.settings.clearAll()
        }
    }

    override fun onCleared() {
        super.onCleared()
        voiceManager.shutdown()
    }
}
