import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/assessment.dart';
import '../../models/scan_result.dart';
import '../../models/item_analysis.dart';
import '../../services/item_analysis_service.dart';

/// Screen showing per-question item analysis for a graded assessment.
///
/// Displays:
/// - Summary cards (easy/medium/hard counts, low discrimination warnings)
/// - Question list sorted by difficulty (hardest first)
/// - Tap question for answer distribution detail
class ItemAnalysisScreen extends StatefulWidget {
  final Assessment assessment;
  final List<ScanResult> results;

  const ItemAnalysisScreen({
    super.key,
    required this.assessment,
    required this.results,
  });

  @override
  State<ItemAnalysisScreen> createState() => _ItemAnalysisScreenState();
}

class _ItemAnalysisScreenState extends State<ItemAnalysisScreen> {
  late final ClassAnalysisSummary _summary;
  late final List<ScanResult> _gradedResults;
  bool _sortByDifficulty = true;

  @override
  void initState() {
    super.initState();
    // Filter to only graded/reviewed results for consistency
    _gradedResults = widget.results
        .where(
          (r) =>
              r.status == ScanStatus.graded || r.status == ScanStatus.reviewed,
        )
        .toList();
    _summary = const ItemAnalysisService().computeSummary(
      results: _gradedResults,
      assessment: widget.assessment,
    );
  }

