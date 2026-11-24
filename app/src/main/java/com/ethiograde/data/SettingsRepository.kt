package com.ethiograde.data

import android.content.Context
import android.util.Base64
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import androidx.datastore.preferences.preferencesDataStore
import com.ethiograde.model.GradingScale
import com.ethiograde.model.WeightedGradeScale
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.security.SecureRandom
import java.util.Calendar

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "ethiograde_settings")

enum class VoiceFeedbackMode(val label: String, val description: String) {
    OFF("Off", "No scan voice readout"),
    STATUS_ONLY("Status only", "Announces graded or needs review"),
    SCORE_ONLY("Score only", "Reads out marks like 18 out of 20"),
    GRADE_ONLY("Grade only", "Reads out letter grades like A"),
    SCORE_AND_GRADE("Score + grade", "Reads out both score and letter grade")
}

data class QuickGradeTemplate(
    val count: Int = 20,
    val answers: List<String> = emptyList(),
    val questionTypes: List<String> = emptyList()
)

data class AppSettings(
    val firstLaunch: Boolean = true,
    val schoolName: String = "",
    val teacherName: String = "",
    val teacherPhone: String = "",
    val telegramHandle: String = "",
    val whatsappNumber: String = "",
    val defaultRubric: String = "moe_national",
    val autoEnhanceImages: Boolean = true,
    val voiceFeedbackMode: VoiceFeedbackMode = VoiceFeedbackMode.SCORE_ONLY,
    val darkMode: Boolean = false,
    val currentAcademicYear: String = defaultAcademicYear(),
    val academicYears: List<String> = listOf(defaultAcademicYear()),
    val subjects: List<String> = DEFAULT_SUBJECTS,
    val customScales: List<GradingScale> = emptyList(),
    val weightedScales: List<WeightedGradeScale> = emptyList(),
    val lastQuickTemplate: QuickGradeTemplate? = null
) {
    companion object {
        val DEFAULT_SUBJECTS = listOf(
            "Mathematics",
            "Afan Oromo",
            "Amharic",
            "Biology",
            "Chemistry",
            "Civics",
            "Economics",
            "English",
            "Geography",
            "History",
            "ICT",
            "Physical Education",
            "Physics",
            "Science"
        )

        fun defaultAcademicYear(): String {
            val cal = Calendar.getInstance()
            val month = cal.get(Calendar.MONTH) + 1
            val year = cal.get(Calendar.YEAR)
            val start = if (month >= 9) year else year - 1
            return "$start-${start + 1}"
        }
    }
}

class SettingsRepository(private val context: Context) {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    private object Keys {
        val FIRST_LAUNCH = booleanPreferencesKey("first_launch")
        val SCHOOL_NAME = stringPreferencesKey("school_name")
        val TEACHER_NAME = stringPreferencesKey("teacher_name")
        val TEACHER_PHONE = stringPreferencesKey("teacher_phone")
        val TELEGRAM = stringPreferencesKey("telegram_handle")
        val WHATSAPP = stringPreferencesKey("whatsapp_number")
        val DEFAULT_RUBRIC = stringPreferencesKey("default_rubric")
        val AUTO_ENHANCE = booleanPreferencesKey("auto_enhance")
        val VOICE_MODE = stringPreferencesKey("voice_feedback_mode")
        val DARK_MODE = booleanPreferencesKey("dark_mode")
        val CURRENT_ACADEMIC_YEAR = stringPreferencesKey("current_academic_year")
        val ACADEMIC_YEARS_JSON = stringPreferencesKey("academic_years_json")
        val SUBJECTS_JSON = stringPreferencesKey("subjects_json")
        val CUSTOM_SCALES_JSON = stringPreferencesKey("custom_scales_json")
        val WEIGHTED_SCALES_JSON = stringPreferencesKey("weighted_scales_json")
        val QUICK_TEMPLATE_ANSWERS = stringPreferencesKey("quick_template_answers")
        val BACKUP_AES_KEY = stringPreferencesKey("backup_aes_key")
    }

