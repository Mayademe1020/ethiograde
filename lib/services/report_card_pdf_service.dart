import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../models/homeroom_report.dart';

/// Service generating official Ethiopian student report cards (የተማሪ ውጤት መግለጫ ካርድ)
/// and Card Day PDF batches (4-up slips per A4 page).
class ReportCardPdfService {
  static final ReportCardPdfService _instance = ReportCardPdfService._();
  factory ReportCardPdfService() => _instance;
  ReportCardPdfService._();

  static String _safeFileName(String name) =>
      name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

  Future<pw.Font?> _loadFontSafe(String path) async {
    try {
      final data = await rootBundle.load(path);
      return pw.Font.ttf(data);
    } catch (_) {
      return null;
    }
  }

  /// Generates the Card Day PDF packages:
  /// - `allCards`: Document containing all student cards (4 per A4 page)
  /// - `heldCards`: Document containing only cards with finance hold watermark
  Future<Map<String, File>> generateCardDay({
    required HomeroomClassReport report,
    String schoolName = 'EthioGrade Academy',
  }) async {
    final ethiopicFont = await _loadFontSafe('assets/fonts/NotoSansEthiopic-Regular.ttf');
    final latinBoldFont = await _loadFontSafe('assets/fonts/PlusJakartaSans-Bold.ttf');
    final baseFont = ethiopicFont ?? pw.Font.helvetica();
    final boldFont = latinBoldFont ?? ethiopicFont ?? pw.Font.helveticaBold();

    final theme = pw.ThemeData.withFont(
      base: baseFont,
      bold: boldFont,
    );

    final allDoc = pw.Document(theme: theme);
    final heldDoc = pw.Document(theme: theme);

    // Group students in chunks of 4 for 4-up A4 printing
    final allStudents = report.students;
    for (int i = 0; i < allStudents.length; i += 4) {
      final chunk = allStudents.sublist(
        i,
        i + 4 > allStudents.length ? allStudents.length : i + 4,
      );
      allDoc.addPage(_buildCardPage(chunk, report, schoolName, baseFont, boldFont));
    }

    // Filter held students (እዳ ያለበት)
    final heldStudents = allStudents.where((s) => s.hasFinanceHold).toList();
    for (int i = 0; i < heldStudents.length; i += 4) {
      final chunk = heldStudents.sublist(
        i,
        i + 4 > heldStudents.length ? heldStudents.length : i + 4,
      );
      heldDoc.addPage(_buildCardPage(chunk, report, schoolName, baseFont, boldFont));
    }

    final outputDir = await getApplicationDocumentsDirectory();
    final dateStr = DateTime.now().toIso8601String().substring(0, 10);
    final safeClass = _safeFileName(report.className);

    final allFile = File('${outputDir.path}/EthioGrade_Cards_${safeClass}_$dateStr.pdf');
    await allFile.writeAsBytes(await allDoc.save());

    final heldFile = File('${outputDir.path}/EthioGrade_HeldCards_${safeClass}_$dateStr.pdf');
    if (heldStudents.isNotEmpty) {
      await heldFile.writeAsBytes(await heldDoc.save());
    }

    return {
      'allCards': allFile,
      if (heldStudents.isNotEmpty) 'heldCards': heldFile,
    };
  }

