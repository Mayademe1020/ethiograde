package com.ethiograde

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import com.ethiograde.model.BubbleTemplate
import com.ethiograde.model.ExamDayStartMode
import com.ethiograde.ui.navigation.*
import com.ethiograde.ui.screens.*
import com.ethiograde.ui.theme.EthioGradeTheme
import com.ethiograde.viewmodel.EthioGradeViewModel

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val vm: EthioGradeViewModel = viewModel()
            val state by vm.uiState.collectAsStateWithLifecycle()

            EthioGradeTheme(darkTheme = state.settings.darkMode) {
                EthioGradeNavHost(vm = vm, state = state)
            }
        }
    }
}

private data class MainTabItem(val label: String, val icon: ImageVector)

@Composable
private fun EthioGradeNavHost(
    vm: EthioGradeViewModel,
    state: com.ethiograde.viewmodel.EthioGradeUiState
) {
    if (!state.settingsLoaded) {
        Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {}
        return
    }
    val navController = rememberNavController()
    val snackbarHostState = remember { SnackbarHostState() }
    var selectedTab by remember { mutableIntStateOf(0) }
    val startDestination: Any = remember {
        if (state.settings.firstLaunch) OnboardingRoute else DashboardRoute
    }

    LaunchedEffect(state.statusBanner) {
        val msg = state.statusBanner
        if (!msg.isNullOrBlank()) {
            snackbarHostState.showSnackbar(msg)
            vm.clearBanner()
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
    NavHost(
        navController = navController,
        startDestination = startDestination
    ) {
        composable<OnboardingRoute> {
            OnboardingScreen(
                settings = state.settings,
                onFinishSetup = { teacherName, schoolName, year, grades, subjects, seedDemo ->
                    vm.completeOnboarding(teacherName, schoolName, year, grades, subjects, seedDemo)
                    navController.navigate(DashboardRoute) {
                        popUpTo(OnboardingRoute) { inclusive = true }
                    }
                }
            )
        }

        composable<DashboardRoute> {
            val tabs = listOf(
                MainTabItem("Home", Icons.Default.Home),
                MainTabItem("Classes", Icons.Default.Class),
                MainTabItem("Assess", Icons.Default.Quiz),
                MainTabItem("Students", Icons.Default.Groups),
                MainTabItem("Settings", Icons.Default.Settings)
            )
            BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
                val useRail = maxWidth >= 600.dp
                Scaffold(
                    bottomBar = {
                        if (!useRail) {
                            NavigationBar {
                                tabs.forEachIndexed { idx, tab ->
                                    NavigationBarItem(
                                        selected = selectedTab == idx,
                                        onClick = { selectedTab = idx },
                                        icon = { Icon(tab.icon, contentDescription = tab.label) },
                                        label = { Text(tab.label) },
                                        modifier = Modifier.testTag("nav_tab_${tab.label.lowercase()}")
                                    )
                                }
                            }
                        }
                    },
                    contentWindowInsets = WindowInsets.safeDrawing
                ) { padding ->
                    Row(modifier = Modifier.fillMaxSize().padding(padding)) {
                        if (useRail) {
                            NavigationRail {
                                tabs.forEachIndexed { idx, tab ->
                                    NavigationRailItem(
                                        selected = selectedTab == idx,
                                        onClick = { selectedTab = idx },
                                        icon = { Icon(tab.icon, contentDescription = tab.label) },
                                        label = { Text(tab.label) }
                                    )
                                }
                            }
                        }
                        Box(modifier = Modifier.weight(1f).fillMaxHeight()) {
                            when (selectedTab) {
                                0 -> HomeDashboardTab(
                                    state = state,
                                    onSetAcademicYear = { vm.setAcademicYear(it) },
                                    onCreateClass = { vm.saveClass(it) },
                                    onNavigateCreateExam = { mode -> navController.navigate(ExamDayCreateRoute(mode.name)) },
                                    onNavigateAnswerKey = { navController.navigate(AnswerKeyRoute(it)) },
                                    onNavigateScan = { navController.navigate(CameraScanRoute(it, batchMode = false)) },
                                    onNavigateReview = { navController.navigate(ReviewRoute(it)) },
                                    onNavigateQuickEnter = { navController.navigate(QuickEnterRoute(it)) },
                                    onNavigateQuickGrade = { navController.navigate(QuickGradeRoute) },
                                    onNavigateHomeroomCard = { navController.navigate(HomeroomCardRoute) },
                                    onNavigateAnalytics = { navController.navigate(AnalyticsRoute) },
                                    onNavigateClassDetail = { navController.navigate(ClassDetailRoute(it)) },
                                    onNavigateStudentDetail = { navController.navigate(StudentDetailRoute(it)) },
                                    onSwitchToTab = { selectedTab = it }
                                )
                                1 -> ClassesTab(
                                    state = state,
                                    onSaveClass = { vm.saveClass(it) },
                                    canDeleteClass = { vm.canDeleteClass(it) },
                                    onDeleteClass = { vm.deleteClass(it) },
                                    onOpenClassDetail = { navController.navigate(ClassDetailRoute(it)) },
                                    onOpenAddStudent = { classId -> navController.navigate(AddStudentRoute(classId = classId)) }
                                )
                                2 -> AssessmentsTab(
                                    state = state,
                                    onCreateExam = { navController.navigate(ExamDayCreateRoute(ExamDayStartMode.CREATE_FORM.name)) },
                                    onQuickGrade = { navController.navigate(QuickGradeRoute) },
                                    onOpenAnswerKey = { navController.navigate(AnswerKeyRoute(it)) },
                                    onOpenScan = { navController.navigate(CameraScanRoute(it, batchMode = false)) },
                                    onOpenReview = { navController.navigate(ReviewRoute(it)) },
                                    onDeleteAssessment = { vm.deleteAssessment(it) }
                                )
                                3 -> StudentsTab(
                                    state = state,
                                    onAddStudent = { navController.navigate(AddStudentRoute()) },
                                    onImportCsv = { navController.navigate(ImportCsvRoute()) },
                                    onOpenStudentDetail = { navController.navigate(StudentDetailRoute(it)) }
                                )
                                else -> SettingsTab(
                                    state = state,
                                    onUpdateProfile = { name, school, phone -> vm.updateProfile(name, school, phone) },
                                    onSwitchTeacher = { vm.addOrSwitchTeacher(it) },
                                    onSetDefaultRubric = { vm.setDefaultRubric(it) },
                                    onSetVoiceFeedbackMode = { vm.setVoiceFeedbackMode(it) },
                                    onToggleAutoEnhance = { vm.toggleAutoEnhance() },
                                    onToggleDarkMode = { vm.toggleDarkMode() },
                                    onSetAcademicYear = { vm.setAcademicYear(it) },
                                    onSaveSubjects = { vm.saveSubjects(it) },
                                    onOpenScaleEditor = { navController.navigate(GradingScaleEditorRoute(it)) },
                                    onDeleteCustomScale = { vm.deleteCustomScale(it) },
                                    onExportEncryptedBackup = { pass -> vm.exportEncryptedBackupBytes(pass) },
                                    onImportBackupBytes = { bytes, pass, replace, cb -> vm.importBackupBytes(bytes, pass, replace, cb) },
                                    onLoadDemoData = { vm.loadDemoData() },
                                    onClearAllData = { vm.clearAllData() },
                                    onOpenSmsHistory = { navController.navigate(SmsHistoryRoute) }
                                )
                            }
                        }
                    }
                }
            }
        }

        composable<ExamDayCreateRoute> { entry ->
            val route = entry.toRoute<ExamDayCreateRoute>()
            val mode = runCatching { ExamDayStartMode.valueOf(route.startMode) }.getOrDefault(ExamDayStartMode.CREATE_FORM)
            ExamDayCreateScreen(
                startMode = mode,
                state = state,
                onBack = { navController.popBackStack() },
                onCreatedForKey = { assessment ->
                    vm.saveAssessmentWithRecalculation(assessment)
                    navController.navigate(AnswerKeyRoute(assessment.id)) {
                        popUpTo<ExamDayCreateRoute> { inclusive = true }
                    }
                },
                onCreatedForFastCa = { assessment ->
                    vm.saveAssessmentWithRecalculation(assessment)
                    navController.navigate(CaFastEntryRoute(assessment.id)) {
                        popUpTo<ExamDayCreateRoute> { inclusive = true }
                    }
                }
            )
        }

        composable<AnswerKeyRoute> { entry ->
            val route = entry.toRoute<AnswerKeyRoute>()
            val assessment = state.assessments.firstOrNull { it.id == route.assessmentId }
            if (assessment == null) {
                LaunchedEffect(Unit) { navController.popBackStack() }
            } else {
                AnswerKeyScreen(
                    assessment = assessment,
                    onBack = { navController.popBackStack() },
                    onSaveAssessment = { vm.saveAssessmentWithRecalculation(it) },
                    onOpenSections = { navController.navigate(AnswerKeySectionSetupRoute(assessment.id)) },
                    onStartScanning = { navController.navigate(CameraScanRoute(assessment.id, batchMode = false)) },
                    onOpenQuickEnter = { navController.navigate(QuickEnterRoute(assessment.id)) }
                )
            }
        }

        composable<AnswerKeySectionSetupRoute> { entry ->
            val route = entry.toRoute<AnswerKeySectionSetupRoute>()
            val assessment = state.assessments.firstOrNull { it.id == route.assessmentId }
            if (assessment != null) {
                AnswerKeySectionSetupScreen(
                    assessment = assessment,
                    onBack = { navController.popBackStack() },
                    onApplySections = { vm.saveAssessmentWithRecalculation(it) }
                )
            }
        }

        composable<QuickGradeRoute> {
            QuickGradeScreen(
                state = state,
                onBack = { navController.popBackStack() },
                onCreateAndScan = { answers ->
                    vm.createQuickGradeAssessment(answers) { created ->
                        navController.navigate(CameraScanRoute(created.id, batchMode = true)) {
                            popUpTo(QuickGradeRoute) { inclusive = true }
                        }
                    }
                }
            )
        }

        composable<QuickEnterRoute> { entry ->
            val route = entry.toRoute<QuickEnterRoute>()
            val assessment = state.assessments.firstOrNull { it.id == route.assessmentId }
            if (assessment != null) {
                QuickEnterScreen(
                    assessment = assessment,
                    state = state,
                    onBack = { navController.popBackStack() },
                    onSaveStudentAnswers = { student, map -> vm.saveManualQuestionEntry(assessment, student, map) },
                    onOpenFastCa = { navController.navigate(CaFastEntryRoute(assessment.id)) },
                    onFinishReview = {
                        vm.clearDraft(assessment.id)
                        navController.navigate(ReviewRoute(assessment.id))
                    }
                )
            }
        }

        composable<CaFastEntryRoute> { entry ->
            val route = entry.toRoute<CaFastEntryRoute>()
            val assessment = state.assessments.firstOrNull { it.id == route.assessmentId }
            if (assessment != null) {
                CaFastEntryScreen(
                    assessment = assessment,
                    state = state,
                    onBack = { navController.popBackStack() },
                    onSaveScore = { student, score -> vm.saveFastCaScore(assessment, student, score) }
                )
            }
        }

        composable<CameraScanRoute> { entry ->
            val route = entry.toRoute<CameraScanRoute>()
            val assessment = state.assessments.firstOrNull { it.id == route.assessmentId }
            if (assessment != null) {
                CameraScanScreen(
                    assessment = assessment,
                    batchMode = route.batchMode,
                    state = state,
                    onBack = { navController.popBackStack() },
                    onGradePhotoUri = { uri, st, cb -> vm.gradePhotoUri(uri, assessment, st, cb) },
                    onGradeCapturedFile = { path, st, cb -> vm.gradeCapturedFile(path, true, assessment, st, cb) },
                    onGradeBitmap = { bmp, st, cb -> vm.gradeBitmap(bmp, assessment, st, cb) },
                    onOpenCalibration = { navController.navigate(OmrCalibrationRoute(assessment.id)) },
                    onOpenReview = { navController.navigate(ReviewRoute(assessment.id)) }
                )
            }
        }

        composable<OmrCalibrationRoute> { entry ->
            val route = entry.toRoute<OmrCalibrationRoute>()
            val assessment = state.assessments.firstOrNull { it.id == route.assessmentId }
            val savedCalibration by produceState<BubbleTemplate?>(initialValue = null, route.assessmentId) {
                value = vm.loadOmrCalibration(route.assessmentId)
            }
            if (assessment != null) {
                OmrCalibrationScreen(
                    assessment = assessment,
                    savedTemplate = savedCalibration,
                    onBack = { navController.popBackStack() },
                    onSaveCalibration = { tpl -> vm.saveOmrCalibration(assessment.id, tpl) }
                )
            }
        }

        composable<ReviewRoute> { entry ->
            val route = entry.toRoute<ReviewRoute>()
            val assessment = state.assessments.firstOrNull { it.id == route.assessmentId }
            if (assessment != null) {
                ReviewScreen(
                    assessment = assessment,
                    state = state,
                    onBack = { navController.popBackStack() },
                    onOpenScan = { navController.navigate(CameraScanRoute(assessment.id, batchMode = true)) },
                    onOpenQuickEnter = { navController.navigate(QuickEnterRoute(assessment.id)) },
                    onOpenItemAnalysis = { navController.navigate(ItemAnalysisRoute(assessment.id)) },
                    onOpenGradeDetail = { resId -> navController.navigate(GradeReviewRoute(assessment.id, resId)) },
                    onMarkAssessmentCompleted = { completed -> vm.setAssessmentCompleted(assessment, completed) },
                    onDeleteResult = { vm.deleteScanResult(it) }
                )
            }
        }

        composable<GradeReviewRoute> { entry ->
            val route = entry.toRoute<GradeReviewRoute>()
            val assessment = state.assessments.firstOrNull { it.id == route.assessmentId }
            val result = state.scanResults.firstOrNull { it.id == route.resultId }
            if (assessment != null && result != null) {
                GradeReviewScreen(
                    assessment = assessment,
                    result = result,
                    state = state,
                    onBack = { navController.popBackStack() },
                    onToggleAnswerOverride = { qNum -> vm.toggleAnswerOverride(result, qNum) },
                    onOverrideTotalScore = { s, reason -> vm.overrideTotalScore(result, s, reason) },
                    onMarkReviewed = { vm.markResultReviewed(result) },
                    onReassignStudent = { st -> vm.reassignStudent(result, st) },
                    onRevertAudit = { audit -> vm.revertAuditEntry(result, audit) },
                    onOpenProofVault = { proofId -> navController.navigate(ProofVaultRoute(proofId)) },
                    onSendParentSms = { stId -> navController.navigate(SmsComposeRoute(stId, assessment.id)) },
                    onRescan = { navController.navigate(CameraScanRoute(assessment.id, batchMode = false)) }
                )
            }
        }

        composable<ProofVaultRoute> { entry ->
            val route = entry.toRoute<ProofVaultRoute>()
            val proof = state.proofVaultEntries.firstOrNull { it.id == route.proofId }
            if (proof != null) {
                ProofVaultInspectorScreen(entry = proof, onBack = { navController.popBackStack() })
            }
        }

        composable<AnalyticsRoute> {
            AnalyticsScreen(
                state = state,
                onBack = { navController.popBackStack() },
                onOpenStudentDetail = { navController.navigate(StudentDetailRoute(it)) },
                onOpenItemAnalysis = { navController.navigate(ItemAnalysisRoute(it)) }
            )
        }

        composable<ItemAnalysisRoute> { entry ->
            val route = entry.toRoute<ItemAnalysisRoute>()
            val assessment = state.assessments.firstOrNull { it.id == route.assessmentId }
            if (assessment != null) {
                ItemAnalysisScreen(
                    assessment = assessment,
                    state = state,
                    onBack = { navController.popBackStack() }
                )
            }
        }

        composable<ClassDetailRoute> { entry ->
            val route = entry.toRoute<ClassDetailRoute>()
            val cls = state.classes.firstOrNull { it.id == route.classId }
            if (cls != null) {
                ClassDetailScreen(
                    classInfo = cls,
                    students = state.studentsInClass(cls.id),
                    allClasses = state.classes,
                    onBack = { navController.popBackStack() },
                    onAddStudent = { navController.navigate(AddStudentRoute(classId = cls.id)) },
                    onImportCsv = { navController.navigate(ImportCsvRoute(classId = cls.id)) },
                    onOpenAttendance = { navController.navigate(AttendanceRoute(cls.id)) },
                    onOpenNotes = { navController.navigate(ClassNotesRoute(cls.id)) },
                    onOpenStudentDetail = { navController.navigate(StudentDetailRoute(it)) },
                    onTransferStudent = { st, target -> vm.transferStudent(st, target) },
                    onDeleteStudent = { vm.deleteStudent(it) }
                )
            }
        }

        composable<AttendanceRoute> { entry ->
            val route = entry.toRoute<AttendanceRoute>()
            val cls = state.classes.firstOrNull { it.id == route.classId }
            if (cls != null) {
                AttendanceScreen(
                    classInfo = cls,
                    students = state.studentsInClass(cls.id),
                    records = state.attendanceRecords,
                    onBack = { navController.popBackStack() },
                    onSave = { vm.saveAttendance(it) }
                )
            }
        }

        composable<ClassNotesRoute> { entry ->
            val route = entry.toRoute<ClassNotesRoute>()
            val cls = state.classes.firstOrNull { it.id == route.classId }
            if (cls != null) {
                ClassNotesScreen(
                    classInfo = cls,
                    notes = state.classNotes,
                    onBack = { navController.popBackStack() },
                    onSaveNote = { vm.saveClassNote(it) },
                    onDeleteNote = { vm.deleteClassNote(it) }
                )
            }
        }

        composable<AddStudentRoute> { entry ->
            val route = entry.toRoute<AddStudentRoute>()
            val existing = route.studentId?.let { id -> state.students.firstOrNull { it.id == id } }
            AddOrEditStudentScreen(
                existingStudent = existing,
                preselectedClassId = route.classId,
                classes = state.classes,
                onBack = { navController.popBackStack() },
                onSave = { vm.saveStudent(it) }
            )
        }

        composable<StudentDetailRoute> { entry ->
            val route = entry.toRoute<StudentDetailRoute>()
            val student = state.students.firstOrNull { it.id == route.studentId }
            if (student != null) {
                StudentDetailScreen(
                    student = student,
                    state = state,
                    onBack = { navController.popBackStack() },
                    onEdit = { navController.navigate(AddStudentRoute(studentId = student.id)) },
                    onDelete = { vm.deleteStudent(student.id) },
                    onSendSms = { navController.navigate(SmsComposeRoute(studentId = student.id)) }
                )
            }
        }

        composable<ImportCsvRoute> { entry ->
            val route = entry.toRoute<ImportCsvRoute>()
            val cls = route.classId?.let { id -> state.classes.firstOrNull { it.id == id } }
            ImportCsvScreen(
                classInfo = cls,
                onBack = { navController.popBackStack() },
                onImportConfirmed = { vm.importStudents(it) }
            )
        }

        composable<HomeroomCardRoute> {
            HomeroomCardScreen(
                state = state,
                onBack = { navController.popBackStack() },
                onUpdateOverride = { classId, studentId, conduct, hold ->
                    vm.updateHomeroomOverride(classId, studentId, conduct, hold)
                }
            )
        }

        composable<SmsComposeRoute> { entry ->
            val route = entry.toRoute<SmsComposeRoute>()
            SmsComposeScreen(
                preselectedStudentId = route.studentId,
                preselectedAssessmentId = route.assessmentId,
                state = state,
                onBack = { navController.popBackStack() },
                onLogSms = { vm.logSms(it) },
                onOpenHistory = { navController.navigate(SmsHistoryRoute) }
            )
        }

        composable<SmsHistoryRoute> {
            SmsHistoryScreen(
                logs = state.smsLogs,
                onBack = { navController.popBackStack() }
            )
        }

        composable<GradingScaleEditorRoute> { entry ->
            val route = entry.toRoute<GradingScaleEditorRoute>()
            val existing = route.scaleId?.let { id -> state.settings.customScales.firstOrNull { it.id == id } }
            GradingScaleEditorScreen(
                existingScale = existing,
                onBack = { navController.popBackStack() },
                onSaveScale = { vm.saveCustomScale(it) }
            )
        }
    }
    SnackbarHost(
        hostState = snackbarHostState,
        modifier = Modifier
            .align(Alignment.BottomCenter)
            .navigationBarsPadding()
            .padding(horizontal = 16.dp, vertical = 12.dp)
    )
    }
}
