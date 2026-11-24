package com.ethiograde.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(
    entities = [
        AssessmentEntity::class,
        ClassInfoEntity::class,
        StudentEntity::class,
        ScanResultEntity::class,
        TeacherEntity::class,
        AttendanceRecordEntity::class,
        ClassNoteEntity::class,
        AuditEntryEntity::class,
        ProofVaultEntity::class,
        GradingDraftEntity::class,
        SmsLogEntity::class,
        HomeroomOverrideEntity::class,
        OmrCalibrationEntity::class
    ],
    version = 1,
    exportSchema = true
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun assessmentDao(): AssessmentDao
    abstract fun classDao(): ClassDao
    abstract fun studentDao(): StudentDao
    abstract fun scanResultDao(): ScanResultDao
    abstract fun teacherDao(): TeacherDao
    abstract fun attendanceDao(): AttendanceDao
    abstract fun classNoteDao(): ClassNoteDao
    abstract fun auditDao(): AuditDao
    abstract fun proofVaultDao(): ProofVaultDao
    abstract fun draftDao(): DraftDao
    abstract fun smsLogDao(): SmsLogDao
    abstract fun homeroomOverrideDao(): HomeroomOverrideDao
    abstract fun omrCalibrationDao(): OmrCalibrationDao

    companion object {
        @Volatile
        private var INSTANCE: AppDatabase? = null

        fun getInstance(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "ethiograde_db"
                ).build().also { INSTANCE = it }
            }
        }
    }
}
