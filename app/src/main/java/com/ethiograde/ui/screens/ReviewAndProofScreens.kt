package com.ethiograde.ui.screens

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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.ethiograde.model.*
import com.ethiograde.service.PdfExportAndCsvService
import com.ethiograde.ui.components.MiniStatCard
import com.ethiograde.ui.theme.LocalEthioColors
import com.ethiograde.viewmodel.EthioGradeUiState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.text.DateFormat
import java.util.Date

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReviewScreen(
    assessment: Assessment,
    state: EthioGradeUiState,
    onBack: () -> Unit,
    onOpenScan: () -> Unit,
    onOpenQuickEnter: () -> Unit,
    onOpenItemAnalysis: () -> Unit,
    onOpenGradeDetail: (String) -> Unit,
    onMarkAssessmentCompleted: (Boolean) -> Unit,
    onDeleteResult: (String) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val ethio = LocalEthioColors.current
    val results = state.resultsForAssessment(assessment.id)
    var filterNeedsReview by remember { mutableStateOf(false) }

    val displayed = remember(results, filterNeedsReview, assessment.answerKeyFingerprint) {
        if (filterNeedsReview) results.filter { it.requiresTeacherAction(assessment.answerKeyFingerprint) }
        else results
    }

    val flaggedCount = results.count { it.requiresTeacherAction(assessment.answerKeyFingerprint) }
    val avgPct = if (results.isEmpty()) 0.0 else results.sumOf { it.percentage } / results.size
    val passRate = if (results.isEmpty()) 0.0 else results.count { it.percentage >= 50.0 }.toDouble() / results.size * 100.0

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(assessment.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text("${assessment.subject} • ${results.size} papers", style = MaterialTheme.typography.labelSmall)
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = onOpenItemAnalysis, modifier = Modifier.testTag("review_item_analysis_btn")) {
                        Icon(Icons.Default.Analytics, contentDescription = "Item Analysis")
                    }
                    IconButton(onClick = {
                        scope.launch {
                            val file = withContext(Dispatchers.IO) {
                                PdfExportAndCsvService.generateResultsPdf(
                                    context = context,
                                    assessment = assessment,
                                    results = results,
                                    schoolName = state.settings.schoolName,
                                    teacherName = state.settings.teacherName
                                )
                            }
                            PdfExportAndCsvService.shareFile(context, file, "application/pdf", "${assessment.title} Results PDF")
                        }
                    }, modifier = Modifier.testTag("review_export_pdf_btn")) {
                        Icon(Icons.Default.PictureAsPdf, contentDescription = "Export PDF")
                    }
                    IconButton(onClick = {
                        scope.launch {
                            val file = withContext(Dispatchers.IO) {
                                PdfExportAndCsvService.exportResultsCsv(context, assessment, results)
                            }
                            PdfExportAndCsvService.shareFile(context, file, "text/csv", "${assessment.title} Results CSV")
                        }
                    }, modifier = Modifier.testTag("review_export_csv_btn")) {
                        Icon(Icons.Default.TableView, contentDescription = "Export CSV")
                    }
                }
            )
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = onOpenScan,
                icon = { Icon(Icons.Default.CameraAlt, contentDescription = null) },
                text = { Text("Scan Papers") },
                modifier = Modifier.testTag("review_scan_fab")
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
                    MiniStatCard("Average", "${"%.1f".format(avgPct)}%", Icons.Default.Percent, MaterialTheme.colorScheme.primary, Modifier.weight(1f))
                    MiniStatCard("Pass Rate", "${"%.0f".format(passRate)}%", Icons.Default.CheckCircle, ethio.success, Modifier.weight(1f))
                    MiniStatCard("Flagged", "$flaggedCount", Icons.Default.Flag, ethio.warning, Modifier.weight(1f))
                }
            }

            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    FilterChip(
                        selected = !filterNeedsReview,
                        onClick = { filterNeedsReview = false },
                        label = { Text("All (${results.size})") }
                    )
                    FilterChip(
                        selected = filterNeedsReview,
                        onClick = { filterNeedsReview = true },
                        label = { Text("Needs Review ($flaggedCount)") }
                    )
                    Spacer(modifier = Modifier.weight(1f))
                    TextButton(onClick = onOpenQuickEnter) { Text("Quick Enter") }
                }
            }

            item {
                Surface(
                    color = if (assessment.isCompleted) ethio.successContainer else MaterialTheme.colorScheme.surfaceVariant,
                    shape = MaterialTheme.shapes.medium,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                if (assessment.isCompleted) "Assessment Completed" else "Assessment In Progress",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.Bold
                            )
                            Text(
                                if (flaggedCount > 0) "Resolve $flaggedCount flagged paper(s) before closing"
                                else "All papers verified",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        Switch(
                            checked = assessment.isCompleted,
                            onCheckedChange = { onMarkAssessmentCompleted(it) },
                            modifier = Modifier.testTag("toggle_assessment_completed")
                        )
                    }
                }
            }

            if (displayed.isEmpty()) {
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
                            Icon(Icons.Default.FactCheck, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(36.dp))
                            Text(
                                if (filterNeedsReview) "No papers need teacher review" else "No graded papers yet",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.Bold
                            )
                            if (!filterNeedsReview) {
                                Button(onClick = onOpenScan) { Text("Scan First Paper") }
                            }
                        }
                    }
                }
            } else {
                items(displayed, key = { it.id }) { res ->
                    val needsAction = res.requiresTeacherAction(assessment.answerKeyFingerprint)
                    Surface(
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("review_result_${res.id}")
                            .clickable { onOpenGradeDetail(res.id) },
                        color = MaterialTheme.colorScheme.surface,
                        shape = MaterialTheme.shapes.medium,
                        border = BorderStroke(
                            1.dp,
                            if (needsAction) ethio.warning else MaterialTheme.colorScheme.outline
                        )
                    ) {
                        Row(
                            modifier = Modifier.padding(14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Text(res.studentName, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                                    if (needsAction) {
                                        Surface(color = ethio.warningContainer, shape = MaterialTheme.shapes.small) {
                                            Text(
                                                "Flagged",
                                                style = MaterialTheme.typography.labelSmall,
                                                color = ethio.warning,
                                                modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                                            )
                                        }
                                    }
                                }
                                Text(
                                    "${res.detectedMethod.uppercase()} • Conf ${(res.confidence * 100).toInt()}%",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Column(horizontalAlignment = Alignment.End) {
                                    Text(
                                        "${"%.1f".format(res.totalScore)}/${"%.0f".format(res.maxScore)}",
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.Bold
                                    )
                                    Text(
                                        "${"%.1f".format(res.percentage)}% (${res.grade})",
                                        style = MaterialTheme.typography.labelMedium,
                                        color = if (res.percentage >= 50) ethio.success else MaterialTheme.colorScheme.error,
                                        fontWeight = FontWeight.Bold
                                    )
                                }
                                IconButton(onClick = { onDeleteResult(res.id) }) {
                                    Icon(Icons.Default.DeleteOutline, contentDescription = "Delete result", tint = MaterialTheme.colorScheme.onSurfaceVariant)
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
fun GradeReviewScreen(
    assessment: Assessment,
    result: ScanResult,
    state: EthioGradeUiState,
    onBack: () -> Unit,
    onToggleAnswerOverride: (Int) -> Unit,
    onOverrideTotalScore: (Double, String) -> Unit,
    onMarkReviewed: () -> Unit,
    onReassignStudent: (Student) -> Unit,
    onRevertAudit: (AuditEntry) -> Unit,
    onOpenProofVault: (String) -> Unit,
    onSendParentSms: (String) -> Unit,
    onRescan: () -> Unit = {}
) {
    val ethio = LocalEthioColors.current
    val audits = remember(state.auditEntries, result.id) {
        state.auditEntries.filter { it.scanResultId == result.id }.sortedByDescending { it.timestampMillis }
    }
    val proof = remember(state.proofVaultEntries, result) {
        state.proofVaultEntries.firstOrNull {
            it.assessmentId == result.assessmentId && (it.studentId == result.studentId || it.studentName == result.studentName)
        }
    }
    var showAuditDialog by remember { mutableStateOf(false) }
    var showOverrideDialog by remember { mutableStateOf(false) }
    var showReassignDialog by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(result.studentName, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { showAuditDialog = true }, modifier = Modifier.testTag("grade_review_audit_btn")) {
                        Icon(Icons.Default.History, contentDescription = "Audit Trail")
                    }
                    if (proof != null) {
                        IconButton(onClick = { onOpenProofVault(proof.id) }, modifier = Modifier.testTag("grade_review_proof_btn")) {
                            Icon(Icons.Default.VerifiedUser, contentDescription = "Proof Vault")
                        }
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
                        onClick = { showOverrideDialog = true },
                        modifier = Modifier.weight(1f).heightIn(min = 48.dp)
                    ) {
                        Text("Override")
                    }
                    Button(
                        onClick = { onMarkReviewed(); onBack() },
                        modifier = Modifier.weight(1f).heightIn(min = 48.dp).testTag("mark_reviewed_button")
                    ) {
                        Icon(Icons.Default.DoneAll, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("Confirm")
                    }
                }
            }
        },
        contentWindowInsets = WindowInsets.safeDrawing
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                Surface(
                    color = MaterialTheme.colorScheme.primaryContainer,
                    shape = MaterialTheme.shapes.large,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column {
                                Text(result.studentName, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                                Text(assessment.title, style = MaterialTheme.typography.bodySmall)
                            }
                            Text(
                                "${"%.1f".format(result.percentage)}% (${result.grade})",
                                style = MaterialTheme.typography.headlineSmall,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.primary
                            )
                        }
                        Text(
                            "Score: ${"%.1f".format(result.totalScore)} / ${"%.0f".format(result.maxScore)} • Status: ${result.status.name}",
                            style = MaterialTheme.typography.bodyMedium
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            AssistChip(
                                onClick = { showReassignDialog = true },
                                label = { Text("Assign Student") },
                                leadingIcon = { Icon(Icons.Default.PersonSearch, contentDescription = null, modifier = Modifier.size(16.dp)) }
                            )
                            AssistChip(
                                onClick = onRescan,
                                label = { Text("Rescan") },
                                leadingIcon = { Icon(Icons.Default.CameraAlt, contentDescription = null, modifier = Modifier.size(16.dp)) }
                            )
                            if (result.studentId.isNotBlank()) {
                                AssistChip(
                                    onClick = { onSendParentSms(result.studentId) },
                                    label = { Text("SMS Parent") },
                                    leadingIcon = { Icon(Icons.Default.Sms, contentDescription = null, modifier = Modifier.size(16.dp)) }
                                )
                            }
                        }
                    }
                }
            }

            if (result.imagePath.isNotBlank() && File(result.imagePath).exists()) {
                item {
                    Surface(
                        shape = MaterialTheme.shapes.medium,
                        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                        modifier = Modifier.fillMaxWidth().height(200.dp)
                    ) {
                        AsyncImage(
                            model = File(result.imagePath),
                            contentDescription = "Scanned sheet image",
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                }
            }

            item {
                Text("Question Breakdown (Tap to Toggle Override)", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            }

            items(result.answers, key = { it.questionNumber }) { m ->
                val isFlagged = m.questionNumber in result.uncertainQuestions ||
                    m.detectedAnswer == "[MISSING]" || m.detectedAnswer == "[MULTIPLE]"
                Surface(
                    color = MaterialTheme.colorScheme.surface,
                    shape = MaterialTheme.shapes.medium,
                    border = BorderStroke(1.dp, if (isFlagged) ethio.warning else MaterialTheme.colorScheme.outline),
                    modifier = Modifier.fillMaxWidth().clickable { onToggleAnswerOverride(m.questionNumber) }
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                "Q${m.questionNumber}${if (m.isOverridden) " (Overridden)" else ""}",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.Bold
                            )
                            Text(
                                "Detected: ${m.detectedAnswer} • Key: ${m.correctAnswer}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        Surface(
                            color = if (m.isCorrect) ethio.successContainer else MaterialTheme.colorScheme.errorContainer,
                            shape = MaterialTheme.shapes.small
                        ) {
                            Text(
                                if (m.isCorrect) "✓ ${m.score.toInt()}/${m.maxScore.toInt()}" else "✗ 0/${m.maxScore.toInt()}",
                                color = if (m.isCorrect) ethio.success else MaterialTheme.colorScheme.error,
                                style = MaterialTheme.typography.labelLarge,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp)
                            )
                        }
                    }
                }
            }
        }
    }

    if (showOverrideDialog) {
        var scoreInput by remember { mutableStateOf(result.totalScore.toString()) }
        var reasonInput by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { showOverrideDialog = false },
            title = { Text("Override Total Score") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = scoreInput,
                        onValueChange = { scoreInput = it },
                        label = { Text("New Score (max ${result.maxScore.toInt()})") },
                        singleLine = true
                    )
                    OutlinedTextField(
                        value = reasonInput,
                        onValueChange = { reasonInput = it },
                        label = { Text("Reason") },
                        singleLine = true
                    )
                }
            },
            confirmButton = {
                Button(onClick = {
                    val v = scoreInput.toDoubleOrNull() ?: result.totalScore
                    onOverrideTotalScore(v, reasonInput)
                    showOverrideDialog = false
                }) { Text("Apply") }
            },
            dismissButton = { TextButton(onClick = { showOverrideDialog = false }) { Text("Cancel") } }
        )
    }

    if (showReassignDialog) {
        val candidates = if (assessment.classId.isNotBlank()) state.studentsInClass(assessment.classId) else state.students
        AlertDialog(
            onDismissRequest = { showReassignDialog = false },
            title = { Text("Assign to Student") },
            text = {
                LazyColumn(modifier = Modifier.heightIn(max = 320.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    items(candidates, key = { it.id }) { st ->
                        OutlinedButton(
                            onClick = { onReassignStudent(st); showReassignDialog = false },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text("${st.fullName} (${st.studentId.ifBlank { "No ID" }})")
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { showReassignDialog = false }) { Text("Close") } }
        )
    }

    if (showAuditDialog) {
        AlertDialog(
            onDismissRequest = { showAuditDialog = false },
            title = { Text("Grade Audit Trail") },
            text = {
                if (audits.isEmpty()) {
                    Text("No audit entries recorded yet.")
                } else {
                    LazyColumn(modifier = Modifier.heightIn(max = 340.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(audits, key = { it.id }) { entry ->
                            Surface(
                                color = MaterialTheme.colorScheme.surfaceVariant,
                                shape = MaterialTheme.shapes.small,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Column(modifier = Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Text(entry.action.label, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold)
                                    Text(
                                        "${"%.1f".format(entry.previousScore)} (${entry.previousGrade}) → ${"%.1f".format(entry.newScore)} (${entry.newGrade})",
                                        style = MaterialTheme.typography.bodySmall
                                    )
                                    if (entry.reason.isNotBlank()) {
                                        Text(entry.reason, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.SpaceBetween,
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Text(
                                            DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(entry.timestampMillis)),
                                            style = MaterialTheme.typography.labelSmall
                                        )
                                        if (entry.action != AuditAction.CREATED && entry.action != AuditAction.REVERTED) {
                                            TextButton(onClick = { onRevertAudit(entry); showAuditDialog = false }) {
                                                Text("Revert")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { showAuditDialog = false }) { Text("Close") } }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProofVaultInspectorScreen(
    entry: ProofVaultEntry,
    onBack: () -> Unit
) {
    val ethio = LocalEthioColors.current
    val verified = remember(entry) { entry.verifyIntegrity() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Proof Vault Inspector") },
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
                Surface(
                    color = if (verified) ethio.successContainer else MaterialTheme.colorScheme.errorContainer,
                    shape = MaterialTheme.shapes.large,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(
                            if (verified) Icons.Default.VerifiedUser else Icons.Default.GppBad,
                            contentDescription = null,
                            tint = if (verified) ethio.success else MaterialTheme.colorScheme.error,
                            modifier = Modifier.size(32.dp)
                        )
                        Column {
                            Text(
                                if (verified) "SHA-256 Integrity Verified" else "Integrity Hash Mismatch",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold
                            )
                            Text(
                                "${entry.studentName} • Score ${"%.1f".format(entry.totalScore)}/${"%.0f".format(entry.maxScore)}",
                                style = MaterialTheme.typography.bodySmall
                            )
                        }
                    }
                }
            }

            item {
                Surface(
                    color = MaterialTheme.colorScheme.surface,
                    shape = MaterialTheme.shapes.medium,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
                ) {
                    Column(modifier = Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("Cryptographic Fingerprint", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                        Text(entry.integrityHash, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }

            item {
                Text("Raw Bubble Densities", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            }

            items(entry.bubbleDensities.entries.sortedBy { it.key }) { (qNum, opts) ->
                val detected = entry.detectedAnswers[qNum].orEmpty()
                Surface(
                    color = MaterialTheme.colorScheme.surface,
                    shape = MaterialTheme.shapes.medium,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
                ) {
                    Column(modifier = Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("Q$qNum", fontWeight = FontWeight.Bold)
                            Text("Detected: $detected", color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
                        }
                        opts.entries.sortedBy { it.key }.forEach { (opt, density) ->
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(opt, style = MaterialTheme.typography.labelMedium, modifier = Modifier.width(28.dp))
                                LinearProgressIndicator(
                                    progress = { density.toFloat().coerceIn(0f, 1f) },
                                    modifier = Modifier.weight(1f).height(8.dp)
                                )
                                Text("${(density * 100).toInt()}%", style = MaterialTheme.typography.labelSmall)
                            }
                        }
                    }
                }
            }
        }
    }
}