  pw.Page _buildCardPage(
    List<StudentCardRecord> students,
    HomeroomClassReport report,
    String schoolName,
    pw.Font baseFont,
    pw.Font boldFont,
  ) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(12),
      build: (context) {
        return pw.Column(
          children: [
            pw.Expanded(
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: students.isNotEmpty
                        ? _buildStudentSlip(students[0], report, schoolName, baseFont, boldFont)
                        : pw.Container(),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: students.length > 1
                        ? _buildStudentSlip(students[1], report, schoolName, baseFont, boldFont)
                        : pw.Container(),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Expanded(
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: students.length > 2
                        ? _buildStudentSlip(students[2], report, schoolName, baseFont, boldFont)
                        : pw.Container(),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: students.length > 3
                        ? _buildStudentSlip(students[3], report, schoolName, baseFont, boldFont)
                        : pw.Container(),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  pw.Widget _buildStudentSlip(
    StudentCardRecord student,
    HomeroomClassReport report,
    String schoolName,
    pw.Font baseFont,
    pw.Font boldFont,
  ) {
    const primaryColor = PdfColor.fromInt(0xFF0B6E4F);
    const borderColor = PdfColor.fromInt(0xFFDDE4E0);
    const holdColor = PdfColor.fromInt(0xFFDA2A2A);

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: student.hasFinanceHold ? holdColor : borderColor,
          width: student.hasFinanceHold ? 1.5 : 1.0,
        ),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      padding: const pw.EdgeInsets.all(8),
      child: pw.Stack(
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Center(
                child: pw.Text(
                  schoolName,
                  style: pw.TextStyle(font: boldFont, fontSize: 9, color: primaryColor),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  'የተማሪ ውጤት መግለጫ ካርድ | Student Report Card',
                  style: pw.TextStyle(font: boldFont, fontSize: 7),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Class: ${report.className}', style: const pw.TextStyle(fontSize: 6.5)),
                  pw.Text('Sem: ${report.semester}', style: const pw.TextStyle(fontSize: 6.5)),
                  pw.Text('Year: ${report.academicYear}', style: const pw.TextStyle(fontSize: 6.5)),
                ],
              ),
              pw.Divider(thickness: 0.5, color: borderColor),

              // Student Identity
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      'ስም (Name): ${student.fullName}',
                      style: pw.TextStyle(font: boldFont, fontSize: 7),
                      maxLines: 1,
                    ),
                  ),
                  pw.Text('ተ.ቁ (Roll): ${student.rollNumber}', style: const pw.TextStyle(fontSize: 6.5)),
                ],
              ),
              pw.SizedBox(height: 4),

              // Subject Table
              pw.Table(
                border: pw.TableBorder.all(color: borderColor, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2.5),
                  1: const pw.FlexColumnWidth(1.2),
                  2: const pw.FlexColumnWidth(0.8),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF4F7F5)),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(2),
                        child: pw.Text('ትምህርት (Subject)', style: pw.TextStyle(font: boldFont, fontSize: 6)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(2),
                        child: pw.Center(child: pw.Text('ውጤት (100%)', style: pw.TextStyle(font: boldFont, fontSize: 6))),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(2),
                        child: pw.Center(child: pw.Text('ደረጃ', style: pw.TextStyle(font: boldFont, fontSize: 6))),
                      ),
                    ],
                  ),
                  ...student.subjects.values.take(7).map((sub) {
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                          child: pw.Text(sub.subjectName, style: const pw.TextStyle(fontSize: 5.5)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                          child: pw.Center(
                            child: pw.Text(
                              sub.totalScore.toStringAsFixed(1),
                              style: const pw.TextStyle(fontSize: 5.5),
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                          child: pw.Center(
                            child: pw.Text(
                              sub.letterGrade,
                              style: pw.TextStyle(font: boldFont, fontSize: 5.5),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 4),

              // Summary Box
              pw.Container(
                decoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFF0F4F2),
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                ),
                padding: const pw.EdgeInsets.all(3),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    pw.Text('አማካይ (Avg): ${student.semesterAverage.toStringAsFixed(1)}%', style: pw.TextStyle(font: boldFont, fontSize: 6.5)),
                    pw.Text('ደረጃ (Rank): ${student.classRank}', style: pw.TextStyle(font: boldFont, fontSize: 6.5, color: primaryColor)),
                    pw.Text('ባህሪ (Conduct): ${student.conduct}', style: pw.TextStyle(font: boldFont, fontSize: 6.5)),
                  ],
                ),
              ),
              pw.SizedBox(height: 3),

              // Teacher Remark
              pw.Text(
                'አስተያየት: ${student.remarkAm.isNotEmpty ? student.remarkAm : student.remarkEn}',
                style: const pw.TextStyle(fontSize: 5.5),
                maxLines: 1,
              ),

              const pw.Spacer(),

              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(width: 60, height: 0.5, color: borderColor),
                      pw.Text('የክፍል ኃላፊ (Homeroom)', style: const pw.TextStyle(fontSize: 5)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(width: 60, height: 0.5, color: borderColor),
                      pw.Text('ርዕሰ መምህር (Director)', style: const pw.TextStyle(fontSize: 5)),
                    ],
                  ),
                ],
              ),
            ],
          ),

          // Finance Hold Watermark / Stamp
          if (student.hasFinanceHold)
            pw.Positioned.fill(
              child: pw.Center(
                child: pw.Transform.rotate(
                  angle: -0.4,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: holdColor, width: 1.5),
                      color: const PdfColor(1, 1, 1, 0.85),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Column(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text(
                          'እዳ ያለበት | FINANCE HOLD',
                          style: pw.TextStyle(font: boldFont, fontSize: 9, color: holdColor),
                        ),
                        pw.Text(
                          'FOR ACADEMIC REVIEW ONLY - VISIT FINANCE OFFICE',
                          style: pw.TextStyle(font: boldFont, fontSize: 5, color: holdColor),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
