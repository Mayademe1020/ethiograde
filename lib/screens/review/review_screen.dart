import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/scan_result.dart';
import '../../models/assessment.dart';
import '../../services/locale_provider.dart';
import '../../services/scoring_service.dart';
import '../../services/voice_service.dart';
import '../../services/assessment_provider.dart';
import '../../services/hybrid_grading_service.dart';

// ──── Review List ────

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  List<ScanResult>? _results;
  _SortMode _sortMode = _SortMode.highestFirst;
  bool _hasUnsavedChanges = false;
  bool _isSaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Capture route args once so we can sort a local copy.
    _results ??=
        (ModalRoute.of(context)?.settings.arguments as List<ScanResult>? ?? [])
            .toList();
  }

  void _applySort() {
    setState(() {
      switch (_sortMode) {
        case _SortMode.lowestFirst:
          _results!.sort((a, b) => a.percentage.compareTo(b.percentage));
        case _SortMode.highestFirst:
          _results!.sort((a, b) => b.percentage.compareTo(a.percentage));
        case _SortMode.needsReviewFirst:
          _results!.sort((a, b) {
            // needs-review first, then lowest score
            if (a.needsReview != b.needsReview) {
              return a.needsReview ? -1 : 1;
            }
            return a.percentage.compareTo(b.percentage);
          });
      }
    });
  }

  /// Replace a single result after teacher overrides scores.
  void _updateResult(int index, ScanResult updated) {
    setState(() {
      _results![index] = updated;
      _hasUnsavedChanges = true;
    });
  }

  /// Save all reviewed results to Hive.
  Future<void> _saveAll(bool isAm) async {
    if (_results == null || _results!.isEmpty) return;
    setState(() => _isSaving = true);

    final grading = HybridGradingService();
    int saved = 0;
    int failed = 0;

    for (final result in _results!) {
      // Only save results that were reviewed/overridden
      if (result.status == ScanStatus.reviewed) {
        final ok = await grading.saveScanResult(result);
        if (ok) saved++;
        else failed++;
      }
    }

    if (mounted) {
      setState(() {
        _isSaving = false;
        _hasUnsavedChanges = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? (isAm ? '$saved ተቀምጧል' : '$saved result(s) saved')
                : (isAm
                    ? '$saved ተቀምጧል፣ $failed አልተቻለም'
                    : '$saved saved, $failed failed'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAm = context.watch<LocaleProvider>().isAmharic;
    final results = _results ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(isAm ? 'ውጤቶችን ይገምግሙ' : 'Review Results'),
        actions: [
          if (_hasUnsavedChanges && !_isSaving)
            TextButton.icon(
              onPressed: () => _saveAll(isAm),
              icon: const Icon(Icons.save, size: 18),
              label: Text(isAm ? 'ሁሉን አስቀምጥ' : 'Save All'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryGreen,
              ),
            ),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () => _showSortOptions(context, isAm),
          ),
        ],
      ),
      body: results.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    isAm ? 'ውጤት የለም' : 'No results to review',
                    style: TextStyle(color: AppTheme.lightText, fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: results.length,
              itemBuilder: (context, index) {
                final result = results[index];
                return _ResultCard(
                  result: result,
                  isAmharic: isAm,
                  onTap: () async {
                    final updated = await Navigator.pushNamed(
                      context,
                      AppRoutes.sideBySide,
                      arguments: result,
                    );
                    if (updated is ScanResult) {
                      _updateResult(index, updated);
                    }
                  },
                );
              },
            ),
    );
  }

  void _showSortOptions(BuildContext context, bool isAm) {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.arrow_downward),
              title: Text(isAm ? 'ከዝቅተኛ ወደ ከፍተኛ' : 'Lowest to Highest'),
              trailing: _sortMode == _SortMode.lowestFirst
                  ? const Icon(Icons.check, color: AppTheme.primaryGreen)
                  : null,
              onTap: () {
                _sortMode = _SortMode.lowestFirst;
                _applySort();
                Navigator.pop(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: Text(isAm ? 'ከከፍተኛ ወደ ዝቅተኛ' : 'Highest to Lowest'),
              trailing: _sortMode == _SortMode.highestFirst
                  ? const Icon(Icons.check, color: AppTheme.primaryGreen)
                  : null,
              onTap: () {
                _sortMode = _SortMode.highestFirst;
                _applySort();
                Navigator.pop(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.warning),
              title: Text(isAm ? 'ማረሚያ የሚያስፈልጉ' : 'Needs Review First'),
              trailing: _sortMode == _SortMode.needsReviewFirst
                  ? const Icon(Icons.check, color: AppTheme.primaryGreen)
                  : null,
              onTap: () {
                _sortMode = _SortMode.needsReviewFirst;
                _applySort();
                Navigator.pop(c);
              },
            ),
          ],
        ),
      ),
    );
  }
}