    val settingsFlow: Flow<AppSettings> = context.dataStore.data.map { prefs ->
        val defaultYear = AppSettings.defaultAcademicYear()
        val currentYear = prefs[Keys.CURRENT_ACADEMIC_YEAR]?.takeIf { it.isNotBlank() } ?: defaultYear
        val years = prefs[Keys.ACADEMIC_YEARS_JSON]?.let {
            runCatching { json.decodeFromString<List<String>>(it) }.getOrNull()
        }?.takeIf { it.isNotEmpty() } ?: listOf(currentYear)

        val subjects = prefs[Keys.SUBJECTS_JSON]?.let {
            runCatching { json.decodeFromString<List<String>>(it) }.getOrNull()
        }?.takeIf { it.isNotEmpty() } ?: AppSettings.DEFAULT_SUBJECTS

        val scales = prefs[Keys.CUSTOM_SCALES_JSON]?.let {
            runCatching { json.decodeFromString<List<GradingScale>>(it) }.getOrNull()
        } ?: emptyList()

        val weighted = prefs[Keys.WEIGHTED_SCALES_JSON]?.let {
            runCatching { json.decodeFromString<List<WeightedGradeScale>>(it) }.getOrNull()
        } ?: emptyList()

        val quickAnswers = prefs[Keys.QUICK_TEMPLATE_ANSWERS]?.let {
            runCatching { json.decodeFromString<List<String>>(it) }.getOrNull()
        }

        AppSettings(
            firstLaunch = prefs[Keys.FIRST_LAUNCH] ?: true,
            schoolName = prefs[Keys.SCHOOL_NAME] ?: "",
            teacherName = prefs[Keys.TEACHER_NAME] ?: "",
            teacherPhone = prefs[Keys.TEACHER_PHONE] ?: "",
            telegramHandle = prefs[Keys.TELEGRAM] ?: "",
            whatsappNumber = prefs[Keys.WHATSAPP] ?: "",
            defaultRubric = prefs[Keys.DEFAULT_RUBRIC] ?: "moe_national",
            autoEnhanceImages = prefs[Keys.AUTO_ENHANCE] ?: true,
            voiceFeedbackMode = runCatching {
                VoiceFeedbackMode.valueOf(prefs[Keys.VOICE_MODE] ?: VoiceFeedbackMode.SCORE_ONLY.name)
            }.getOrDefault(VoiceFeedbackMode.SCORE_ONLY),
            darkMode = prefs[Keys.DARK_MODE] ?: false,
            currentAcademicYear = currentYear,
            academicYears = years,
            subjects = subjects,
            customScales = scales,
            weightedScales = weighted,
            lastQuickTemplate = quickAnswers?.takeIf { it.isNotEmpty() }?.let {
                QuickGradeTemplate(count = it.size, answers = it)
            }
        )
    }

    suspend fun completeOnboarding(
        teacherName: String,
        schoolName: String,
        academicYear: String
    ) {
        context.dataStore.edit { prefs ->
            prefs[Keys.FIRST_LAUNCH] = false
            prefs[Keys.TEACHER_NAME] = teacherName
            prefs[Keys.SCHOOL_NAME] = schoolName
            if (academicYear.isNotBlank()) {
                prefs[Keys.CURRENT_ACADEMIC_YEAR] = academicYear
                val existing = prefs[Keys.ACADEMIC_YEARS_JSON]?.let {
                    runCatching { json.decodeFromString<List<String>>(it) }.getOrNull()
                } ?: emptyList()
                val updated = (listOf(academicYear) + existing).distinct()
                prefs[Keys.ACADEMIC_YEARS_JSON] = json.encodeToString(updated)
            }
        }
    }

