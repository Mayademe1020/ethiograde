import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/assessment.dart';
import '../../models/scan_result.dart';
import '../../models/student.dart';
import '../../models/class_info.dart';
import '../../services/assessment_provider.dart';
import '../../services/hybrid_grading_service.dart';
import '../../services/answer_key_recalculation_service.dart';
import '../../services/student_provider.dart';
import '../../services/class_provider.dart';
import '../../services/answer_sheet_pdf_service.dart';
import '../../services/answer_key_fingerprint_service.dart';

enum _KeyChangeAction { recalculateNow, saveAndRecalculateLater, cancel }

class AnswerKeyRouteArgs {
  final Assessment assessment;
  final bool returnToReview;

  const AnswerKeyRouteArgs({
    required this.assessment,
    this.returnToReview = false,
  });
}

class AnswerKeyScreen extends StatefulWidget {
  const AnswerKeyScreen({super.key});

  @override
  State<AnswerKeyScreen> createState() => _AnswerKeyScreenState();
}

class _AnswerKeyScreenState extends State<AnswerKeyScreen> {
  Assessment? _assessment;
  String? _preEditFingerprint;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_assessment != null) return;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is AnswerKeyRouteArgs) {
      _assessment = args.assessment;
    } else if (args is Assessment) {
      _assessment = args;
    } else {
      _assessment = context.watch<AssessmentProvider>().currentAssessment;
    }

    // Capture pre-edit fingerprint for change detection
    if (_assessment != null && _preEditFingerprint == null) {
      _preEditFingerprint = _assessment!.answerKeyFingerprint.isNotEmpty
          ? _assessment!.answerKeyFingerprint
          : const AnswerKeyFingerprintService().compute(_assessment!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final assessment = _assessment;
    final args = ModalRoute.of(context)?.settings.arguments;
    final returnToReview = args is AnswerKeyRouteArgs && args.returnToReview;

    if (assessment == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('No assessment selected')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Answer Key'),
        actions: [
          TextButton.icon(
            onPressed: () => _handleDone(context, assessment, returnToReview),
            icon: const Icon(Icons.check),
            label: Text('Done'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Assessment info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    assessment.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${assessment.subject} • ${assessment.questionCount} ${'questions'} • ${assessment.maxScore} ${'pts'}',
                    style: TextStyle(color: AppTheme.lightText),
                  ),
                  if (assessment.answerKeyRevision > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Revision ${assessment.answerKeyRevision}',
                      style: TextStyle(color: AppTheme.lightText, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Answer key table
            Text(
              'Answer Key',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap answers to edit',
              style: TextStyle(color: AppTheme.lightText, fontSize: 12),
            ),
            const SizedBox(height: 16),

            // Question answer cards
            ...assessment.questions.map(
              (q) => _AnswerKeyCard(
                question: q,
                onChanged: (correctAnswer) {
                  // Update question answer
                  final index = assessment.questions.indexOf(q);
                  final updatedQuestions = List<Question>.from(
                    assessment.questions,
                  );
                  updatedQuestions[index] = Question(
                    id: q.id,
                    number: q.number,
                    type: q.type,
                    text: q.text,
                    points: q.points,
                    options: q.options,
                    correctAnswer: correctAnswer,
                    topicTag: q.topicTag,
                    keywords: q.keywords,
                    essayRubric: q.essayRubric,
                  );
                  final updatedAssessment = assessment.copyWith(
                    questions: updatedQuestions,
                  );
                  setState(() => _assessment = updatedAssessment);
                },
              ),
            ),

            const SizedBox(height: 24),

            // Next steps info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.info.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.info.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppTheme.info),
                      const SizedBox(width: 8),
                      Text(
                        'Next Steps',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.info,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '1. Prepare student papers\n'
                    '2. Open camera and scan\n'
                    '3. Results are graded automatically',
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (!assessment.isAnswerKeyComplete) {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              icon: const Icon(
                                Icons.warning_amber,
                                color: Colors.orange,
                                size: 36,
                              ),
                              title: Text('Answer Key Incomplete'),
                              content: Text(
                                "${assessment.answerKeyStatus}. Set all answers for accurate grading.",
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text('Close'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text('Set Answers'),
                                ),
                              ],
                            ),
                          );
                          return;
                        }
                        Navigator.pushNamed(
                          context,
                          AppRoutes.camera,
                          arguments: assessment,
                        );
                      },
                      icon: Icon(
                        Icons.camera_alt,
                        color: assessment.isAnswerKeyComplete
                            ? null
                            : Colors.orange,
                      ),
                      label: Text('Start Scanning'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Handle the Done button press with answer-key change detection.
  Future<void> _handleDone(
    BuildContext context,
    Assessment assessment,
    bool returnToReview,
  ) async {
    final provider = context.read<AssessmentProvider>();
    final currentFingerprint = const AnswerKeyFingerprintService().compute(assessment);
    final keyChanged = _preEditFingerprint != null &&
        _preEditFingerprint!.isNotEmpty &&
        currentFingerprint != _preEditFingerprint;

    if (!keyChanged) {
      // No scoring change — save normally
      await provider.saveAssessment(assessment);
      if (returnToReview) {
        if (context.mounted) Navigator.pop(context, assessment);
        return;
      }
      if (context.mounted) {
        await _showAnswerSheetPrompt(context, assessment);
        if (context.mounted) {
          Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
        }
      }
      return;
    }

    // Scoring key changed — check for existing results
    final List<ScanResult> results = await HybridGradingService().loadScanResults(assessment.id);

    if (!context.mounted) return;

    if (results.isEmpty) {
      // No results — save normally with incremented revision
      final updated = await provider.saveAnswerKeyChange(assessment);
      if (returnToReview) {
        Navigator.pop(context, updated);
        return;
      }
      await _showAnswerSheetPrompt(context, updated);
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
      }
      return;
    }

    // Results exist — show recalculation dialog
    await _showRecalculationDialog(context, assessment, results, returnToReview);
  }

  /// Show the three-action recalculation dialog.
  Future<void> _showRecalculationDialog(
    BuildContext context,
    Assessment assessment,
    List<ScanResult> results,
    bool returnToReview,
  ) async {
    final action = await showDialog<_KeyChangeAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Answer key changed'),
        content: Text(
          '${results.length} paper${results.length == 1 ? ' was' : 's were'} graded '
          'using the previous answer key. Their scores must be recalculated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _KeyChangeAction.cancel),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () =>
                Navigator.pop(context, _KeyChangeAction.saveAndRecalculateLater),
            child: const Text('Save and recalculate later'),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pop(context, _KeyChangeAction.recalculateNow),
            icon: const Icon(Icons.refresh),
            label: const Text('Recalculate now'),
          ),
        ],
      ),
    );

    if (!context.mounted) return;

    switch (action) {
      case _KeyChangeAction.recalculateNow:
        await _recalculateNow(context, assessment, results, returnToReview);
        break;
      case _KeyChangeAction.saveAndRecalculateLater:
        await _saveAndRecalculateLater(context, assessment, returnToReview);
        break;
      case _KeyChangeAction.cancel:
      case null:
        // Do nothing — stay on screen
        break;
    }
  }

  /// Save the new key and immediately recalculate all results.
  Future<void> _recalculateNow(
    BuildContext context,
    Assessment assessment,
    List<ScanResult> results,
    bool returnToReview,
  ) async {
    final provider = context.read<AssessmentProvider>();

    // Save the new key with incremented revision
    final updatedAssessment = await provider.saveAnswerKeyChange(assessment);

    if (!context.mounted) return;

    // Show progress
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Recalculating ${results.length} results...'),
        duration: const Duration(seconds: 2),
      ),
    );

    // Run recalculation
    final recalcService = AnswerKeyRecalculationService();
    final result = await recalcService.recalculateAll(
      assessment: updatedAssessment,
      results: results,
    );

    if (!context.mounted) return;

    // Show summary
    final summary = StringBuffer();
    summary.write('${result.recalculated} recalculated');
    if (result.scoresChanged > 0) {
      summary.write(', ${result.scoresChanged} scores changed');
    }
    if (result.scoresUnchanged > 0) {
      summary.write(', ${result.scoresUnchanged} unchanged');
    }
    if (result.preserved > 0) {
      summary.write(', ${result.preserved} preserved (manual)');
    }
    if (result.failed > 0) {
      summary.write(', ${result.failed} failed');
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(summary.toString()),
        backgroundColor: result.allSucceeded ? AppTheme.primaryGreen : Colors.orange,
      ),
    );

    if (returnToReview) {
      Navigator.pop(context, updatedAssessment);
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
    }
  }

  /// Save the new key and mark results for later recalculation.
  Future<void> _saveAndRecalculateLater(
    BuildContext context,
    Assessment assessment,
    bool returnToReview,
  ) async {
    final provider = context.read<AssessmentProvider>();

    // Save the new key with incremented revision
    final updatedAssessment = await provider.saveAnswerKeyChange(assessment);

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Key saved. Recalculate results when ready.'),
      ),
    );

    if (returnToReview) {
      Navigator.pop(context, updatedAssessment);
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
    }
  }

  /// Show answer sheet generation prompt after assessment creation.
  Future<void> _showAnswerSheetPrompt(
    BuildContext context,
    Assessment assessment,
  ) async {
    final generate = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Generate answer sheet?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create a printable answer sheet for students. They fill it → you scan it → 99% accurate.',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.picture_as_pdf,
                  color: AppTheme.primaryGreen,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Prints as PDF — photocopiable',
                    style: TextStyle(fontSize: 12, color: AppTheme.lightText),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Not now'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.picture_as_pdf, size: 18),
            label: Text('Generate'),
          ),
        ],
      ),
    );

    if (generate == true && context.mounted) {
      await _generateAnswerSheet(context, assessment);
    }
  }

  /// Generate and show the answer sheet PDF.
  Future<void> _generateAnswerSheet(
    BuildContext context,
    Assessment assessment,
  ) async {
    // Get students from linked class, or all students
    List<Student> students;
    final classProv = context.read<ClassProvider>();
    final studentProv = context.read<StudentProvider>();

    if (assessment.className.isNotEmpty) {
      final matchingClass = classProv.classes.cast<ClassInfo?>().firstWhere(
        (c) => c?.displayName == assessment.className,
        orElse: () => null,
      );
      students = matchingClass != null
          ? matchingClass.studentIds
                .map((id) => studentProv.getStudentById(id))
                .whereType<Student>()
                .toList()
          : List.from(studentProv.students);
    } else {
      students = List.from(studentProv.students);
    }

    if (students.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Add students first to generate answer sheets'),
          ),
        );
      }
      return;
    }

    try {
      final file = await AnswerSheetPdfService().generateAnswerSheetTemplate(
        assessment: assessment,
        students: students,
        prefillNames: true,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("PDF generated — ${students.length} sheets"),
            backgroundColor: AppTheme.primaryGreen,
            action: SnackBarAction(
              label: 'Print',
              onPressed: () => AnswerSheetPdfService().printPdf(file),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not generate PDF')));
      }
    }
  }
}

