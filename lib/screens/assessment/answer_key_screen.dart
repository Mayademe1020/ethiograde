import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/assessment.dart';
import '../../models/scan_result.dart';
import '../../services/assessment_provider.dart';
import '../../services/hybrid_grading_service.dart';
import '../../services/answer_key_recalculation_service.dart';
import '../../services/answer_key_fingerprint_service.dart';

enum _KeyChangeAction { recalculateNow, saveAndRecalculateLater, cancel }

class AnswerKeyRouteArgs {
  final Assessment assessment;
  final bool returnToReview;
  final bool returnToConfirmation;

  const AnswerKeyRouteArgs({
    required this.assessment,
    this.returnToReview = false,
    this.returnToConfirmation = false,
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

            // Bulk "Set All" option
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.tune, size: 16, color: AppTheme.lightText),
                  const SizedBox(width: 8),
                  Text('Set all ', style: TextStyle(fontSize: 12, color: AppTheme.lightText)),
                  // Set all type
                  DropdownButton<QuestionType>(
                    value: null,
                    hint: Text('Type', style: TextStyle(fontSize: 12)),
                    isDense: true,
                    underline: const SizedBox(),
                    items: QuestionType.values.map((t) => DropdownMenuItem(
                      value: t,
                      child: Text({
                        QuestionType.mcq: 'MCQ',
                        QuestionType.trueFalse: 'T/F',
                        QuestionType.shortAnswer: 'Short',
                        QuestionType.essay: 'Essay',
                        QuestionType.matching: 'Match',
                      }[t]!, style: const TextStyle(fontSize: 12)),
                    )).toList(),
                    onChanged: (type) {
                      if (type == null) return;
                      final updated = assessment.questions.map((q) => Question(
                        id: q.id, number: q.number, type: type,
                        text: q.text, points: q.points, options: q.options,
                        correctAnswer: q.correctAnswer,
                      )).toList();
                      setState(() => _assessment = assessment.copyWith(questions: updated));
                    },
                  ),
                  const SizedBox(width: 8),
                  // Set all points
                  DropdownButton<double>(
                    value: null,
                    hint: Text('Points', style: TextStyle(fontSize: 12)),
                    isDense: true,
                    underline: const SizedBox(),
                    items: [1.0, 2.0, 5.0, 10.0].map((p) => DropdownMenuItem(
                      value: p,
                      child: Text('${p.toInt()} pts', style: const TextStyle(fontSize: 12)),
                    )).toList(),
                    onChanged: (pts) {
                      if (pts == null) return;
                      final updated = assessment.questions.map((q) => Question(
                        id: q.id, number: q.number, type: q.type,
                        text: q.text, points: pts, options: q.options,
                        correctAnswer: q.correctAnswer,
                      )).toList();
                      setState(() => _assessment = assessment.copyWith(questions: updated));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Question rows with inline type/weight editing
            ...assessment.questions.map(
              (q) => _QuestionRow(
                question: q,
                onAnswerChanged: (correctAnswer) {
                  final index = assessment.questions.indexOf(q);
                  final updated = List<Question>.from(assessment.questions);
                  updated[index] = q.copyWith(correctAnswer: correctAnswer);
                  setState(() => _assessment = assessment.copyWith(questions: updated));
                },
                onTypeChanged: (type) {
                  final index = assessment.questions.indexOf(q);
                  final updated = List<Question>.from(assessment.questions);
                  updated[index] = q.copyWith(type: type);
                  setState(() => _assessment = assessment.copyWith(questions: updated));
                },
                onPointsChanged: (points) {
                  final index = assessment.questions.indexOf(q);
                  final updated = List<Question>.from(assessment.questions);
                  updated[index] = q.copyWith(points: points);
                  setState(() => _assessment = assessment.copyWith(questions: updated));
                },
              ),
            ),

            const SizedBox(height: 24),
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

      // Check if we should go directly to camera (manual answer key path)
      final args = ModalRoute.of(context)?.settings.arguments;
      final returnToConfirmation = args is AnswerKeyRouteArgs && args.returnToConfirmation;

      if (returnToConfirmation) {
        // Manual path: go directly to camera for student paper scanning
        if (context.mounted) {
          Navigator.pushReplacementNamed(
            context,
            AppRoutes.camera,
            arguments: {
              'assessment': assessment,
              'scanMode': 'batch',
            },
          );
        }
        return;
      }

      if (returnToReview) {
        if (context.mounted) Navigator.pop(context, assessment);
        return;
      }
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
      }
      return;
    }

    // Scoring key changed — check for existing results
    final List<ScanResult> results = await HybridGradingService().loadScanResults(assessment.id);

    if (!context.mounted) return;

    if (results.isEmpty) {
      // No results — save normally with incremented revision
      final updated = await provider.saveAnswerKeyChange(assessment);

      // Check if we should go directly to camera (manual answer key path)
      final args = ModalRoute.of(context)?.settings.arguments;
      final returnToConfirmation = args is AnswerKeyRouteArgs && args.returnToConfirmation;

      if (returnToConfirmation) {
        // Manual path: go directly to camera for student paper scanning
        if (context.mounted) {
          Navigator.pushReplacementNamed(
            context,
            AppRoutes.camera,
            arguments: {
              'assessment': updated,
              'scanMode': 'batch',
            },
          );
        }
        return;
      }

      if (returnToReview) {
        Navigator.pop(context, updated);
        return;
      }
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
}

class _QuestionRow extends StatelessWidget {
  final Question question;
  final Function(dynamic) onAnswerChanged;
  final Function(QuestionType) onTypeChanged;
  final Function(double) onPointsChanged;

  const _QuestionRow({
    required this.question,
    required this.onAnswerChanged,
    required this.onTypeChanged,
    required this.onPointsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Row 1: Q# + Type dropdown + Points dropdown
          Row(
            children: [
              // Question number
              CircleAvatar(
                radius: 14,
                backgroundColor: AppTheme.primaryGreen.withOpacity(0.1),
                child: Text(
                  '${question.number}',
                  style: TextStyle(
                    color: AppTheme.primaryGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Type dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: DropdownButton<QuestionType>(
                  value: question.type,
                  isDense: true,
                  underline: const SizedBox(),
                  style: TextStyle(fontSize: 11, color: AppTheme.darkText),
                  items: QuestionType.values.map((t) => DropdownMenuItem(
                    value: t,
                    child: Text({
                      QuestionType.mcq: 'MCQ',
                      QuestionType.trueFalse: 'T/F',
                      QuestionType.shortAnswer: 'Short',
                      QuestionType.essay: 'Essay',
                      QuestionType.matching: 'Match',
                    }[t]!),
                  )).toList(),
                  onChanged: (t) => onTypeChanged(t!),
                ),
              ),
              const SizedBox(width: 6),

              // Points dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: DropdownButton<double>(
                  value: question.points,
                  isDense: true,
                  underline: const SizedBox(),
                  style: TextStyle(fontSize: 11, color: AppTheme.darkText),
                  items: [1.0, 2.0, 5.0, 10.0].map((p) => DropdownMenuItem(
                    value: p,
                    child: Text('${p.toInt()}pt'),
                  )).toList(),
                  onChanged: (p) => onPointsChanged(p!),
                ),
              ),

              const Spacer(),

              // Answer indicator
              if (question.correctAnswer != null &&
                  question.correctAnswer.toString().isNotEmpty)
                Icon(Icons.check_circle, color: AppTheme.primaryGreen, size: 16)
              else
                Icon(Icons.circle_outlined, color: Colors.grey.shade300, size: 16),
            ],
          ),

          const SizedBox(height: 6),

          // Row 2: Answer options
          if (question.type == QuestionType.mcq)
            Row(
              children: question.options.map((opt) {
                final isSelected = question.correctAnswer == opt;
                return GestureDetector(
                  onTap: () => onAnswerChanged(opt),
                  child: Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primaryGreen : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected ? AppTheme.primaryGreen : Colors.grey.shade200,
                      ),
                    ),
                    child: Text(
                      opt,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isSelected ? Colors.white : AppTheme.darkText,
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
                return GestureDetector(
                  onTap: () => onAnswerChanged(opt),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (opt == 'True' ? AppTheme.primaryGreen : AppTheme.primaryRed)
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected
                            ? (opt == 'True' ? AppTheme.primaryGreen : AppTheme.primaryRed)
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Text(
                      opt,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: isSelected ? Colors.white : AppTheme.darkText,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

          if (question.type == QuestionType.shortAnswer ||
              question.type == QuestionType.essay)
            GestureDetector(
              onTap: () => _editAnswer(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  question.correctAnswer?.toString().isNotEmpty == true
                      ? question.correctAnswer.toString()
                      : 'Tap to set answer',
                  style: TextStyle(
                    fontSize: 12,
                    color: question.correctAnswer?.toString().isNotEmpty == true
                        ? AppTheme.darkText
                        : AppTheme.lightText,
                  ),
                ),
              ),
            ),

          if (question.type == QuestionType.matching)
            GestureDetector(
              onTap: () => _editAnswer(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  question.correctAnswer?.toString().isNotEmpty == true
                      ? question.correctAnswer.toString()
                      : 'Tap to set matches',
                  style: TextStyle(
                    fontSize: 12,
                    color: question.correctAnswer?.toString().isNotEmpty == true
                        ? AppTheme.darkText
                        : AppTheme.lightText,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _editAnswer(BuildContext context) {
    final ctrl = TextEditingController(
      text: question.correctAnswer?.toString() ?? '',
    );

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Q${question.number} Answer'),
        content: TextField(
          controller: ctrl,
          maxLines: question.type == QuestionType.essay ? 4 : 1,
          decoration: const InputDecoration(labelText: 'Correct Answer'),
        ),
        actions: [
          TextButton(
            onPressed: () { ctrl.dispose(); Navigator.pop(c); },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              onAnswerChanged(ctrl.text);
              ctrl.dispose();
              Navigator.pop(c);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
