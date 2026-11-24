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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.ethiograde.model.*
import com.ethiograde.ui.components.CreateOrEditClassDialog
import com.ethiograde.ui.components.MiniStatCard
import com.ethiograde.ui.theme.LocalEthioColors
import com.ethiograde.viewmodel.EthioGradeUiState
import java.time.LocalDate

@Composable
fun ClassesTab(
    state: EthioGradeUiState,
    onSaveClass: (ClassInfo) -> Unit,
    canDeleteClass: (String) -> Pair<Boolean, String?>,
    onDeleteClass: (String) -> Unit,
    onOpenClassDetail: (String) -> Unit,
    onOpenAddStudent: (String) -> Unit
) {
    val ethio = LocalEthioColors.current
    var search by remember { mutableStateOf("") }
    var selectedSubject by remember { mutableStateOf("All") }
    var editingClass by remember { mutableStateOf<ClassInfo?>(null) }
    var showCreateDialog by remember { mutableStateOf(false) }
    var deleteErrorMsg by remember { mutableStateOf<String?>(null) }
    var confirmDeleteClass by remember { mutableStateOf<ClassInfo?>(null) }

    val subjectChips = remember(state.classes) {
        listOf("All") + state.classes.map { it.subject }.distinct().sorted()
    }

    val filtered = remember(state.classes, search, selectedSubject) {
        state.classes.filter { cls ->
            (selectedSubject == "All" || cls.subject == selectedSubject) &&
                (search.isBlank() || cls.displayName.contains(search, true) || cls.subject.contains(search, true))
        }
    }

    Scaffold(
        floatingActionButton = {
            FloatingActionButton(
                onClick = { showCreateDialog = true },
                containerColor = MaterialTheme.colorScheme.primary,
                modifier = Modifier.testTag("fab_add_class")
            ) {
                Icon(Icons.Default.Add, contentDescription = "Add Class")
            }
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                Text("My Classes", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    MiniStatCard("Classes", "${state.classes.size}", Icons.Default.Class, MaterialTheme.colorScheme.primary, Modifier.weight(1f))
                    MiniStatCard("Students", "${state.students.size}", Icons.Default.Groups, ethio.info, Modifier.weight(1f))
                    MiniStatCard("Subjects", "${state.classes.map { it.subject }.distinct().size}", Icons.Default.MenuBook, ethio.success, Modifier.weight(1f))
                }
            }
            item {
                OutlinedTextField(
                    value = search,
                    onValueChange = { search = it },
                    placeholder = { Text("Search classes or subjects…") },
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().testTag("classes_search_input")
                )
            }
            if (subjectChips.size > 1) {
                item {
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(subjectChips) { subj ->
                            FilterChip(
                                selected = selectedSubject == subj,
                                onClick = { selectedSubject = subj },
                                label = { Text(subj) }
                            )
                        }
                    }
                }
            }
            if (filtered.isEmpty()) {
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
                            Icon(Icons.Default.School, contentDescription = null, modifier = Modifier.size(40.dp), tint = MaterialTheme.colorScheme.primary)
                            Text("No classes match your filter", style = MaterialTheme.typography.titleSmall)
                            Button(onClick = { showCreateDialog = true }) { Text("Create Class") }
                        }
                    }
                }
            } else {
                items(filtered, key = { it.id }) { cls ->
                    val count = state.studentsInClass(cls.id).size
                    var menuOpen by remember { mutableStateOf(false) }
                    Surface(
                        modifier = Modifier.fillMaxWidth().clickable { onOpenClassDetail(cls.id) }.testTag("class_card_${cls.id}"),
                        color = MaterialTheme.colorScheme.surface,
                        shape = MaterialTheme.shapes.medium,
                        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
                    ) {
                        Row(
                            modifier = Modifier.padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Text(cls.displayName, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                                    if (cls.isHomeroom) {
                                        Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = MaterialTheme.shapes.small) {
                                            Text(
                                                "Homeroom",
                                                style = MaterialTheme.typography.labelSmall,
                                                color = MaterialTheme.colorScheme.onSecondaryContainer,
                                                modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                                            )
                                        }
                                    }
                                }
                                Text(
                                    "Grade ${cls.grade}${cls.section} • ${cls.subject} • $count student(s)",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            Box {
                                IconButton(onClick = { menuOpen = true }) {
                                    Icon(Icons.Default.MoreVert, contentDescription = "Class options")
                                }
                                DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                                    DropdownMenuItem(
                                        text = { Text("Add Student") },
                                        leadingIcon = { Icon(Icons.Default.PersonAdd, contentDescription = null) },
                                        onClick = { menuOpen = false; onOpenAddStudent(cls.id) }
                                    )
                                    DropdownMenuItem(
                                        text = { Text("Edit Class") },
                                        leadingIcon = { Icon(Icons.Default.Edit, contentDescription = null) },
                                        onClick = { menuOpen = false; editingClass = cls }
                                    )
                                    DropdownMenuItem(
                                        text = { Text("Delete Class") },
                                        leadingIcon = { Icon(Icons.Default.Delete, contentDescription = null) },
                                        onClick = {
                                            menuOpen = false
                                            val (ok, reason) = canDeleteClass(cls.id)
                                            if (ok) confirmDeleteClass = cls else deleteErrorMsg = reason
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (showCreateDialog) {
        CreateOrEditClassDialog(
            subjects = state.settings.subjects,
            academicYear = state.settings.currentAcademicYear,
            onDismiss = { showCreateDialog = false },
            onSave = { onSaveClass(it); showCreateDialog = false }
        )
    }

    editingClass?.let { cls ->
        CreateOrEditClassDialog(
            initialClass = cls,
            subjects = state.settings.subjects,
            academicYear = state.settings.currentAcademicYear,
            onDismiss = { editingClass = null },
            onSave = { onSaveClass(it); editingClass = null }
        )
    }

    deleteErrorMsg?.let { msg ->
        AlertDialog(
            onDismissRequest = { deleteErrorMsg = null },
            title = { Text("Cannot Delete Class") },
            text = { Text(msg) },
            confirmButton = { Button(onClick = { deleteErrorMsg = null }) { Text("OK") } }
        )
    }

    confirmDeleteClass?.let { cls ->
        AlertDialog(
            onDismissRequest = { confirmDeleteClass = null },
            title = { Text("Delete Class?") },
            text = { Text("Delete ${cls.displayName} permanently?") },
            confirmButton = {
                Button(
                    onClick = { onDeleteClass(cls.id); confirmDeleteClass = null },
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
                ) { Text("Delete") }
            },
            dismissButton = { TextButton(onClick = { confirmDeleteClass = null }) { Text("Cancel") } }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClassDetailScreen(
    classInfo: ClassInfo,
    students: List<Student>,
    allClasses: List<ClassInfo>,
    onBack: () -> Unit,
    onAddStudent: () -> Unit,
    onImportCsv: () -> Unit,
    onOpenAttendance: () -> Unit,
    onOpenNotes: () -> Unit,
    onOpenStudentDetail: (String) -> Unit,
    onTransferStudent: (Student, ClassInfo) -> Unit,
    onDeleteStudent: (String) -> Unit
) {
    var search by remember { mutableStateOf("") }
    var transferTargetStudent by remember { mutableStateOf<Student?>(null) }

    val filtered = remember(students, search) {
        students.filter {
            search.isBlank() || it.fullName.contains(search, true) || it.studentId.contains(search, true)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(classInfo.displayName, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
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
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    FilledTonalButton(onClick = onAddStudent, modifier = Modifier.weight(1f).testTag("class_detail_add_student")) {
                        Icon(Icons.Default.PersonAdd, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Add")
                    }
                    FilledTonalButton(onClick = onImportCsv, modifier = Modifier.weight(1f).testTag("class_detail_import_csv")) {
                        Icon(Icons.Default.UploadFile, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("CSV")
                    }
                    FilledTonalButton(onClick = onOpenAttendance, modifier = Modifier.weight(1f).testTag("class_detail_attendance")) {
                        Icon(Icons.Default.FactCheck, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Roll")
                    }
                    FilledTonalButton(onClick = onOpenNotes, modifier = Modifier.weight(1f).testTag("class_detail_notes")) {
                        Icon(Icons.Default.NoteAlt, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Notes")
                    }
                }
            }
            item {
                OutlinedTextField(
                    value = search,
                    onValueChange = { search = it },
                    placeholder = { Text("Filter ${students.size} students…") },
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            }
            items(filtered, key = { it.id }) { st ->
                var menuOpen by remember { mutableStateOf(false) }
                Surface(
                    modifier = Modifier.fillMaxWidth().clickable { onOpenStudentDetail(st.id) },
                    color = MaterialTheme.colorScheme.surface,
                    shape = MaterialTheme.shapes.medium,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.weight(1f)) {
                            CircleAvatar(st.initials)
                            Spacer(modifier = Modifier.width(12.dp))
                            Column {
                                Text(st.fullName, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                                Text(
                                    "ID: ${st.studentId.ifBlank { "—" }} • ${st.gender.ifBlank { "—" }}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                        Box {
                            IconButton(onClick = { menuOpen = true }) {
                                Icon(Icons.Default.MoreVert, contentDescription = "Student options")
                            }
                            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                                DropdownMenuItem(
                                    text = { Text("Transfer Class") },
                                    onClick = { menuOpen = false; transferTargetStudent = st }
                                )
                                DropdownMenuItem(
                                    text = { Text("Remove Student") },
                                    onClick = { menuOpen = false; onDeleteStudent(st.id) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    transferTargetStudent?.let { st ->
        val otherClasses = allClasses.filter { it.id != classInfo.id }
        AlertDialog(
            onDismissRequest = { transferTargetStudent = null },
            title = { Text("Transfer ${st.fullName}") },
            text = {
                if (otherClasses.isEmpty()) {
                    Text("No other classes available to transfer to.")
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        otherClasses.forEach { target ->
                            OutlinedButton(
                                onClick = {
                                    onTransferStudent(st, target)
                                    transferTargetStudent = null
                                },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(target.displayName)
                            }
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { transferTargetStudent = null }) { Text("Close") } }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AttendanceScreen(
    classInfo: ClassInfo,
    students: List<Student>,
    records: List<AttendanceRecord>,
    onBack: () -> Unit,
    onSave: (AttendanceRecord) -> Unit
) {
    val ethio = LocalEthioColors.current
    var selectedDate by remember { mutableStateOf(LocalDate.now()) }
    val dateIso = selectedDate.toString()
    val existing = records.firstOrNull { it.classId == classInfo.id && it.dateIso == dateIso }
    val statusMap = remember(dateIso, existing) {
        mutableStateMapOf<String, AttendanceStatus>().apply {
            students.forEach { st ->
                put(st.id, existing?.entries?.get(st.id) ?: AttendanceStatus.PRESENT)
            }
        }
    }
    var savedToast by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Attendance • ${classInfo.displayName}", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                },
                actions = {
                    TextButton(onClick = {
                        onSave(
                            AttendanceRecord(
                                id = existing?.id ?: "${classInfo.id}_$dateIso",
                                classId = classInfo.id,
                                dateIso = dateIso,
                                entries = statusMap.toMap()
                            )
                        )
                        savedToast = true
                    }) { Text("Save") }
                }
            )
        },
        contentWindowInsets = WindowInsets.safeDrawing
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = { selectedDate = selectedDate.minusDays(1); savedToast = false }) {
                    Icon(Icons.Default.ChevronLeft, contentDescription = "Previous day")
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(dateIso, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Text(
                        com.ethiograde.service.EthiopianCalendarService.toEthiopic(selectedDate).formatted(),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                IconButton(onClick = { selectedDate = selectedDate.plusDays(1); savedToast = false }) {
                    Icon(Icons.Default.ChevronRight, contentDescription = "Next day")
                }
            }

            if (savedToast) {
                Surface(color = ethio.successContainer, shape = MaterialTheme.shapes.small, modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                    Text("Attendance saved for $dateIso", color = ethio.success, modifier = Modifier.padding(8.dp))
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                val present = statusMap.values.count { it == AttendanceStatus.PRESENT }
                val absent = statusMap.values.count { it == AttendanceStatus.ABSENT }
                Text("Present: $present  •  Absent: $absent", style = MaterialTheme.typography.labelLarge)
                TextButton(onClick = { students.forEach { statusMap[it.id] = AttendanceStatus.PRESENT } }) {
                    Text("Mark All Present")
                }
            }

            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(students, key = { it.id }) { st ->
                    val current = statusMap[st.id] ?: AttendanceStatus.PRESENT
                    Surface(
                        color = MaterialTheme.colorScheme.surface,
                        shape = MaterialTheme.shapes.medium,
                        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(12.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(st.fullName, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                AttendanceStatus.entries.forEach { stOption ->
                                    FilterChip(
                                        selected = current == stOption,
                                        onClick = { statusMap[st.id] = stOption; savedToast = false },
                                        label = { Text(stOption.shortCode) }
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClassNotesScreen(
    classInfo: ClassInfo,
    notes: List<ClassNote>,
    onBack: () -> Unit,
    onSaveNote: (ClassNote) -> Unit,
    onDeleteNote: (String) -> Unit
) {
    var showAdd by remember { mutableStateOf(false) }
    var title by remember { mutableStateOf("") }
    var content by remember { mutableStateOf("") }
    val classNotes = remember(notes, classInfo.id) { notes.filter { it.classId == classInfo.id } }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Class Notes • ${classInfo.displayName}", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                }
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = { showAdd = true }, modifier = Modifier.testTag("fab_add_class_note")) {
                Icon(Icons.Default.Add, contentDescription = "Add Note")
            }
        },
        contentWindowInsets = WindowInsets.safeDrawing
    ) { padding ->
        if (classNotes.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Text("No notes recorded yet. Tap + to add a lesson log.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                items(classNotes, key = { it.id }) { note ->
                    Surface(
                        color = MaterialTheme.colorScheme.surface,
                        shape = MaterialTheme.shapes.medium,
                        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
                    ) {
                        Column(modifier = Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(note.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                                IconButton(onClick = { onDeleteNote(note.id) }, modifier = Modifier.size(32.dp)) {
                                    Icon(Icons.Default.DeleteOutline, contentDescription = "Delete note", modifier = Modifier.size(18.dp))
                                }
                            }
                            Text(note.dateIso, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                            Text(note.content, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }
        }
    }

    if (showAdd) {
        AlertDialog(
            onDismissRequest = { showAdd = false },
            title = { Text("New Class Note") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedTextField(value = title, onValueChange = { title = it }, label = { Text("Title") }, singleLine = true)
                    OutlinedTextField(value = content, onValueChange = { content = it }, label = { Text("Details") }, minLines = 3)
                }
            },
            confirmButton = {
                Button(onClick = {
                    if (title.isNotBlank() || content.isNotBlank()) {
                        onSaveNote(
                            ClassNote(
                                classId = classInfo.id,
                                dateIso = LocalDate.now().toString(),
                                title = title.ifBlank { "Lesson Note" },
                                content = content.trim()
                            )
                        )
                    }
                    title = ""; content = ""; showAdd = false
                }) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { showAdd = false }) { Text("Cancel") } }
        )
    }
}