  List<QuestionStats> get _sortedQuestions {
    final questions = List<QuestionStats>.from(_summary.questions);
    if (_sortByDifficulty) {
      questions.sort((a, b) => a.difficulty.compareTo(b.difficulty));
    } else {
      questions.sort((a, b) => a.questionNumber.compareTo(b.questionNumber));
    }
    return questions;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Item Analysis'),
        actions: [
          IconButton(
            icon: Icon(_sortByDifficulty ? Icons.sort : Icons.sort_by_alpha),
            onPressed: () =>
                setState(() => _sortByDifficulty = !_sortByDifficulty),
            tooltip: _sortByDifficulty
                ? 'Sort by number'
                : 'Sort by difficulty',
          ),
        ],
      ),
      body: SafeArea(
        child: _summary.totalStudents == 0
            ? const Center(child: Text('No graded results to analyze'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SummaryCards(summary: _summary),
                  const SizedBox(height: 16),
                  if (_summary.lowDiscriminationCount > 0)
                    _WarningBanner(
                      count: _summary.lowDiscriminationCount,
                      message:
                          '${_summary.lowDiscriminationCount} question(s) have low discrimination — review these',
                    ),
                  const SizedBox(height: 8),
                  _SectionHeader(
                    title: 'Questions',
                    subtitle: _sortByDifficulty
                        ? 'Sorted by difficulty (hardest first)'
                        : 'Sorted by number',
                  ),
                  const SizedBox(height: 8),
                  ..._sortedQuestions.map(
                    (q) => _QuestionRow(
                      stats: q,
                      onTap: () => _showQuestionDetail(q),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _showQuestionDetail(QuestionStats stats) {
    final breakdown = const ItemAnalysisService().getAnswerBreakdown(
      questionNumber: stats.questionNumber,
      results: _gradedResults,
      correctAnswer:
          widget.assessment.questions
              .firstWhere(
                (q) => q.number == stats.questionNumber,
                orElse: () => Question(number: 0, type: QuestionType.mcq),
              )
              .correctAnswer
              ?.toString() ??
          '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) =>
          _QuestionDetailSheet(stats: stats, breakdown: breakdown),
    );
  }
}

/// Summary cards showing easy/medium/hard counts.
class _SummaryCards extends StatelessWidget {
  final ClassAnalysisSummary summary;
  const _SummaryCards({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _SummaryCard(
              label: 'Students',
              value: '${summary.totalStudents}',
              color: AppTheme.info,
            ),
            const SizedBox(width: 8),
            _SummaryCard(
              label: 'Avg Score',
              value: '${summary.averageScore.toStringAsFixed(1)}%',
              color: AppTheme.info,
            ),
            const SizedBox(width: 8),
            _SummaryCard(
              label: 'Pass Rate',
              value: '${summary.passRate.toStringAsFixed(0)}%',
              color: summary.passRate >= 50
                  ? context.primaryGreen
                  : context.primaryRed,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _SummaryCard(
              label: 'Easy',
              value: '${summary.easyCount}',
              color: context.primaryGreen,
            ),
            const SizedBox(width: 8),
            _SummaryCard(
              label: 'Medium',
              value: '${summary.mediumCount}',
              color: Colors.orange,
            ),
            const SizedBox(width: 8),
            _SummaryCard(
              label: 'Hard',
              value: '${summary.hardCount}',
              color: context.primaryRed,
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: color)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Warning banner for low discrimination questions.
class _WarningBanner extends StatelessWidget {
  final int count;
  final String message;

  const _WarningBanner({required this.count, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: Colors.orange.shade800),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: context.darkText,
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            style: TextStyle(fontSize: 12, color: context.lightText),
          ),
      ],
    );
  }
}

/// Single question row in the list.
class _QuestionRow extends StatelessWidget {
  final QuestionStats stats;
  final VoidCallback onTap;

  const _QuestionRow({required this.stats, required this.onTap});

  Color get _difficultyColor {
    switch (stats.difficultyLabel) {
      case 'Easy':
        return AppTheme.primaryGreen;
      case 'Medium':
        return Colors.orange;
      case 'Hard':
        return AppTheme.primaryRed;
      default:
        return AppTheme.lightText;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Question number
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _difficultyColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    'Q${stats.questionNumber}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _difficultyColor,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Difficulty bar
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${stats.correctCount}/${stats.totalStudents} correct',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _difficultyColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            stats.difficultyLabel,
                            style: TextStyle(
                              fontSize: 11,
                              color: _difficultyColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: stats.difficulty,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _difficultyColor,
                        ),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${(stats.difficulty * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.lightText,
                          ),
                        ),
                        if (stats.mostCommonWrong != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            'Common wrong: ${stats.mostCommonWrong}',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.lightText,
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (stats.isLowDiscrimination)
                          const Icon(
                            Icons.info_outline,
                            size: 14,
                            color: Colors.orange,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: context.lightText),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet showing detailed answer distribution for a question.
class _QuestionDetailSheet extends StatelessWidget {
  final QuestionStats stats;
  final List<AnswerBreakdown> breakdown;

  const _QuestionDetailSheet({required this.stats, required this.breakdown});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Question ${stats.questionNumber}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${stats.correctCount}/${stats.totalStudents} students correct (${(stats.difficulty * 100).toStringAsFixed(0)}%)',
                style: TextStyle(color: context.lightText),
              ),
              const SizedBox(height: 20),
              // Stats row
              Row(
                children: [
                  _DetailStat(
                    label: 'Difficulty',
                    value: stats.difficultyLabel,
                  ),
                  const SizedBox(width: 12),
                  _DetailStat(
                    label: 'Discrimination',
                    value: stats.discrimination.toStringAsFixed(2),
                    isWarning: stats.isLowDiscrimination,
                  ),
                  const SizedBox(width: 12),
                  _DetailStat(
                    label: 'Unanswered',
                    value: '${stats.unansweredCount}',
                    isWarning: stats.unansweredCount > 0,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Answer Distribution',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...breakdown.map(
                (b) => _AnswerBar(
                  option: b.option,
                  count: b.count,
                  percentage: b.percentage,
                  isCorrect: b.isCorrectOption,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DetailStat extends StatelessWidget {
  final String label;
  final String value;
  final bool isWarning;

  const _DetailStat({
    required this.label,
    required this.value,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isWarning
              ? Colors.orange.withValues(alpha: 0.1)
              : context.warmGray,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 10, color: context.lightText),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isWarning ? Colors.orange : context.darkText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal bar showing answer distribution.
class _AnswerBar extends StatelessWidget {
  final String option;
  final int count;
  final double percentage;
  final bool isCorrect;

  const _AnswerBar({
    required this.option,
    required this.count,
    required this.percentage,
    required this.isCorrect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              option,
              style: TextStyle(
                fontWeight: isCorrect ? FontWeight.bold : FontWeight.normal,
                color: isCorrect ? context.primaryGreen : context.darkText,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percentage / 100,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isCorrect ? context.primaryGreen : AppTheme.info,
                ),
                minHeight: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(
              '$count (${percentage.toStringAsFixed(0)}%)',
            style: TextStyle(fontSize: 12, color: context.lightText),
            ),
          ),
        ],
      ),
    );
  }
}
