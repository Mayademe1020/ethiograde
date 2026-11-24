package com.ethiograde.service

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Paint
import android.graphics.pdf.PdfDocument
import android.net.Uri
import androidx.core.content.FileProvider
import com.ethiograde.model.*
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

data class CsvImportResult(
    val success: Boolean,
    val message: String,
    val students: List<Student> = emptyList(),
    val warnings: List<String> = emptyList()
)

object PdfExportAndCsvService {

    fun shareFile(context: Context, file: File, mimeType: String, title: String) {
        val uri: Uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            file
        )
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, title)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, title))
    }

    fun generateResultsPdf(
        context: Context,
        assessment: Assessment,
        results: List<ScanResult>,
        schoolName: String,
        teacherName: String
    ): File {
        val doc = PdfDocument()
        val pageWidth = 595
        val pageHeight = 842
        val titlePaint = Paint().apply { color = Color.rgb(11, 110, 79); textSize = 18f; isFakeBoldText = true; isAntiAlias = true }
        val subPaint = Paint().apply { color = Color.DKGRAY; textSize = 11f; isAntiAlias = true }
        val rowPaint = Paint().apply { color = Color.BLACK; textSize = 10.5f; isAntiAlias = true }
        val linePaint = Paint().apply { color = Color.LTGRAY; strokeWidth = 1f }

        var pageNum = 1
        var page = doc.startPage(PdfDocument.PageInfo.Builder(pageWidth, pageHeight, pageNum).create())
        var canvas = page.canvas
        var y = 48f

        fun drawHeader() {
            canvas.drawText(schoolName.ifBlank { "EthioGrade Assessment Report" }, 40f, y, titlePaint)
            y += 20f
            canvas.drawText("${assessment.title}  •  ${assessment.subject}  •  Teacher: ${teacherName.ifBlank { "—" }}", 40f, y, subPaint)
            y += 18f
            canvas.drawLine(40f, y, pageWidth - 40f, y, linePaint)
            y += 18f
            canvas.drawText("#   Student Name", 40f, y, rowPaint)
            canvas.drawText("Score", 330f, y, rowPaint)
            canvas.drawText("Percent", 410f, y, rowPaint)
            canvas.drawText("Grade", 495f, y, rowPaint)
            y += 10f
            canvas.drawLine(40f, y, pageWidth - 40f, y, linePaint)
            y += 16f
        }

        drawHeader()
        results.sortedByDescending { it.totalScore }.forEachIndexed { idx, res ->
            if (y > pageHeight - 60) {
                doc.finishPage(page)
                pageNum++
                page = doc.startPage(PdfDocument.PageInfo.Builder(pageWidth, pageHeight, pageNum).create())
                canvas = page.canvas
                y = 48f
                drawHeader()
            }
            canvas.drawText("${idx + 1}.  ${res.studentName.take(34)}", 40f, y, rowPaint)
            canvas.drawText("${"%.1f".format(res.totalScore)}/${"%.0f".format(res.maxScore)}", 330f, y, rowPaint)
            canvas.drawText("${"%.1f".format(res.percentage)}%", 410f, y, rowPaint)
            canvas.drawText(res.grade, 500f, y, rowPaint)
            y += 20f
        }
        doc.finishPage(page)

        val outFile = File(context.filesDir, "Results_${assessment.title.replace(Regex("[^\\w]"), "_")}.pdf")
        FileOutputStream(outFile).use { doc.writeTo(it) }
        doc.close()
        return outFile
    }

    fun generateHomeroomReportCardsPdf(
        context: Context,
        report: HomeroomClassReport,
        schoolName: String
    ): File {
        val doc = PdfDocument()
        val pageWidth = 595
        val pageHeight = 842
        val headerPaint = Paint().apply { color = Color.rgb(11, 110, 79); textSize = 13f; isFakeBoldText = true; isAntiAlias = true }
        val boldPaint = Paint().apply { color = Color.BLACK; textSize = 10f; isFakeBoldText = true; isAntiAlias = true }
        val bodyPaint = Paint().apply { color = Color.DKGRAY; textSize = 9.5f; isAntiAlias = true }
        val borderPaint = Paint().apply { color = Color.rgb(11, 110, 79); style = Paint.Style.STROKE; strokeWidth = 1.5f }

        // 4-up grid per A4 page
        val chunks = report.students.chunked(4)
        chunks.forEachIndexed { pIdx, fourStudents ->
            val page = doc.startPage(PdfDocument.PageInfo.Builder(pageWidth, pageHeight, pIdx + 1).create())
            val canvas = page.canvas
            fourStudents.forEachIndexed { slot, student ->
                val col = slot % 2
                val row = slot / 2
                val left = 24f + col * 280f
                val top = 24f + row * 395f
                canvas.drawRect(left, top, left + 266f, top + 380f, borderPaint)

                var y = top + 22f
                canvas.drawText(schoolName.ifBlank { "Ministry Report Card" }, left + 10f, y, headerPaint)
                y += 15f
                canvas.drawText("${report.className} • ${report.semester} • ${report.academicYear}", left + 10f, y, bodyPaint)
                y += 16f
                canvas.drawText("Student: ${student.fullName}", left + 10f, y, boldPaint)
                y += 14f
                canvas.drawText("Roll: ${student.rollNumber} | Sex: ${student.gender} | Rank: #${student.classRank}", left + 10f, y, bodyPaint)
                y += 16f

                report.subjectList.take(8).forEach { subName ->
                    val s = student.subjects[subName]
                    val scoreStr = if (s != null) "${"%.1f".format(s.totalScore)}% (${s.letterGrade})" else "—"
                    canvas.drawText(subName.take(18), left + 10f, y, bodyPaint)
                    canvas.drawText(scoreStr, left + 160f, y, boldPaint)
                    y += 14f
                }

                y = top + 318f
                canvas.drawText("Total: ${"%.1f".format(student.grandTotal)} | Avg: ${"%.1f".format(student.semesterAverage)}%", left + 10f, y, boldPaint)
                y += 14f
                canvas.drawText("Conduct: ${student.conduct} | Absent: ${student.absentDays}d", left + 10f, y, bodyPaint)
                y += 14f
                val remark = if (student.hasFinanceHold) "እዳ ያለበት (Finance Hold)" else student.remarkEn
                canvas.drawText(remark.take(40), left + 10f, y, bodyPaint)
            }
            doc.finishPage(page)
        }

        val outFile = File(context.filesDir, "ReportCards_${report.className.replace(Regex("[^\\w]"), "_")}.pdf")
        FileOutputStream(outFile).use { doc.writeTo(it) }
        doc.close()
        return outFile
    }

    fun generatePrintableBubbleSheetPdf(context: Context, assessment: Assessment): File {
        val doc = PdfDocument()
        val pageWidth = 595
        val pageHeight = 842
        val titlePaint = Paint().apply { color = Color.BLACK; textSize = 16f; isFakeBoldText = true; isAntiAlias = true }
        val textPaint = Paint().apply { color = Color.DKGRAY; textSize = 11f; isAntiAlias = true }
        val circlePaint = Paint().apply { color = Color.BLACK; style = Paint.Style.STROKE; strokeWidth = 1.2f; isAntiAlias = true }

        val options = listOf("A", "B", "C", "D", "E")
        val sortedQuestions = assessment.questions.sortedBy { it.number }
        val pages = if (sortedQuestions.isEmpty()) listOf(emptyList()) else sortedQuestions.chunked(60)

        pages.forEachIndexed { pIdx, pageQuestions ->
            val page = doc.startPage(PdfDocument.PageInfo.Builder(pageWidth, pageHeight, pIdx + 1).create())
            val canvas = page.canvas

            canvas.drawText("${assessment.title} — Answer Sheet (Page ${pIdx + 1}/${pages.size})", 40f, 48f, titlePaint)
            canvas.drawText("Student Name: _________________________   ID: ____________", 40f, 72f, textPaint)

            var y = 110f
            var colX = 40f
            pageQuestions.forEach { q ->
                if (y > 790f) {
                    y = 110f
                    colX += 265f
                }
                canvas.drawText("${q.number}.", colX, y + 4f, textPaint)
                options.forEachIndexed { oi, opt ->
                    val cx = colX + 40f + oi * 36f
                    canvas.drawCircle(cx, y, 8f, circlePaint)
                    canvas.drawText(opt, cx - 3.5f, y + 4f, textPaint)
                }
                y += 22f
            }
            doc.finishPage(page)
        }

        val outFile = File(context.filesDir, "AnswerSheet_${assessment.id.take(8)}.pdf")
        FileOutputStream(outFile).use { doc.writeTo(it) }
        doc.close()
        return outFile
    }

    fun exportResultsCsv(context: Context, assessment: Assessment, results: List<ScanResult>): File {
        val sb = StringBuilder()
        sb.appendLine("StudentName,StudentID,Score,MaxScore,Percentage,Grade,Status")
        for (r in results) {
            sb.appendLine("\"${r.studentName}\",\"${r.studentId}\",${r.totalScore},${r.maxScore},${"%.1f".format(r.percentage)}%,${r.grade},${r.status.name}")
        }
        val file = File(context.filesDir, "Results_${assessment.title.replace(Regex("[^\\w]"), "_")}.csv")
        file.writeText(sb.toString())
        return file
    }

    fun exportMinistryBroadsheetCsv(context: Context, report: HomeroomClassReport): File {
        val sb = StringBuilder()
        sb.appendLine("Ministry of Education - Semester Broadsheet")
        sb.appendLine("Class,${report.className},Semester,${report.semester},Year,${report.academicYear}")
        val headers = listOf("No", "Student Full Name", "Sex") + report.subjectList + listOf("Total", "Average %", "Rank", "Conduct", "Remark")
        sb.appendLine(headers.joinToString(",") { "\"$it\"" })
        report.students.forEachIndexed { idx, s ->
            val subScores = report.subjectList.map { name ->
                s.subjects[name]?.let { "%.1f".format(it.totalScore) } ?: "—"
            }
            val remark = if (s.hasFinanceHold) "እዳ ያለበት (Finance Hold)" else s.remarkAm
            val row = listOf(s.rollNumber.ifBlank { "${idx + 1}" }, s.fullName, s.gender) +
                subScores +
                listOf("%.1f".format(s.grandTotal), "%.1f%%".format(s.semesterAverage), "${s.classRank}", s.conduct, remark)
            sb.appendLine(row.joinToString(",") { "\"$it\"" })
        }
        val file = File(context.filesDir, "Broadsheet_${report.className.replace(Regex("[^\\w]"), "_")}.csv")
        file.writeText(sb.toString())
        return file
    }

    fun parseStudentsFromCsv(content: String, classId: String?, className: String = ""): CsvImportResult {
        val lines = content.lines().map { it.trim() }.filter { it.isNotEmpty() }
        if (lines.isEmpty()) return CsvImportResult(false, "CSV content is empty")

        val rows = lines.map { parseCsvLine(it) }
        val header = rows.first().map { it.lowercase().trim() }
        val firstIdx = header.indexOfFirst { it.contains("first") || it == "name" || it == "ስም" || it.contains("full") }.takeIf { it >= 0 } ?: 0
        val lastIdx = header.indexOfFirst { it.contains("last") || it.contains("father") || it.contains("surname") }
        val idIdx = header.indexOfFirst { it == "id" || it.contains("roll") || it.contains("student_id") || it.contains("student id") }
        val genderIdx = header.indexOfFirst { it.contains("gender") || it.contains("sex") || it == "ጾታ" }
        val phoneIdx = header.indexOfFirst { it.contains("phone") || it.contains("tel") || it.contains("ስልክ") }

        val startRow = if (header.any { it.contains("name") || it.contains("id") || it == "ስም" }) 1 else 0
        val students = mutableListOf<Student>()
        val warnings = mutableListOf<String>()

        for (r in startRow until rows.size) {
            val cols = rows[r]
            val rawFirst = cols.getOrNull(firstIdx)?.trim().orEmpty()
            val rawLast = if (lastIdx >= 0) cols.getOrNull(lastIdx)?.trim().orEmpty() else ""
            if (rawFirst.isEmpty() && rawLast.isEmpty()) continue

            val (firstName, lastName) = if (rawLast.isEmpty() && rawFirst.contains(" ")) {
                val parts = rawFirst.split(Regex("\\s+"), limit = 2)
                parts[0] to parts.getOrElse(1) { "" }
            } else rawFirst to rawLast

            val rawPhone = if (phoneIdx >= 0) cols.getOrNull(phoneIdx)?.trim().orEmpty() else ""
            val validPhone = if (rawPhone.isNotBlank()) {
                val norm = PhoneUtils.normalize(rawPhone)
                if (PhoneUtils.isValid(norm)) norm else {
                    warnings.add("Row ${r + 1}: invalid phone '$rawPhone' skipped")
                    null
                }
            } else null

            val rawGender = if (genderIdx >= 0) cols.getOrNull(genderIdx)?.trim().orEmpty().lowercase() else ""
            val gender = when (rawGender) {
                "m", "male", "ወንድ", "ወ" -> "M"
                "f", "female", "ሴት", "ሴ" -> "F"
                else -> ""
            }

            students.add(
                Student(
                    id = UUID.randomUUID().toString(),
                    studentId = if (idIdx >= 0) cols.getOrNull(idIdx)?.trim().orEmpty() else "",
                    firstName = firstName,
                    lastName = lastName,
                    gender = gender,
                    classIds = if (!classId.isNullOrBlank()) listOf(classId) else emptyList(),
                    className = className,
                    parentPhone = validPhone
                )
            )
        }

        if (students.isEmpty()) {
            return CsvImportResult(false, "No valid student rows found", warnings = warnings)
        }
        return CsvImportResult(true, "Imported ${students.size} students", students = students, warnings = warnings)
    }

    private fun parseCsvLine(line: String): List<String> {
        val result = mutableListOf<String>()
        val current = StringBuilder()
        var inQuotes = false
        for (ch in line) {
            when {
                ch == '"' -> inQuotes = !inQuotes
                ch == ',' && !inQuotes -> {
                    result.add(current.toString())
                    current.clear()
                }
                else -> current.append(ch)
            }
        }
        result.add(current.toString())
        return result
    }
}
