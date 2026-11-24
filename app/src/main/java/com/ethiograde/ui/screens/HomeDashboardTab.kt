package com.ethiograde.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.ethiograde.model.Assessment
import com.ethiograde.model.ClassInfo
import com.ethiograde.model.ExamDayStartMode
import com.ethiograde.service.EthiopianCalendarService
import com.ethiograde.ui.components.AssessmentCard
import com.ethiograde.ui.components.CreateOrEditClassDialog
import com.ethiograde.ui.components.MiniStatCard
import com.ethiograde.ui.components.OfflineBadge
import com.ethiograde.ui.theme.LocalEthioColors
import com.ethiograde.viewmodel.DashboardPrimaryAction
import com.ethiograde.viewmodel.EthioGradeUiState

@Composable
fun HomeDashboardTab(
    state: EthioGradeUiState,
    onSetAcademicYear: (String) -> Unit,
    onCreateClass: (ClassInfo) -> Unit,
    onNavigateCreateExam: (ExamDayStartMode) -> Unit,
    onNavigateAnswerKey: (String) -> Unit,
    onNavigateScan: (String) -> Unit,
    onNavigateReview: (String) -> Unit,
    onNavigateQuickEnter: (String) -> Unit,
    onNavigateQuickGrade: () -> Unit,
    onNavigateHomeroomCard: () -> Unit,
    onNavigateAnalytics: () -> Unit,
    onNavigateClassDetail: (String) -> Unit,
    onNavigateStudentDetail: (String) -> Unit,
    onSwitchToTab: (Int) -> Unit
) {
    val ethio = LocalEthioColors.current
    val primaryAction = remember(state.assessments, state.scanResults, state.drafts) {
        state.resolveDashboardAction()
    }
    var searchQuery by remember { mutableStateOf("") }
    var showYearDialog by remember { mutableStateOf(false) }
    var showCreateClassDialog by remember { mutableStateOf(false) }
    var showCaPickerDialog by remember { mutableStateOf(false) }

    val matchingStudents = remember(searchQuery, state.students) {
        if (searchQuery.trim().length < 2) emptyList()
        else state.students.filter {
            it.fullName.contains(searchQuery.trim(), ignoreCase = true) ||
                it.studentId.contains(searchQuery.trim(), ignoreCase = true)
        }.take(5)
    }

    val ethiopicToday = remember { EthiopianCalendarService.toEthiopic().formatted() }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Header Welcome Card
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "Welcome, ${state.settings.teacherName.ifBlank { "Teacher" }}",
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            text = listOfNotNull(
                                state.settings.schoolName.takeIf { it.isNotBlank() },
                                ethiopicToday
                            ).joinToString(" • "),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    OfflineBadge()
                }

                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    AssistChip(
                        onClick = { showYearDialog = true },
                        label = { Text("AY ${state.settings.currentAcademicYear}") },
                        leadingIcon = { Icon(Icons.Default.CalendarToday, contentDescription = "Academic Year", modifier = Modifier.size(16.dp)) },
                        modifier = Modifier.testTag("academic_year_chip")
                    )
                    AssistChip(
                        onClick = onNavigateAnalytics,
                        label = { Text("Class Analytics") },
                        leadingIcon = { Icon(Icons.Default.Insights, contentDescription = "Class Analytics", modifier = Modifier.size(16.dp)) },
                        modifier = Modifier.testTag("open_analytics_chip")
                    )
                }
            }
        }

        // Student Quick Search Bar
        item {
            Column {
                OutlinedTextField(
                    value = searchQuery,
                    onValueChange = { searchQuery = it },
                    placeholder = { Text("Find a student by name or ID…") },
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                    trailingIcon = {
                        if (searchQuery.isNotEmpty()) {
                            IconButton(onClick = { searchQuery = "" }) {
                                Icon(Icons.Default.Close, contentDescription = "Clear search")
                            }
                        }
                    },
                    singleLine = true,
                    shape = MaterialTheme.shapes.medium,
                    modifier = Modifier.fillMaxWidth().testTag("dashboard_student_search")
                )
                if (matchingStudents.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(6.dp))
                    Surface(
                        color = MaterialTheme.colorScheme.surface,
                        shape = MaterialTheme.shapes.medium,
                        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
                    ) {
                        Column {
                            matchingStudents.forEach { st ->
                                ListItem(
                                    headlineContent = { Text(st.fullName, fontWeight = FontWeight.SemiBold) },
                                    supportingContent = { Text("${st.className.ifBlank { "Unassigned" }} • ID ${st.studentId.ifBlank { "—" }}") },
                                    leadingContent = {
                                        CircleAvatar(st.initials)
                                    },
                                    trailingContent = { Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null) },
                                    modifier = Modifier.clickable {
                                        searchQuery = ""
                                        onNavigateStudentDetail(st.id)
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }

        // Priority Primary Action Card
        item {
            PrimaryActionCard(
                action = primaryAction,
                onClick = {
                    when (primaryAction) {
                        is DashboardPrimaryAction.ResumeDraft -> onNavigateQuickEnter(primaryAction.assessment.id)
                        is DashboardPrimaryAction.FinishAnswerKey -> onNavigateAnswerKey(primaryAction.assessment.id)
                        is DashboardPrimaryAction.ReviewPapers -> onNavigateReview(primaryAction.assessment.id)
                        is DashboardPrimaryAction.StartScanning -> onNavigateScan(primaryAction.assessment.id)
                        DashboardPrimaryAction.DefaultGradePapers -> onNavigateQuickGrade()
                    }
                }
            )
        }

        // Summary Stats Row
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                MiniStatCard(
                    label = "Classes",
                    value = "${state.classes.size}",
                    icon = Icons.Default.Class,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.weight(1f)
                )
                MiniStatCard(
                    label = "Students",
                    value = "${state.students.size}",
                    icon = Icons.Default.Groups,
                    tint = ethio.info,
                    modifier = Modifier.weight(1f)
                )
                MiniStatCard(
                    label = "Graded",
                    value = "${state.scanResults.size}",
                    icon = Icons.Default.TaskAlt,
                    tint = ethio.success,
                    modifier = Modifier.weight(1f)
                )
            }
        }

        // Quick Actions 2x2 Grid
        item {
            Text(
                text = "Quick Actions",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(8.dp))
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                    QuickActionTile(
                        title = "Create Exam",
                        subtitle = "MCQ, T/F, Short Answer",
                        icon = Icons.Default.NoteAdd,
                        tint = MaterialTheme.colorScheme.primary,
                        testTag = "quick_action_create_exam",
                        onClick = { onNavigateCreateExam(ExamDayStartMode.CREATE_FORM) },
                        modifier = Modifier.weight(1f)
                    )
                    QuickActionTile(
                        title = "Create Class",
                        subtitle = "Roster & Attendance",
                        icon = Icons.Default.GroupAdd,
                        tint = ethio.info,
                        testTag = "quick_action_create_class",
                        onClick = { showCreateClassDialog = true },
                        modifier = Modifier.weight(1f)
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                    QuickActionTile(
                        title = "Card Day",
                        subtitle = "የካርድ ቀን • Report Cards",
                        icon = Icons.Default.Badge,
                        tint = MaterialTheme.colorScheme.secondary,
                        testTag = "quick_action_card_day",
                        onClick = onNavigateHomeroomCard,
                        modifier = Modifier.weight(1f)
                    )
                    QuickActionTile(
                        title = "Fast Enter CA",
                        subtitle = "ፈጣን ምዘና • Rapid Numpad",
                        icon = Icons.Default.Dialpad,
                        tint = ethio.success,
                        testTag = "quick_action_fast_ca",
                        onClick = { showCaPickerDialog = true },
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }

        // My Classes Horizontal Carousel
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("My Classes", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                TextButton(onClick = { onSwitchToTab(1) }) { Text("See All") }
            }
            if (state.classes.isEmpty()) {
                Surface(
                    color = MaterialTheme.colorScheme.surface,
                    shape = MaterialTheme.shapes.medium,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                    modifier = Modifier.fillMaxWidth().clickable { showCreateClassDialog = true }
                ) {
                    Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.AddCircleOutline, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                        Spacer(modifier = Modifier.width(12.dp))
                        Text("Create your first class to manage students and attendance")
                    }
                }
            } else {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(state.classes, key = { it.id }) { cls ->
                        val count = state.studentsInClass(cls.id).size
                        Surface(
                            modifier = Modifier
                                .width(200.dp)
                                .clickable { onNavigateClassDetail(cls.id) },
                            color = MaterialTheme.colorScheme.surface,
                            shape = MaterialTheme.shapes.medium,
                            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
                        ) {
                            Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Row(horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                                    Text(
                                        text = "Grade ${cls.grade}${cls.section}",
                                        style = MaterialTheme.typography.labelMedium,
                                        color = MaterialTheme.colorScheme.primary,
                                        fontWeight = FontWeight.Bold
                                    )
                                    if (cls.isHomeroom) {
                                        Icon(Icons.Default.Home, contentDescription = "Homeroom", tint = MaterialTheme.colorScheme.secondary, modifier = Modifier.size(16.dp))
                                    }
                                }
                                Text(
                                    text = cls.subject,
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.Bold,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Text(
                                    text = "$count students",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }
            }
        }

        // Recent Assessments
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Recent Assessments", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                TextButton(onClick = { onSwitchToTab(2) }) { Text("View All") }
            }
        }

        if (state.assessments.isEmpty()) {
            item {
                Surface(
                    color = MaterialTheme.colorScheme.surface,
                    shape = MaterialTheme.shapes.medium,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(
                        modifier = Modifier.padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(Icons.Default.Quiz, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(36.dp))
                        Text("No assessments yet", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                        Button(onClick = { onNavigateCreateExam(ExamDayStartMode.CREATE_FORM) }) {
                            Text("Create Exam")
                        }
                    }
                }
            }
        } else {
            items(state.assessments.take(4), key = { it.id }) { assessment ->
                val results = state.resultsForAssessment(assessment.id)
                AssessmentCard(
                    assessment = assessment,
                    results = results,
                    onPrimaryAction = {
                        when {
                            !assessment.hasCompleteAnswerKey -> onNavigateAnswerKey(assessment.id)
                            results.any { it.requiresTeacherAction(assessment.answerKeyFingerprint) } -> onNavigateReview(assessment.id)
                            assessment.isCompleted -> onNavigateReview(assessment.id)
                            else -> onNavigateScan(assessment.id)
                        }
                    },
                    onOpenCard = { onNavigateReview(assessment.id) }
                )
            }
        }
    }

    if (showYearDialog) {
        var newYear by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { showYearDialog = false },
            title = { Text("Academic Year") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    state.settings.academicYears.forEach { yr ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onSetAcademicYear(yr); showYearDialog = false }
                                .padding(vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            RadioButton(selected = yr == state.settings.currentAcademicYear, onClick = { onSetAcademicYear(yr); showYearDialog = false })
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(yr, style = MaterialTheme.typography.bodyLarge)
                        }
                    }
                    OutlinedTextField(
                        value = newYear,
                        onValueChange = { newYear = it },
                        label = { Text("Add Year (e.g. 2025-2026)") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                Button(onClick = {
                    if (newYear.isNotBlank()) onSetAcademicYear(newYear.trim())
                    showYearDialog = false
                }) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { showYearDialog = false }) { Text("Close") } }
        )
    }

    if (showCreateClassDialog) {
        CreateOrEditClassDialog(
            subjects = state.settings.subjects,
            academicYear = state.settings.currentAcademicYear,
            onDismiss = { showCreateClassDialog = false },
            onSave = {
                onCreateClass(it)
                showCreateClassDialog = false
            }
        )
    }

    if (showCaPickerDialog) {
        AlertDialog(
            onDismissRequest = { showCaPickerDialog = false },
            title = { Text("Fast Enter CA (ፈጣን ምዘና)") },
            text = {
                if (state.assessments.isEmpty()) {
                    Text("Create an assessment first to enter Continuous Assessment scores.")
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Pick an assessment to launch rapid numpad entry:")
                        state.assessments.take(5).forEach { a ->
                            OutlinedButton(
                                onClick = { showCaPickerDialog = false; onNavigateQuickEnter(a.id) },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text("${a.title} (${a.maxScore.toInt()} pts)", maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    showCaPickerDialog = false
                    onNavigateCreateExam(ExamDayStartMode.CA_FAST_ENTRY)
                }) { Text("New CA Exam") }
            },
            dismissButton = { TextButton(onClick = { showCaPickerDialog = false }) { Text("Cancel") } }
        )
    }
}

@Composable
private fun PrimaryActionCard(action: DashboardPrimaryAction, onClick: () -> Unit) {
    val (title, subtitle, buttonLabel, icon) = when (action) {
        is DashboardPrimaryAction.ResumeDraft -> Quad(
            "Resume Grading",
            "${action.assessment.title} • ${action.draft.completedCount} entered (${action.draft.ageLabel})",
            "Resume",
            Icons.Default.PlayArrow
        )
        is DashboardPrimaryAction.FinishAnswerKey -> Quad(
            "Finish Answer Key",
            "${action.assessment.title} needs answers before scanning",
            "Set Key",
            Icons.Default.Key
        )
        is DashboardPrimaryAction.ReviewPapers -> Quad(
            "Review Flagged Papers",
            "${action.count} paper(s) in ${action.assessment.title} need attention",
            "Review",
            Icons.Default.RateReview
        )
        is DashboardPrimaryAction.StartScanning -> Quad(
            "Ready to Scan",
            "${action.assessment.title} answer key is confirmed",
            "Scan Now",
            Icons.Default.CameraAlt
        )
        DashboardPrimaryAction.DefaultGradePapers -> Quad(
            "Grade Papers Offline",
            "Instant bubble sheet OMR or handwriting OCR with Quick Grade",
            "Quick Grade",
            Icons.Default.FlashOn
        )
    }

    Surface(
        modifier = Modifier.fillMaxWidth().clickable { onClick() }.testTag("dashboard_primary_action_card"),
        color = MaterialTheme.colorScheme.primary,
        shape = MaterialTheme.shapes.large
    ) {
        Row(
            modifier = Modifier.padding(18.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onPrimary,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.88f)
                )
                Spacer(modifier = Modifier.height(6.dp))
                Surface(
                    color = MaterialTheme.colorScheme.onPrimary,
                    shape = RoundedCornerShape(10.dp)
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = buttonLabel,
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.primary,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
            Spacer(modifier = Modifier.width(12.dp))
            Box(
                modifier = Modifier.size(52.dp).clip(CircleShape).background(MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.16f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(icon, contentDescription = title, tint = MaterialTheme.colorScheme.onPrimary, modifier = Modifier.size(28.dp))
            }
        }
    }
}

@Composable
private fun QuickActionTile(
    title: String,
    subtitle: String,
    icon: ImageVector,
    tint: Color,
    testTag: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier
            .heightIn(min = 84.dp)
            .testTag(testTag)
            .clickable { onClick() },
        color = MaterialTheme.colorScheme.surface,
        shape = MaterialTheme.shapes.medium,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
    ) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Box(
                modifier = Modifier.size(34.dp).clip(RoundedCornerShape(10.dp)).background(tint.copy(alpha = 0.12f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(icon, contentDescription = title, tint = tint, modifier = Modifier.size(20.dp))
            }
            Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
            Text(
                subtitle,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
fun CircleAvatar(initials: String, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .size(40.dp)
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.primaryContainer),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = initials,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onPrimaryContainer,
            fontWeight = FontWeight.Bold
        )
    }
}

private data class Quad<A, B, C, D>(val first: A, val second: B, val third: C, val fourth: D)
