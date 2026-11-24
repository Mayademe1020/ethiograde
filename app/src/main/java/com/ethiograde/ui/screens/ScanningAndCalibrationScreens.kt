package com.ethiograde.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import android.view.ViewGroup
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.ethiograde.model.*
import com.ethiograde.service.OmrAndOcrService
import com.ethiograde.viewmodel.EthioGradeUiState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CameraScanScreen(
    assessment: Assessment,
    batchMode: Boolean,
    state: EthioGradeUiState,
    onBack: () -> Unit,
    onGradePhotoUri: (android.net.Uri, Student?, (ScanResult?, String?) -> Unit) -> Unit,
    onGradeCapturedFile: (String, Student?, (ScanResult?, String?) -> Unit) -> Unit,
    onGradeBitmap: (android.graphics.Bitmap, Student?, (ScanResult, String?) -> Unit) -> Unit,
    onOpenCalibration: () -> Unit,
    onOpenReview: () -> Unit
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()

    var hasCameraPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        )
    }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        hasCameraPermission = granted
    }

    var selectedStudent by remember { mutableStateOf<Student?>(null) }
    var lastScanMsg by remember { mutableStateOf<String?>(null) }
    var imageCapture by remember { mutableStateOf<ImageCapture?>(null) }
    var boundCameraProvider by remember { mutableStateOf<ProcessCameraProvider?>(null) }
    val classStudents = remember(state.students, assessment.classId) {
        if (assessment.classId.isNotBlank()) state.studentsInClass(assessment.classId) else state.students
    }

    DisposableEffect(lifecycleOwner) {
        onDispose {
            runCatching { boundCameraProvider?.unbindAll() }
        }
    }

    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) {
            onGradePhotoUri(uri, selectedStudent) { res, dup ->
                lastScanMsg = if (res != null) {
                    "Graded ${res.studentName}: ${"%.1f".format(res.totalScore)}/${"%.0f".format(res.maxScore)} (${res.grade})" +
                        (dup?.let { " • $it" } ?: "")
                } else dup ?: "Scan failed"
            }
        }
    }

    val recentSessionResults = state.resultsForAssessment(assessment.id)

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(if (batchMode) "Batch Scan • ${assessment.title}" else "Scan Paper • ${assessment.title}", maxLines = 1)
                        Text("${recentSessionResults.size} graded so far", style = MaterialTheme.typography.labelSmall)
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                },
                actions = {
                    IconButton(onClick = onOpenCalibration) {
                        Icon(Icons.Default.Tune, contentDescription = "OMR Calibration")
                    }
                    TextButton(onClick = onOpenReview) { Text("Review (${recentSessionResults.size})") }
                }
            )
        },
        contentWindowInsets = WindowInsets.safeDrawing
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            // Optional student pre-selection strip
            if (classStudents.isNotEmpty()) {
                LazyRow(
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    item {
                        FilterChip(
                            selected = selectedStudent == null,
                            onClick = { selectedStudent = null },
                            label = { Text("Auto-Detect Name") }
                        )
                    }
                    items(classStudents, key = { it.id }) { st ->
                        FilterChip(
                            selected = selectedStudent?.id == st.id,
                            onClick = { selectedStudent = st },
                            label = { Text(st.fullName) }
                        )
                    }
                }
            }

            // Camera Preview or Permission / Photo Fallback Box
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .background(Color.Black),
                contentAlignment = Alignment.Center
            ) {
                if (hasCameraPermission) {
                    AndroidView(
                        factory = { ctx ->
                            val previewView = PreviewView(ctx).apply {
                                layoutParams = ViewGroup.LayoutParams(
                                    ViewGroup.LayoutParams.MATCH_PARENT,
                                    ViewGroup.LayoutParams.MATCH_PARENT
                                )
                            }
                            val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)
                            cameraProviderFuture.addListener({
                                runCatching {
                                    val cameraProvider = cameraProviderFuture.get()
                                    boundCameraProvider = cameraProvider
                                    val preview = Preview.Builder().build().also {
                                        it.surfaceProvider = previewView.surfaceProvider
                                    }
                                    val capture = ImageCapture.Builder().build()
                                    imageCapture = capture
                                    cameraProvider.unbindAll()
                                    cameraProvider.bindToLifecycle(
                                        lifecycleOwner,
                                        CameraSelector.DEFAULT_BACK_CAMERA,
                                        preview,
                                        capture
                                    )
                                }
                            }, ContextCompat.getMainExecutor(ctx))
                            previewView
                        },
                        modifier = Modifier.fillMaxSize()
                    )
                    // Paper alignment guide frame
                    Box(
                        modifier = Modifier
                            .fillMaxWidth(0.86f)
                            .fillMaxHeight(0.82f)
                            .border(2.dp, Color.White.copy(alpha = 0.7f), RoundedCornerShape(16.dp))
                    )
                } else {
                    Column(
                        modifier = Modifier.padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Icon(Icons.Default.CameraAlt, contentDescription = null, tint = Color.White, modifier = Modifier.size(48.dp))
                        Text(
                            "Grant Camera permission to scan live sheets, or import an exam photo below.",
                            color = Color.White
                        )
                        Button(onClick = { permissionLauncher.launch(Manifest.permission.CAMERA) }) {
                            Text("Allow Camera")
                        }
                    }
                }

                if (state.isScanning) {
                    Surface(color = Color.Black.copy(alpha = 0.7f), shape = MaterialTheme.shapes.medium) {
                        Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(modifier = Modifier.size(24.dp), color = Color.White)
                            Spacer(modifier = Modifier.width(12.dp))
                            Text("Running OMR + OCR…", color = Color.White)
                        }
                    }
                }
            }

            lastScanMsg?.let { msg ->
                Surface(color = MaterialTheme.colorScheme.primaryContainer, modifier = Modifier.fillMaxWidth()) {
                    Text(msg, modifier = Modifier.padding(12.dp), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                }
            }

            // Bottom Action Controls
            Surface(tonalElevation = 4.dp) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(14.dp),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    FilledTonalButton(
                        enabled = !state.isScanning,
                        onClick = {
                            photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                        },
                        modifier = Modifier.heightIn(min = 48.dp).testTag("scan_import_photo_button")
                    ) {
                        Icon(Icons.Default.PhotoLibrary, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("Import Photo")
                    }

                    if (hasCameraPermission && imageCapture != null) {
                        FloatingActionButton(
                            onClick = {
                                if (state.isScanning) return@FloatingActionButton
                                val cap = imageCapture ?: return@FloatingActionButton
                                val file = File(context.cacheDir, "cam_${System.currentTimeMillis()}.jpg")
                                val opts = ImageCapture.OutputFileOptions.Builder(file).build()
                                cap.takePicture(
                                    opts,
                                    ContextCompat.getMainExecutor(context),
                                    object : ImageCapture.OnImageSavedCallback {
                                        override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
                                            onGradeCapturedFile(file.absolutePath, selectedStudent) { res, dup ->
                                                lastScanMsg = if (res != null) {
                                                    "Graded ${res.studentName}: ${"%.1f".format(res.totalScore)}/${"%.0f".format(res.maxScore)}" +
                                                        (dup?.let { " • $it" } ?: "")
                                                } else dup ?: "Scan failed"
                                            }
                                        }

                                        override fun onError(exception: ImageCaptureException) {
                                            runCatching { file.delete() }
                                            lastScanMsg = "Camera capture error: ${exception.message}"
                                        }
                                    }
                                )
                            },
                            shape = CircleShape,
                            containerColor = if (state.isScanning) MaterialTheme.colorScheme.surfaceVariant else MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(64.dp).testTag("camera_shutter_button")
                        ) {
                            Icon(Icons.Default.Camera, contentDescription = "Capture Paper", modifier = Modifier.size(28.dp))
                        }
                    }

                    OutlinedButton(
                        enabled = !state.isScanning,
                        onClick = {
                            scope.launch {
                                val bmp = withContext(Dispatchers.Default) {
                                    OmrAndOcrService.generateSampleOmrBitmap(assessment)
                                }
                                onGradeBitmap(bmp, selectedStudent ?: classStudents.firstOrNull()) { res, _ ->
                                    lastScanMsg = "Sample sheet graded for ${res.studentName}: ${"%.1f".format(res.totalScore)}/${"%.0f".format(res.maxScore)} (${res.grade})"
                                }
                            }
                        },
                        modifier = Modifier.heightIn(min = 48.dp).testTag("scan_sample_sheet_button")
                    ) {
                        Text("Test Sheet")
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OmrCalibrationScreen(
    assessment: Assessment,
    savedTemplate: BubbleTemplate? = null,
    onBack: () -> Unit,
    onSaveCalibration: (BubbleTemplate) -> Unit
) {
    val defaultTpl = remember(assessment.id) {
        StandardTemplates.matchAssessment(
            assessment.questionCount,
            assessment.mcqCount == 0 && assessment.trueFalseCount > 0
        )
    }
    var selected by remember { mutableStateOf(defaultTpl) }
    var threshold by remember { mutableFloatStateOf(selected.fillThreshold.toFloat()) }
    var offsetX by remember { mutableFloatStateOf(0f) }
    var offsetY by remember { mutableFloatStateOf(0f) }
    var calibrationInfo by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(savedTemplate) {
        if (savedTemplate != null) {
            val base = StandardTemplates.all.firstOrNull { it.name == savedTemplate.name } ?: defaultTpl
            selected = base
            threshold = savedTemplate.fillThreshold.toFloat()
            offsetX = (savedTemplate.startX - base.startX).toFloat().coerceIn(-60f, 60f)
            offsetY = (savedTemplate.startY - base.startY).toFloat().coerceIn(-60f, 60f)
        }
    }

    val adjustedTemplate = remember(selected, threshold, offsetX, offsetY) {
        selected.copy(
            startX = selected.startX + offsetX.toDouble(),
            startY = selected.startY + offsetY.toDouble(),
            fillThreshold = threshold.toDouble()
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("OMR Calibration") },
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
            item {
                Text("Select Bubble Sheet Template", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            }
            items(StandardTemplates.all) { tpl ->
                Surface(
                    color = if (selected.name == tpl.name) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface,
                    shape = MaterialTheme.shapes.medium,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier.padding(14.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(tpl.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                            Text("${tpl.questionCount} questions • Options: ${tpl.options.joinToString(",")}", style = MaterialTheme.typography.bodySmall)
                        }
                        RadioButton(selected = selected.name == tpl.name, onClick = {
                            selected = tpl
                            threshold = tpl.fillThreshold.toFloat()
                            offsetX = 0f
                            offsetY = 0f
                        })
                    }
                }
            }
            item {
                Text("Fill Sensitivity Threshold: ${(threshold * 100).toInt()}%", style = MaterialTheme.typography.titleSmall)
                Slider(value = threshold, onValueChange = { threshold = it }, valueRange = 0.15f..0.60f)
            }
            item {
                Text("Horizontal Margin Shift (X): ${offsetX.roundToInt()} px", style = MaterialTheme.typography.titleSmall)
                Slider(value = offsetX, onValueChange = { offsetX = it }, valueRange = -60f..60f)
                Text("Vertical Margin Shift (Y): ${offsetY.roundToInt()} px", style = MaterialTheme.typography.titleSmall)
                Slider(value = offsetY, onValueChange = { offsetY = it }, valueRange = -60f..60f)
            }
            item {
                OutlinedButton(
                    onClick = {
                        val bmp = OmrAndOcrService.generateSampleOmrBitmap(assessment)
                        val out = OmrAndOcrService.detectBubbles(bmp, adjustedTemplate)
                        calibrationInfo = "Aligned ${out.detectedAnswers.size}/${assessment.questionCount.coerceAtMost(adjustedTemplate.questionCount)} bubbles (${adjustedTemplate.name})"
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Test Template Alignment")
                }
            }
            calibrationInfo?.let { info ->
                item {
                    Surface(color = MaterialTheme.colorScheme.primaryContainer, shape = MaterialTheme.shapes.small) {
                        Text(info, modifier = Modifier.fillMaxWidth().padding(12.dp))
                    }
                }
            }
            item {
                Button(
                    onClick = {
                        onSaveCalibration(adjustedTemplate)
                        onBack()
                    },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp).testTag("save_omr_calibration_button")
                ) {
                    Text("Save Calibration")
                }
            }
        }
    }
}
