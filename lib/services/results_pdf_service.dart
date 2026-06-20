import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../models/assessment.dart';
import '../models/scan_result.dart';

class ResultsPdfService {
  static final ResultsPdfService _instance = ResultsPdfService._();
  factory ResultsPdfService() => _instance;
  ResultsPdfService._();

  static String _safeFileName(String name) =>
      name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

  Future<File> generateResultsReport({
    required Assessment assessment,
    required List<ScanResult> results,
    String schoolName = '',
    String teacherName = '',
  }) async {
    final pdf = pw.Document();
    final sorted = List<ScanResult>.from(results)
      ..sort((a, b) => b.totalScore.compareTo(a.totalScore));

    final stats = _computeStats(sorted);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => _buildHeader(
          schoolName: schoolName,
          teacherName: teacherName,
        ),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          _buildAssessmentInfo(assessment),
          pw.SizedBox(height: 16),
          _buildStatsBox(stats),
          pw.SizedBox(height: 16),
          _buildResultsTable(sorted, stats),
        ],
      ),
    );

    final dateStr = DateTime.now().toString().substring(0, 10);
    final safeTitle = _safeFileName(assessment.title);
    final safeClass = assessment.className.isNotEmpty
        ? '_${_safeFileName(assessment.className)}'
        : '';
    final fileName = 'EthioGrade_${safeTitle}${safeClass}_$dateStr.pdf';

    // Save to app documents directory
    final docsDir = await getApplicationDocumentsDirectory();
    final file = File('${docsDir.path}/$fileName');
    await file.writeAsBytes(await pdf.save());

    // Also copy to Downloads folder if external storage is available
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final downloadsDir = Directory('${extDir.path}/Download');
        if (!await downloadsDir.exists()) {
          await downloadsDir.create(recursive: true);
        }
        final downloadFile = File('${downloadsDir.path}/$fileName');
        await file.copy(downloadFile.path);
      }
    } catch (_) {}

    return file;
  }

  Future<void> shareResultsReport({
    required Assessment assessment,
    required List<ScanResult> results,
    String schoolName = '',
    String teacherName = '',
  }) async {
    final file = await generateResultsReport(
      assessment: assessment,
      results: results,
      schoolName: schoolName,
      teacherName: teacherName,
    );
    await Share.shareXFiles([XFile(file.path)]);
  }

  _ClassStats _computeStats(List<ScanResult> results) {
    if (results.isEmpty) {
      return const _ClassStats(
        average: 0,
        median: 0,
        passRate: 0,
        highest: 0,
        lowest: 0,
        passCount: 0,
        total: 0,
      );
    }

    final percentages = results.map((r) => r.percentage).toList()..sort();
    final avg = percentages.reduce((a, b) => a + b) / percentages.length;
    final mid = percentages.length ~/ 2;
    final median = percentages.length.isOdd
        ? percentages[mid]
        : (percentages[mid - 1] + percentages[mid]) / 2;
    final passCount = results.where((r) => r.percentage >= 50).length;

    return _ClassStats(
      average: avg,
      median: median,
      passRate: passCount / results.length * 100,
      highest: percentages.last,
      lowest: percentages.first,
      passCount: passCount,
      total: results.length,
    );
  }

  pw.Widget _buildHeader({
    required String schoolName,
    required String teacherName,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'EthioGrade Results Report',
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.teal800,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (schoolName.isNotEmpty)
                  pw.Text('School: $schoolName',
                      style: const pw.TextStyle(fontSize: 11)),
                if (teacherName.isNotEmpty)
                  pw.Text('Teacher: $teacherName',
                      style: const pw.TextStyle(fontSize: 11)),
              ],
            ),
            pw.Text(
              'Date: ${DateTime.now().toString().substring(0, 10)}',
              style: const pw.TextStyle(fontSize: 11),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Divider(color: PdfColors.teal200, height: 1),
        pw.SizedBox(height: 8),
      ],
    );
  }

  pw.Widget _buildFooter(pw.Context context) {
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey300, height: 1),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generated by EthioGrade',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildAssessmentInfo(Assessment assessment) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.teal50,
        border: pw.Border.all(color: PdfColors.teal200),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            assessment.title,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              if (assessment.subject.isNotEmpty) ...[
                pw.Text('Subject: ${assessment.subject}',
                    style: const pw.TextStyle(fontSize: 10)),
                pw.Text('  |  ',
                    style: pw.TextStyle(
                        fontSize: 10, color: PdfColors.grey500)),
              ],
              pw.Text('${assessment.questionCount} Questions',
                  style: const pw.TextStyle(fontSize: 10)),
              pw.Text('  |  ',
                  style:
                      pw.TextStyle(fontSize: 10, color: PdfColors.grey500)),
              pw.Text('${assessment.maxScore.toInt()} Points',
                  style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildStatsBox(_ClassStats stats) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        border: pw.Border.all(color: PdfColors.blue200),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Class Summary',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _statItem('Average', '${stats.average.toStringAsFixed(1)}%'),
              _statItem('Median', '${stats.median.toStringAsFixed(1)}%'),
              _statItem(
                  'Pass Rate', '${stats.passRate.toStringAsFixed(0)}%'),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _statItem('Highest', '${stats.highest.toStringAsFixed(1)}%'),
              _statItem('Lowest', '${stats.lowest.toStringAsFixed(1)}%'),
              _statItem('Students', '${stats.total}'),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _statItem(String label, String value) {
    return pw.Column(
      children: [
        pw.Text(label,
            style: pw.TextStyle(fontSize: 9, color: PdfColors.blue600)),
        pw.SizedBox(height: 2),
        pw.Text(value,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue900,
            )),
      ],
    );
  }

  pw.Widget _buildResultsTable(List<ScanResult> results, _ClassStats stats) {
    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      cellStyle: const pw.TextStyle(fontSize: 10),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellAlignment: pw.Alignment.centerLeft,
      headerAlignment: pw.Alignment.centerLeft,
      cellHeight: 28,
      cellAlignments: {
        0: pw.Alignment.center,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
        3: pw.Alignment.center,
        4: pw.Alignment.center,
        5: pw.Alignment.center,
        6: pw.Alignment.center,
      },
      headerAlignments: {
        0: pw.Alignment.center,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
        3: pw.Alignment.center,
        4: pw.Alignment.center,
        5: pw.Alignment.center,
        6: pw.Alignment.center,
      },
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
      headers: ['#', 'Student Name', 'Score', 'Max', '%', 'Grade', 'Status'],
      data: results.asMap().entries.map((entry) {
        final i = entry.key;
        final r = entry.value;
        final passed = r.percentage >= 50;
        return [
          '${i + 1}',
          r.studentName,
          '${r.totalScore.toInt()}',
          '${r.maxScore.toInt()}',
          '${r.percentage.toStringAsFixed(1)}%',
          r.grade,
          passed ? 'PASS' : 'FAIL',
        ];
      }).toList(),
    );
  }
}

class _ClassStats {
  final double average;
  final double median;
  final double passRate;
  final double highest;
  final double lowest;
  final int passCount;
  final int total;

  const _ClassStats({
    required this.average,
    required this.median,
    required this.passRate,
    required this.highest,
    required this.lowest,
    required this.passCount,
    required this.total,
  });
}
