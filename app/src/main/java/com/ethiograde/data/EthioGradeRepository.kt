package com.ethiograde.data

import com.ethiograde.model.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.encodeToString

class EthioGradeRepository(
    private val db: AppDatabase,
    val settings: SettingsRepository
) {
    val assessments: Flow<List<Assessment>> = db.assessmentDao().observeAll().map { it.map(AssessmentEntity::toDomain) }
    val classes: Flow<List<ClassInfo>> = db.classDao().observeAll().map { it.map(ClassInfoEntity::toDomain) }
    val students: Flow<List<Student>> = db.studentDao().observeAll().map { it.map(StudentEntity::toDomain) }
    val scanResults: Flow<List<ScanResult>> = db.scanResultDao().observeAll().map { it.map(ScanResultEntity::toDomain) }
    val teachers: Flow<List<Teacher>> = db.teacherDao().observeAll().map { it.map(TeacherEntity::toDomain) }
    val attendanceRecords: Flow<List<AttendanceRecord>> = db.attendanceDao().observeAll().map { it.map(AttendanceRecordEntity::toDomain) }
    val classNotes: Flow<List<ClassNote>> = db.classNoteDao().observeAll().map { it.map(ClassNoteEntity::toDomain) }
    val auditEntries: Flow<List<AuditEntry>> = db.auditDao().observeAll().map { it.map(AuditEntryEntity::toDomain) }
    val proofVaultEntries: Flow<List<ProofVaultEntry>> = db.proofVaultDao().observeAll().map { it.map(ProofVaultEntity::toDomain) }
    val drafts: Flow<List<GradingDraft>> = db.draftDao().observeAll().map { it.map(GradingDraftEntity::toDomain) }
    val smsLogs: Flow<List<SmsLogEntry>> = db.smsLogDao().observeAll().map { it.map(SmsLogEntity::toDomain) }
    val homeroomOverrides: Flow<List<HomeroomOverride>> = db.homeroomOverrideDao().observeAll().map { it.map(HomeroomOverrideEntity::toDomain) }

    suspend fun upsertAssessment(assessment: Assessment) = db.assessmentDao().upsert(assessment.toEntity())
    suspend fun deleteAssessment(id: String) {
        db.scanResultDao().getByAssessment(id).forEach { deleteScanFiles(it.imagePath, it.enhancedImagePath) }
        db.assessmentDao().deleteById(id)
        db.scanResultDao().deleteByAssessment(id)
        db.proofVaultDao().deleteByAssessment(id)
        db.draftDao().deleteByAssessment(id)
    }

    suspend fun upsertClass(classInfo: ClassInfo) = db.classDao().upsert(classInfo.toEntity())
    suspend fun deleteClass(id: String) = db.classDao().deleteById(id)

    suspend fun upsertStudent(student: Student) = db.studentDao().upsert(student.toEntity())
    suspend fun upsertStudents(list: List<Student>) = db.studentDao().upsertAll(list.map(Student::toEntity))
    suspend fun deleteStudent(id: String) {
        db.scanResultDao().getByStudent(id).forEach { deleteScanFiles(it.imagePath, it.enhancedImagePath) }
        db.studentDao().deleteById(id)
        db.scanResultDao().deleteByStudent(id)
        db.proofVaultDao().deleteByStudent(id)
        db.homeroomOverrideDao().deleteByStudent(id)
    }

    suspend fun upsertScanResult(result: ScanResult) = db.scanResultDao().upsert(result.toEntity())
    suspend fun upsertScanResults(list: List<ScanResult>) = db.scanResultDao().upsertAll(list.map(ScanResult::toEntity))
    suspend fun deleteScanResult(id: String) {
        db.scanResultDao().getById(id)?.let { deleteScanFiles(it.imagePath, it.enhancedImagePath) }
        db.scanResultDao().deleteById(id)
    }

    private fun deleteScanFiles(imagePath: String, enhancedPath: String) {
        listOf(imagePath, enhancedPath).filter { it.isNotBlank() }.distinct().forEach { path ->
            runCatching { java.io.File(path).delete() }
        }
    }

    suspend fun upsertTeacher(teacher: Teacher) = db.teacherDao().upsert(teacher.toEntity())
    suspend fun deleteTeacher(id: String) = db.teacherDao().deleteById(id)

    suspend fun upsertAttendance(record: AttendanceRecord) = db.attendanceDao().upsert(record.toEntity())
    suspend fun upsertClassNote(note: ClassNote) = db.classNoteDao().upsert(note.toEntity())
    suspend fun deleteClassNote(id: String) = db.classNoteDao().deleteById(id)

    suspend fun insertAuditEntry(entry: AuditEntry) = db.auditDao().upsert(entry.toEntity())
    suspend fun upsertProofVault(entry: ProofVaultEntry) = db.proofVaultDao().upsert(entry.toEntity())

    suspend fun saveDraft(draft: GradingDraft) = db.draftDao().upsert(draft.toEntity())
    suspend fun deleteDraft(assessmentId: String) = db.draftDao().deleteByAssessment(assessmentId)

    suspend fun insertSmsLog(entry: SmsLogEntry) = db.smsLogDao().upsert(entry.toEntity())
    suspend fun upsertHomeroomOverride(override: HomeroomOverride) = db.homeroomOverrideDao().upsert(override.toEntity())

    suspend fun saveOmrCalibration(assessmentId: String, template: BubbleTemplate) {
        db.omrCalibrationDao().upsert(
            OmrCalibrationEntity(assessmentId, roomJson.encodeToString(template), System.currentTimeMillis())
        )
    }

    suspend fun loadOmrCalibration(assessmentId: String): BubbleTemplate? {
        val raw = db.omrCalibrationDao().getByAssessment(assessmentId) ?: return null
        return runCatching { roomJson.decodeFromString<BubbleTemplate>(raw.templateJson) }.getOrNull()
    }

    suspend fun seedAll(
        classes: List<ClassInfo>,
        students: List<Student>,
        assessments: List<Assessment>,
        scanResults: List<ScanResult>
    ) {
        db.classDao().upsertAll(classes.map(ClassInfo::toEntity))
        db.studentDao().upsertAll(students.map(Student::toEntity))
        db.assessmentDao().upsertAll(assessments.map(Assessment::toEntity))
        db.scanResultDao().upsertAll(scanResults.map(ScanResult::toEntity))
    }

    suspend fun clearAllDatabaseTables() {
        db.scanResultDao().getAllImagePaths().forEach { deleteScanFiles(it.imagePath, it.enhancedImagePath) }
        db.assessmentDao().clearAll()
        db.classDao().clearAll()
        db.studentDao().clearAll()
        db.scanResultDao().clearAll()
        db.teacherDao().clearAll()
        db.attendanceDao().clearAll()
        db.classNoteDao().clearAll()
        db.auditDao().clearAll()
        db.proofVaultDao().clearAll()
        db.draftDao().clearAll()
        db.smsLogDao().clearAll()
        db.homeroomOverrideDao().clearAll()
        db.omrCalibrationDao().clearAll()
    }
}
