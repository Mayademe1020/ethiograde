package com.ethiograde.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import com.ethiograde.model.ClassInfo
import com.ethiograde.model.Student
import com.ethiograde.service.CsvImportResult
import com.ethiograde.service.PdfExportAndCsvService
import com.ethiograde.service.PhoneUtils
import com.ethiograde.ui.components.MiniStatCard
import com.ethiograde.ui.theme.LocalEthioColors
import com.ethiograde.viewmodel.EthioGradeUiState

@Composable
fun StudentsTab(
    state: EthioGradeUiState,
    onAddStudent: () -> Unit,
    onImportCsv: () -> Unit,
    onOpenStudentDetail: (String) -> Unit
) {
    var search by remember { mutableStateOf("") }
    var selectedClassId by remember { mutableStateOf("All") }

    val filtered = remember(state.students, search, selectedClassId) {
        state.students.filter { st ->
            (selectedClassId == "All" || st.belongsToClass(selectedClassId)) &&
                (search.isBlank() || st.fullName.contains(search, true) || st.studentId.contains(search, true))
        }
    }

    Scaffold(
        floatingActionButton = {
            FloatingActionButton(
                onClick = onAddStudent,
                containerColor = MaterialTheme.colorScheme.primary,
                modifier = Modifier.testTag("fab_add_student")
            ) {
                Icon(Icons.Default.PersonAdd, contentDescription = "Add Student")
            }
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("Students (${state.students.size})", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                    FilledTonalButton(onClick = onImportCsv, modifier = Modifier.testTag("students_import_csv_button")) {
                        Icon(Icons.Default.UploadFile, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("Import CSV")
                    }
                }
            }
            item {
                OutlinedTextField(
                    value = search,
                    onValueChange = { search = it },
                    placeholder = { Text("Search students by name or roll ID…") },
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().testTag("students_search_input")
                )
            }
            if (state.classes.isNotEmpty()) {
                item {
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        item {
                            FilterChip(
                                selected = selectedClassId == "All",
                                onClick = { selectedClassId = "All" },
                                label = { Text("All") }
                            )
                        }
                        items(state.classes, key = { it.id }) { cls ->
                            FilterChip(
                                selected = selectedClassId == cls.id,
                                onClick = { selectedClassId = cls.id },
                                label = { Text(cls.displayName) }
                            )
                        }
                    }
                }
            }
            items(filtered, key = { it.id }) { st ->
                val count = state.scanResults.count { it.studentId == st.id }
                Surface(
                    modifier = Modifier.fillMaxWidth().clickable { onOpenStudentDetail(st.id) }.testTag("student_row_${st.id}"),
                    color = MaterialTheme.colorScheme.surface,
                    shape = MaterialTheme.shapes.medium,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
                ) {
                    Row(
                        modifier = Modifier.padding(14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.weight(1f)) {
                            CircleAvatar(st.initials)
                            Spacer(modifier = Modifier.width(12.dp))
                            Column {
                                Text(st.fullName, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                                Text(
                                    listOfNotNull(
                                        st.className.takeIf { it.isNotBlank() },
                                        st.studentId.takeIf { it.isNotBlank() }?.let { "ID $it" },
                                        "$count result(s)"
                                    ).joinToString(" • "),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                        Icon(Icons.Default.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddOrEditStudentScreen(
    existingStudent: Student?,
    preselectedClassId: String?,
    classes: List<ClassInfo>,
    onBack: () -> Unit,
    onSave: (Student) -> Unit
) {
    var firstName by remember { mutableStateOf(existingStudent?.firstName ?: "") }
    var lastName by remember { mutableStateOf(existingStudent?.lastName ?: "") }
    var rollId by remember { mutableStateOf(existingStudent?.studentId ?: "") }
    var gender by remember { mutableStateOf(existingStudent?.gender ?: "M") }
    var parentPhone by remember { mutableStateOf(existingStudent?.parentPhone ?: "") }
    var selectedClassId by remember {
        mutableStateOf(
            existingStudent?.classIds?.firstOrNull()
                ?: preselectedClassId
                ?: classes.firstOrNull()?.id.orEmpty()
        )
    }
    var errorMsg by remember { mutableStateOf<String?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (existingStudent == null) "Add Student" else "Edit Student") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                }
            )
        },
        contentWindowInsets = WindowInsets.safeDrawing
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            OutlinedTextField(
                value = firstName,
                onValueChange = { firstName = it; errorMsg = null },
                label = { Text("First Name *") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().testTag("student_first_name_input")
            )
            OutlinedTextField(
                value = lastName,
                onValueChange = { lastName = it },
                label = { Text("Father's / Last Name") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().testTag("student_last_name_input")
            )
            OutlinedTextField(
                value = rollId,
                onValueChange = { rollId = it },
                label = { Text("Student ID / Roll No") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().testTag("student_roll_input")
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = gender == "M", onClick = { gender = "M" }, label = { Text("Male (M)") })
                FilterChip(selected = gender == "F", onClick = { gender = "F" }, label = { Text("Female (F)") })
            }
            OutlinedTextField(
                value = parentPhone,
                onValueChange = { parentPhone = PhoneUtils.filterInput(it); errorMsg = null },
                label = { Text("Parent Phone (+2519...)") },
                placeholder = { Text("0911223344 or +251911223344") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().testTag("student_phone_input")
            )
            if (classes.isNotEmpty()) {
                Text("Assign Class", style = MaterialTheme.typography.titleSmall)
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(classes, key = { it.id }) { cls ->
                        FilterChip(
                            selected = selectedClassId == cls.id,
                            onClick = { selectedClassId = cls.id },
                            label = { Text(cls.displayName) }
                        )
                    }
                }
            }
            errorMsg?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }

            Spacer(modifier = Modifier.weight(1f))
            Button(
                onClick = {
                    if (firstName.isBlank()) {
                        errorMsg = "First name is required"
                        return@Button
                    }
                    val trimmedPhone = parentPhone.trim()
                    val normalizedPhone = if (trimmedPhone.isEmpty()) null else {
                        val n = PhoneUtils.normalize(trimmedPhone)
                        if (!PhoneUtils.isValid(n)) {
                            errorMsg = "Enter a valid Ethiopian mobile (+2519/7XXXXXXXX)"
                            return@Button
                        }
                        n
                    }
                    val cls = classes.firstOrNull { it.id == selectedClassId }
                    val student = (existingStudent ?: Student(firstName = firstName.trim())).copy(
                        firstName = firstName.trim(),
                        lastName = lastName.trim(),
                        studentId = rollId.trim(),
                        gender = gender,
                        parentPhone = normalizedPhone,
                        classIds = if (cls != null) listOf(cls.id) else existingStudent?.classIds.orEmpty(),
                        className = cls?.displayName ?: existingStudent?.className.orEmpty(),
                        grade = cls?.grade ?: existingStudent?.grade ?: 5,
                        section = cls?.section ?: existingStudent?.section.orEmpty()
                    )
                    onSave(student)
                    onBack()
                },
                modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp).testTag("save_student_button")
            ) {
                Text("Save Student")
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StudentDetailScreen(
    student: Student,
    state: EthioGradeUiState,
    onBack: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    onSendSms: () -> Unit
) {
    val ethio = LocalEthioColors.current
    val results = remember(state.scanResults, student.id) {
        state.scanResults.filter { it.studentId == student.id }.sortedByDescending { it.scannedAtMillis }
    }
    val avg = if (results.isEmpty()) 0.0 else results.sumOf { it.percentage } / results.size
    val assessmentMap = remember(state.assessments) { state.assessments.associateBy { it.id } }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(student.fullName) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                },
                actions = {
                    IconButton(onClick = onEdit) { Icon(Icons.Default.Edit, contentDescription = "Edit student") }
                    IconButton(onClick = { onDelete(); onBack() }) { Icon(Icons.Default.DeleteOutline, contentDescription = "Delete student") }
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
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                    MiniStatCard("Average", "${"%.1f".format(avg)}%", Icons.Default.Percent, MaterialTheme.colorScheme.primary, Modifier.weight(1f))
                    MiniStatCard("Exams", "${results.size}", Icons.Default.AssignmentTurnedIn, ethio.info, Modifier.weight(1f))
                }
            }
            item {
                Surface(
                    color = MaterialTheme.colorScheme.surface,
                    shape = MaterialTheme.shapes.medium,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
                ) {
                    Column(modifier = Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("Class: ${student.className.ifBlank { "Unassigned" }}")
                        Text("Student ID: ${student.studentId.ifBlank { "—" }} • Gender: ${student.gender.ifBlank { "—" }}")
                        Text("Parent Phone: ${student.parentPhone ?: "Not set"}")
                        Spacer(modifier = Modifier.height(6.dp))
                        Button(onClick = onSendSms, modifier = Modifier.fillMaxWidth().testTag("student_send_sms_button")) {
                            Icon(Icons.Default.Sms, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(modifier = Modifier.width(6.dp))
                            Text("Send Parent SMS")
                        }
                    }
                }
            }
            item {
                Text("Score History", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            }
            if (results.isEmpty()) {
                item { Text("No graded assessments recorded yet.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
            } else {
                items(results, key = { it.id }) { res ->
                    val title = assessmentMap[res.assessmentId]?.title ?: "Assessment"
                    Surface(
                        color = MaterialTheme.colorScheme.surface,
                        shape = MaterialTheme.shapes.medium,
                        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(14.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                                Text(
                                    "${"%.1f".format(res.totalScore)} / ${"%.0f".format(res.maxScore)} pts",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            Text(
                                "${"%.1f".format(res.percentage)}% (${res.grade})",
                                style = MaterialTheme.typography.titleSmall,
                                color = if (res.percentage >= 50) ethio.success else MaterialTheme.colorScheme.error,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ImportCsvScreen(
    classInfo: ClassInfo?,
    onBack: () -> Unit,
    onImportConfirmed: (List<Student>) -> Unit
) {
    val context = LocalContext.current
    var csvText by remember { mutableStateOf("") }
    var previewResult by remember { mutableStateOf<CsvImportResult?>(null) }

    val openDocLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            val content = runCatching {
                context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
            }.getOrNull().orEmpty()
            csvText = content
            previewResult = PdfExportAndCsvService.parseStudentsFromCsv(content, classInfo?.id, classInfo?.displayName.orEmpty())
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Import Students (CSV)") },
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
                Button(
                    onClick = { openDocLauncher.launch(arrayOf("text/csv", "text/comma-separated-values", "text/plain", "*/*")) },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("pick_csv_file_button")
                ) {
                    Icon(Icons.Default.FolderOpen, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Choose CSV File from Device")
                }
            }
            item {
                OutlinedTextField(
                    value = csvText,
                    onValueChange = {
                        csvText = it
                        previewResult = if (it.isNotBlank()) {
                            PdfExportAndCsvService.parseStudentsFromCsv(it, classInfo?.id, classInfo?.displayName.orEmpty())
                        } else null
                    },
                    label = { Text("Or Paste CSV Rows (Name, ID, Gender, Phone)") },
                    placeholder = { Text("FirstName,LastName,ID,Gender,Phone\nAbebe,Kebede,106,M,+251911223344") },
                    minLines = 4,
                    modifier = Modifier.fillMaxWidth().testTag("csv_paste_input")
                )
            }
            previewResult?.let { res ->
                item {
                    Surface(
                        color = if (res.success) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.errorContainer,
                        shape = MaterialTheme.shapes.medium
                    ) {
                        Column(modifier = Modifier.fillMaxWidth().padding(12.dp)) {
                            Text(res.message, fontWeight = FontWeight.Bold)
                            res.warnings.take(3).forEach { w -> Text("• $w", style = MaterialTheme.typography.bodySmall) }
                        }
                    }
                }
                items(res.students) { st ->
                    Text("• ${st.fullName} (ID: ${st.studentId.ifBlank { "—" }}, ${st.gender.ifBlank { "—" }})", style = MaterialTheme.typography.bodyMedium)
                }
                if (res.success) {
                    item {
                        Button(
                            onClick = { onImportConfirmed(res.students); onBack() },
                            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("confirm_csv_import_button")
                        ) {
                            Text("Import ${res.students.size} Students")
                        }
                    }
                }
            }
        }
    }
}
