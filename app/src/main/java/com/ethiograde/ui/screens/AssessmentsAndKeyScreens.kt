package com.ethiograde.ui.screens

import androidx.activity.compose.BackHandler
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
import androidx.compose.ui.unit.dp
import com.ethiograde.model.*
import com.ethiograde.service.AnswerKeyParser
import com.ethiograde.service.PdfExportAndCsvService
import com.ethiograde.ui.components.AssessmentCard
import com.ethiograde.viewmodel.EthioGradeUiState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun AssessmentsTab(
    state: EthioGradeUiState,
    onCreateExam: () -> Unit,
    onQuickGrade: () -> Unit,
    onOpenAnswerKey: (String) -> Unit,
    onOpenScan: (String) -> Unit,
    onOpenReview: (String) -> Unit,
    onDeleteAssessment: (String) -> Unit
) {
    var showCompleted by remember { mutableStateOf(false) }
    var deleteConfirm by remember { mutableStateOf<Assessment?>(null) }

    val list = remember(state.assessments, showCompleted) {
        state.assessments.filter { it.isCompleted == showCompleted }
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Text("Assessments", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                Button(
                    onClick = onCreateExam,
                    modifier = Modifier.weight(1f).heightIn(min = 48.dp).testTag("assessments_create_exam_button")
                ) {
                    Icon(Icons.Default.NoteAdd, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Create Exam")
                }
                FilledTonalButton(
                    onClick = onQuickGrade,
                    modifier = Modifier.weight(1f).heightIn(min = 48.dp).testTag("assessments_quick_grade_button")
                ) {
                    Icon(Icons.Default.FlashOn, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Quick Grade")
                }
            }
        }
        item {
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                SegmentedButton(
                    selected = !showCompleted,
                    onClick = { showCompleted = false },
                    shape = SegmentedButtonDefaults.itemShape(0, 2)
                ) {
                    Text("Active (${state.assessments.count { !it.isCompleted }})")
                }
                SegmentedButton(
                    selected = showCompleted,
                    onClick = { showCompleted = true },
                    shape = SegmentedButtonDefaults.itemShape(1, 2)
                ) {
                    Text("Completed (${state.assessments.count { it.isCompleted }})")
                }
            }
        }
        if (list.isEmpty()) {
            item {
                Surface(
                    color = MaterialTheme.colorScheme.surface,
                    shape = MaterialTheme.shapes.medium,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(
                        modifier = Modifier.padding(28.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(Icons.Default.Assignment, contentDescription = null, modifier = Modifier.size(40.dp), tint = MaterialTheme.colorScheme.primary)
                        Text(if (showCompleted) "No completed assessments yet" else "No active assessments", style = MaterialTheme.typography.titleSmall)
                    }
                }
            }
        } else {
            items(list, key = { it.id }) { a ->
                val results = state.resultsForAssessment(a.id)
                AssessmentCard(
                    assessment = a,
                    results = results,
                    onPrimaryAction = {
                        when {
                            !a.hasCompleteAnswerKey -> onOpenAnswerKey(a.id)
                            results.any { it.requiresTeacherAction(a.answerKeyFingerprint) } -> onOpenReview(a.id)
                            a.isCompleted -> onOpenReview(a.id)
                            else -> onOpenScan(a.id)
                        }
                    },
                    onOpenCard = { onOpenReview(a.id) },
                    onDelete = { deleteConfirm = a }
                )
            }
        }
    }

    deleteConfirm?.let { a ->
        AlertDialog(
            onDismissRequest = { deleteConfirm = null },
            title = { Text("Delete Assessment?") },
            text = { Text("Delete \"${a.title}\" and all its scanned student results?") },
            confirmButton = {
                Button(
                    onClick = { onDeleteAssessment(a.id); deleteConfirm = null },
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
                ) { Text("Delete") }
            },
            dismissButton = { TextButton(onClick = { deleteConfirm = null }) { Text("Cancel") } }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExamDayCreateScreen(
    startMode: ExamDayStartMode,
    state: EthioGradeUiState,
    onBack: () -> Unit,
    onCreatedForKey: (Assessment) -> Unit,
    onCreatedForFastCa: (Assessment) -> Unit
) {
    var title by remember { mutableStateOf("") }
    var selectedSubject by remember { mutableStateOf(state.settings.subjects.firstOrNull() ?: "Mathematics") }
    var selectedClass by remember { mutableStateOf(state.classes.firstOrNull()) }
    var questionCountText by remember { mutableStateOf("20") }
    var category by remember { mutableStateOf(if (startMode == ExamDayStartMode.CA_FAST_ENTRY) "CA" else "Quiz") }
    var semester by remember { mutableStateOf("Semester 1") }
    var errorMsg by remember { mutableStateOf<String?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (startMode == ExamDayStartMode.CA_FAST_ENTRY) "New Continuous Assessment" else "Create Exam") },
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
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            item {
                OutlinedTextField(
                    value = title,
                    onValueChange = { title = it; errorMsg = null },
                    label = { Text("Assessment Title *") },
                    placeholder = { Text("e.g. Unit 2 Mathematics Quiz") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().testTag("exam_title_input")
                )
            }
            item {
                Text("Subject", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Spacer(modifier = Modifier.height(6.dp))
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(state.settings.subjects) { subj ->
                        FilterChip(
                            selected = selectedSubject == subj,
                            onClick = { selectedSubject = subj },
                            label = { Text(subj) }
                        )
                    }
                }
            }
            if (state.classes.isNotEmpty()) {
                item {
                    Text("Class", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    Spacer(modifier = Modifier.height(6.dp))
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(state.classes, key = { it.id }) { cls ->
                            FilterChip(
                                selected = selectedClass?.id == cls.id,
                                onClick = { selectedClass = cls; selectedSubject = cls.subject },
                                label = { Text(cls.displayName) }
                            )
                        }
                    }
                }
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedTextField(
                        value = questionCountText,
                        onValueChange = { questionCountText = it.filter(Char::isDigit).take(3) },
                        label = { Text("Questions (1-200)") },
                        singleLine = true,
                        modifier = Modifier.weight(1f).testTag("exam_question_count_input")
                    )
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("Category", style = MaterialTheme.typography.labelMedium)
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            items(listOf("Quiz", "Midterm", "Final", "CA")) { cat ->
                                FilterChip(selected = category == cat, onClick = { category = cat }, label = { Text(cat) })
                            }
                        }
                    }
                }
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("Semester 1", "Semester 2").forEach { sem ->
                        FilterChip(selected = semester == sem, onClick = { semester = sem }, label = { Text(sem) })
                    }
                }
            }
            errorMsg?.let { item { Text(it, color = MaterialTheme.colorScheme.error) } }
            item {
                Spacer(modifier = Modifier.height(8.dp))
                Button(
                    onClick = {
                        val qCount = questionCountText.toIntOrNull()?.coerceIn(1, 200) ?: 20
                        val finalTitle = title.trim().ifEmpty { "$selectedSubject $category" }
                        val questions = (1..qCount).map { num ->
                            Question(number = num, text = "Question $num", type = QuestionType.MCQ, correctAnswer = "", points = 1.0)
                        }
                        val created = Assessment(
                            title = finalTitle,
                            subject = selectedSubject,
                            classId = selectedClass?.id.orEmpty(),
                            className = selectedClass?.displayName.orEmpty(),
                            gradeLevel = selectedClass?.grade ?: 5,
                            academicYear = state.settings.currentAcademicYear,
                            rubricType = state.settings.defaultRubric,
                            semester = semester,
                            category = category,
                            questions = questions,
                            sections = listOf(AnswerKeySection(title = "Part I", type = QuestionType.MCQ, start = 1, end = qCount))
                        )
                        if (startMode == ExamDayStartMode.CA_FAST_ENTRY) onCreatedForFastCa(created)
                        else onCreatedForKey(created)
                    },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp).testTag("create_exam_continue_button")
                ) {
                    Text(if (startMode == ExamDayStartMode.CA_FAST_ENTRY) "Open Fast Entry Numpad" else "Set Answer Key")
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AnswerKeyScreen(
    assessment: Assessment,
    onBack: () -> Unit,
    onSaveAssessment: (Assessment) -> Unit,
    onOpenSections: () -> Unit,
    onStartScanning: () -> Unit,
    onOpenQuickEnter: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var questions by remember(assessment.id, assessment.questions) { mutableStateOf(assessment.questions) }
    var isLocked by remember { mutableStateOf(false) }
    var showBulkPaste by remember { mutableStateOf(false) }
    var bulkInput by remember { mutableStateOf("") }
    var editingShortQuestion by remember { mutableStateOf<Question?>(null) }
    var onlyEmpty by remember { mutableStateOf(false) }

    val answeredCount = questions.count { it.hasAnswer }
    val filtered = remember(questions, onlyEmpty) {
        if (onlyEmpty) questions.filter { !it.hasAnswer || it.isFlagged } else questions
    }

    fun updateQuestion(qNum: Int, transform: (Question) -> Question) {
        if (isLocked) return
        questions = questions.map { if (it.number == qNum) transform(it) else it }
    }

    fun persist(confirm: Boolean = false) {
        val stamped = assessment.copy(
            questions = questions,
            isAnswerKeyConfirmed = confirm || assessment.isAnswerKeyConfirmed,
            updatedAtMillis = System.currentTimeMillis()
        )
        onSaveAssessment(stamped)
    }

    BackHandler {
        persist()
        onBack()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("Answer Key • ${assessment.title}", maxLines = 1)
                        Text("$answeredCount/${questions.size} answered", style = MaterialTheme.typography.labelSmall)
                    }
                },
                navigationIcon = {
                    IconButton(onClick = { persist(); onBack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { isLocked = !isLocked }) {
                        Icon(
                            if (isLocked) Icons.Default.Lock else Icons.Default.LockOpen,
                            contentDescription = "Toggle key lock"
                        )
                    }
                    IconButton(onClick = {
                        scope.launch {
                            val file = withContext(Dispatchers.IO) {
                                PdfExportAndCsvService.generatePrintableBubbleSheetPdf(context, assessment)
                            }
                            PdfExportAndCsvService.shareFile(context, file, "application/pdf", "${assessment.title} Answer Sheet")
                        }
                    }) {
                        Icon(Icons.Default.Print, contentDescription = "Print Bubble Sheet PDF")
                    }
                }
            )
        },
        bottomBar = {
            Surface(tonalElevation = 3.dp) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(12.dp).navigationBarsPadding(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(
                        onClick = { persist(true); onOpenQuickEnter() },
                        modifier = Modifier.weight(1f).heightIn(min = 48.dp).testTag("key_quick_enter_button")
                    ) {
                        Text("Quick Enter")
                    }
                    Button(
                        onClick = { persist(true); onStartScanning() },
                        enabled = answeredCount > 0,
                        modifier = Modifier.weight(1f).heightIn(min = 48.dp).testTag("key_save_and_scan_button")
                    ) {
                        Icon(Icons.Default.CameraAlt, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("Save & Scan")
                    }
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
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    FilledTonalButton(onClick = onOpenSections, modifier = Modifier.weight(1f).testTag("key_sections_button")) {
                        Icon(Icons.Default.ViewList, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Sections")
                    }
                    FilledTonalButton(onClick = { showBulkPaste = true }, modifier = Modifier.weight(1f).testTag("key_bulk_paste_button")) {
                        Icon(Icons.Default.ContentPaste, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Paste Key")
                    }
                    FilterChip(
                        selected = onlyEmpty,
                        onClick = { onlyEmpty = !onlyEmpty },
                        label = { Text("Missing") }
                    )
                }
            }

            // Answer Distribution Bar for MCQ
            item {
                val dist = listOf("A", "B", "C", "D", "E").associateWith { opt ->
                    questions.count { it.correctAnswer.equals(opt, true) }
                }
                if (dist.values.sum() > 0) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        dist.forEach { (opt, count) ->
                            Surface(
                                color = MaterialTheme.colorScheme.surfaceVariant,
                                shape = MaterialTheme.shapes.small,
                                modifier = Modifier.weight(1f)
                            ) {
                                Text(
                                    "$opt:$count",
                                    style = MaterialTheme.typography.labelSmall,
                                    modifier = Modifier.padding(vertical = 4.dp, horizontal = 6.dp)
                                )
                            }
                        }
                    }
                }
            }

            items(filtered, key = { it.number }) { q ->
                Surface(
                    color = MaterialTheme.colorScheme.surface,
                    shape = MaterialTheme.shapes.medium,
                    border = BorderStroke(
                        1.dp,
                        if (q.hasAnswer) MaterialTheme.colorScheme.outline else MaterialTheme.colorScheme.error.copy(alpha = 0.5f)
                    )
                ) {
                    Column(modifier = Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                "Q${q.number} • ${q.type.shortCode} (${q.points.toInt()}pt)",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.Bold
                            )
                            Text(
                                q.correctAnswer.ifBlank { "Not set" },
                                style = MaterialTheme.typography.labelLarge,
                                color = if (q.hasAnswer) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
                                fontWeight = FontWeight.Bold
                            )
                        }

                        when (q.type) {
                            QuestionType.MCQ -> {
                                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    listOf("A", "B", "C", "D", "E").forEach { opt ->
                                        val selected = q.correctAnswer.equals(opt, true)
                                        FilterChip(
                                            selected = selected,
                                            onClick = { updateQuestion(q.number) { it.copy(correctAnswer = opt) } },
                                            label = { Text(opt) },
                                            modifier = Modifier.weight(1f)
                                        )
                                    }
                                }
                            }
                            QuestionType.TRUE_FALSE -> {
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    listOf("True", "False").forEach { tf ->
                                        FilterChip(
                                            selected = q.correctAnswer.equals(tf, true),
                                            onClick = { updateQuestion(q.number) { it.copy(correctAnswer = tf) } },
                                            label = { Text(tf) },
                                            modifier = Modifier.weight(1f)
                                        )
                                    }
                                }
                            }
                            QuestionType.MULTI_ANSWER -> {
                                val currentSet = q.correctAnswer.split(",").filter { it.isNotBlank() }.toMutableSet()
                                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    listOf("A", "B", "C", "D", "E").forEach { opt ->
                                        val selected = currentSet.contains(opt)
                                        FilterChip(
                                            selected = selected,
                                            onClick = {
                                                if (selected) currentSet.remove(opt) else currentSet.add(opt)
                                                updateQuestion(q.number) { it.copy(correctAnswer = currentSet.sorted().joinToString(",")) }
                                            },
                                            label = { Text(opt) },
                                            modifier = Modifier.weight(1f)
                                        )
                                    }
                                }
                            }
                            else -> {
                                OutlinedButton(
                                    onClick = { if (!isLocked) editingShortQuestion = q },
                                    modifier = Modifier.fillMaxWidth()
                                ) {
                                    Text(q.correctAnswer.ifBlank { "Tap to type expected answer" })
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (showBulkPaste) {
        AlertDialog(
            onDismissRequest = { showBulkPaste = false },
            title = { Text("Paste Answer Key") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Separate answers by commas (e.g. A, B, C, True, Addis Ababa):")
                    OutlinedTextField(
                        value = bulkInput,
                        onValueChange = { bulkInput = it },
                        minLines = 3,
                        modifier = Modifier.fillMaxWidth().testTag("bulk_paste_input")
                    )
                }
            },
            confirmButton = {
                Button(onClick = {
                    val parsed = AnswerKeyParser.parseBulkPaste(bulkInput)
                    if (parsed.isNotEmpty()) {
                        val map = parsed.associateBy { it.number }
                        questions = questions.map { q ->
                            map[q.number]?.let { p -> q.copy(correctAnswer = p.answer, type = p.type) } ?: q
                        }
                    }
                    bulkInput = ""
                    showBulkPaste = false
                }) { Text("Apply") }
            },
            dismissButton = { TextButton(onClick = { showBulkPaste = false }) { Text("Cancel") } }
        )
    }

    editingShortQuestion?.let { q ->
        var textVal by remember { mutableStateOf(q.correctAnswer) }
        var ptsVal by remember { mutableStateOf(q.points.toString()) }
        AlertDialog(
            onDismissRequest = { editingShortQuestion = null },
            title = { Text("Q${q.number} Answer") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = textVal,
                        onValueChange = { textVal = it },
                        label = { Text("Expected Answer") },
                        minLines = 2
                    )
                    OutlinedTextField(
                        value = ptsVal,
                        onValueChange = { ptsVal = it },
                        label = { Text("Points") },
                        singleLine = true
                    )
                }
            },
            confirmButton = {
                Button(onClick = {
                    updateQuestion(q.number) {
                        it.copy(correctAnswer = textVal.trim(), points = ptsVal.toDoubleOrNull()?.coerceAtLeast(0.5) ?: it.points)
                    }
                    editingShortQuestion = null
                }) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { editingShortQuestion = null }) { Text("Cancel") } }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AnswerKeySectionSetupScreen(
    assessment: Assessment,
    onBack: () -> Unit,
    onApplySections: (Assessment) -> Unit
) {
    val sections = remember(assessment.id) {
        mutableStateListOf<AnswerKeySection>().apply {
            if (assessment.sections.isNotEmpty()) addAll(assessment.sections)
            else add(AnswerKeySection(title = "Part I", type = QuestionType.MCQ, start = 1, end = assessment.questionCount.coerceAtLeast(1)))
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Section Setup") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") } }
            )
        },
        contentWindowInsets = WindowInsets.safeDrawing
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            items(sections.indices.toList()) { idx ->
                val sec = sections[idx]
                Surface(
                    color = MaterialTheme.colorScheme.surface,
                    shape = MaterialTheme.shapes.medium,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
                ) {
                    Column(modifier = Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(
                            value = sec.title,
                            onValueChange = { sections[idx] = sec.copy(title = it) },
                            label = { Text("Section Title") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth()
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedTextField(
                                value = sec.start.toString(),
                                onValueChange = { sections[idx] = sec.copy(start = (it.toIntOrNull() ?: sec.start).coerceIn(1, 200)) },
                                label = { Text("From Q") },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                            OutlinedTextField(
                                value = sec.end.toString(),
                                onValueChange = { sections[idx] = sec.copy(end = (it.toIntOrNull() ?: sec.end).coerceIn(1, 200)) },
                                label = { Text("To Q") },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                            OutlinedTextField(
                                value = sec.pointsPerQuestion.toString(),
                                onValueChange = { sections[idx] = sec.copy(pointsPerQuestion = it.toDoubleOrNull() ?: 1.0) },
                                label = { Text("Pts/Q") },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                        }
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            items(QuestionType.entries) { qt ->
                                FilterChip(
                                    selected = sec.type == qt,
                                    onClick = { sections[idx] = sec.copy(type = qt) },
                                    label = { Text(qt.shortCode) }
                                )
                            }
                        }
                    }
                }
            }
            item {
                OutlinedButton(
                    onClick = {
                        val nextStart = (sections.maxOfOrNull { it.end } ?: 0) + 1
                        sections.add(AnswerKeySection(title = "Part ${sections.size + 1}", type = QuestionType.SHORT_ANSWER, start = nextStart, end = nextStart + 4))
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Icon(Icons.Default.Add, contentDescription = null)
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Add Section")
                }
            }
            item {
                Button(
                    onClick = {
                        val totalQ = (sections.maxOfOrNull { it.end } ?: assessment.questionCount).coerceIn(1, 200)
                        val existingMap = assessment.questions.associateBy { it.number }
                        val rebuilt = (1..totalQ).map { qNum ->
                            val matchingSec = sections.firstOrNull { qNum in it.start..it.end }
                            val prev = existingMap[qNum]
                            Question(
                                number = qNum,
                                text = prev?.text ?: "Question $qNum",
                                type = matchingSec?.type ?: prev?.type ?: QuestionType.MCQ,
                                correctAnswer = prev?.correctAnswer.orEmpty(),
                                points = matchingSec?.pointsPerQuestion ?: prev?.points ?: 1.0
                            )
                        }
                        onApplySections(assessment.copy(sections = sections.toList(), questions = rebuilt))
                        onBack()
                    },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp)
                ) {
                    Text("Apply Sections")
                }
            }
        }
    }
}
