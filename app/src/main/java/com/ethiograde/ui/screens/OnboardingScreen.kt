package com.ethiograde.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.ethiograde.data.AppSettings
import com.ethiograde.ui.theme.LocalEthioColors
import kotlinx.coroutines.launch

private data class IntroPageData(
    val title: String,
    val subtitle: String,
    val icon: ImageVector,
    val tintColor: Color
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun OnboardingScreen(
    settings: AppSettings,
    onFinishSetup: (
        teacherName: String,
        schoolName: String,
        academicYear: String,
        grades: List<Int>,
        subjects: List<String>,
        seedDemo: Boolean
    ) -> Unit
) {
    val ethio = LocalEthioColors.current
    val pages = listOf(
        IntroPageData(
            title = "Scan & Grade in Seconds",
            subtitle = "Point your camera at bubble sheets or handwritten worksheets. Automatic OMR + OCR grades an entire class effortlessly.",
            icon = Icons.Default.DocumentScanner,
            tintColor = MaterialTheme.colorScheme.primary
        ),
        IntroPageData(
            title = "100% Offline Ready",
            subtitle = "Works reliably inside every classroom with zero internet connection, keeping student records private on your device.",
            icon = Icons.Default.WifiOff,
            tintColor = ethio.success
        ),
        IntroPageData(
            title = "Quick Enter & Fast CA",
            subtitle = "Enter continuous assessment marks with a custom rapid numpad or spreadsheet matrix built for Ethiopian schools.",
            icon = Icons.Default.Speed,
            tintColor = MaterialTheme.colorScheme.secondary
        ),
        IntroPageData(
            title = "Card Day & Analytics",
            subtitle = "Generate Ethiopian Ministry of Education broadsheets, 4-up PDF report cards, item analysis, and parent SMS updates.",
            icon = Icons.Default.BarChart,
            tintColor = ethio.info
        )
    )

    val pagerState = rememberPagerState(pageCount = { pages.size + 1 })
    val scope = rememberCoroutineScope()

    var teacherName by remember { mutableStateOf("") }
    var schoolName by remember { mutableStateOf("") }
    var academicYear by remember { mutableStateOf(settings.currentAcademicYear) }
    var showAddYear by remember { mutableStateOf(false) }
    var customYearInput by remember { mutableStateOf("") }
    var availableYears by remember { mutableStateOf(settings.academicYears) }
    val selectedGrades = remember { mutableStateListOf(5) }
    val selectedSubjects = remember { mutableStateListOf("Mathematics") }
    var customSubjectInput by remember { mutableStateOf("") }
    var seedDemo by remember { mutableStateOf(true) }
    var nameError by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        contentWindowInsets = WindowInsets.safeDrawing
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(horizontal = 20.dp, vertical = 12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "EthioGrade",
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Bold
                )
                if (pagerState.currentPage < pages.size) {
                    TextButton(
                        onClick = { scope.launch { pagerState.animateScrollToPage(pages.size) } },
                        modifier = Modifier.testTag("onboarding_skip_button")
                    ) {
                        Text("Skip")
                    }
                }
            }

            HorizontalPager(
                state = pagerState,
                modifier = Modifier.weight(1f)
            ) { page ->
                if (page < pages.size) {
                    val data = pages[page]
                    Column(
                        modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        Box(
                            modifier = Modifier
                                .size(116.dp)
                                .clip(CircleShape)
                                .background(data.tintColor.copy(alpha = 0.14f)),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                data.icon,
                                contentDescription = data.title,
                                tint = data.tintColor,
                                modifier = Modifier.size(56.dp)
                            )
                        }
                        Spacer(modifier = Modifier.height(28.dp))
                        Text(
                            text = data.title,
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.Bold,
                            textAlign = TextAlign.Center
                        )
                        Spacer(modifier = Modifier.height(12.dp))
                        Text(
                            text = data.subtitle,
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center
                        )
                    }
                } else {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .verticalScroll(rememberScrollState())
                            .padding(vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(14.dp)
                    ) {
                        Text(
                            text = "Set Up Your Classroom",
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            text = "Personalize your workspace — everything stays offline on your device.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )

                        OutlinedTextField(
                            value = teacherName,
                            onValueChange = { teacherName = it; nameError = false },
                            label = { Text("Your Name *") },
                            placeholder = { Text("e.g. Teacher Abebe") },
                            isError = nameError,
                            supportingText = if (nameError) { { Text("Please enter your name") } } else null,
                            leadingIcon = { Icon(Icons.Default.Person, contentDescription = null) },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth().testTag("onboarding_teacher_name_input")
                        )

                        OutlinedTextField(
                            value = schoolName,
                            onValueChange = { schoolName = it },
                            label = { Text("School Name (optional)") },
                            placeholder = { Text("e.g. Bole Secondary School") },
                            leadingIcon = { Icon(Icons.Default.School, contentDescription = null) },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth().testTag("onboarding_school_name_input")
                        )

                        Text("Academic Year", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            availableYears.forEach { yr ->
                                FilterChip(
                                    selected = academicYear == yr,
                                    onClick = { academicYear = yr },
                                    label = { Text(yr) }
                                )
                            }
                            AssistChip(
                                onClick = { showAddYear = true },
                                label = { Text("+ Year") },
                                leadingIcon = { Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(16.dp)) }
                            )
                        }

                        Text("Grade Levels Taught", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            (1..12).forEach { g ->
                                val selected = selectedGrades.contains(g)
                                FilterChip(
                                    selected = selected,
                                    onClick = {
                                        if (selected && selectedGrades.size > 1) selectedGrades.remove(g)
                                        else if (!selected) selectedGrades.add(g)
                                    },
                                    label = { Text("G$g") }
                                )
                            }
                        }

                        Text("Subjects", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        val subjectChoices = remember(settings.subjects, selectedSubjects.toList()) {
                            (settings.subjects + selectedSubjects).distinct()
                        }
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            subjectChoices.take(10).forEach { subj ->
                                val selected = selectedSubjects.contains(subj)
                                FilterChip(
                                    selected = selected,
                                    onClick = {
                                        if (selected && selectedSubjects.size > 1) selectedSubjects.remove(subj)
                                        else if (!selected) selectedSubjects.add(subj)
                                    },
                                    label = { Text(subj) }
                                )
                            }
                        }

                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedTextField(
                                value = customSubjectInput,
                                onValueChange = { customSubjectInput = it },
                                label = { Text("Add another subject") },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                            FilledTonalButton(
                                onClick = {
                                    val s = customSubjectInput.trim()
                                    if (s.isNotEmpty() && !selectedSubjects.contains(s)) {
                                        selectedSubjects.add(s)
                                        customSubjectInput = ""
                                    }
                                },
                                modifier = Modifier.heightIn(min = 48.dp)
                            ) { Text("Add") }
                        }

                        Surface(
                            color = MaterialTheme.colorScheme.surface,
                            shape = MaterialTheme.shapes.medium,
                            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth().clickable { seedDemo = !seedDemo }.padding(12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text("Include Sample Classroom Data", style = MaterialTheme.typography.titleSmall)
                                    Text(
                                        "Pre-loads Grade 5A Mathematics with 5 students and quizzes to explore right away",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                Switch(checked = seedDemo, onCheckedChange = { seedDemo = it })
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    repeat(pages.size + 1) { idx ->
                        val active = pagerState.currentPage == idx
                        Box(
                            modifier = Modifier
                                .height(8.dp)
                                .width(if (active) 24.dp else 8.dp)
                                .clip(RoundedCornerShape(4.dp))
                                .background(
                                    if (active) MaterialTheme.colorScheme.primary
                                    else MaterialTheme.colorScheme.outline
                                )
                        )
                    }
                }

                if (pagerState.currentPage < pages.size) {
                    Button(
                        onClick = { scope.launch { pagerState.animateScrollToPage(pagerState.currentPage + 1) } },
                        modifier = Modifier.heightIn(min = 48.dp).testTag("onboarding_next_button")
                    ) {
                        Text(if (pagerState.currentPage == pages.size - 1) "Get Started" else "Next")
                        Spacer(modifier = Modifier.width(6.dp))
                        Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null, modifier = Modifier.size(18.dp))
                    }
                } else {
                    Button(
                        onClick = {
                            if (teacherName.trim().isEmpty()) {
                                nameError = true
                            } else {
                                onFinishSetup(
                                    teacherName.trim(),
                                    schoolName.trim(),
                                    academicYear,
                                    selectedGrades.toList(),
                                    selectedSubjects.toList(),
                                    seedDemo
                                )
                            }
                        },
                        modifier = Modifier.heightIn(min = 48.dp).testTag("onboarding_finish_button")
                    ) {
                        Icon(Icons.Default.Check, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("Finish Setup")
                    }
                }
            }
        }
    }

    if (showAddYear) {
        AlertDialog(
            onDismissRequest = { showAddYear = false },
            title = { Text("Add Academic Year") },
            text = {
                OutlinedTextField(
                    value = customYearInput,
                    onValueChange = { customYearInput = it },
                    label = { Text("Academic Year (e.g. 2025-2026 or 2018 E.C.)") },
                    singleLine = true
                )
            },
            confirmButton = {
                Button(onClick = {
                    val y = customYearInput.trim()
                    if (y.isNotEmpty()) {
                        availableYears = (listOf(y) + availableYears).distinct()
                        academicYear = y
                    }
                    customYearInput = ""
                    showAddYear = false
                }) { Text("Add") }
            },
            dismissButton = { TextButton(onClick = { showAddYear = false }) { Text("Cancel") } }
        )
    }
}