enum _SortMode { lowestFirst, highestFirst, needsReviewFirst }

// ──── Result Card ────

class _ResultCard extends StatelessWidget {
  final ScanResult result;
  final bool isAmharic;
  final VoidCallback onTap;

  const _ResultCard({
    required this.result,
    required this.isAmharic,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final passMark = 50;
    final passed = result.percentage >= passMark;
    final needsReview = result.needsReview;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Student avatar
                  CircleAvatar(
                    backgroundColor: passed
                        ? AppTheme.primaryGreen.withOpacity(0.1)
                        : AppTheme.primaryRed.withOpacity(0.1),
                    child: Text(
                      result.studentName.isNotEmpty
                          ? result.studentName[0]
                          : '?',
                      style: TextStyle(
                        color: passed
                            ? AppTheme.primaryGreen
                            : AppTheme.primaryRed,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.studentName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        if (needsReview)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.warning.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isAmharic ? 'ማረሚያ ያስፈልጋል' : 'Needs Review',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.warning,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Score badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: passed
                          ? AppTheme.primaryGreen.withOpacity(0.1)
                          : AppTheme.primaryRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${result.percentage.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: passed
                                ? AppTheme.primaryGreen
                                : AppTheme.primaryRed,
                          ),
                        ),
                        Text(
                          result.grade,
                          style: TextStyle(
                            fontSize: 12,
                            color: passed
                                ? AppTheme.primaryGreen
                                : AppTheme.primaryRed,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Answer summary
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: result.answers.map((a) {
                  return Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: a.isCorrect
                          ? AppTheme.primaryGreen.withOpacity(0.15)
                          : a.detectedAnswer == '[MISSING]'
                              ? Colors.grey.shade200
                              : AppTheme.primaryRed.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: a.isCorrect
                            ? AppTheme.primaryGreen
                            : a.detectedAnswer == '[MISSING]'
                                ? Colors.grey
                                : AppTheme.primaryRed,
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${a.questionNumber}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: a.isCorrect
                              ? AppTheme.primaryGreen
                              : a.detectedAnswer == '[MISSING]'
                                  ? Colors.grey
                                  : AppTheme.primaryRed,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${result.totalScore.toInt()}/${result.maxScore.toInt()}',
                    style: TextStyle(
                      color: AppTheme.lightText,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${isAmharic ? 'መተማመን' : 'Confidence'}: ${(result.confidence * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: AppTheme.lightText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──── Side-by-Side Review ────

class SideBySideReview extends StatefulWidget {
  const SideBySideReview({super.key});

  @override
  State<SideBySideReview> createState() => _SideBySideReviewState();
}

class _SideBySideReviewState extends State<SideBySideReview> {
  final VoiceService _voice = VoiceService();
  late TextEditingController _commentController;

  // Mutable copy of the result — override buttons modify this.
  late ScanResult _result;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _result = ModalRoute.of(context)?.settings.arguments as ScanResult ??
          ScanResult(
            assessmentId: '',
            studentId: '',
            studentName: 'Unknown',
            imagePath: '',
          );
      _commentController =
          TextEditingController(text: _result.teacherComment ?? '');
      _initialized = true;
    }
  }

  /// Recalculate totals after an answer override, then rebuild.
  void _recalculateAndRefresh() {
    final scoring = const ScoringService();

    // Look up the actual assessment for correct rubric type
    final assessments = context.read<AssessmentProvider>().assessments;
    final assessment = assessments.cast<Assessment?>().firstWhere(
          (a) => a?.id == _result.assessmentId,
          orElse: () => null,
        );
    final rubricType = assessment?.rubricType ?? 'moe_national';

    final newTotal = scoring.calculateTotalScore(_result.answers);
    final newPct = scoring.calculatePercentage(
      totalScore: newTotal,
      maxScore: _result.maxScore,
    );
    final newGrade = scoring.calculateGrade(newPct, rubricType);
    final newConfidence = scoring.calculateConfidence(_result.answers);

    setState(() {
      _result = _result.copyWith(
        answers: _result.answers,
        totalScore: newTotal,
        percentage: newPct,
        grade: newGrade,
        status: ScanStatus.reviewed,
        confidence: newConfidence,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAm = context.watch<LocaleProvider>().isAmharic;
    final result = _result;

    return Scaffold(
      appBar: AppBar(
        title: Text(result.studentName),
        actions: [
          IconButton(
            icon: const Icon(Icons.mic),
            onPressed: () => _recordVoiceNote(isAm),
            tooltip: isAm ? 'የድምጽ ማስታወሻ' : 'Voice Note',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Score summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryGreen.withOpacity(0.1),
                    AppTheme.primaryGreen.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ScoreItem(
                    label: isAm ? 'ውጤት' : 'Score',
                    value: '${result.totalScore.toInt()}/${result.maxScore.toInt()}',
                  ),
                  _ScoreItem(
                    label: '%',
                    value: '${result.percentage.toStringAsFixed(1)}%',
                  ),
                  _ScoreItem(
                    label: isAm ? 'ደረጃ' : 'Grade',
                    value: result.grade,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Image preview
            if (result.imagePath.isNotEmpty)
              Container(
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(result.imagePath),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Answer table
            Text(
              isAm ? 'በጥያቄ ውጤት' : 'Question-by-Question',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...result.answers.map((answer) => _AnswerTile(
                  answer: answer,
                  isAmharic: isAm,
                  onOverride: () => _overrideScore(answer, isAm),
                )),

            const SizedBox(height: 16),

            // Comment section
            Text(
              isAm ? 'አስተያየት' : 'Comment',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: isAm
                    ? 'የተማሪ አስተያየት ይጻፉ...'
                    : 'Write feedback for this student...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.mic),
                  onPressed: () => _recordVoiceNote(isAm),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Voice note indicator
            if (result.voiceNotePath != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.info.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mic, color: AppTheme.info),
                    const SizedBox(width: 8),
                    Text(
                      isAm ? 'የድምጽ ማስታወሻ ተቀምጧል' : 'Voice note recorded',
                      style: const TextStyle(color: AppTheme.info),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      // Re-scan: open camera in single-capture mode for this student.
                      final assessments = context.read<AssessmentProvider>().assessments;
                      final assessment = assessments.cast<Assessment?>().firstWhere(
                        (a) => a?.id == _result.assessmentId,
                        orElse: () => null,
                      );
                      if (assessment == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isAm ? 'ፈተና አልተገኘም' : 'Assessment not found',
                            ),
                          ),
                        );
                        return;
                      }

                      final updatedResult = await Navigator.pushNamed(
                        context,
                        AppRoutes.camera,
                        arguments: <String, dynamic>{
                          'assessment': assessment,
                          'studentId': _result.studentId,
                          'studentName': _result.studentName,
                        },
                      );

                      if (updatedResult is ScanResult && mounted) {
                        setState(() {
                          _result = updatedResult;
                          _commentController.text = updatedResult.teacherComment ?? '';
                        });
                      }
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: Text(isAm ? 'እንደገና ስል' : 'Re-Scan'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      // Persist comment into the result
                      final finalResult = _result.copyWith(
                        teacherComment: _commentController.text,
                        status: ScanStatus.reviewed,
                      );

                      // Auto-save to Hive — teacher overrides must persist
                      final saved = await HybridGradingService()
                          .saveScanResult(finalResult);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              saved
                                  ? (isAm ? 'ተቀምጧል' : 'Saved')
                                  : (isAm ? 'ማስቀመጥ አልተቻለም' : 'Save failed'),
                            ),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      }

                      if (mounted) Navigator.pop(context, finalResult);
                    },
                    icon: const Icon(Icons.check),
                    label: Text(isAm ? 'አረጋግጥ' : 'Confirm'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Score override ──────────────────────────────────────────────

  void _overrideScore(AnswerMatch answer, bool isAm) {
    // Look up question type from assessment for appropriate edit UI
    final assessments = context.read<AssessmentProvider>().assessments;
    final assessment = assessments.cast<Assessment?>().firstWhere(
          (a) => a?.id == _result.assessmentId,
          orElse: () => null,
        );
    final question = assessment?.questions.cast<Question?>().firstWhere(
          (q) => q?.number == answer.questionNumber,
          orElse: () => null,
        );
    final questionType = question?.type ?? QuestionType.mcq;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${isAm ? 'ጥያቄ' : 'Question'} ${answer.questionNumber}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '${isAm ? 'የተገኘ' : 'Detected'}: ${answer.detectedAnswer}',
                style: TextStyle(color: AppTheme.lightText),
              ),
              const SizedBox(height: 16),

              // Change answer section
              Text(
                isAm ? 'ትክክለኛው መልስ' : 'Change Answer',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),

              if (questionType == QuestionType.mcq)
                _McqAnswerPicker(
                  currentAnswer: answer.detectedAnswer,
                  correctAnswer: answer.correctAnswer,
                  isAmharic: isAm,
                  onSelected: (newAnswer) {
                    _applyAnswerChange(
                      answer.questionNumber,
                      newAnswer: newAnswer,
                      correctAnswer: answer.correctAnswer,
                    );
                    Navigator.pop(c);
                  },
                )
              else if (questionType == QuestionType.trueFalse)
                _TfAnswerPicker(
                  currentAnswer: answer.detectedAnswer,
                  isAmharic: isAm,
                  onSelected: (newAnswer) {
                    _applyAnswerChange(
                      answer.questionNumber,
                      newAnswer: newAnswer,
                      correctAnswer: answer.correctAnswer,
                    );
                    Navigator.pop(c);
                  },
                )
              else
                _ShortAnswerEditor(
                  currentAnswer: answer.detectedAnswer,
                  isAmharic: isAm,
                  onSubmitted: (newAnswer) {
                    _applyAnswerChange(
                      answer.questionNumber,
                      newAnswer: newAnswer,
                      correctAnswer: answer.correctAnswer,
                    );
                    Navigator.pop(c);
                  },
                ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // Quick correct/wrong toggle
              Text(
                isAm ? 'ወይም ቀጥታ' : 'Or Quick Toggle',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _applyOverride(answer.questionNumber,
                            markCorrect: true);
                        Navigator.pop(c);
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: Text(isAm ? 'ትክክል ነው' : 'Correct'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _applyOverride(answer.questionNumber,
                            markCorrect: false);
                        Navigator.pop(c);
                      },
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryRed,
                      ),
                      label: Text(isAm ? 'ስህተት ነው' : 'Wrong'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Change the actual detected answer for a question, then recalculate.
  void _applyAnswerChange(
    int questionNumber, {
    required String newAnswer,
    required String correctAnswer,
  }) {
    final updatedAnswers = _result.answers.map((a) {
      if (a.questionNumber != questionNumber) return a;
      final isCorrect = newAnswer.toUpperCase() == correctAnswer.toUpperCase();
      return AnswerMatch(
        questionNumber: a.questionNumber,
        detectedAnswer: newAnswer,
        correctAnswer: a.correctAnswer,
        isCorrect: isCorrect,
        score: isCorrect ? a.maxScore : 0,
        maxScore: a.maxScore,
        confidence: 1.0, // teacher corrected → max confidence
        ocrRawText: '(manual: $newAnswer)',
        boundingBox: a.boundingBox,
      );
    }).toList();

    setState(() {
      _result = _result.copyWith(answers: updatedAnswers);
    });
    _recalculateAndRefresh();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Q$questionNumber → $newAnswer'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// Flip isCorrect for [questionNumber], recalculate totals, rebuild.
  void _applyOverride(int questionNumber, {required bool markCorrect}) {
    final updatedAnswers = _result.answers.map((a) {
      if (a.questionNumber != questionNumber) return a;
      return AnswerMatch(
        questionNumber: a.questionNumber,
        detectedAnswer: a.detectedAnswer,
        correctAnswer: a.correctAnswer,
        isCorrect: markCorrect,
        score: markCorrect ? a.maxScore : 0,
        maxScore: a.maxScore,
        confidence: 1.0, // teacher verified → max confidence
        ocrRawText: a.ocrRawText,
        boundingBox: a.boundingBox,
      );
    }).toList();

    // Replace answers, then recalc totals.
    setState(() {
      _result = _result.copyWith(answers: updatedAnswers);
    });
    _recalculateAndRefresh();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(markCorrect
            ? 'Q$questionNumber → Correct'
            : 'Q$questionNumber → Wrong'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ── Voice note ──────────────────────────────────────────────────

  void _recordVoiceNote(bool isAm) async {
    if (_voice.isRecording) {
      final path = await _voice.stopRecording();
      if (path != null && mounted) {
        setState(() {
          _result = _result.copyWith(voiceNotePath: path);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(isAm ? 'የድምጽ ማስታወሻ ተቀምጧል' : 'Voice note saved'),
          ),
        );
      }
    } else {
      await _voice.startRecording();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAm ? 'በመቅዳት ላይ...' : 'Recording...'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }
}

// ──── Answer picker widgets ────

/// MCQ answer selector: A, B, C, D, E as tappable chips.
class _McqAnswerPicker extends StatelessWidget {
  final String currentAnswer;
  final String correctAnswer;
  final bool isAmharic;
  final ValueChanged<String> onSelected;

  const _McqAnswerPicker({
    required this.currentAnswer,
    required this.correctAnswer,
    required this.isAmharic,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    const options = ['A', 'B', 'C', 'D', 'E'];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final isCurrent = opt.toUpperCase() == currentAnswer.toUpperCase();
        final isCorrect = opt.toUpperCase() == correctAnswer.toUpperCase();
        return ChoiceChip(
          label: Text(
            opt,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isCurrent ? Colors.white : null,
            ),
          ),
          selected: isCurrent,
          selectedColor: AppTheme.primaryGreen,
          avatar: isCorrect
              ? const Icon(Icons.check, size: 16, color: AppTheme.primaryGreen)
              : null,
          onSelected: (_) => onSelected(opt),
        );
      }).toList(),
    );
  }
}

/// True/False answer selector: two large tappable buttons.
class _TfAnswerPicker extends StatelessWidget {
  final String currentAnswer;
  final bool isAmharic;
  final ValueChanged<String> onSelected;

  const _TfAnswerPicker({
    required this.currentAnswer,
    required this.isAmharic,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isTrue = currentAnswer.toUpperCase() == 'TRUE';
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => onSelected('True'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: isTrue
                    ? AppTheme.primaryGreen.withOpacity(0.15)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isTrue ? AppTheme.primaryGreen : Colors.grey.shade300,
                  width: isTrue ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    isTrue ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: isTrue ? AppTheme.primaryGreen : Colors.grey,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isAmharic ? 'እውነት' : 'True',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isTrue ? AppTheme.primaryGreen : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () => onSelected('False'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: !isTrue
                    ? AppTheme.primaryRed.withOpacity(0.15)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: !isTrue ? AppTheme.primaryRed : Colors.grey.shade300,
                  width: !isTrue ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    !isTrue ? Icons.cancel : Icons.radio_button_unchecked,
                    color: !isTrue ? AppTheme.primaryRed : Colors.grey,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isAmharic ? 'ሐሰት' : 'False',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: !isTrue ? AppTheme.primaryRed : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Short answer text editor with submit button.
class _ShortAnswerEditor extends StatefulWidget {
  final String currentAnswer;
  final bool isAmharic;
  final ValueChanged<String> onSubmitted;

  const _ShortAnswerEditor({
    required this.currentAnswer,
    required this.isAmharic,
    required this.onSubmitted,
  });

  @override
  State<_ShortAnswerEditor> createState() => _ShortAnswerEditorState();
}

class _ShortAnswerEditorState extends State<_ShortAnswerEditor> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentAnswer);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: widget.isAmharic ? 'መልስ ይጻፉ...' : 'Type answer...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
            onSubmitted: widget.onSubmitted,
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: () => widget.onSubmitted(_controller.text.trim()),
          icon: const Icon(Icons.check, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.primaryGreen,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

// ──── Shared widgets ────

class _ScoreItem extends StatelessWidget {
  final String label;
  final String value;
  const _ScoreItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppTheme.lightText),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _AnswerTile extends StatelessWidget {
  final AnswerMatch answer;
  final bool isAmharic;
  final VoidCallback onOverride;

  const _AnswerTile({
    required this.answer,
    required this.isAmharic,
    required this.onOverride,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: answer.isCorrect
              ? AppTheme.primaryGreen.withOpacity(0.1)
              : AppTheme.primaryRed.withOpacity(0.1),
          child: Text(
            '${answer.questionNumber}',
            style: TextStyle(
              color: answer.isCorrect
                  ? AppTheme.primaryGreen
                  : AppTheme.primaryRed,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          '${isAmharic ? 'ተገኘ' : 'Detected'}: ${answer.detectedAnswer}',
          style: TextStyle(
            color: answer.isCorrect
                ? AppTheme.darkText
                : AppTheme.primaryRed,
          ),
        ),
        subtitle: Text(
          '${isAmharic ? 'ትክክል' : 'Correct'}: ${answer.correctAnswer}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${answer.score.toInt()}/${answer.maxScore.toInt()}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: onOverride,
            ),
          ],
        ),
      ),
    );
  }
}
