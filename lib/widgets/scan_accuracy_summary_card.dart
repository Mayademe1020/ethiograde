import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/assessment.dart';
import '../../models/scan_result.dart';
import '../../services/scan_accuracy_reporter.dart';

/// Compact scan-accuracy summary shown on the results screen.
///
/// Surfaces the field-test accuracy metric (correct / correct+wrong+missed)
/// from [ScanAccuracyReporter] so teachers can see, per assessment:
/// - Overall detection accuracy
/// - Problem questions (accuracy below threshold)
class ScanAccuracySummaryCard extends StatefulWidget {
  final Assessment assessment;
  final List<ScanResult> results;

  const ScanAccuracySummaryCard({
    super.key,
    required this.assessment,
    required this.results,
  });

  @override
  State<ScanAccuracySummaryCard> createState() =>
      _ScanAccuracySummaryCardState();
}

class _ScanAccuracySummaryCardState extends State<ScanAccuracySummaryCard> {
  static const double _problemThreshold = 0.8;
  late final ScanAccuracyReport _report;

  @override
  void initState() {
    super.initState();
    _report = const ScanAccuracyReporter().report(
      assessment: widget.assessment,
      results: widget.results,
    );
  }

  @override
  Widget build(BuildContext context) {
    final problemQuestions = _report.problemQuestions(
      threshold: _problemThreshold,
    );
    final accuracy = _report.overallAccuracy;
    final color = accuracy >= _problemThreshold
        ? AppTheme.success
        : accuracy >= 0.6
        ? AppTheme.warning
        : AppTheme.error;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.radar, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                'Scan Accuracy',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const Spacer(),
              Text(
                '${(accuracy * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_report.correctCount} correct, ${_report.wrongCount} wrong, '
            '${_report.missedCount} not read across '
            '${_report.totalStudents} paper(s)',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (problemQuestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Low-accuracy questions',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            ...problemQuestions.map((q) {
              final qColor = q.accuracy >= 0.6
                  ? AppTheme.warning
                  : AppTheme.error;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: qColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Q${q.questionNumber}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: qColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: q.accuracy,
                          minHeight: 5,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.outlineVariant,
                          color: qColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${(q.accuracy * 100).toStringAsFixed(0)}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: qColor,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
