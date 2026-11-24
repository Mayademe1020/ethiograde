package com.ethiograde.data

import androidx.room.Entity
import androidx.room.PrimaryKey
import com.ethiograde.model.*
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

internal val roomJson = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
}

@Entity(tableName = "assessments")
data class AssessmentEntity(
    @PrimaryKey val id: String,
    val title: String,
    val subject: String,
    val classId: String,
    val className: String,
    val gradeLevel: Int,
    val academicYear: String,
    val rubricType: String,
    val semester: String,
    val category: String,
    val weightPercent: Double,
    val questionsJson: String,
    val sectionsJson: String,
    val isCompleted: Boolean,
    val isAnswerKeyConfirmed: Boolean,
    val answerKeyFingerprint: String,
    val answerKeyRevision: Int,
    val createdAtMillis: Long,
    val updatedAtMillis: Long
)

fun Assessment.toEntity(): AssessmentEntity = AssessmentEntity(
    id = id,
    title = title,
    subject = subject,
    classId = classId,
    className = className,
    gradeLevel = gradeLevel,
    academicYear = academicYear,
    rubricType = rubricType,
    semester = semester,
    category = category,
    weightPercent = weightPercent,
    questionsJson = roomJson.encodeToString(questions),
    sectionsJson = roomJson.encodeToString(sections),
    isCompleted = isCompleted,
    isAnswerKeyConfirmed = isAnswerKeyConfirmed,
    answerKeyFingerprint = answerKeyFingerprint,
    answerKeyRevision = answerKeyRevision,
    createdAtMillis = createdAtMillis,
    updatedAtMillis = updatedAtMillis
)

fun AssessmentEntity.toDomain(): Assessment = Assessment(
    id = id,
    title = title,
    subject = subject,
    classId = classId,
    className = className,
    gradeLevel = gradeLevel,
    academicYear = academicYear,
    rubricType = rubricType,
    semester = semester,
    category = category,
    weightPercent = weightPercent,
    questions = runCatching { roomJson.decodeFromString<List<Question>>(questionsJson) }.getOrDefault(emptyList()),
    sections = runCatching { roomJson.decodeFromString<List<AnswerKeySection>>(sectionsJson) }.getOrDefault(emptyList()),
    isCompleted = isCompleted,
    isAnswerKeyConfirmed = isAnswerKeyConfirmed,
    answerKeyFingerprint = answerKeyFingerprint,
    answerKeyRevision = answerKeyRevision,
    createdAtMillis = createdAtMillis,
    updatedAtMillis = updatedAtMillis
)

@Entity(tableName = "classes")
data class ClassInfoEntity(
    @PrimaryKey val id: String,
    val name: String,
    val grade: Int,
    val section: String,
    val subject: String,
    val academicYear: String,
    val studentCount: Int,
    val isHomeroom: Boolean,
    val createdAtMillis: Long
)

fun ClassInfo.toEntity(): ClassInfoEntity = ClassInfoEntity(
    id = id,
    name = name,
    grade = grade,
    section = section,
    subject = subject,
    academicYear = academicYear,
    studentCount = studentCount,
    isHomeroom = isHomeroom,
    createdAtMillis = createdAtMillis
)

fun ClassInfoEntity.toDomain(): ClassInfo = ClassInfo(
    id = id,
    name = name,
    grade = grade,
    section = section,
    subject = subject,
    academicYear = academicYear,
    studentCount = studentCount,
    isHomeroom = isHomeroom,
    createdAtMillis = createdAtMillis
)

@Entity(tableName = "students")
data class StudentEntity(
    @PrimaryKey val id: String,
    val studentId: String,
    val firstName: String,
    val lastName: String,
    val gender: String,
    val classIdsJson: String,
    val className: String,
    val section: String,
    val grade: Int,
    val parentPhone: String?,
    val createdAtMillis: Long
)

