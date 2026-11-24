package com.ethiograde.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.ethiograde.R
import com.ethiograde.model.*
import com.ethiograde.ui.theme.LocalEthioColors

@Composable
fun OfflineBadge(modifier: Modifier = Modifier) {
    val ethio = LocalEthioColors.current
    Surface(
        modifier = modifier,
        color = ethio.successContainer,
        shape = RoundedCornerShape(20.dp)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Icon(
                Icons.Default.WifiOff,
                contentDescription = stringResource(R.string.offline_badge),
                tint = ethio.success,
                modifier = Modifier.size(14.dp)
            )
            Text(
                text = stringResource(R.string.offline_badge),
                style = MaterialTheme.typography.labelSmall,
                color = ethio.success,
                fontWeight = FontWeight.Bold
            )
        }
    }
}

@Composable
fun MiniStatCard(
    label: String,
    value: String,
    icon: ImageVector,
    tint: Color,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier,
        color = MaterialTheme.colorScheme.surface,
        shape = MaterialTheme.shapes.medium,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(32.dp)
                    .clip(CircleShape)
                    .background(tint.copy(alpha = 0.12f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(icon, contentDescription = label, tint = tint, modifier = Modifier.size(18.dp))
            }
            Text(
                text = value,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface
            )
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
fun AssessmentCard(
    assessment: Assessment,
    results: List<ScanResult>,
    onPrimaryAction: () -> Unit,
    onOpenCard: () -> Unit,
    onDelete: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val ethio = LocalEthioColors.current
    val opState = assessment.operationalState(results)
    val nextAction = assessment.nextAction(results)
    val actionCount = results.count { it.requiresTeacherAction(assessment.answerKeyFingerprint) }

    val (badgeText, badgeColor, badgeBg) = when (opState) {
        AssessmentOperationalState.NEEDS_SETUP -> Triple("Setup Needed", MaterialTheme.colorScheme.error, MaterialTheme.colorScheme.errorContainer)
        AssessmentOperationalState.NEEDS_KEY -> Triple("Key Incomplete", ethio.warning, ethio.warningContainer)
        AssessmentOperationalState.READY_TO_SCAN -> Triple("Ready to Scan", MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.primaryContainer)
        AssessmentOperationalState.IN_PROGRESS -> Triple("${results.size} Graded", ethio.info, ethio.info.copy(alpha = 0.12f))
        AssessmentOperationalState.NEEDS_REVIEW -> Triple("$actionCount Need Review", ethio.warning, ethio.warningContainer)
        AssessmentOperationalState.COMPLETED -> Triple("Completed", ethio.success, ethio.successContainer)
    }

    val ctaLabel = when (nextAction) {
        AssessmentNextAction.FINISH_KEY -> "Finish Key"
        AssessmentNextAction.START_SCANNING -> "Start Scan"
        AssessmentNextAction.RESUME_SCANNING -> "Scan More"
        AssessmentNextAction.REVIEW_PAPERS -> "Review ($actionCount)"
        AssessmentNextAction.VIEW_RESULTS -> "View Results"
    }

    Surface(
        modifier = modifier
            .fillMaxWidth()
            .testTag("assessment_card_${assessment.id}")
            .clickable { onOpenCard() },
        color = MaterialTheme.colorScheme.surface,
        shape = MaterialTheme.shapes.medium,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Surface(color = badgeBg, shape = RoundedCornerShape(8.dp)) {
                    Text(
                        text = badgeText,
                        style = MaterialTheme.typography.labelSmall,
                        color = badgeColor,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                    )
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = "${assessment.questionCount}Q • ${assessment.maxScore.toInt()} pts",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    if (onDelete != null) {
                        IconButton(
                            onClick = onDelete,
                            modifier = Modifier.size(36.dp)
                        ) {
                            Icon(
                                Icons.Default.DeleteOutline,
                                contentDescription = "Delete assessment",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    }
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = assessment.title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = listOf(assessment.subject, assessment.className.ifBlank { "All Classes" }, assessment.category)
                    .filter { it.isNotBlank() }
                    .joinToString(" • "),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(modifier = Modifier.height(12.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (results.isNotEmpty()) {
                    val avg = results.sumOf { it.percentage } / results.size
                    Text(
                        text = "Avg ${"%.1f".format(avg)}% • ${results.size} papers",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.SemiBold
                    )
                } else {
                    Text(
                        text = "Key: ${assessment.answeredQuestionCount}/${assessment.questionCount}",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                FilledTonalButton(
                    onClick = onPrimaryAction,
                    modifier = Modifier.heightIn(min = 40.dp).testTag("assessment_cta_${assessment.id}")
                ) {
                    Text(ctaLabel, style = MaterialTheme.typography.labelMedium)
                    Spacer(modifier = Modifier.width(4.dp))
                    Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null, modifier = Modifier.size(16.dp))
                }
            }
        }
    }
}

@Composable
fun CreateOrEditClassDialog(
    initialClass: ClassInfo? = null,
    subjects: List<String>,
    academicYear: String,
    onDismiss: () -> Unit,
    onSave: (ClassInfo) -> Unit
) {
    var grade by remember { mutableIntStateOf(initialClass?.grade ?: 5) }
    var section by remember { mutableStateOf(initialClass?.section ?: "A") }
    var subject by remember { mutableStateOf(initialClass?.subject ?: (subjects.firstOrNull() ?: "Mathematics")) }
    var customName by remember { mutableStateOf(initialClass?.name ?: "") }
    var isHomeroom by remember { mutableStateOf(initialClass?.isHomeroom ?: false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (initialClass == null) "Create Class" else "Edit Class") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = customName,
                    onValueChange = { customName = it },
                    label = { Text("Class Name (optional)") },
                    placeholder = { Text("Grade $grade$section — $subject") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().testTag("class_name_input")
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    OutlinedTextField(
                        value = grade.toString(),
                        onValueChange = { grade = (it.toIntOrNull() ?: grade).coerceIn(1, 12) },
                        label = { Text("Grade (1-12)") },
                        singleLine = true,
                        modifier = Modifier.weight(1f)
                    )
                    OutlinedTextField(
                        value = section,
                        onValueChange = { section = it.uppercase().take(3) },
                        label = { Text("Section") },
                        singleLine = true,
                        modifier = Modifier.weight(1f)
                    )
                }
                var expanded by remember { mutableStateOf(false) }
                Box {
                    OutlinedTextField(
                        value = subject,
                        onValueChange = { subject = it },
                        label = { Text("Subject") },
                        readOnly = true,
                        trailingIcon = {
                            IconButton(onClick = { expanded = true }) {
                                Icon(Icons.Default.ArrowDropDown, contentDescription = "Select subject")
                            }
                        },
                        modifier = Modifier.fillMaxWidth().clickable { expanded = true }
                    )
                    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                        subjects.forEach { s ->
                            DropdownMenuItem(
                                text = { Text(s) },
                                onClick = { subject = s; expanded = false }
                            )
                        }
                    }
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Homeroom Class (Card Day)", style = MaterialTheme.typography.bodyMedium)
                    Switch(checked = isHomeroom, onCheckedChange = { isHomeroom = it })
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val finalName = customName.trim().ifEmpty { "Grade $grade$section — $subject" }
                    onSave(
                        (initialClass ?: ClassInfo(name = finalName)).copy(
                            name = finalName,
                            grade = grade,
                            section = section.ifBlank { "A" },
                            subject = subject,
                            academicYear = academicYear,
                            isHomeroom = isHomeroom
                        )
                    )
                },
                modifier = Modifier.testTag("save_class_button")
            ) {
                Text("Save")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    )
}