    suspend fun updateProfile(
        teacherName: String? = null,
        schoolName: String? = null,
        teacherPhone: String? = null,
        telegram: String? = null,
        whatsapp: String? = null
    ) {
        context.dataStore.edit { prefs ->
            teacherName?.let { prefs[Keys.TEACHER_NAME] = it }
            schoolName?.let { prefs[Keys.SCHOOL_NAME] = it }
            teacherPhone?.let { prefs[Keys.TEACHER_PHONE] = it }
            telegram?.let { prefs[Keys.TELEGRAM] = it }
            whatsapp?.let { prefs[Keys.WHATSAPP] = it }
        }
    }

    suspend fun setDefaultRubric(rubricKey: String) {
        context.dataStore.edit { it[Keys.DEFAULT_RUBRIC] = rubricKey }
    }

    suspend fun toggleDarkMode() {
        context.dataStore.edit { prefs ->
            prefs[Keys.DARK_MODE] = !(prefs[Keys.DARK_MODE] ?: false)
        }
    }

    suspend fun toggleAutoEnhance() {
        context.dataStore.edit { prefs ->
            prefs[Keys.AUTO_ENHANCE] = !(prefs[Keys.AUTO_ENHANCE] ?: true)
        }
    }

    suspend fun setVoiceFeedbackMode(mode: VoiceFeedbackMode) {
        context.dataStore.edit { it[Keys.VOICE_MODE] = mode.name }
    }

    suspend fun setAcademicYear(year: String) {
        val trimmed = year.trim()
        if (trimmed.isEmpty()) return
        context.dataStore.edit { prefs ->
            prefs[Keys.CURRENT_ACADEMIC_YEAR] = trimmed
            val existing = prefs[Keys.ACADEMIC_YEARS_JSON]?.let {
                runCatching { json.decodeFromString<List<String>>(it) }.getOrNull()
            } ?: emptyList()
            if (!existing.contains(trimmed)) {
                prefs[Keys.ACADEMIC_YEARS_JSON] = json.encodeToString(listOf(trimmed) + existing)
            }
        }
    }

    suspend fun saveSubjects(subjects: List<String>) {
        context.dataStore.edit {
            it[Keys.SUBJECTS_JSON] = json.encodeToString(subjects.distinct().sorted())
        }
    }

    suspend fun saveCustomScale(scale: GradingScale) {
        context.dataStore.edit { prefs ->
            val current = prefs[Keys.CUSTOM_SCALES_JSON]?.let {
                runCatching { json.decodeFromString<List<GradingScale>>(it) }.getOrNull()
            }?.toMutableList() ?: mutableListOf()
            val idx = current.indexOfFirst { it.id == scale.id }
            if (idx >= 0) current[idx] = scale else current.add(scale)
            prefs[Keys.CUSTOM_SCALES_JSON] = json.encodeToString(current)
        }
    }

    suspend fun deleteCustomScale(scaleId: String) {
        context.dataStore.edit { prefs ->
            val current = prefs[Keys.CUSTOM_SCALES_JSON]?.let {
                runCatching { json.decodeFromString<List<GradingScale>>(it) }.getOrNull()
            }?.filterNot { it.id == scaleId } ?: emptyList()
            prefs[Keys.CUSTOM_SCALES_JSON] = json.encodeToString(current)
        }
    }

    suspend fun saveQuickTemplate(answers: List<String>) {
        context.dataStore.edit {
            it[Keys.QUICK_TEMPLATE_ANSWERS] = json.encodeToString(answers)
        }
    }

    suspend fun getOrCreateAesKey(): ByteArray {
        val prefs = context.dataStore.data.first()
        val existing = prefs[Keys.BACKUP_AES_KEY]
        if (!existing.isNullOrBlank()) {
            return Base64.decode(existing, Base64.NO_WRAP)
        }
        val key = ByteArray(32)
        SecureRandom().nextBytes(key)
        val encoded = Base64.encodeToString(key, Base64.NO_WRAP)
        context.dataStore.edit { it[Keys.BACKUP_AES_KEY] = encoded }
        return key
    }

    suspend fun clearAll() {
        context.dataStore.edit { it.clear() }
    }
}
