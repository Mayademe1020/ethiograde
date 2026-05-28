import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/assessment.dart';
import '../../services/assessment_provider.dart';
import '../../services/settings_provider.dart';

/// Quick Grade — no-setup scanning path.
///
/// Teacher enters question count + answer key, app auto-creates an Assessment,
/// and immediately opens BatchScanScreen. After scanning, teacher can save or discard.
///
/// This is the demo hook for the pilot.
class QuickGradeScreen extends StatefulWidget {
  const QuickGradeScreen({super.key});

  @override
  State<QuickGradeScreen> createState() => _QuickGradeScreenState();
}

class _QuickGradeScreenState extends State<QuickGradeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _questionCountController = TextEditingController();
  final _answerKeyController = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _questionCountController.dispose();
    _answerKeyController.dispose();
    super.dispose();
  }

  /// Parse answer key string into validated list of uppercase answers.
  List<String>? _parseAnswerKey(String raw, int expectedCount) {
    final parts = raw
        .split(RegExp(r'[,;\s]+'))
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toList();

    if (parts.length != expectedCount) return null;

    const validAnswers = {'A', 'B', 'C', 'D', 'E', 'T', 'F'};
    for (final ans in parts) {
      if (!validAnswers.contains(ans)) return null;
    }

    return parts;
  }

  /// Create assessment and navigate to scanning.
  Future<void> _createAndScan() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isProcessing = true);

    final count = int.parse(_questionCountController.text.trim());
    final answers = _parseAnswerKey(_answerKeyController.text.trim(), count)!;

    // Build questions from answer key
    final questions = List.generate(count, (i) {
      final ans = answers[i];
      final isTF = ans == 'T' || ans == 'F';
      return Question(
        id: 'qg_q${i + 1}',
        number: i + 1,
        type: isTF ? QuestionType.trueFalse : QuestionType.mcq,
        points: 1,
        correctAnswer: isTF ? (ans == 'T' ? 'True' : 'False') : ans,
        options: isTF ? ['True', 'False'] : ['A', 'B', 'C', 'D']);
    });

    final now = DateTime.now();
    final dateStr = now.toString().substring(0, 10);
    final rubric = context.read<SettingsProvider>().defaultRubric;

    final assessment = Assessment(
      id: 'quickgrade_${now.millisecondsSinceEpoch}',
      title: 'Quick Grade — $dateStr',
      subject: '',
      rubricType: rubric,
      questions: questions,
      status: AssessmentStatus.active,
      isQuickGrade: true);

    // Save to Hive
    await context.read<AssessmentProvider>().addAssessment(assessment);

    if (!mounted) return;
    setState(() => _isProcessing = false);

    // Navigate to batch scan
    Navigator.pushReplacementNamed(
      context,
      AppRoutes.camera,
      arguments: {'assessment': assessment, 'isQuickGrade': true});
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(title: Text('Quick Grade')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Explanation card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal.withOpacity(0.2))),
                child: Row(
                  children: [
                    const Icon(Icons.flash_on, color: Colors.teal, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Skip setup — scan papers immediately. Just enter question count and correct answers.',
                        style: const TextStyle(fontSize: 14))),
                  ])),
              const SizedBox(height: 32),

              // Question count
              Text(
                'Number of questions',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _questionCountController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  hintText: 'e.g. 30',
                  prefixIcon: const Icon(Icons.format_list_numbered)),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Enter a valid number';
                  }
                  final n = int.tryParse(v.trim());
                  if (n == null || n < 1 || n > 100) {
                    return 'Enter a number between 1 and 100';
                  }
                  return null;
                }),
              const SizedBox(height: 24),

              // Answer key
              Text(
                'Answer key (e.g. A,B,C,D,A)',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _answerKeyController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'A,B,C,D,A,B,C,D...',
                  prefixIcon: const Icon(Icons.check_circle_outline),
                  helperText: 'A-E for MCQ, T/F for True/False'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Enter the answer key';
                  }
                  final countText = _questionCountController.text.trim();
                  final count = int.tryParse(countText);
                  if (count == null)
                    return null; // count field will show its own error

                  final parsed = _parseAnswerKey(v.trim(), count);
                  if (parsed == null) {
                    return 'Answers must match question count (A-E, T/F)';
                  }
                  return null;
                }),
              const SizedBox(height: 32),

              // Start scanning button
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _createAndScan,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white))
                      : const Icon(Icons.document_scanner),
                  label: Text(
                    _isProcessing
                        ? ('Preparing...')
                        : ('Start Scanning'),
                    style: const TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))))),
              const SizedBox(height: 16),

              // Hint text
              Text(
                'After scanning, you can review and save the assessment properly.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppTheme.lightText)),
            ]))));
  }
}
