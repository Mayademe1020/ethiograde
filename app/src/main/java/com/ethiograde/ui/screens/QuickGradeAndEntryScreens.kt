package com.ethiograde.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Backspace
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.ethiograde.model.Assessment
import com.ethiograde.model.Student
import com.ethiograde.ui.theme.LocalEthioColors
import com.ethiograde.viewmodel.EthioGradeUiState

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuickGradeScreen(
    state: EthioGradeUiState,
    onBack: () -> Unit,
    onCreateAndScan: (List<String>) -> Unit
) {
    val lastTemplate = state.settings.lastQuickTemplate
    var count by remember { mutableIntStateOf(lastTemplate?.count ?: 10) }
    val answers = remember {
        mutableStateListOf<String>().apply {
            val init = lastTemplate?.answers?.takeIf { it.isNotEmpty() } ?: List(10) { "A" }
            addAll(init)
        }
    }

    fun resizeCount(newCount: Int) {
        val c = newCount.coerceIn(5, 50)
        count = c
        while (answers.size < c) answers.add("A")
        while (answers.size > c) answers.removeAt(answers.lastIndex)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Quick Grade") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                }
            )
        },
        bottomBar = {
            Surface(tonalElevation = 3.dp) {
                Button(
                    onClick = { onCreateAndScan(answers.toList()) },
                    modifier = Modifier.fillMaxWidth().padding(16.dp).navigationBarsPadding().heightIn(min = 50.dp).testTag("quick_grade_scan_button")
                ) {
                    Icon(Icons.Default.CameraAlt, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Save Key & Start Scanning (${answers.size}Q)")
                }
            }
        },
        contentWindowInsets = WindowInsets.safeDrawing
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            if (lastTemplate != null) {
                item {
                    Surface(
                        color = MaterialTheme.colorScheme.primaryContainer,
                        shape = MaterialTheme.shapes.medium,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier.padding(14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text("Repeat Last Template", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                                Text("${lastTemplate.count} Questions ready", style = MaterialTheme.typography.bodySmall)
                            }
                            Button(onClick = { onCreateAndScan(lastTemplate.answers) }) { Text("Use & Scan") }
                        }
                    }
                }
            }
            item {
                Text("Question Count: $count", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(5, 10, 15, 20, 30, 50).forEach { preset ->
                        FilterChip(
                            selected = count == preset,
                            onClick = { resizeCount(preset) },
                            label = { Text("$preset") }
                        )
                    }
                }
            }
            itemsIndexed(answers.toList()) { idx, currentAns ->
                Surface(
                    color = MaterialTheme.colorScheme.surface,
                    shape = MaterialTheme.shapes.medium,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Q${idx + 1}", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, modifier = Modifier.width(42.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.weight(1f)) {
                            listOf("A", "B", "C", "D", "E").forEach { opt ->
                                FilterChip(
                                    selected = currentAns == opt,
                                    onClick = { answers[idx] = opt },
                                    label = { Text(opt) },
                                    modifier = Modifier.weight(1f)
                                )
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
fun QuickEnterScreen(
    assessment: Assessment,
    state: EthioGradeUiState,
    onBack: () -> Unit,
    onSaveStudentAnswers: (Student, Map<Int, String>) -> Unit,
    onOpenFastCa: () -> Unit,
    onFinishReview: () -> Unit
) {
    val ethio = LocalEthioColors.current
    val classStudents = remember(state.students, assessment.classId) {
        if (assessment.classId.isNotBlank()) state.studentsInClass(assessment.classId) else state.students
    }
    val resultsByStudent = remember(state.scanResults, assessment.id) {
        state.resultsForAssessment(assessment.id).associateBy { it.studentId }
    }
    var selectedStudent by remember { mutableStateOf<Student?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Quick Enter • ${assessment.title}", maxLines = 1) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") } },
                actions = {
                    TextButton(onClick = onOpenFastCa) { Text("Numpad CA") }
                    TextButton(onClick = onFinishReview) { Text("Review") }
                }
            )
        },
        contentWindowInsets = WindowInsets.safeDrawing
    ) { padding ->
        if (classStudents.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Text("No students in this class yet.")
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                item {
                    Text(
                        "Tap any student to enter answers rapidly. Entered: ${resultsByStudent.size}/${classStudents.size}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                items(classStudents, key = { it.id }) { student ->
                    val existing = resultsByStudent[student.id]
                    Surface(
                        modifier = Modifier.fillMaxWidth().clickable { selectedStudent = student }.testTag("quick_enter_student_${student.id}"),
                        color = MaterialTheme.colorScheme.surface,
                        shape = MaterialTheme.shapes.medium,
                        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
                    ) {
                        Row(
                            modifier = Modifier.padding(14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Column {
                                Text(student.fullName, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                                Text(
                                    if (existing != null) "Entered: ${"%.1f".format(existing.totalScore)}/${"%.0f".format(existing.maxScore)} (${existing.grade})"
                                    else "Not entered yet",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = if (existing != null) ethio.success else MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            Icon(Icons.Default.Edit, contentDescription = "Enter answers", tint = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
            }
        }
    }

    selectedStudent?.let { st ->
        val existingAnswers = resultsByStudent[st.id]?.answers?.associate { it.questionNumber to it.detectedAnswer }.orEmpty()
        val draftMap = remember(st.id) {
            mutableStateMapOf<Int, String>().apply {
                assessment.questions.forEach { q ->
                    put(q.number, existingAnswers[q.number]?.takeUnless { it == "[MISSING]" }.orEmpty())
                }
            }
        }
        AlertDialog(
            onDismissRequest = { selectedStudent = null },
            title = { Text(st.fullName) },
            text = {
                LazyColumn(
                    modifier = Modifier.heightIn(max = 360.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(assessment.questions, key = { it.number }) { q ->
                        val ans = draftMap[q.number].orEmpty()
                        when (q.type) {
                            com.ethiograde.model.QuestionType.TRUE_FALSE -> {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Text("Q${q.number}", style = MaterialTheme.typography.labelLarge, modifier = Modifier.width(34.dp))
                                    listOf("True", "False").forEach { tf ->
                                        FilterChip(
                                            selected = ans.equals(tf, ignoreCase = true),
                                            onClick = { draftMap[q.number] = tf },
                                            label = { Text(tf) },
                                            modifier = Modifier.weight(1f)
                                        )
                                    }
                                }
                            }
                            com.ethiograde.model.QuestionType.MCQ,
                            com.ethiograde.model.QuestionType.MULTI_ANSWER -> {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Text("Q${q.number}", style = MaterialTheme.typography.labelLarge, modifier = Modifier.width(34.dp))
                                    listOf("A", "B", "C", "D", "E").forEach { opt ->
                                        FilterChip(
                                            selected = ans == opt,
                                            onClick = { draftMap[q.number] = opt },
                                            label = { Text(opt) },
                                            modifier = Modifier.weight(1f)
                                        )
                                    }
                                }
                            }
                            else -> {
                                OutlinedTextField(
                                    value = ans,
                                    onValueChange = { draftMap[q.number] = it },
                                    label = { Text("Q${q.number} (${q.type.shortCode})") },
                                    singleLine = true,
                                    modifier = Modifier.fillMaxWidth()
                                )
                            }
                        }
                    }
                }
            },
            confirmButton = {
                Button(onClick = {
                    onSaveStudentAnswers(st, draftMap.toMap())
                    selectedStudent = null
                }) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { selectedStudent = null }) { Text("Cancel") } }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CaFastEntryScreen(
    assessment: Assessment,
    state: EthioGradeUiState,
    onBack: () -> Unit,
    onSaveScore: (Student, Double) -> Unit
) {
    val ethio = LocalEthioColors.current
    val classStudents = remember(state.students, assessment.classId) {
        if (assessment.classId.isNotBlank()) state.studentsInClass(assessment.classId) else state.students
    }
    val resultsByStudent = remember(state.scanResults, assessment.id) {
        state.resultsForAssessment(assessment.id).associateBy { it.studentId }
    }
    var currentIndex by remember { mutableIntStateOf(0) }
    var inputBuffer by remember { mutableStateOf("") }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Fast CA • ${assessment.title} (/${assessment.maxScore.toInt()})", maxLines = 1) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") } }
            )
        },
        contentWindowInsets = WindowInsets.safeDrawing
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            if (classStudents.isEmpty()) {
                Box(modifier = Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                    Text("No students in this class.")
                }
            } else {
                LazyColumn(
                    modifier = Modifier.weight(1f).fillMaxWidth(),
                    contentPadding = PaddingValues(12.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    itemsIndexed(classStudents) { idx, st ->
                        val active = idx == currentIndex
                        val existing = resultsByStudent[st.id]
                        Surface(
                            modifier = Modifier.fillMaxWidth().clickable {
                                currentIndex = idx
                                inputBuffer = ""
                            },
                            color = if (active) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface,
                            shape = MaterialTheme.shapes.small,
                            border = BorderStroke(
                                if (active) 2.dp else 1.dp,
                                if (active) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
                            )
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text("${idx + 1}. ${st.fullName}", fontWeight = if (active) FontWeight.Bold else FontWeight.Medium)
                                Text(
                                    text = if (active && inputBuffer.isNotEmpty()) "$inputBuffer / ${assessment.maxScore.toInt()}"
                                    else if (existing != null) "${"%.1f".format(existing.totalScore)} / ${assessment.maxScore.toInt()}"
                                    else "—",
                                    color = if (existing != null) ethio.success else MaterialTheme.colorScheme.primary,
                                    fontWeight = FontWeight.Bold
                                )
                            }
                        }
                    }
                }

                // Persistent Rapid Numpad
                Surface(tonalElevation = 4.dp, modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        val rows = listOf(
                            listOf("1", "2", "3"),
                            listOf("4", "5", "6"),
                            listOf("7", "8", "9"),
                            listOf(".", "0", "BACK", "NEXT")
                        )
                        rows.forEach { row ->
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                                row.forEach { key ->
                                    when (key) {
                                        "BACK" -> FilledTonalButton(
                                            onClick = { if (inputBuffer.isNotEmpty()) inputBuffer = inputBuffer.dropLast(1) },
                                            modifier = Modifier.weight(1f).height(52.dp)
                                        ) {
                                            Icon(Icons.AutoMirrored.Filled.Backspace, contentDescription = "Backspace")
                                        }
                                        "NEXT" -> Button(
                                            onClick = {
                                                val st = classStudents.getOrNull(currentIndex) ?: return@Button
                                                val score = inputBuffer.toDoubleOrNull()
                                                if (score != null) {
                                                    onSaveScore(st, score)
                                                }
                                                inputBuffer = ""
                                                if (currentIndex < classStudents.lastIndex) currentIndex++
                                            },
                                            modifier = Modifier.weight(1f).height(52.dp).testTag("ca_numpad_submit")
                                        ) {
                                            Icon(Icons.Default.Check, contentDescription = "Confirm and advance")
                                        }
                                        else -> OutlinedButton(
                                            onClick = {
                                                if (key == "." && inputBuffer.contains(".")) return@OutlinedButton
                                                if (inputBuffer.length < 5) inputBuffer += key
                                            },
                                            modifier = Modifier.weight(1f).height(52.dp)
                                        ) {
                                            Text(key, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
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
}
