package com.ethiograde.service

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.speech.tts.TextToSpeech
import com.ethiograde.data.VoiceFeedbackMode
import com.ethiograde.model.ScanResult
import com.ethiograde.model.ScanStatus
import java.util.Locale

class VoiceFeedbackManager(context: Context) {
    private var tts: TextToSpeech? = null
    private var ready = false

    init {
        tts = TextToSpeech(context.applicationContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts?.language = Locale.US
                ready = true
            }
        }
    }

    fun speakResult(result: ScanResult, mode: VoiceFeedbackMode) {
        if (!ready || mode == VoiceFeedbackMode.OFF) return
        val text = when (mode) {
            VoiceFeedbackMode.OFF -> return
            VoiceFeedbackMode.STATUS_ONLY -> if (result.status == ScanStatus.NEEDS_RESCAN) "Needs rescan" else "Graded"
            VoiceFeedbackMode.SCORE_ONLY -> "${result.totalScore.toInt()} out of ${result.maxScore.toInt()}"
            VoiceFeedbackMode.GRADE_ONLY -> "Grade ${result.grade}"
            VoiceFeedbackMode.SCORE_AND_GRADE -> "${result.totalScore.toInt()} out of ${result.maxScore.toInt()}, grade ${result.grade}"
        }
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "ethiograde_${result.id}")
    }

    fun shutdown() {
        tts?.stop()
        tts?.shutdown()
        ready = false
    }
}

data class SmsTemplatePreset(
    val name: String,
    val englishTemplate: String,
    val amharicTemplate: String
) {
    fun render(
        studentName: String,
        subject: String,
        percentage: Double,
        schoolName: String,
        amharic: Boolean = false
    ): String {
        val raw = if (amharic) amharicTemplate else englishTemplate
        return raw
            .replace("{student}", studentName)
            .replace("{subject}", subject)
            .replace("{percentage}", "%.1f".format(percentage))
            .replace("{school}", schoolName.ifBlank { "School" })
    }

    companion object {
        val resultNotification = SmsTemplatePreset(
            name = "Result Notification",
            englishTemplate = "{student} scored {percentage}% in {subject}. - {school}",
            amharicTemplate = "{student} በ{subject} {percentage}% አስመዝግቧል። - {school}"
        )
        val atRiskWarning = SmsTemplatePreset(
            name = "At-Risk Warning",
            englishTemplate = "Warning: {student} is struggling ({percentage}% avg). Please follow up. - {school}",
            amharicTemplate = "ማስጠንቀቂያ: {student} እየተቸገረ ነው (አማካይ {percentage}%)። እባክዎን ይከታተሉ። - {school}"
        )
        val all = listOf(resultNotification, atRiskWarning)
    }
}

object SmsIntentService {
    fun launchSmsApp(context: Context, phoneNumber: String, message: String): Boolean {
        val normalized = PhoneUtils.normalize(phoneNumber)
        if (!PhoneUtils.isValid(normalized)) return false
        val uri = Uri.parse("smsto:${Uri.encode(normalized)}")
        val intent = Intent(Intent.ACTION_SENDTO, uri).apply {
            putExtra("sms_body", message)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return runCatching {
            context.startActivity(intent)
            true
        }.getOrDefault(false)
    }
}
