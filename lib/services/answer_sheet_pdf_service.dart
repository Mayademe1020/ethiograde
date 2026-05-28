import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../models/assessment.dart';
import '../models/student.dart';

/// Generates printable answer sheet PDFs (bubble sheets + block capital sheets).
///
/// Pure Dart PDF generation — no ML Kit, no network.
/// Extracted from the old PdfService to keep concerns separate.
class AnswerSheetPdfService {
  static final AnswerSheetPdfService _instance = AnswerSheetPdfService._();
  factory AnswerSheetPdfService() => _instance;
  AnswerSheetPdfService._();

  static String _safeFileName(String name) =>
      name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

  /// Generate printable answer sheet template (bubble circles).
  Future<File> generateAnswerSheetTemplate({
    required Assessment assessment,
    String? outputDir,
    required List<Student> students,
    String schoolName = '',
    bool prefillNames = true,
    bool dualLabels = false,
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
                        fontWeight: pw.FontWeight.bold)),
                    pw.Text(
                      assessment.title,
                      style: const pw.TextStyle(fontSize: 12)),
                  ]),
                pw.SizedBox(height: 8),

                // Student info
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                    borderRadius: pw.BorderRadius.circular(4)),
                  child: pw.Row(
                    children: [
                      pw.Text(
                        'Name: ${prefillNames ? student.fullName : "________________"}',
                        style: const pw.TextStyle(fontSize: 11)),
                      pw.Spacer(),
                      pw.Text(
                        'ID: ${student.studentId.isNotEmpty ? student.studentId : "______"}',
                        style: const pw.TextStyle(fontSize: 11)),
                    ])),
                pw.SizedBox(height: 12),

                // Answer bubbles
                pw.Expanded(
                  child: _buildBubbleSheet(assessment, dualLabels: dualLabels)),
              ]);
          }));
    }

    final dirPath =
        outputDir ?? (await getApplicationDocumentsDirectory()).path;
    final file = File(
      '$dirPath/answer_sheet_${_safeFileName(assessment.title)}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// Generate block capital answer sheet (handwritten letters in boxes).
  ///
  /// Students write capital letters (A/B/C/D/E) inside numbered boxes.
  /// Works on plain paper — no special printing needed.
  Future<File> generateBlockCapitalTemplate({
    required Assessment assessment,
    String? outputDir,
    required List<Student> students,
    String schoolName = '',
    bool prefillNames = true,
    bool dualLabels = false,
  }) async {
    final pdf = pw.Document();

    for (final student in students) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      schoolName.isNotEmpty
                          ? schoolName
                          : ('School Name'),
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold)),
                    pw.Text(
                      assessment.title,
                      style: const pw.TextStyle(fontSize: 12)),
                  ]),
                pw.SizedBox(height: 4),

                // Instruction
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 8),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#FFF3CD'),
                    borderRadius: pw.BorderRadius.circular(4)),
                  child: pw.Text(
                    'Instructions: Write ONE capital letter inside the box for each question. Choose only one answer.',
                    style: const pw.TextStyle(fontSize: 9))),
                pw.SizedBox(height: 6),

                // Student info bar
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                    borderRadius: pw.BorderRadius.circular(4)),
                  child: pw.Row(
                    children: [
                      pw.Text(
                        '${'Name'}: '
                        '${prefillNames ? student.fullName : "________________________"}',
                        style: const pw.TextStyle(fontSize: 11)),
                      pw.SizedBox(width: 16),
                      pw.Text(
                        '${'ID'}: '
                        '${student.studentId.isNotEmpty ? student.studentId : "________"}',
                        style: const pw.TextStyle(fontSize: 11)),
                      pw.SizedBox(width: 16),
                      pw.Text(
                        '${'Class'}: '
                        '${student.className.isNotEmpty ? student.className : "________"}',
                        style: const pw.TextStyle(fontSize: 11)),
                    ])),
                pw.SizedBox(height: 10),

                // Block capital grid
                pw.Expanded(
                  child: _buildBlockCapitalGrid(
                    assessment: assessment,
                    dualLabels: dualLabels)),

                pw.SizedBox(height: 8),
                // Footer
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'EthioGrade',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey400)),
                    pw.Text(
                      'Write ONE answer only',
                      style: pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey400,
                        fontStyle: pw.FontStyle.italic)),
                  ]),
              ]);
          }));
    }

    final dirPath =
        outputDir ?? (await getApplicationDocumentsDirectory()).path;
    final file = File(
      '$dirPath/block_capital_${_safeFileName(assessment.title)}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// Share a PDF file via the system share sheet.
  Future<void> printPdf(File file) async {
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'EthioGrade Answer Sheet');
  }

  Future<Uint8List> getPdfBytes(File file) async {
    return await file.readAsBytes();
  }

  // ──── Private builders ────

  pw.Widget _buildBubbleSheet(
    Assessment assessment, {
    bool dualLabels = false,
  }) {
    const amharicOptions = ['ሀ', 'ለ', 'መ', 'ሠ', 'ረ'];
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
                    fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(width: 4),
              ...question.options.asMap().entries.map((entry) {
                final i = entry.key;
                final option = entry.value;
                final amLabel = i < amharicOptions.length
                    ? amharicOptions[i]
                    : '';
                final displayLabel =
                    dualLabels && amLabel.isNotEmpty
                        ? '$option / $amLabel'
                        : option;
                return pw.Container(
                  margin: const pw.EdgeInsets.only(right: 12),
                  child: pw.Row(
                    children: [
                      pw.Container(
                        width: 16,
                        height: 16,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.black),
                          borderRadius: pw.BorderRadius.circular(8))),
                      pw.SizedBox(width: 4),
                      pw.Text(
                        displayLabel,
                        style: pw.TextStyle(
                          fontSize: dualLabels ? 8 : 10)),
                    ]));
              }),
            ]));
      }).toList());
  }

  pw.Widget _buildBlockCapitalGrid({
    required Assessment assessment,
    required bool dualLabels,
  }) {
    const amharicOptions = ['ሀ', 'ለ', 'መ', 'ሠ', 'ረ'];
    final maxOptions = assessment.questions.fold<int>(
      1,
      (max, q) => q.options.length > max ? q.options.length : max);

    const boxWidth = 44.0;
    const boxHeight = 28.0;
    const questionWidth = 28.0;
    const rowHeight = 34.0;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Header row with option labels
        pw.Row(
          children: [
            pw.SizedBox(width: questionWidth),
            ...List.generate(maxOptions, (i) {
              final label = i < assessment.questions.first.options.length
                  ? assessment.questions.first.options[i]
                  : String.fromCharCode(65 + i);
              final amLabel = i < amharicOptions.length
                  ? amharicOptions[i]
                  : '';

              return pw.Container(
                width: boxWidth,
                height: 18,
                alignment: pw.Alignment.center,
                child: pw.Text(
                  dualLabels && amLabel.isNotEmpty
                      ? '$label / $amLabel'
                      : label,
                  style: pw.TextStyle(
                    fontSize: dualLabels ? 8 : 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700)));
            }),
          ]),
        pw.SizedBox(height: 2),
        pw.Divider(color: PdfColors.grey300, height: 1),
        pw.SizedBox(height: 4),

        // Question rows
        ...assessment.questions.map((question) {
          final optCount = question.options.length;
          return pw.Container(
            height: rowHeight,
            margin: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Row(
              children: [
                // Question number
                pw.Container(
                  width: questionWidth,
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    'Q${question.number}',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold))),
                // Answer boxes
                ...List.generate(maxOptions, (i) {
                  final isActive = i < optCount;
                  final label = isActive ? question.options[i] : '';
                  final amLabel = isActive && i < amharicOptions.length
                      ? amharicOptions[i]
                      : '';

                  return pw.Container(
                    width: boxWidth,
                    height: boxHeight,
                    margin: const pw.EdgeInsets.only(right: 2),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: isActive ? PdfColors.black : PdfColors.grey300,
                        width: isActive ? 1.2 : 0.5),
                      borderRadius: pw.BorderRadius.circular(3),
                      color: isActive
                          ? PdfColors.white
                          : PdfColor.fromHex('#F7F7F7')),
                    child: isActive
                        ? pw.Column(
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            children: [
                              if (dualLabels && amLabel.isNotEmpty) ...[
                                pw.Text(
                                  label,
                                  style: pw.TextStyle(
                                    fontSize: 7,
                                    color: PdfColors.grey400)),
                                pw.Text(
                                  amLabel,
                                  style: pw.TextStyle(
                                    fontSize: 7,
                                    color: PdfColors.grey400)),
                              ],
                            ])
                        : null);
                }),
              ]));
        }),
      ]);
  }
}