class _AnswerKeyCard extends StatelessWidget {
  final Question question;
  final Function(dynamic) onChanged;

  const _AnswerKeyCard({required this.question, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final typeLabel = {
      QuestionType.mcq: 'MCQ',
      QuestionType.trueFalse: 'T/F',
      QuestionType.shortAnswer: 'Short',
      QuestionType.essay: 'Essay',
      QuestionType.matching: 'Match',
    }[question.type]!;

    final typeColor = {
      QuestionType.mcq: AppTheme.primaryGreen,
      QuestionType.trueFalse: AppTheme.info,
      QuestionType.shortAnswer: AppTheme.warning,
      QuestionType.essay: AppTheme.primaryRed,
      QuestionType.matching: AppTheme.primaryGreen,
    }[question.type]!;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Question number
            CircleAvatar(
              backgroundColor: typeColor.withOpacity(0.1),
              child: Text(
                '${question.number}',
                style: TextStyle(color: typeColor, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),

            // Type and points
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: typeColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          typeLabel,
                          style: TextStyle(
                            fontSize: 10,
                            color: typeColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${question.points} ${'pts'}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.lightText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Answer options
                  if (question.type == QuestionType.mcq)
                    Row(
                      children: question.options.map((opt) {
                        final isSelected = question.correctAnswer == opt;
                        final displayLabel = opt;
                        return GestureDetector(
                          onTap: () => onChanged(opt),
                          child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.primaryGreen
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.primaryGreen
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Text(
                              displayLabel,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isSelected
                                    ? Colors.white
                                    : AppTheme.darkText,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                  if (question.type == QuestionType.trueFalse)
                    Row(
                      children: ['True', 'False'].map((opt) {
                        final isSelected = question.correctAnswer == opt;
                        final label = opt == 'True' ? ('True') : ('False');
                        return GestureDetector(
                          onTap: () => onChanged(opt),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (opt == 'True'
                                        ? AppTheme.primaryGreen
                                        : AppTheme.primaryRed)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? (opt == 'True'
                                          ? AppTheme.primaryGreen
                                          : AppTheme.primaryRed)
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : AppTheme.darkText,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                  if (question.type == QuestionType.shortAnswer ||
                      question.type == QuestionType.essay)
                    Text(
                      '${'Answer'}: ${question.correctAnswer ?? ('Not set')}',
                      style: TextStyle(color: AppTheme.lightText, fontSize: 13),
                    ),

                  if (question.type == QuestionType.matching)
                    Text(
                      '${'Correct matches'}: ${question.correctAnswer ?? ('Not set')}',
                      style: TextStyle(color: AppTheme.lightText, fontSize: 13),
                    ),
                ],
              ),
            ),

            // Edit button
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: () => _editAnswer(context),
            ),
          ],
        ),
      ),
    );
  }

  void _editAnswer(BuildContext context) {
    if (question.type == QuestionType.mcq ||
        question.type == QuestionType.trueFalse) {
      // Options already tappable
      return;
    }

    final ctrl = TextEditingController(
      text: question.correctAnswer?.toString() ?? '',
    );

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${'Question'} ${question.number}'),
        content: TextField(
          controller: ctrl,
          maxLines: question.type == QuestionType.essay ? 4 : 1,
          decoration: InputDecoration(labelText: 'Correct Answer'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ctrl.dispose();
              Navigator.pop(c);
            },
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              onChanged(ctrl.text);
              ctrl.dispose();
              Navigator.pop(c);
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }
}