fun Student.toEntity(): StudentEntity = StudentEntity(
    id = id,
    studentId = studentId,
    firstName = firstName,
    lastName = lastName,
    gender = gender,
    classIdsJson = roomJson.encodeToString(classIds),
    className = className,
    section = section,
    grade = grade,
    parentPhone = parentPhone,
    createdAtMillis = createdAtMillis
)

fun StudentEntity.toDomain(): Student = Student(
    id = id,
    studentId = studentId,
    firstName = firstName,
    lastName = lastName,
    gender = gender,
    classIds = runCatching { roomJson.decodeFromString<List<String>>(classIdsJson) }.getOrDefault(emptyList()),
    className = className,
    section = section,
    grade = grade,
    parentPhone = parentPhone,
    createdAtMillis = createdAtMillis
)

@Entity(tableName = "scan_results")
data class ScanResultEntity(
    @PrimaryKey val id: String,
    val assessmentId: String,
    val studentId: String,
    val studentName: String,
    val imagePath: String,
    val enhancedImagePath: String,
    val answersJson: String,
    val totalScore: Double,
    val maxScore: Double,
    val percentage: Double,
    val grade: String,
    val statusName: String,
    val confidence: Double,
    val imageHash: String?,
    val paperLabel: String,
    val teacherNotes: String,
    val scannedAtMillis: Long,
    val uncertainQuestionsJson: String,
    val detectedMethod: String,
    val scoredWithKeyFingerprint: String,
    val scoredWithKeyRevision: Int,
    val weightedScoring: Boolean
)

fun ScanResult.toEntity(): ScanResultEntity = ScanResultEntity(
    id = id,
    assessmentId = assessmentId,
    studentId = studentId,
    studentName = studentName,
    imagePath = imagePath,
    enhancedImagePath = enhancedImagePath,
    answersJson = roomJson.encodeToString(answers),
    totalScore = totalScore,
    maxScore = maxScore,
    percentage = percentage,
    grade = grade,
    statusName = status.name,
    confidence = confidence,
    imageHash = imageHash,
    paperLabel = paperLabel,
    teacherNotes = teacherNotes,
    scannedAtMillis = scannedAtMillis,
    uncertainQuestionsJson = roomJson.encodeToString(uncertainQuestions),
    detectedMethod = detectedMethod,
    scoredWithKeyFingerprint = scoredWithKeyFingerprint,
    scoredWithKeyRevision = scoredWithKeyRevision,
    weightedScoring = weightedScoring
)

fun ScanResultEntity.toDomain(): ScanResult = ScanResult(
    id = id,
    assessmentId = assessmentId,
    studentId = studentId,
    studentName = studentName,
    imagePath = imagePath,
    enhancedImagePath = enhancedImagePath,
    answers = runCatching { roomJson.decodeFromString<List<AnswerMatch>>(answersJson) }.getOrDefault(emptyList()),
    totalScore = totalScore,
    maxScore = maxScore,
    percentage = percentage,
    grade = grade,
    status = runCatching { ScanStatus.valueOf(statusName) }.getOrDefault(ScanStatus.GRADED),
    confidence = confidence,
    imageHash = imageHash,
    paperLabel = paperLabel,
    teacherNotes = teacherNotes,
    scannedAtMillis = scannedAtMillis,
    uncertainQuestions = runCatching { roomJson.decodeFromString<List<Int>>(uncertainQuestionsJson) }.getOrDefault(emptyList()),
    detectedMethod = detectedMethod,
    scoredWithKeyFingerprint = scoredWithKeyFingerprint,
    scoredWithKeyRevision = scoredWithKeyRevision,
    weightedScoring = weightedScoring
)

@Entity(tableName = "teachers")
data class TeacherEntity(
    @PrimaryKey val id: String,
    val name: String,
    val schoolName: String,
    val phone: String,
    val gradeLevelsJson: String,
    val subjectsJson: String,
    val isActive: Boolean,
    val createdAtMillis: Long
)

fun Teacher.toEntity(): TeacherEntity = TeacherEntity(
    id = id,
    name = name,
    schoolName = schoolName,
    phone = phone,
    gradeLevelsJson = roomJson.encodeToString(gradeLevels),
    subjectsJson = roomJson.encodeToString(subjects),
    isActive = isActive,
    createdAtMillis = createdAtMillis
)

