package com.ethiograde.data

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface AssessmentDao {
    @Query("SELECT * FROM assessments ORDER BY updatedAtMillis DESC")
    fun observeAll(): Flow<List<AssessmentEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: AssessmentEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(entities: List<AssessmentEntity>)

    @Query("DELETE FROM assessments WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM assessments")
    suspend fun clearAll()
}

@Dao
interface ClassDao {
    @Query("SELECT * FROM classes ORDER BY name ASC")
    fun observeAll(): Flow<List<ClassInfoEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: ClassInfoEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(entities: List<ClassInfoEntity>)

    @Query("DELETE FROM classes WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM classes")
    suspend fun clearAll()
}

@Dao
interface StudentDao {
    @Query("SELECT * FROM students ORDER BY firstName ASC, lastName ASC")
    fun observeAll(): Flow<List<StudentEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: StudentEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(entities: List<StudentEntity>)

    @Query("DELETE FROM students WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM students")
    suspend fun clearAll()
}

data class ScanImagePaths(
    val imagePath: String,
    val enhancedImagePath: String
)

@Dao
interface ScanResultDao {
    @Query("SELECT * FROM scan_results ORDER BY scannedAtMillis DESC")
    fun observeAll(): Flow<List<ScanResultEntity>>

    @Query("SELECT * FROM scan_results WHERE assessmentId = :assessmentId ORDER BY totalScore DESC")
    fun observeByAssessment(assessmentId: String): Flow<List<ScanResultEntity>>

    @Query("SELECT * FROM scan_results WHERE id = :id")
    suspend fun getById(id: String): ScanResultEntity?

    @Query("SELECT * FROM scan_results WHERE assessmentId = :assessmentId")
    suspend fun getByAssessment(assessmentId: String): List<ScanResultEntity>

    @Query("SELECT * FROM scan_results WHERE studentId = :studentId")
    suspend fun getByStudent(studentId: String): List<ScanResultEntity>

    @Query("SELECT imagePath, enhancedImagePath FROM scan_results")
    suspend fun getAllImagePaths(): List<ScanImagePaths>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: ScanResultEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(entities: List<ScanResultEntity>)

    @Query("DELETE FROM scan_results WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM scan_results WHERE assessmentId = :assessmentId")
    suspend fun deleteByAssessment(assessmentId: String)

    @Query("DELETE FROM scan_results WHERE studentId = :studentId")
    suspend fun deleteByStudent(studentId: String)

    @Query("DELETE FROM scan_results")
    suspend fun clearAll()
}

@Dao
interface TeacherDao {
    @Query("SELECT * FROM teachers ORDER BY createdAtMillis ASC")
    fun observeAll(): Flow<List<TeacherEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: TeacherEntity)

    @Query("DELETE FROM teachers WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM teachers")
    suspend fun clearAll()
}

@Dao
interface AttendanceDao {
    @Query("SELECT * FROM attendance_records ORDER BY dateIso DESC")
    fun observeAll(): Flow<List<AttendanceRecordEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: AttendanceRecordEntity)

    @Query("DELETE FROM attendance_records")
    suspend fun clearAll()
}

@Dao
interface ClassNoteDao {
    @Query("SELECT * FROM class_notes ORDER BY createdAtMillis DESC")
    fun observeAll(): Flow<List<ClassNoteEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: ClassNoteEntity)

    @Query("DELETE FROM class_notes WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM class_notes")
    suspend fun clearAll()
}

@Dao
interface AuditDao {
    @Query("SELECT * FROM audit_entries ORDER BY timestampMillis DESC")
    fun observeAll(): Flow<List<AuditEntryEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: AuditEntryEntity)

    @Query("DELETE FROM audit_entries")
    suspend fun clearAll()
}

@Dao
interface ProofVaultDao {
    @Query("SELECT * FROM proof_vault_entries ORDER BY scannedAtMillis DESC")
    fun observeAll(): Flow<List<ProofVaultEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: ProofVaultEntity)

    @Query("DELETE FROM proof_vault_entries WHERE assessmentId = :assessmentId")
    suspend fun deleteByAssessment(assessmentId: String)

    @Query("DELETE FROM proof_vault_entries WHERE studentId = :studentId")
    suspend fun deleteByStudent(studentId: String)

    @Query("DELETE FROM proof_vault_entries")
    suspend fun clearAll()
}

@Dao
interface DraftDao {
    @Query("SELECT * FROM grading_drafts ORDER BY savedAtMillis DESC")
    fun observeAll(): Flow<List<GradingDraftEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: GradingDraftEntity)

    @Query("DELETE FROM grading_drafts WHERE assessmentId = :assessmentId")
    suspend fun deleteByAssessment(assessmentId: String)

    @Query("DELETE FROM grading_drafts")
    suspend fun clearAll()
}

@Dao
interface SmsLogDao {
    @Query("SELECT * FROM sms_logs ORDER BY sentAtMillis DESC")
    fun observeAll(): Flow<List<SmsLogEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: SmsLogEntity)

    @Query("DELETE FROM sms_logs")
    suspend fun clearAll()
}

@Dao
interface HomeroomOverrideDao {
    @Query("SELECT * FROM homeroom_overrides")
    fun observeAll(): Flow<List<HomeroomOverrideEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: HomeroomOverrideEntity)

    @Query("DELETE FROM homeroom_overrides WHERE studentId = :studentId")
    suspend fun deleteByStudent(studentId: String)

    @Query("DELETE FROM homeroom_overrides")
    suspend fun clearAll()
}

@Dao
interface OmrCalibrationDao {
    @Query("SELECT * FROM omr_calibrations WHERE assessmentId = :assessmentId")
    suspend fun getByAssessment(assessmentId: String): OmrCalibrationEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: OmrCalibrationEntity)

    @Query("DELETE FROM omr_calibrations")
    suspend fun clearAll()
}
