package com.ethiograde.service

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Matrix
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import com.ethiograde.model.*
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import kotlin.coroutines.resume
import kotlin.math.min
import kotlin.math.roundToInt

data class OmrScanOutput(
    val detectedAnswers: List<DetectedAnswer>,
    val fillMatrix: Map<Int, Map<String, Double>>,
    val templateName: String
)

data class GradingPipelineOutput(
    val scanResult: ScanResult,
    val proofVaultEntry: ProofVaultEntry
)

object OmrAndOcrService {

    private fun calculateInSampleSize(width: Int, height: Int, maxDim: Int): Int {
        var inSampleSize = 1
        var longest = maxOf(width, height)
        while (longest / 2 >= maxDim) {
            longest /= 2
            inSampleSize *= 2
        }
        return inSampleSize.coerceAtLeast(1)
    }

    suspend fun loadOrientedBitmapAsync(context: Context, uri: Uri, maxDim: Int = 1600): Bitmap? =
        withContext(Dispatchers.IO) { loadOrientedBitmap(context, uri, maxDim) }

    suspend fun loadOrientedBitmapFromFileAsync(filePath: String, maxDim: Int = 1600): Bitmap? =
        withContext(Dispatchers.IO) { loadOrientedBitmapFromFile(filePath, maxDim) }