fun TeacherEntity.toDomain(): Teacher = Teacher(
    id = id,
    name = name,
    schoolName = schoolName,
    phone = phone,
    gradeLevels = runCatching { roomJson.decodeFromString<List<Int>>(gradeLevelsJson) }.getOrDefault(emptyList()),
    subjects = runCatching { roomJson.decodeFromString<List<String>>(subjectsJson) }.getOrDefault(emptyList()),
    isActive = isActive,
    createdAtMillis = createdAtMillis
)

@Entity(tableName = "attendance_records")
data class AttendanceRecordEntity(
    @PrimaryKey val id: String,
    val classId: String,
    val dateIso: String,
    val entriesJson: String,
    val notes: String,
    val updatedAtMillis: Long
)

fun AttendanceRecord.toEntity(): AttendanceRecordEntity = AttendanceRecordEntity(
    id = id,
    classId = classId,
    dateIso = dateIso,
    entriesJson = roomJson.encodeToString(entries),
    notes = notes,
    updatedAtMillis = updatedAtMillis
)

fun AttendanceRecordEntity.toDomain(): AttendanceRecord = AttendanceRecord(
    id = id,
    classId = classId,
    dateIso = dateIso,
    entries = runCatching { roomJson.decodeFromString<Map<String, AttendanceStatus>>(entriesJson) }.getOrDefault(emptyMap()),
    notes = notes,
    updatedAtMillis = updatedAtMillis
)

@Entity(tableName = "class_notes")
data class ClassNoteEntity(
    @PrimaryKey val id: String,
    val classId: String,
    val dateIso: String,
    val title: String,
    val content: String,
    val category: String,
    val createdAtMillis: Long
)

fun ClassNote.toEntity(): ClassNoteEntity = ClassNoteEntity(
    id = id,
    classId = classId,
    dateIso = dateIso,
    title = title,
    content = content,
    category = category,
    createdAtMillis = createdAtMillis
)

fun ClassNoteEntity.toDomain(): ClassNote = ClassNote(
    id = id,
    classId = classId,
    dateIso = dateIso,
    title = title,
    content = content,
    category = category,
    createdAtMillis = createdAtMillis
)

@Entity(tableName = "audit_entries")
data class AuditEntryEntity(
    @PrimaryKey val id: String,
    val scanResultId: String,
    val assessmentId: String,
    val actionName: String,
    val previousScore: Double,
    val newScore: Double,
    val previousGrade: String,
    val newGrade: String,
    val reason: String,
    val changedBy: String,
    val timestampMillis: Long
)

fun AuditEntry.toEntity(): AuditEntryEntity = AuditEntryEntity(
    id = id,
    scanResultId = scanResultId,
    assessmentId = assessmentId,
    actionName = action.name,
    previousScore = previousScore,
    newScore = newScore,
    previousGrade = previousGrade,
    newGrade = newGrade,
    reason = reason,
    changedBy = changedBy,
    timestampMillis = timestampMillis
)

fun AuditEntryEntity.toDomain(): AuditEntry = AuditEntry(
    id = id,
    scanResultId = scanResultId,
    assessmentId = assessmentId,
    action = runCatching { AuditAction.valueOf(actionName) }.getOrDefault(AuditAction.SCORE_OVERRIDE),
    previousScore = previousScore,
    newScore = newScore,
    previousGrade = previousGrade,
    newGrade = newGrade,
    reason = reason,
    changedBy = changedBy,
    timestampMillis = timestampMillis
)

@Entity(tableName = "proof_vault_entries")
data class ProofVaultEntity(
    @PrimaryKey val id: String, // "${assessmentId}_${studentId}"
    val assessmentId: String,
    val studentId: String,
    val studentName: String,
    val totalScore: Double,
    val maxScore: Double,
    val bubbleDensitiesJson: String,
    val detectedAnswersJson: String,
    val integrityHash: String,
    val scannedAtMillis: Long
)

