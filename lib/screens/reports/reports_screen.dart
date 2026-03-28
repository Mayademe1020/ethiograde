import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/assessment.dart';
import '../../models/scan_result.dart';
import '../../models/class_info.dart';
import '../../services/locale_provider.dart';
import '../../services/assessment_provider.dart';
import '../../services/analytics_provider.dart';
import '../../services/student_provider.dart';
import '../../services/settings_provider.dart';
import '../../services/pdf_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Assessment? _selectedAssessment;
  bool _isGenerating = false;
  File? _generatedPdf;

  @override
  Widget build(BuildContext context) {
    final isAm = context.watch<LocaleProvider>().isAmharic;
    final assessments = context.watch<AssessmentProvider>().assessments;
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(isAm ? 'ሪፖርት' : 'Reports'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Assessment selector
            Text(
              isAm ? 'ፈተና ይምረጡ' : 'Select Assessment',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Assessment>(
              value: _selectedAssessment,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.assignment),
                hintText: isAm ? 'ፈተና ይምረጡ...' : 'Choose assessment...',
              ),
              items: assessments
                  .where((a) =>
                      a.status == AssessmentStatus.completed ||
                      a.status == AssessmentStatus.grading)
                  .map((a) => DropdownMenuItem(
                        value: a,
                        child: Text('${a.title} (${a.subject})'),
                      ))
                  .toList(),
              onChanged: (a) => setState(() => _selectedAssessment = a),
            ),
            const SizedBox(height: 24),

            // Report type cards
            Text(
              isAm ? 'የሪፖርት አይነት' : 'Report Type',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            _ReportTypeCard(
              icon: Icons.person,
              titleEn: 'Individual Student Report',
              titleAm: 'የግል ተማሪ ሪፖርት',
              descEn: 'Detailed report card for each student',
              descAm: 'ለእያንዳንዱ ተማሪ ዝርዝር ሪፖርት ካርድ',
              isAmharic: isAm,
              onTap: () => _generateStudentReports(isAm, settings),
            ),
            const SizedBox(height: 12),

            _ReportTypeCard(
              icon: Icons.class_,
              titleEn: 'Class Summary Report',
              titleAm: 'የክፍል ማጠቃለያ ሪፖርት',
              descEn: 'Full class performance with analytics',
              descAm: 'ሙሉ የክፍል አፈጻጸም ከትንተና ጋር',
              isAmharic: isAm,
              onTap: () => _generateClassReport(isAm, settings),
            ),
            const SizedBox(height: 12),

            _ReportTypeCard(
              icon: Icons.grid_on,
              titleEn: 'Answer Sheet Template',
              titleAm: 'የመልስ ወረቀት ቴምፕሌት',
              descEn: 'Printable bubble sheets for students',
              descAm: 'ለተማሪዎች ለመሳብ የሚያገለግል',
              isAmharic: isAm,
              onTap: () => _generateAnswerSheet(isAm, settings),
            ),

            const SizedBox(height: 24),

            // Generated PDF preview
            if (_generatedPdf != null) ...[
              Text(
                isAm ? 'የተፈጠረ ሪፖርት' : 'Generated Report',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primaryGreen.withOpacity(0.2),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.picture_as_pdf,
                            color: AppTheme.primaryGreen, size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _generatedPdf!.path.split('/').last,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              Text(
                                isAm ? 'ዝግጁ' : 'Ready',
                                style: TextStyle(
                                  color: AppTheme.lightText,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final pdf = PdfService();
                              await pdf.printPdf(_generatedPdf!);
                            },
                            icon: const Icon(Icons.print),
                            label: Text(isAm ? 'አትም' : 'Print'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await Share.shareXFiles(
                                [XFile(_generatedPdf!.path)],
                                text: 'EthioGrade Report',
                              );
                            },
                            icon: const Icon(Icons.share),
                            label: Text(isAm ? 'አጋራ' : 'Share'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // Loading indicator
            if (_isGenerating)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateStudentReports(bool isAm, SettingsProvider settings) async {
    if (_selectedAssessment == null) {
      _showSelectError(isAm);
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final students = context.read<StudentProvider>().students;
      final pdf = PdfService();

      // Generate first student report as example
      if (students.isNotEmpty) {
        final result = ScanResult(
          assessmentId: _selectedAssessment!.id,
          studentId: students.first.id,
          studentName: students.first.fullName,
          imagePath: '',
          totalScore: 75,
          maxScore: 100,
          percentage: 75,
          grade: 'B',
          answers: _selectedAssessment!.questions.map((q) => AnswerMatch(
            questionNumber: q.number,
            detectedAnswer: 'A',
            correctAnswer: q.correctAnswer?.toString() ?? 'A',
            isCorrect: true,
            score: q.points,
            maxScore: q.points,
          )).toList(),
        );

        final file = await pdf.generateStudentReport(
          student: students.first,
          assessment: _selectedAssessment!,
          result: result,
          schoolName: settings.schoolName,
          teacherName: settings.teacherName,
          rubricType: _selectedAssessment!.rubricType,
          isAmharic: isAm,
        );

        setState(() => _generatedPdf = file);
      }
    } catch (e) {
      debugPrint('PDF generation error: $e');
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _generateClassReport(bool isAm, SettingsProvider settings) async {
    if (_selectedAssessment == null) {
      _showSelectError(isAm);
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final analytics = context.read<AnalyticsProvider>().currentAnalytics;
      final pdf = PdfService();

      if (analytics != null) {
        final file = await pdf.generateClassReport(
          assessment: _selectedAssessment!,
          results: [],
          analytics: analytics,
          schoolName: settings.schoolName,
          teacherName: settings.teacherName,
          rubricType: _selectedAssessment!.rubricType,
          isAmharic: isAm,
        );

        setState(() => _generatedPdf = file);
      }
    } catch (e) {
      debugPrint('PDF generation error: $e');
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _generateAnswerSheet(bool isAm, SettingsProvider settings) async {
    if (_selectedAssessment == null) {
      _showSelectError(isAm);
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final students = context.read<StudentProvider>().getStudentsByClass(
        _selectedAssessment!.className,
      );
      final pdf = PdfService();

      final file = await pdf.generateAnswerSheetTemplate(
        assessment: _selectedAssessment!,
        students: students.isNotEmpty ? students : [],
        schoolName: settings.schoolName,
      );

      setState(() => _generatedPdf = file);
    } catch (e) {
      debugPrint('PDF generation error: $e');
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  void _showSelectError(bool isAm) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isAm ? 'ፈተና ይምረጡ' : 'Please select an assessment first',
        ),
      ),
    );
  }
}

class _ReportTypeCard extends StatelessWidget {
  final IconData icon;
  final String titleEn;
  final String titleAm;
  final String descEn;
  final String descAm;
  final bool isAmharic;
  final VoidCallback onTap;

  const _ReportTypeCard({
    required this.icon,
    required this.titleEn,
    required this.titleAm,
    required this.descEn,
    required this.descAm,
    required this.isAmharic,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.primaryGreen),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isAmharic ? titleAm : titleEn,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isAmharic ? descAm : descEn,
                    style: TextStyle(fontSize: 12, color: AppTheme.lightText),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
