package com.ethiograde

import android.app.Application
import com.ethiograde.data.AppDatabase
import com.ethiograde.data.EthioGradeRepository
import com.ethiograde.data.SettingsRepository

class EthioGradeApp : Application() {
    val database: AppDatabase by lazy { AppDatabase.getInstance(this) }
    val settingsRepository: SettingsRepository by lazy { SettingsRepository(this) }
    val repository: EthioGradeRepository by lazy { EthioGradeRepository(database, settingsRepository) }
}
