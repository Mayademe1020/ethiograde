package com.ethiograde.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
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
import com.ethiograde.data.VoiceFeedbackMode
import com.ethiograde.model.GradeRange
import com.ethiograde.model.GradingScale
import com.ethiograde.model.Teacher
import com.ethiograde.service.BackupService
import com.ethiograde.ui.components.OfflineBadge
import com.ethiograde.viewmodel.EthioGradeUiState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun SettingsTab(
    state: EthioGradeUiState,
    onUpdateProfile: (name: String, school: String, phone: String) -> Unit,
    onSwitchTeacher: (Teacher) -> Unit,
    onSetDefaultRubric: (String) -> Unit,
    onSetVoiceFeedbackMode: (VoiceFeedbackMode) -> Unit,
    onToggleAutoEnhance: () -> Unit,
    onToggleDarkMode: () -> Unit,
    onSetAcademicYear: (String) -> Unit,
    onSaveSubjects: (List<String>) -> Unit,
    onOpenScaleEditor: (String?) -> Unit,
    onDeleteCustomScale: (String) -> Unit,
    onExportEncryptedBackup: suspend (String) -> ByteArray,
    onImportBackupBytes: (ByteArray, String?, Boolean, (String) -> Unit) -> Unit,
    onLoadDemoData: () -> Unit,
    onClearAllData: () -> Unit,
    onOpenSmsHistory: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var showProfileDialog by remember { mutableStateOf(false) }
    var showSubjectsDialog by remember { mutableStateOf(false) }
    var showScalePicker by remember { mutableStateOf(false) }
    var showVoicePicker by remember { mutableStateOf(false) }
    var showClearConfirm by remember { mutableStateOf(false) }
    var showExportPassphraseDialog by remember { mutableStateOf(false) }
    var pendingExportPassphrase by remember { mutableStateOf("") }
    var pendingImportBytes by remember { mutableStateOf<ByteArray?>(null) }
    var statusMessage by remember { mutableStateOf<String?>(null) }

    val exportBackupLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/octet-stream")
    ) { uri ->
        val passphrase = pendingExportPassphrase
        pendingExportPassphrase = ""
        if (uri != null) {
            scope.launch {
                val bytes = onExportEncryptedBackup(passphrase)
                runCatching {
                    withContext(Dispatchers.IO) {
                        context.contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    }
                }.onSuccess {
                    statusMessage = if (passphrase.isNotBlank()) {
                        "Portable passphrase-encrypted backup (.egb) saved"
                    } else {
                        "Encrypted AES-256 backup saved"
                    }
                }.onFailure {
                    statusMessage = "Backup export failed: ${it.message}"
                }
            }
        }
    }

    val importBackupLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) {
            scope.launch {
                val bytes = withContext(Dispatchers.IO) {
                    runCatching {
                        context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    }.getOrNull()
                }
                if (bytes != null) {
                    if (BackupService.isPortablePassphraseBackup(bytes)) {
                        pendingImportBytes = bytes
                    } else {
                        onImportBackupBytes(bytes, null, false) { msg -> statusMessage = msg }
                    }
                }
            }
        }
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text("Settings", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                OfflineBadge()
            }
        }

        statusMessage?.let { msg ->
            item {
                Surface(color = MaterialTheme.colorScheme.primaryContainer, shape = MaterialTheme.shapes.medium, modifier = Modifier.fillMaxWidth()) {
                    Text(msg, modifier = Modifier.padding(12.dp), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                }
            }
        }

        // Teacher Profile Card
        item {
            Surface(
                color = MaterialTheme.colorScheme.surface,
                shape = MaterialTheme.shapes.medium,
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                modifier = Modifier.fillMaxWidth().clickable { showProfileDialog = true }
            ) {
                Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(state.settings.teacherName.ifBlank { "Set Teacher Name" }, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                        Text(
                            listOf(state.settings.schoolName.ifBlank { "School not set" }, "AY ${state.settings.currentAcademicYear}")
                                .joinToString(" • "),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Icon(Icons.Default.Edit, contentDescription = "Edit Profile")
                }
            }
        }

        if (state.teachers.size > 1) {
            item {
                Text("Switch Teacher Profile", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    state.teachers.forEach { t ->
                        FilterChip(selected = t.isActive, onClick = { onSwitchTeacher(t) }, label = { Text(t.name) })
                    }
                }
            }
        }

        // Grading & Scanning Preferences
        item {
            Surface(
                color = MaterialTheme.colorScheme.surface,
                shape = MaterialTheme.shapes.medium,
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
            ) {
                Column {
                    ListItem(
                        headlineContent = { Text("Default Grading Scale") },
                        supportingContent = {
                            val activeScale = (GradingScale.builtInPresets + state.settings.customScales)
                                .firstOrNull { it.rubricKey == state.settings.defaultRubric }
                            Text(activeScale?.name ?: "Ethiopian MoE National")
                        },
                        leadingContent = { Icon(Icons.Default.Grade, contentDescription = null) },
                        modifier = Modifier.clickable { showScalePicker = true }
                    )
                    HorizontalDivider()
                    ListItem(
                        headlineContent = { Text("Create Custom Grading Scale") },
                        supportingContent = { Text("${state.settings.customScales.size} custom scale(s)") },
                        leadingContent = { Icon(Icons.Default.Tune, contentDescription = null) },
                        modifier = Modifier.clickable { onOpenScaleEditor(null) }
                    )
                    HorizontalDivider()
                    ListItem(
                        headlineContent = { Text("Voice Scan Readout") },
                        supportingContent = { Text(state.settings.voiceFeedbackMode.label) },
                        leadingContent = { Icon(Icons.Default.RecordVoiceOver, contentDescription = null) },
                        modifier = Modifier.clickable { showVoicePicker = true }
                    )
                    HorizontalDivider()
                    ListItem(
                        headlineContent = { Text("Auto-Enhance Paper Contrast") },
                        leadingContent = { Icon(Icons.Default.AutoFixHigh, contentDescription = null) },
                        trailingContent = {
                            Switch(checked = state.settings.autoEnhanceImages, onCheckedChange = { onToggleAutoEnhance() })
                        }
                    )
                    HorizontalDivider()
                    ListItem(
                        headlineContent = { Text("Dark Mode") },
                        leadingContent = { Icon(Icons.Default.DarkMode, contentDescription = null) },
                        trailingContent = {
                            Switch(
                                checked = state.settings.darkMode,
                                onCheckedChange = { onToggleDarkMode() },
                                modifier = Modifier.testTag("dark_mode_switch")
                            )
                        }
                    )
                }
            }
        }

        // Subjects & Communications
        item {
            Surface(
                color = MaterialTheme.colorScheme.surface,
                shape = MaterialTheme.shapes.medium,
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
            ) {
                Column {
                    ListItem(
                        headlineContent = { Text("Manage Subjects") },
                        supportingContent = { Text("${state.settings.subjects.size} subjects configured") },
                        leadingContent = { Icon(Icons.Default.Book, contentDescription = null) },
                        modifier = Modifier.clickable { showSubjectsDialog = true }
                    )
                    HorizontalDivider()
                    ListItem(
                        headlineContent = { Text("Parent SMS History") },
                        supportingContent = { Text("${state.smsLogs.size} sent log(s)") },
                        leadingContent = { Icon(Icons.Default.Sms, contentDescription = null) },
                        modifier = Modifier.clickable { onOpenSmsHistory() }
                    )
                }
            }
        }

        // Backup & Data
        item {
            Surface(
                color = MaterialTheme.colorScheme.surface,
                shape = MaterialTheme.shapes.medium,
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
            ) {
                Column {
                    ListItem(
                        headlineContent = { Text("Export Encrypted Backup (.egb)") },
                        supportingContent = { Text("Portable PBKDF2 + AES-256 offline archive") },
                        leadingContent = { Icon(Icons.Default.Lock, contentDescription = null) },
                        modifier = Modifier.clickable { showExportPassphraseDialog = true }
                    )
                    HorizontalDivider()
                    ListItem(
                        headlineContent = { Text("Restore Backup (.egb)") },
                        supportingContent = { Text("Merge saved classes, students & grades") },
                        leadingContent = { Icon(Icons.Default.Restore, contentDescription = null) },
                        modifier = Modifier.clickable { importBackupLauncher.launch(arrayOf("*/*")) }
                    )
                    HorizontalDivider()
                    ListItem(
                        headlineContent = { Text("Load Sample Classroom Data") },
                        leadingContent = { Icon(Icons.Default.Dataset, contentDescription = null) },
                        modifier = Modifier.clickable { onLoadDemoData() }
                    )
                    HorizontalDivider()
                    ListItem(
                        headlineContent = { Text("Clear All App Data", color = MaterialTheme.colorScheme.error) },
                        leadingContent = { Icon(Icons.Default.DeleteForever, contentDescription = null, tint = MaterialTheme.colorScheme.error) },
                        modifier = Modifier.clickable { showClearConfirm = true }
                    )
                }
            }
        }
    }

    if (showProfileDialog) {
        var name by remember { mutableStateOf(state.settings.teacherName) }
        var school by remember { mutableStateOf(state.settings.schoolName) }
        var phone by remember { mutableStateOf(state.settings.teacherPhone) }
        var year by remember { mutableStateOf(state.settings.currentAcademicYear) }
        AlertDialog(
            onDismissRequest = { showProfileDialog = false },
            title = { Text("Teacher Profile") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("Teacher Name") }, singleLine = true)
                    OutlinedTextField(value = school, onValueChange = { school = it }, label = { Text("School Name") }, singleLine = true)
                    OutlinedTextField(value = phone, onValueChange = { phone = it }, label = { Text("Phone (+251...)") }, singleLine = true)
                    OutlinedTextField(value = year, onValueChange = { year = it }, label = { Text("Academic Year") }, singleLine = true)
                }
            },
            confirmButton = {
                Button(onClick = {
                    onUpdateProfile(name, school, phone)
                    if (year.isNotBlank()) onSetAcademicYear(year)
                    showProfileDialog = false
                }) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { showProfileDialog = false }) { Text("Cancel") } }
        )
    }

    if (showScalePicker) {
        val allScales = GradingScale.builtInPresets + state.settings.customScales
        AlertDialog(
            onDismissRequest = { showScalePicker = false },
            title = { Text("Default Grading Scale") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    allScales.forEach { scale ->
                        Row(
                            modifier = Modifier.fillMaxWidth().clickable { onSetDefaultRubric(scale.rubricKey); showScalePicker = false }.padding(vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                RadioButton(selected = state.settings.defaultRubric == scale.rubricKey, onClick = { onSetDefaultRubric(scale.rubricKey); showScalePicker = false })
                                Text(scale.name)
                            }
                            if (scale.rubricKey.startsWith("custom:")) {
                                IconButton(onClick = { onDeleteCustomScale(scale.id) }) {
                                    Icon(Icons.Default.DeleteOutline, contentDescription = "Delete custom scale")
                                }
                            }
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { showScalePicker = false }) { Text("Close") } }
        )
    }

    if (showVoicePicker) {
        AlertDialog(
            onDismissRequest = { showVoicePicker = false },
            title = { Text("Voice Scan Readout") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    VoiceFeedbackMode.entries.forEach { mode ->
                        Row(
                            modifier = Modifier.fillMaxWidth().clickable { onSetVoiceFeedbackMode(mode); showVoicePicker = false }.padding(vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            RadioButton(selected = state.settings.voiceFeedbackMode == mode, onClick = { onSetVoiceFeedbackMode(mode); showVoicePicker = false })
                            Column {
                                Text(mode.label, fontWeight = FontWeight.SemiBold)
                                Text(mode.description, style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { showVoicePicker = false }) { Text("Close") } }
        )
    }

    if (showSubjectsDialog) {
        var newSub by remember { mutableStateOf("") }
        val list = remember { mutableStateListOf<String>().apply { addAll(state.settings.subjects) } }
        AlertDialog(
            onDismissRequest = { showSubjectsDialog = false },
            title = { Text("Subjects") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        OutlinedTextField(value = newSub, onValueChange = { newSub = it }, label = { Text("Add Subject") }, singleLine = true, modifier = Modifier.weight(1f))
                        Button(onClick = {
                            if (newSub.isNotBlank()) {
                                list.add(newSub.trim())
                                newSub = ""
                            }
                        }) { Text("Add") }
                    }
                    LazyColumn(modifier = Modifier.heightIn(max = 220.dp)) {
                        items(list) { s ->
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                Text(s)
                                IconButton(onClick = { list.remove(s) }) {
                                    Icon(Icons.Default.Close, contentDescription = "Remove $s")
                                }
                            }
                        }
                    }
                }
            },
            confirmButton = {
                Button(onClick = { onSaveSubjects(list.toList()); showSubjectsDialog = false }) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { showSubjectsDialog = false }) { Text("Cancel") } }
        )
    }

    if (showClearConfirm) {
        AlertDialog(
            onDismissRequest = { showClearConfirm = false },
            title = { Text("Clear All Data?") },
            text = { Text("This deletes all classes, students, exams, and grades from this device.") },
            confirmButton = {
                Button(
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                    onClick = { onClearAllData(); showClearConfirm = false }
                ) { Text("Delete Everything") }
            },
            dismissButton = { TextButton(onClick = { showClearConfirm = false }) { Text("Cancel") } }
        )
    }

    if (showExportPassphraseDialog) {
        var passphrase by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { showExportPassphraseDialog = false },
            title = { Text("Backup Passphrase") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        "Enter a passphrase so you can restore this .egb archive on any device. Keep it safe—it cannot be recovered if forgotten.",
                        style = MaterialTheme.typography.bodySmall
                    )
                    OutlinedTextField(
                        value = passphrase,
                        onValueChange = { passphrase = it },
                        label = { Text("Passphrase") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth().testTag("backup_export_passphrase_input")
                    )
                }
            },
            confirmButton = {
                Button(
                    enabled = passphrase.trim().length >= 4,
                    onClick = {
                        pendingExportPassphrase = passphrase.trim()
                        showExportPassphraseDialog = false
                        exportBackupLauncher.launch("ethiograde_backup.egb")
                    }
                ) { Text("Continue") }
            },
            dismissButton = {
                TextButton(onClick = { showExportPassphraseDialog = false }) { Text("Cancel") }
            }
        )
    }

    pendingImportBytes?.let { bytes ->
        var passphrase by remember { mutableStateOf("") }
        var replaceAll by remember { mutableStateOf(false) }
        AlertDialog(
            onDismissRequest = { pendingImportBytes = null },
            title = { Text("Unlock Backup") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = passphrase,
                        onValueChange = { passphrase = it },
                        label = { Text("Backup Passphrase") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth().testTag("backup_import_passphrase_input")
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("Replace existing device data", style = MaterialTheme.typography.bodySmall)
                        Switch(checked = replaceAll, onCheckedChange = { replaceAll = it })
                    }
                }
            },
            confirmButton = {
                Button(
                    enabled = passphrase.isNotBlank(),
                    onClick = {
                        pendingImportBytes = null
                        onImportBackupBytes(bytes, passphrase.trim(), replaceAll) { msg -> statusMessage = msg }
                    }
                ) { Text("Restore") }
            },
            dismissButton = {
                TextButton(onClick = { pendingImportBytes = null }) { Text("Cancel") }
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GradingScaleEditorScreen(
    existingScale: GradingScale?,
    onBack: () -> Unit,
    onSaveScale: (GradingScale) -> Unit
) {
    var name by remember { mutableStateOf(existingScale?.name ?: "Custom Scale") }
    val ranges = remember {
        mutableStateListOf<GradeRange>().apply {
            addAll(existingScale?.ranges ?: GradingScale.moeNational.ranges)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Grading Scale Editor") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") } }
            )
        },
        bottomBar = {
            Surface(tonalElevation = 3.dp) {
                Button(
                    onClick = {
                        val scale = (existingScale ?: GradingScale(name = name, ranges = ranges.toList())).copy(
                            name = name.trim().ifEmpty { "Custom Scale" },
                            ranges = ranges.toList()
                        )
                        onSaveScale(scale)
                        onBack()
                    },
                    modifier = Modifier.fillMaxWidth().padding(16.dp).navigationBarsPadding().heightIn(min = 50.dp)
                ) {
                    Text("Save Grading Scale")
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
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Scale Name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            }
            items(ranges.indices.toList()) { idx ->
                val r = ranges[idx]
                Surface(
                    color = MaterialTheme.colorScheme.surface,
                    shape = MaterialTheme.shapes.medium,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(10.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        OutlinedTextField(
                            value = r.grade,
                            onValueChange = { ranges[idx] = r.copy(grade = it.take(3)) },
                            label = { Text("Grade") },
                            singleLine = true,
                            modifier = Modifier.weight(1f)
                        )
                        OutlinedTextField(
                            value = r.minScore.toInt().toString(),
                            onValueChange = { ranges[idx] = r.copy(minScore = (it.toDoubleOrNull() ?: r.minScore).coerceIn(0.0, 100.0)) },
                            label = { Text("Min %") },
                            singleLine = true,
                            modifier = Modifier.weight(1f)
                        )
                        OutlinedTextField(
                            value = r.maxScore.toInt().toString(),
                            onValueChange = { ranges[idx] = r.copy(maxScore = (it.toDoubleOrNull() ?: r.maxScore).coerceIn(0.0, 100.0)) },
                            label = { Text("Max %") },
                            singleLine = true,
                            modifier = Modifier.weight(1f)
                        )
                        if (ranges.size > 1) {
                            IconButton(onClick = { ranges.removeAt(idx) }) {
                                Icon(Icons.Default.DeleteOutline, contentDescription = "Remove band ${r.grade}")
                            }
                        }
                    }
                }
            }
            item {
                OutlinedButton(
                    onClick = {
                        ranges.add(GradeRange(grade = "B+", minScore = 75.0, maxScore = 79.0))
                    },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
                ) {
                    Icon(Icons.Default.Add, contentDescription = null)
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Add Grade Band")
                }
            }
        }
    }
}
