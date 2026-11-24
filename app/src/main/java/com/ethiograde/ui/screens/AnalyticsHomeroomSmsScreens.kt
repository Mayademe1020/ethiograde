package com.ethiograde.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.ethiograde.model.*
import com.ethiograde.service.*
import com.ethiograde.ui.components.MiniStatCard
import com.ethiograde.ui.theme.LocalEthioColors
import com.ethiograde.viewmodel.EthioGradeUiState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.DateFormat
import java.util.Date

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AnalyticsScreen(
    state: EthioGradeUiState,
    onBack: () -> Unit,
    onOpenStudentDetail: (String) -> Unit,
    onOpenItemAnalysis: (String) -> Unit
) {
    val ethio = LocalEthioColors.current
    var selectedTab by remember { mutableIntStateOf(0) }
    val subjects = remember(state.assessments, state.scanResults) {
        AnalyticsService.computeBySubject(state.assessments, state.scanResults)
    }
    val atRisk = remember(state.students, state.scanResults) {
        AnalyticsService.findAtRiskStudents(state.students, state.scanResults)
    }
    var trendStudentId by remember { mutableStateOf(state.students.firstOrNull()?.id.orEmpty()) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Class Analytics") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                }
            )
        },
        contentWindowInsets = WindowInsets.safeDrawing
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            PrimaryTabRow(selectedTabIndex = selectedTab) {
                Tab(selected = selectedTab == 0, onClick = { selectedTab = 0 }, text = { Text("Overview") })
                Tab(selected = selectedTab == 1, onClick = { selectedTab = 1 }, text = { Text("At-Risk (${atRisk.size})") })
                Tab(selected = selectedTab == 2, onClick = { selectedTab = 2 }, text = { Text("Trends") })
            }

            when (selectedTab) {
                0 -> {
                    LazyColumn(
                        contentPadding = PaddingValues(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        item {
                            val avg = if (state.scanResults.isEmpty()) 0.0 else state.scanResults.sumOf { it.percentage } / state.scanResults.size
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                                MiniStatCard("Overall Avg", "${"%.1f".format(avg)}%", Icons.Default.Insights, MaterialTheme.colorScheme.primary, Modifier.weight(1f))
                                MiniStatCard("Assessments", "${state.assessments.size}", Icons.Default.Assignment, ethio.info, Modifier.weight(1f))
                                MiniStatCard("Papers", "${state.scanResults.size}", Icons.Default.TaskAlt, ethio.success, Modifier.weight(1f))
                            }
                        }
                        item { Text("Subject Performance", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold) }
                        if (subjects.isEmpty()) {
                            item { Text("Grade some papers to unlock subject analytics.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        } else {
                            items(subjects, key = { it.subject }) { perf ->
                                Surface(
                                    color = MaterialTheme.colorScheme.surface,
                                    shape = MaterialTheme.shapes.medium,
                                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
                                ) {
                                    Column(modifier = Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                            Text(perf.subject, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                                            Text("${"%.1f".format(perf.averagePercentage)}%", color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
                                        }
                                        LinearProgressIndicator(
                                            progress = { (perf.averagePercentage / 100.0).toFloat().coerceIn(0f, 1f) },
                                            modifier = Modifier.fillMaxWidth().height(8.dp)
                                        )
                                        Text(
                                            "${perf.resultCount} graded • Pass Rate ${"%.0f".format(perf.passRate)}% • High ${"%.0f".format(perf.highestScore)}%",
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                                }
                            }
                        }
                        if (state.assessments.isNotEmpty()) {
                            item { Text("Item Analysis by Exam", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold) }
                            items(state.assessments, key = { it.id }) { a ->
                                OutlinedButton(onClick = { onOpenItemAnalysis(a.id) }, modifier = Modifier.fillMaxWidth()) {
                                    Text("Inspect ${a.title} (${a.questionCount}Q)")
                                }
                            }
                        }
                    }
                }
                1 -> {
                    LazyColumn(
                        contentPadding = PaddingValues(16.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        if (atRisk.isEmpty()) {
                            item { Text("No at-risk students flagged below 55%.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        } else {
                            items(atRisk, key = { it.student.id }) { item ->
                                Surface(
                                    color = MaterialTheme.colorScheme.surface,
                                    shape = MaterialTheme.shapes.medium,
                                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.error.copy(alpha = 0.5f)),
                                    modifier = Modifier.fillMaxWidth().clickable { onOpenStudentDetail(item.student.id) }
                                ) {
                                    Row(
                                        modifier = Modifier.padding(14.dp),
                                        horizontalArrangement = Arrangement.SpaceBetween,
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Column(modifier = Modifier.weight(1f)) {
                                            Text(item.student.fullName, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                                            Text(
                                                "${item.student.className} • ${item.failingCount} failing of ${item.assessedCount}",
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                        }
                                        Text(
                                            "${"%.1f".format(item.averagePercentage)}%",
                                            style = MaterialTheme.typography.titleMedium,
                                            color = MaterialTheme.colorScheme.error,
                                            fontWeight = FontWeight.Bold
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                else -> {
                    val points = remember(trendStudentId, state.assessments, state.scanResults) {
                        AnalyticsService.studentTrend(trendStudentId, state.assessments, state.scanResults)
                    }
                    LazyColumn(
                        contentPadding = PaddingValues(16.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        item {
                            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                items(state.students, key = { it.id }) { st ->
                                    FilterChip(
                                        selected = trendStudentId == st.id,
                                        onClick = { trendStudentId = st.id },
                                        label = { Text(st.fullName) }
                                    )
                                }
                            }
                        }
                        if (points.isEmpty()) {
                            item { Text("No scores recorded for selected student.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        } else {
                            items(points) { pt ->
                                Surface(
                                    color = MaterialTheme.colorScheme.surface,
                                    shape = MaterialTheme.shapes.medium,
                                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
                                ) {
                                    Column(modifier = Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                            Text("${pt.assessmentTitle} (${pt.subject})", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                                            Text("${"%.1f".format(pt.percentage)}%", fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
                                        }
                                        LinearProgressIndicator(
                                            progress = { (pt.percentage / 100.0).toFloat().coerceIn(0f, 1f) },
                                            modifier = Modifier.fillMaxWidth().height(8.dp)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ItemAnalysisScreen(
    assessment: Assessment,
    state: EthioGradeUiState,
    onBack: () -> Unit
) {
    val ethio = LocalEthioColors.current
    val results = state.resultsForAssessment(assessment.id)
    val summary = remember(results, assessment) {
        ItemAnalysisService.computeSummary(results, assessment)
    }
    var detailQuestion by remember { mutableStateOf<QuestionStats?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Item Analysis • ${assessment.title}", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                }
            )
        },
        contentWindowInsets = WindowInsets.safeDrawing
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    MiniStatCard("Easy", "${summary.easyCount}", Icons.Default.TrendingUp, ethio.success, Modifier.weight(1f))
                    MiniStatCard("Medium", "${summary.mediumCount}", Icons.Default.DragHandle, ethio.info, Modifier.weight(1f))
                    MiniStatCard("Hard", "${summary.hardCount}", Icons.Default.Warning, MaterialTheme.colorScheme.error, Modifier.weight(1f))
                }
            }
            if (summary.lowDiscriminationCount > 0) {
                item {
                    Surface(color = ethio.warningContainer, shape = MaterialTheme.shapes.medium, modifier = Modifier.fillMaxWidth()) {
                        Text(
                            "${summary.lowDiscriminationCount} question(s) have low discrimination (< 0.20) and may need review.",
                            color = ethio.warning,
                            modifier = Modifier.padding(12.dp),
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }
            items(summary.questions, key = { it.questionNumber }) { qs ->
                Surface(
                    color = MaterialTheme.colorScheme.surface,
                    shape = MaterialTheme.shapes.medium,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                    modifier = Modifier.fillMaxWidth().clickable { detailQuestion = qs }
                ) {
                    Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("Q${qs.questionNumber} • Key: ${qs.correctAnswer}", fontWeight = FontWeight.Bold)
                            Text(
                                "${qs.difficultyLevel.label} (${(qs.difficulty * 100).toInt()}%)",
                                style = MaterialTheme.typography.labelMedium,
                                color = when (qs.difficultyLevel) {
                                    DifficultyLevel.EASY -> ethio.success
                                    DifficultyLevel.MEDIUM -> ethio.info
                                    DifficultyLevel.HARD -> MaterialTheme.colorScheme.error
                                },
                                fontWeight = FontWeight.Bold
                            )
                        }
                        LinearProgressIndicator(
                            progress = { qs.difficulty.toFloat().coerceIn(0f, 1f) },
                            modifier = Modifier.fillMaxWidth().height(8.dp)
                        )
                        Text(
                            "${qs.correctCount}/${qs.totalAttempts} correct • Discrimination ${"%.2f".format(qs.discrimination)}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    }

    detailQuestion?.let { qs ->
        AlertDialog(
            onDismissRequest = { detailQuestion = null },
            title = { Text("Q${qs.questionNumber} Choice Breakdown") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Correct Answer: ${qs.correctAnswer}", fontWeight = FontWeight.Bold)
                    qs.optionCounts.entries.sortedByDescending { it.value }.forEach { (opt, count) ->
                        Text("$opt: $count student(s)")
                    }
                }
            },
            confirmButton = { TextButton(onClick = { detailQuestion = null }) { Text("Close") } }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeroomCardScreen(
    state: EthioGradeUiState,
    onBack: () -> Unit,
    onUpdateOverride: (classId: String, studentId: String, conduct: String, hasFinanceHold: Boolean) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val ethio = LocalEthioColors.current
    val homeroomClasses = remember(state.classes) {
        state.classes.filter { it.isHomeroom }.ifEmpty { state.classes }
    }
    var selectedClass by remember(homeroomClasses) { mutableStateOf(homeroomClasses.firstOrNull()) }
    var semester by remember { mutableStateOf("Semester 1") }
    var editingStudent by remember { mutableStateOf<HomeroomStudentReport?>(null) }

    val report = remember(
        selectedClass, semester, state.students, state.assessments, state.scanResults, state.attendanceRecords, state.homeroomOverrides
    ) {
        selectedClass?.let { cls ->
            HomeroomConsolidationService.consolidate(
                classInfo = cls,
                students = state.students,
                assessments = state.assessments,
                allResults = state.scanResults,
                attendanceRecords = state.attendanceRecords,
                overrides = state.homeroomOverrides,
                semester = semester,
                academicYear = state.settings.currentAcademicYear,
                homeroomTeacherName = state.settings.teacherName,
                customScales = state.settings.customScales
            )
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Card Day (የካርድ ቀን)") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                },
                actions = {
                    if (report != null && report.students.isNotEmpty()) {
                        IconButton(onClick = {
                            scope.launch {
                                val pdf = withContext(Dispatchers.IO) {
                                    PdfExportAndCsvService.generateHomeroomReportCardsPdf(context, report, state.settings.schoolName)
                                }
                                PdfExportAndCsvService.shareFile(context, pdf, "application/pdf", "Ministry Report Cards")
                            }
                        }, modifier = Modifier.testTag("homeroom_pdf_button")) {
                            Icon(Icons.Default.Print, contentDescription = "Export 4-Up Report Cards PDF")
                        }
                        IconButton(onClick = {
                            scope.launch {
                                val csv = withContext(Dispatchers.IO) {
                                    PdfExportAndCsvService.exportMinistryBroadsheetCsv(context, report)
                                }
                                PdfExportAndCsvService.shareFile(context, csv, "text/csv", "Ministry Broadsheet CSV")
                            }
                        }, modifier = Modifier.testTag("homeroom_csv_button")) {
                            Icon(Icons.Default.TableView, contentDescription = "Export Broadsheet CSV")
                        }
                    }
                }
            )
        },
        contentWindowInsets = WindowInsets.safeDrawing
    ) { padding ->
        if (selectedClass == null) {
            Box(modifier = Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Text("Create a class first to generate Ministry Report Cards.")
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                item {
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(homeroomClasses, key = { it.id }) { cls ->
                            FilterChip(
                                selected = selectedClass?.id == cls.id,
                                onClick = { selectedClass = cls },
                                label = { Text(cls.displayName) }
                            )
                        }
                    }
                }
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf("Semester 1", "Semester 2", "All").forEach { sem ->
                            FilterChip(selected = semester == sem, onClick = { semester = sem }, label = { Text(sem) })
                        }
                    }
                }
                val students = report?.students.orEmpty()
                if (students.isEmpty()) {
                    item { Text("No students enrolled in ${selectedClass?.displayName}.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                } else {
                    items(students, key = { it.studentId }) { st ->
                        Surface(
                            color = MaterialTheme.colorScheme.surface,
                            shape = MaterialTheme.shapes.medium,
                            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                            modifier = Modifier.fillMaxWidth().clickable { editingStudent = st }
                        ) {
                            Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                    Text("#${st.classRank} • ${st.fullName}", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                                    Text(
                                        "${"%.1f".format(st.semesterAverage)}%",
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.Bold,
                                        color = if (st.semesterAverage >= 50) ethio.success else MaterialTheme.colorScheme.error
                                    )
                                }
                                Text(
                                    "Total: ${"%.1f".format(st.grandTotal)} • Conduct: ${st.conduct} • Absent: ${st.absentDays}d",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                if (st.hasFinanceHold) {
                                    Text("እዳ ያለበት (Finance Hold)", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
                                } else {
                                    Text(st.remarkAm, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    editingStudent?.let { st ->
        var conduct by remember(st.studentId) { mutableStateOf(st.conduct) }
        var financeHold by remember(st.studentId) { mutableStateOf(st.hasFinanceHold) }
        AlertDialog(
            onDismissRequest = { editingStudent = null },
            title = { Text(st.fullName) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Conduct Grade")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf("A", "B", "C", "D").forEach { c ->
                            FilterChip(selected = conduct == c, onClick = { conduct = c }, label = { Text(c) })
                        }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                        Text("Finance Hold (እዳ ያለበት)")
                        Switch(checked = financeHold, onCheckedChange = { financeHold = it })
                    }
                }
            },
            confirmButton = {
                Button(onClick = {
                    selectedClass?.let { cls -> onUpdateOverride(cls.id, st.studentId, conduct, financeHold) }
                    editingStudent = null
                }) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { editingStudent = null }) { Text("Cancel") } }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SmsComposeScreen(
    preselectedStudentId: String?,
    preselectedAssessmentId: String?,
    state: EthioGradeUiState,
    onBack: () -> Unit,
    onLogSms: (SmsLogEntry) -> Unit,
    onOpenHistory: () -> Unit
) {
    val context = LocalContext.current
    val studentsWithPhone = remember(state.students) {
        state.students.filter { !it.parentPhone.isNullOrBlank() }.ifEmpty { state.students }
    }
    var selectedStudent by remember {
        mutableStateOf(
            studentsWithPhone.firstOrNull { it.id == preselectedStudentId } ?: studentsWithPhone.firstOrNull()
        )
    }
    var selectedPreset by remember { mutableStateOf(SmsTemplatePreset.resultNotification) }
    var useAmharic by remember { mutableStateOf(false) }

    val latestScorePct = remember(selectedStudent, preselectedAssessmentId, state.scanResults) {
        val st = selectedStudent ?: return@remember 0.0
        val res = state.scanResults.filter {
            it.studentId == st.id && (preselectedAssessmentId == null || it.assessmentId == preselectedAssessmentId)
        }
        if (res.isEmpty()) 0.0 else res.sumOf { it.percentage } / res.size
    }

    var messageBody by remember(selectedStudent, selectedPreset, useAmharic, latestScorePct) {
        mutableStateOf(
            selectedPreset.render(
                studentName = selectedStudent?.fullName ?: "Student",
                subject = state.activeAssessment?.subject ?: "Class",
                percentage = latestScorePct,
                schoolName = state.settings.schoolName,
                amharic = useAmharic
            )
        )
    }
    var feedbackMsg by remember { mutableStateOf<String?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Parent SMS") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") } },
                actions = {
                    IconButton(onClick = onOpenHistory) {
                        Icon(Icons.Default.History, contentDescription = "SMS History")
                    }
                }
            )
        },
        contentWindowInsets = WindowInsets.safeDrawing
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                Text("Student Recipient", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(6.dp))
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(studentsWithPhone, key = { it.id }) { st ->
                        FilterChip(
                            selected = selectedStudent?.id == st.id,
                            onClick = { selectedStudent = st },
                            label = { Text(st.fullName) }
                        )
                    }
                }
            }
            item {
                Text("Phone: ${selectedStudent?.parentPhone ?: "No phone saved"}", style = MaterialTheme.typography.bodyMedium)
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    SmsTemplatePreset.all.forEach { preset ->
                        FilterChip(
                            selected = selectedPreset.name == preset.name,
                            onClick = { selectedPreset = preset },
                            label = { Text(preset.name) }
                        )
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                    Text("Amharic Template (አማርኛ)")
                    Switch(checked = useAmharic, onCheckedChange = { useAmharic = it })
                }
            }
            item {
                OutlinedTextField(
                    value = messageBody,
                    onValueChange = { messageBody = it },
                    label = { Text("Message (${messageBody.length} chars)") },
                    minLines = 4,
                    modifier = Modifier.fillMaxWidth().testTag("sms_message_input")
                )
            }
            feedbackMsg?.let { msg -> item { Text(msg, color = MaterialTheme.colorScheme.primary) } }
            item {
                Button(
                    onClick = {
                        val phone = selectedStudent?.parentPhone.orEmpty()
                        val launched = SmsIntentService.launchSmsApp(context, phone, messageBody)
                        onLogSms(
                            SmsLogEntry(
                                studentName = selectedStudent?.fullName ?: "Student",
                                phoneNumber = phone,
                                message = messageBody,
                                templateName = selectedPreset.name,
                                success = launched,
                                errorMessage = if (launched) null else "Invalid or missing phone number"
                            )
                        )
                        feedbackMsg = if (launched) "Opened device SMS composer" else "Parent phone is missing or invalid (+2519/7...)"
                    },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp).testTag("send_sms_button")
                ) {
                    Icon(Icons.Default.Send, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Open SMS App")
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SmsHistoryScreen(
    logs: List<SmsLogEntry>,
    onBack: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("SMS Log") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") } }
            )
        },
        contentWindowInsets = WindowInsets.safeDrawing
    ) { padding ->
        if (logs.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Text("No parent SMS messages sent yet.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                items(logs, key = { it.id }) { log ->
                    Surface(
                        color = MaterialTheme.colorScheme.surface,
                        shape = MaterialTheme.shapes.medium,
                        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
                    ) {
                        Column(modifier = Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(log.studentName, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                                Text(
                                    DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(log.sentAtMillis)),
                                    style = MaterialTheme.typography.labelSmall
                                )
                            }
                            Text(log.phoneNumber.ifBlank { "No phone" }, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(log.message, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
        }
    }
}
