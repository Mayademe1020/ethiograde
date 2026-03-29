import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import '../models/assessment.dart';
import '../models/scan_result.dart';
import '../models/student.dart';
import '../models/class_info.dart';

class PdfService {
  static final PdfService _instance = PdfService._();
  factory PdfService() => _instance;
  PdfService._();

  /// Generate individual student report card
  Future<File> generateStudentReport({
    required Student student,
    required Assessment assessment,
    required ScanResult result,
    String schoolName = '',
    String teacherName = '',
    String? schoolLogoPath,
    String rubricType = 'moe_national',
    bool isAmharic = false,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildReportHeader(
                schoolName: schoolName,
                teacherName: teacherName,
                logoPath: schoolLogoPath,
                isAmharic: isAmharic,
              ),
              pw.SizedBox(height: 20),
              _buildStudentInfo(student, isAmharic),
              pw.SizedBox(height: 16),
              _buildAssessmentInfo(assessment, isAmharic),
              pw.SizedBox(height: 16),
              _buildScoreSummary(result, rubricType, isAmharic),
              pw.SizedBox(height: 16),
              _buildAnswerTable(result, assessment, isAmharic),
              if (result.teacherComment?.isNotEmpty == true) ...[
                pw.SizedBox(height: 16),
                _buildComment(result.teacherComment!, isAmharic),
              ],
              pw.Spacer(),
              _buildReportFooter(isAmharic),
            ],
          );
        },
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/report_${student.firstName}_${assessment.title}.pdf',
    );
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// Generate class summary report
  Future<File> generateClassReport({
    required Assessment assessment,
    required List<ScanResult> results,
    required ClassAnalytics analytics,
    String schoolName = '',
    String teacherName = '',
    String? schoolLogoPath,
    String rubricType = 'moe_national',
    bool isAmharic = false,
  }) async {
    final pdf = pw.Document();

    // Page 1: Summary
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildReportHeader(
                schoolName: schoolName,
                teacherName: teacherName,
                logoPath: schoolLogoPath,
                isAmharic: isAmharic,
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                isAmharic ? 'የክፍል ሪፖርት' : 'Class Report',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                '${assessment.title} - ${assessment.subject}',
                style: const pw.TextStyle(fontSize: 14),
              ),
              pw.SizedBox(height: 20),
              _buildClassSummary(analytics, isAmharic),
              pw.SizedBox(height: 16),
              _buildGradeDistribution(analytics, isAmharic),
              pw.SizedBox(height: 16),
              _buildQuestionDifficulty(analytics, isAmharic),
            ],
          );
        },
      ),
    );

    // Page 2+: Student list
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Text(
          '${assessment.title} - ${isAmharic ? 'የተማሪዎች ዝርዝር' : 'Student List'}',
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey700,
          ),
        ),
        build: (context) => [
          _buildStudentResultsTable(results, isAmharic),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/class_report_${assessment.title}.pdf',
    );
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// Generate printable answer sheet template
  Future<File> generateAnswerSheetTemplate({
    required Assessment assessment,
    required List<Student> students,
    String schoolName = '',
    bool prefillNames = true,
  }) async {
    final pdf = pw.Document();

    for (final student in students) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      schoolName,
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      assessment.title,
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),

                // Student info
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Row(
                    children: [
                      pw.Text(
                        'Name: ${prefillNames ? student.fullName : "________________"}',
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                      pw.Spacer(),
                      pw.Text(
                        'ID: ${student.studentId.isNotEmpty ? student.studentId : "______"}',
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 12),

                // Answer bubbles
                pw.Expanded(
                  child: _buildBubbleSheet(assessment),
                ),
              ],
            );
          },
        ),
      );
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/answer_sheet_${assessment.title}.pdf',
    );
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  // ──── UI Builders ────

  pw.Widget _buildReportHeader({
    required String schoolName,
    required String teacherName,
    String? logoPath,
    bool isAmharic = false,
  }) {
    return pw.Row(
      children: [
        if (logoPath != null && logoPath.isNotEmpty)
          pw.Container(
            width: 48,
            height: 48,
            child: pw.Image(pw.MemoryImage(File(logoPath).readAsBytesSync())),
          )
        else
          pw.Container(
            width: 48,
            height: 48,
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#1B7A43'),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Center(
              child: pw.Text(
                'EG',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                schoolName.isNotEmpty ? schoolName : 'EthioGrade Report',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (teacherName.isNotEmpty)
                pw.Text(
                  '${isAmharic ? 'መምህር' : 'Teacher'}: $teacherName',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey600,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _buildStudentInfo(Student student, bool isAmharic) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F7FAFC'),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '${isAmharic ? 'ስም' : 'Student'}: ${student.fullName}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              if (student.fullNameAmharic.trim().isNotEmpty)
                pw.Text(
                  student.fullNameAmharic,
                  style: const pw.TextStyle(fontSize: 10),
                ),
            ],
          ),
          pw.Spacer(),
          pw.Text(
            '${isAmharic ? 'ክፍል' : 'Class'}: ${student.className}',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildAssessmentInfo(Assessment assessment, bool isAmharic) {
    return pw.Text(
      '${isAmharic ? 'ፈተና' : 'Assessment'}: ${assessment.title} '
      '(${assessment.subject})',
      style: const pw.TextStyle(fontSize: 12),
    );
  }

  pw.Widget _buildScoreSummary(
    ScanResult result,
    String rubricType,
    bool isAmharic,
  ) {
    final passMark = rubricType == 'moe_national' ? 50 : 60;
    final passed = result.percentage >= passMark;

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: passed
            ? PdfColor.fromHex('#F0FFF4')
            : PdfColor.fromHex('#FFF5F5'),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(
          color: passed
              ? PdfColor.fromHex('#38A169')
              : PdfColor.fromHex('#E53E3E'),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _scoreColumn(
            isAmharic ? 'ውጤት' : 'Score',
            '${result.totalScore.toInt()}/${result.maxScore.toInt()}',
          ),
          _scoreColumn(
            '%',
            '${result.percentage.toStringAsFixed(1)}%',
          ),
          _scoreColumn(
            isAmharic ? 'ደረጃ' : 'Grade',
            result.grade,
          ),
          _scoreColumn(
            isAmharic ? 'ሁኔታ' : 'Status',
            passed
                ? (isAmharic ? 'አልፏል' : 'PASS')
                : (isAmharic ? 'ወድቋል' : 'FAIL'),
          ),
        ],
      ),
    );
  }

  pw.Widget _scoreColumn(String label, String value) {
    return pw.Column(
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildAnswerTable(
    ScanResult result,
    Assessment assessment,
    bool isAmharic,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: [
        // Header
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#EDF2F7'),
          ),
          children: [
            _tableCell(isAmharic ? 'ቁጥር' : '#', bold: true),
            _tableCell(isAmharic ? 'መልስ' : 'Answer', bold: true),
            _tableCell(isAmharic ? 'ትክክል' : 'Correct', bold: true),
            _tableCell(isAmharic ? 'ውጤት' : 'Score', bold: true),
          ],
        ),
        // Data rows
        ...result.answers.map(
          (answer) => pw.TableRow(
            children: [
              _tableCell('${answer.questionNumber}'),
              _tableCell(answer.detectedAnswer),
              _tableCell(answer.isCorrect ? '✓' : '✗'),
              _tableCell('${answer.score.toInt()}/${answer.maxScore.toInt()}'),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _tableCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget _buildComment(String comment, bool isAmharic) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#FFFBEB'),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColor.fromHex('#ECC94B')),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            isAmharic ? 'የመምህር አስተያየት' : 'Teacher Comment',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#744210'),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(comment, style: const pw.TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  pw.Widget _buildReportFooter(bool isAmharic) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          '${isAmharic ? 'ቀን' : 'Date'}: ${DateTime.now().toString().substring(0, 10)}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
        ),
        pw.Text(
          'Powered by EthioGrade',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
        ),
      ],
    );
  }

  pw.Widget _buildClassSummary(ClassAnalytics analytics, bool isAmharic) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F7FAFC'),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _scoreColumn(
            isAmharic ? 'አማካይ' : 'Average',
            '${analytics.classAverage.toStringAsFixed(1)}%',
          ),
          _scoreColumn(
            isAmharic ? 'ከፍተኛ' : 'Highest',
            '${analytics.highestScore.toStringAsFixed(1)}%',
          ),
          _scoreColumn(
            isAmharic ? 'ዝቅተኛ' : 'Lowest',
            '${analytics.lowestScore.toStringAsFixed(1)}%',
          ),
          _scoreColumn(
            isAmharic ? 'ማለፍ' : 'Pass Rate',
            '${analytics.passRate.toStringAsFixed(0)}%',
          ),
        ],
      ),
    );
  }

  pw.Widget _buildGradeDistribution(
    ClassAnalytics analytics,
    bool isAmharic,
  ) {
    final entries = analytics.gradeDistribution.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          isAmharic ? 'የደረጃ ስርጭት' : 'Grade Distribution',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
        ),
        pw.SizedBox(height: 8),
        pw.Wrap(
          spacing: 8,
          runSpacing: 4,
          children: entries.map((entry) {
            return pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#EDF2F7'),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                '${entry.key}: ${entry.value}',
                style: const pw.TextStyle(fontSize: 10),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  pw.Widget _buildQuestionDifficulty(
    ClassAnalytics analytics,
    bool isAmharic,
  ) {
    final difficult = analytics.questionAnalytics
        .where((q) => q.correctRate < 0.5)
        .toList()
      ..sort((a, b) => a.correctRate.compareTo(b.correctRate));

    if (difficult.isEmpty) return pw.SizedBox();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          isAmharic
              ? 'ከባድ ጥያቄዎች (< 50%)'
              : 'Difficult Questions (< 50%)',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
        ),
        pw.SizedBox(height: 8),
        ...difficult.map((q) {
          return pw.Text(
            'Q${q.questionNumber}: ${(q.correctRate * 100).toStringAsFixed(0)}% correct',
            style: const pw.TextStyle(fontSize: 10),
          );
        }),
      ],
    );
  }

  pw.Widget _buildStudentResultsTable(
    List<ScanResult> results,
    bool isAmharic,
  ) {
    final sorted = List<ScanResult>.from(results)
      ..sort((a, b) => b.percentage.compareTo(a.percentage));

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(1.5),
        4: const pw.FlexColumnWidth(1),
        5: const pw.FlexColumnWidth(1.5),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#1B7A43'),
          ),
          children: [
            _tableHeader(isAmharic ? 'ተ.ቁ' : '#'),
            _tableHeader(isAmharic ? 'ስም' : 'Name'),
            _tableHeader(isAmharic ? 'ውጤት' : 'Score'),
            _tableHeader('%'),
            _tableHeader(isAmharic ? 'ደረጃ' : 'Grade'),
            _tableHeader(isAmharic ? 'ሁኔታ' : 'Status'),
          ],
        ),
        ...sorted.asMap().entries.map((entry) {
          final i = entry.key + 1;
          final r = entry.value;
          final passed = r.percentage >= 50;
          return pw.TableRow(
            children: [
              _tableCell('$i'),
              _tableCell(r.studentName),
              _tableCell('${r.totalScore.toInt()}/${r.maxScore.toInt()}'),
              _tableCell('${r.percentage.toStringAsFixed(1)}%'),
              _tableCell(r.grade),
              _tableCell(
                passed ? 'PASS' : 'FAIL',
                bold: !passed,
              ),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _tableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );
  }

  pw.Widget _buildBubbleSheet(Assessment assessment) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: assessment.questions.map((question) {
        return pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: 24,
                child: pw.Text(
                  '${question.number}.',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(width: 4),
              ...question.options.map((option) {
                return pw.Container(
                  margin: const pw.EdgeInsets.only(right: 12),
                  child: pw.Row(
                    children: [
                      pw.Container(
                        width: 16,
                        height: 16,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.black),
                          borderRadius: pw.BorderRadius.circular(8),
                        ),
                      ),
                      pw.SizedBox(width: 4),
                      pw.Text(option, style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ──── Print / Share ────

  Future<void> printPdf(File file) async {
    await Printing.layoutPdf(
      onLayout: (_) => file.readAsBytes(),
    );
  }

  Future<Uint8List> getPdfBytes(File file) async {
    return await file.readAsBytes();
  }
}
