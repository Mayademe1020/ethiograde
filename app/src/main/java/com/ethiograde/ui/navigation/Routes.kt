package com.ethiograde.ui.navigation

import kotlinx.serialization.Serializable

@Serializable
data object OnboardingRoute

@Serializable
data object DashboardRoute

@Serializable
data class ExamDayCreateRoute(val startMode: String = "CREATE_FORM")

@Serializable
data class AnswerKeyRoute(val assessmentId: String)

@Serializable
data class AnswerKeySectionSetupRoute(val assessmentId: String)

@Serializable
data class CameraScanRoute(val assessmentId: String, val batchMode: Boolean = false)

@Serializable
data class OmrCalibrationRoute(val assessmentId: String)

@Serializable
data object QuickGradeRoute

@Serializable
data class QuickEnterRoute(val assessmentId: String)

@Serializable
data class CaFastEntryRoute(val assessmentId: String)

@Serializable
data class ReviewRoute(val assessmentId: String)

@Serializable
data class GradeReviewRoute(val assessmentId: String, val resultId: String)

@Serializable
data class ProofVaultRoute(val proofId: String)

@Serializable
data object AnalyticsRoute

@Serializable
data class ItemAnalysisRoute(val assessmentId: String)

@Serializable
data class ClassDetailRoute(val classId: String)

@Serializable
data class AttendanceRoute(val classId: String)

@Serializable
data class ClassNotesRoute(val classId: String)

@Serializable
data class AddStudentRoute(val studentId: String? = null, val classId: String? = null)

@Serializable
data class StudentDetailRoute(val studentId: String)

@Serializable
data class ImportCsvRoute(val classId: String? = null)

@Serializable
data object HomeroomCardRoute

@Serializable
data class SmsComposeRoute(val studentId: String? = null, val assessmentId: String? = null)

@Serializable
data object SmsHistoryRoute

@Serializable
data class GradingScaleEditorRoute(val scaleId: String? = null)