fun ProofVaultEntry.toEntity(): ProofVaultEntity = ProofVaultEntity(
    id = "${assessmentId}_${studentId}",
    assessmentId = assessmentId,
    studentId = studentId,
    studentName = studentName,
    totalScore = totalScore,
    maxScore = maxScore,
    bubbleDensitiesJson = roomJson.encodeToString(bubbleDensities),
    detectedAnswersJson = roomJson.encodeToString(detectedAnswers),
    integrityHash = integrityHash,
    scannedAtMillis = scannedAtMillis
)

fun ProofVaultEntity.toDomain(): ProofVaultEntry = ProofVaultEntry(
    id = id,
    assessmentId = assessmentId,
    studentId = studentId,
    studentName = studentName,
    totalScore = totalScore,
    maxScore = maxScore,
    bubbleDensities = runCatching { roomJson.decodeFromString<Map<Int, Map<String, Double>>>(bubbleDensitiesJson) }.getOrDefault(emptyMap()),
    detectedAnswers = runCatching { roomJson.decodeFromString<Map<Int, String>>(detectedAnswersJson) }.getOrDefault(emptyMap()),
    integrityHash = integrityHash,
    scannedAtMillis = scannedAtMillis
)

@Entity(tableName = "grading_drafts")
data class GradingDraftEntity(
    @PrimaryKey val assessmentId: String,
    val classId: String,
    val completedCount: Int,
    val currentStudentIndex: Int,
    val savedAtMillis: Long,
    val mode: String
)

fun GradingDraft.toEntity(): GradingDraftEntity = GradingDraftEntity(
    assessmentId = assessmentId,
    classId = classId,
    completedCount = completedCount,
    currentStudentIndex = currentStudentIndex,
    savedAtMillis = savedAtMillis,
    mode = mode
)

fun GradingDraftEntity.toDomain(): GradingDraft = GradingDraft(
    assessmentId = assessmentId,
    classId = classId,
    completedCount = completedCount,
    currentStudentIndex = currentStudentIndex,
    savedAtMillis = savedAtMillis,
    mode = mode
)

@Entity(tableName = "sms_logs")
data class SmsLogEntity(
    @PrimaryKey val id: String,
    val studentName: String,
    val phoneNumber: String,
    val message: String,
    val templateName: String,
    val success: Boolean,
    val errorMessage: String?,
    val sentAtMillis: Long
)

fun SmsLogEntry.toEntity(): SmsLogEntity = SmsLogEntity(
    id = id,
    studentName = studentName,
    phoneNumber = phoneNumber,
    message = message,
    templateName = templateName,
    success = success,
    errorMessage = errorMessage,
    sentAtMillis = sentAtMillis
)

fun SmsLogEntity.toDomain(): SmsLogEntry = SmsLogEntry(
    id = id,
    studentName = studentName,
    phoneNumber = phoneNumber,
    message = message,
    templateName = templateName,
    success = success,
    errorMessage = errorMessage,
    sentAtMillis = sentAtMillis
)

@Entity(tableName = "homeroom_overrides")
data class HomeroomOverrideEntity(
    @PrimaryKey val id: String,
    val classId: String,
    val studentId: String,
    val conduct: String,
    val hasFinanceHold: Boolean
)

fun HomeroomOverride.toEntity(): HomeroomOverrideEntity = HomeroomOverrideEntity(
    id = id,
    classId = classId,
    studentId = studentId,
    conduct = conduct,
    hasFinanceHold = hasFinanceHold
)

fun HomeroomOverrideEntity.toDomain(): HomeroomOverride = HomeroomOverride(
    id = id,
    classId = classId,
    studentId = studentId,
    conduct = conduct,
    hasFinanceHold = hasFinanceHold
)

@Entity(tableName = "omr_calibrations")
data class OmrCalibrationEntity(
    @PrimaryKey val assessmentId: String,
    val templateJson: String,
    val updatedAtMillis: Long
)