    fun loadOrientedBitmap(context: Context, uri: Uri, maxDim: Int = 1600): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream, null, bounds)
        }
        val sampleSize = if (bounds.outWidth > 0 && bounds.outHeight > 0) {
            calculateInSampleSize(bounds.outWidth, bounds.outHeight, maxDim)
        } else 1

        val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sampleSize }
        val raw = context.contentResolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream, null, decodeOpts)
        } ?: return null

        val orientation = runCatching {
            context.contentResolver.openInputStream(uri)?.use { stream ->
                ExifInterface(stream).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL
                )
            }
        }.getOrNull() ?: ExifInterface.ORIENTATION_NORMAL

        return finalizeOrientedBitmap(raw, orientation, maxDim)
    }

    fun loadOrientedBitmapFromFile(filePath: String, maxDim: Int = 1600): Bitmap? {
        val file = File(filePath)
        if (!file.exists()) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(filePath, bounds)
        val sampleSize = if (bounds.outWidth > 0 && bounds.outHeight > 0) {
            calculateInSampleSize(bounds.outWidth, bounds.outHeight, maxDim)
        } else 1

        val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sampleSize }
        val raw = BitmapFactory.decodeFile(filePath, decodeOpts) ?: return null
        val orientation = runCatching {
            ExifInterface(filePath).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )
        }.getOrNull() ?: ExifInterface.ORIENTATION_NORMAL

        return finalizeOrientedBitmap(raw, orientation, maxDim)
    }

    private fun finalizeOrientedBitmap(raw: Bitmap, orientation: Int, maxDim: Int): Bitmap {
        val rotated = rotateBitmap(raw, orientation)
        if (rotated !== raw) raw.recycle()
        val longest = maxOf(rotated.width, rotated.height)
        if (longest <= maxDim) return rotated
        val ratio = maxDim.toFloat() / longest
        val w = (rotated.width * ratio).roundToInt().coerceAtLeast(1)
        val h = (rotated.height * ratio).roundToInt().coerceAtLeast(1)
        val scaled = Bitmap.createScaledBitmap(rotated, w, h, true)
        if (scaled !== rotated) rotated.recycle()
        return scaled
    }

    private fun rotateBitmap(bmp: Bitmap, orientation: Int): Bitmap {
        val degrees = when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> 0f
        }
        if (degrees == 0f) return bmp
        val m = Matrix().apply { postRotate(degrees) }
        return Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
    }

    fun saveBitmapToAppStorage(context: Context, bmp: Bitmap, prefix: String = "scan"): String {
        val dir = File(context.filesDir, "scans").apply { mkdirs() }
        val file = File(dir, "${prefix}_${System.currentTimeMillis()}.jpg")
        FileOutputStream(file).use { out ->
            bmp.compress(Bitmap.CompressFormat.JPEG, 92, out)
        }
        return file.absolutePath
    }

    fun computeDHash(bmp: Bitmap): String {
        val scaled = Bitmap.createScaledBitmap(bmp, 9, 8, true)
        val pixels = IntArray(9 * 8)
        scaled.getPixels(pixels, 0, 9, 0, 0, 9, 8)
        if (scaled !== bmp) scaled.recycle()
        val bits = StringBuilder(64)
        for (y in 0 until 8) {
            val rowOff = y * 9
            for (x in 0 until 8) {
                val left = pixelLuminance(pixels[rowOff + x])
                val right = pixelLuminance(pixels[rowOff + x + 1])
                bits.append(if (left > right) '1' else '0')
            }
        }
        return bits.toString()
    }

    private fun pixelLuminance(argb: Int): Float {
        val r = (argb ushr 16) and 0xFF
        val g = (argb ushr 8) and 0xFF
        val b = argb and 0xFF
        return (0.2126f * r + 0.7152f * g + 0.0722f * b) / 255f
    }

    private fun estimateAdaptiveDarkCutoff(pixels: IntArray, width: Int, height: Int): Float {
        val stepX = (width / 24).coerceAtLeast(8)
        val stepY = (height / 32).coerceAtLeast(8)
        val samples = mutableListOf<Float>()
        var y = 0
        while (y < height) {
            val rowOff = y * width
            var x = 0
            while (x < width) {
                samples.add(pixelLuminance(pixels[rowOff + x]))
                x += stepX
            }
            y += stepY
        }
        if (samples.isEmpty()) return 0.60f
        samples.sort()
        val paperLum = samples[(samples.size * 3) / 4]
        return (paperLum * 0.64f).coerceIn(0.32f, 0.64f)
    }

    fun detectBubbles(bmp: Bitmap, template: BubbleTemplate): OmrScanOutput {
        val w = bmp.width
        val h = bmp.height
        val pixels = IntArray(w * h)
        bmp.getPixels(pixels, 0, w, 0, 0, w, h)
        val darkCutoff = estimateAdaptiveDarkCutoff(pixels, w, h)

        val scale = w / 1600.0
        val startX = template.startX * scale
        val startY = template.startY * scale
        val colSpacing = template.columnSpacing * scale
        val rowSpacing = template.rowSpacing * scale
        val radius = (template.bubbleRadius * scale).roundToInt().coerceAtLeast(3)

        val answers = mutableListOf<DetectedAnswer>()
        val fillMatrix = mutableMapOf<Int, Map<String, Double>>()

        for (qi in 0 until template.questionCount) {
            val fills = mutableMapOf<String, Double>()
            var bestOpt: String? = null
            var bestFill = 0.0

            for (oi in 0 until template.optionCount) {
                val cx = (startX + oi * colSpacing).roundToInt()
                val cy = (startY + qi * rowSpacing).roundToInt()
                val ratio = sampleDarkRatio(pixels, w, h, cx, cy, radius, darkCutoff)
                val opt = template.options[oi]
                fills[opt] = ratio
                if (ratio > template.fillThreshold && ratio > bestFill) {
                    bestFill = ratio
                    bestOpt = opt
                }
            }
            fillMatrix[qi + 1] = fills

            if (bestOpt != null) {
                val multi = fills.values.count { it > template.fillThreshold }
                if (multi > 1) {
                    answers.add(
                        DetectedAnswer(
                            questionNumber = qi + 1,
                            answer = "[MULTIPLE]",
                            confidence = 0.2,
                            rawText = "[OMR MULTIPLE]",
                            needsReview = true,
                            source = "omr"
                        )
                    )
                } else {
                    val conf = 0.5 + ((bestFill - template.fillThreshold) / (1.0 - template.fillThreshold)) * 0.5
                    answers.add(
                        DetectedAnswer(
                            questionNumber = qi + 1,
                            answer = bestOpt,
                            confidence = conf.coerceIn(0.5, 1.0),
                            rawText = "[OMR fill=${(bestFill * 100).roundToInt()}%]",
                            source = "omr"
                        )
                    )
                }
            }
        }
        return OmrScanOutput(answers, fillMatrix, template.name)
    }

    private fun sampleDarkRatio(
        pixels: IntArray,
        w: Int,
        h: Int,
        cx: Int,
        cy: Int,
        radius: Int,
        darkCutoff: Float
    ): Double {
        var dark = 0
        var total = 0
        for (dy in -radius..radius) {
            val py = cy + dy
            if (py < 0 || py >= h) continue
            val rowOff = py * w
            for (dx in -radius..radius) {
                val px = cx + dx
                if (px < 0 || px >= w) continue
                if (pixelLuminance(pixels[rowOff + px]) < darkCutoff) dark++
                total++
            }
        }
        return if (total > 0) dark.toDouble() / total else 0.0
    }

    suspend fun extractTextRegions(bmp: Bitmap): List<TextRegionInput> = suspendCancellableCoroutine { cont ->
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        val inputImage = InputImage.fromBitmap(bmp, 0)
        recognizer.process(inputImage)
            .addOnSuccessListener { result ->
                val list = mutableListOf<TextRegionInput>()
                for (block in result.textBlocks) {
                    for (line in block.lines) {
                        val txt = line.text.trim()
                        if (txt.isEmpty()) continue
                        val box = line.boundingBox
                        val conf = line.elements.map { it.confidence.toDouble() }.takeIf { it.isNotEmpty() }?.average() ?: 0.78
                        list.add(
                            TextRegionInput(
                                text = txt,
                                confidence = conf.coerceIn(0.1, 1.0),
                                x = box?.left?.toDouble() ?: 0.0,
                                y = box?.top?.toDouble() ?: 0.0
                            )
                        )
                    }
                }
                recognizer.close()
                if (cont.isActive) cont.resume(list)
            }
            .addOnFailureListener {
                recognizer.close()
                if (cont.isActive) cont.resume(emptyList())
            }
    }

    suspend fun gradePaperBitmap(
        context: Context,
        bmp: Bitmap,
        assessment: Assessment,
        classStudents: List<Student>,
        preferredStudent: Student? = null,
        template: BubbleTemplate? = null,
        customScales: List<GradingScale> = emptyList(),
        existingImagePath: String = ""
    ): GradingPipelineOutput = withContext(Dispatchers.Default) {
        val imagePath = existingImagePath.ifBlank { saveBitmapToAppStorage(context, bmp) }
        val imageHash = computeDHash(bmp)
        val regions = extractTextRegions(bmp)
        val ocrText = regions.joinToString("\n") { it.text }

        // Student match
        val resolvedStudent = preferredStudent ?: StudentMatcher.matchFromOcr(ocrText, classStudents).matchedStudent

        val ocrAnswers = AnswerParser.parseAnswersWithPosition(regions)
        val effectiveTemplate = template ?: StandardTemplates.matchAssessment(
            questionCount = assessment.questionCount,
            isTrueFalse = assessment.mcqCount == 0 && assessment.trueFalseCount > 0
        )
        val omrOut = detectBubbles(bmp, effectiveTemplate)

        // Merge OMR + OCR
        val merged = mutableListOf<DetectedAnswer>()
        val ocrByQ = ocrAnswers.associateBy { it.questionNumber }
        val omrByQ = omrOut.detectedAnswers.associateBy { it.questionNumber }
        for (q in assessment.questions) {
            val omr = omrByQ[q.number]
            val ocr = ocrByQ[q.number]
            if (q.type == QuestionType.MCQ || q.type == QuestionType.TRUE_FALSE) {
                when {
                    omr != null && omr.confidence >= 0.5 -> merged.add(omr)
                    ocr != null -> merged.add(ocr)
                    omr != null -> merged.add(omr)
                }
            } else if (ocr != null) {
                merged.add(ocr)
            }
        }

        val deduped = ScoringService.deduplicateAnswers(merged)
        val scored = ScoringService.scoreAnswers(deduped, assessment)
        val total = scored.sumOf { it.score }
        val max = assessment.maxScore
        val pct = if (max > 0) (total / max * 100.0).coerceIn(0.0, 100.0) else 0.0
        val grade = ScoringService.calculateGrade(pct, assessment.rubricType, customScales)
        val avgConf = if (scored.isEmpty()) 0.0 else scored.sumOf { it.confidence } / scored.size

        val uncertain = deduped.filter { it.needsReview }.map { it.questionNumber }.sorted()
        val fp = assessment.answerKeyFingerprint.ifEmpty { assessment.computeAnswerKeyFingerprint() }

        val scanResult = ScanResult(
            assessmentId = assessment.id,
            studentId = resolvedStudent?.id ?: "",
            studentName = resolvedStudent?.fullName ?: "Unknown Student",
            imagePath = imagePath,
            enhancedImagePath = imagePath,
            answers = scored,
            totalScore = total,
            maxScore = max,
            percentage = pct,
            grade = grade,
            status = if (avgConf < 0.35 && scored.count { it.detectedAnswer != "[MISSING]" } == 0) {
                ScanStatus.NEEDS_RESCAN
            } else {
                ScanStatus.GRADED
            },
            confidence = avgConf,
            imageHash = imageHash,
            uncertainQuestions = uncertain,
            detectedMethod = if (omrOut.detectedAnswers.isNotEmpty() && ocrAnswers.isNotEmpty()) "hybrid"
            else if (omrOut.detectedAnswers.isNotEmpty()) "omr-only" else "ocr-only",
            scoredWithKeyFingerprint = fp,
            scoredWithKeyRevision = assessment.answerKeyRevision
        )

        val now = scanResult.scannedAtMillis
        val detectedMap = scored.associate { it.questionNumber to it.detectedAnswer }
        val proof = ProofVaultEntry(
            id = "${assessment.id}_${scanResult.studentId.ifBlank { scanResult.id }}",
            assessmentId = assessment.id,
            studentId = scanResult.studentId.ifBlank { scanResult.id },
            studentName = scanResult.studentName,
            totalScore = scanResult.totalScore,
            maxScore = scanResult.maxScore,
            bubbleDensities = omrOut.fillMatrix,
            detectedAnswers = detectedMap,
            integrityHash = ProofVaultEntry.computeProofHash(
                assessmentId = assessment.id,
                studentId = scanResult.studentId.ifBlank { scanResult.id },
                totalScore = scanResult.totalScore,
                bubbleDensities = omrOut.fillMatrix,
                detectedAnswers = detectedMap,
                scannedAtMillis = now
            ),
            scannedAtMillis = now
        )
        GradingPipelineOutput(scanResult, proof)
    }

    fun generateSampleOmrBitmap(assessment: Assessment): Bitmap {
        val w = 1600
        val h = 2100
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bmp)
        canvas.drawColor(Color.WHITE)

        val titlePaint = android.graphics.Paint().apply {
            color = Color.BLACK
            textSize = 44f
            isFakeBoldText = true
            isAntiAlias = true
        }
        val textPaint = android.graphics.Paint().apply {
            color = Color.DKGRAY
            textSize = 32f
            isAntiAlias = true
        }
        val ringPaint = android.graphics.Paint().apply {
            color = Color.DKGRAY
            style = android.graphics.Paint.Style.STROKE
            strokeWidth = 3f
            isAntiAlias = true
        }
        val fillPaint = android.graphics.Paint().apply {
            color = Color.rgb(30, 30, 30)
            style = android.graphics.Paint.Style.FILL
            isAntiAlias = true
        }

        canvas.drawText("EthioGrade Bubble Sheet - ${assessment.title}", 100f, 110f, titlePaint)
        canvas.drawText("Name: Practice Sheet", 100f, 165f, textPaint)

        val tpl = StandardTemplates.matchAssessment(
            assessment.questionCount,
            assessment.mcqCount == 0 && assessment.trueFalseCount > 0
        )
        val qLimit = min(assessment.questions.size, tpl.questionCount)
        for (qi in 0 until qLimit) {
            val q = assessment.questions[qi]
            val yRow = (tpl.startY + qi * tpl.rowSpacing).toFloat()
            canvas.drawText("${q.number}.", (tpl.startX - 75).toFloat(), yRow + 10f, textPaint)
            for (oi in 0 until tpl.optionCount) {
                val opt = tpl.options[oi]
                val cx = (tpl.startX + oi * tpl.columnSpacing).toFloat()
                canvas.drawCircle(cx, yRow, tpl.bubbleRadius.toFloat() * 1.4f, ringPaint)
                if (q.correctAnswer.equals(opt, ignoreCase = true)) {
                    canvas.drawCircle(cx, yRow, tpl.bubbleRadius.toFloat() * 1.15f, fillPaint)
                }
            }
        }
        return bmp
    }
}
