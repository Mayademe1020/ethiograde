import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../config/theme.dart';
import '../../services/locale_provider.dart';
import '../../services/analytics_provider.dart';
import '../../models/class_info.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isAm = context.watch<LocaleProvider>().isAmharic;
    final analytics = context.watch<AnalyticsProvider>().currentAnalytics;

    return Scaffold(
      appBar: AppBar(
        title: Text(isAm ? 'ትንተና' : 'Analytics'),
      ),
      body: analytics == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.analytics_outlined,
                      size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    isAm
                        ? 'ትንተና ለማየት ፈተና ያጠናቅቁ'
                        : 'Complete an assessment to see analytics',
                    style: TextStyle(color: AppTheme.lightText),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary cards
                  Row(
                    children: [
                      Expanded(
                        child: _StatBigCard(
                          label: isAm ? 'አማካይ' : 'Average',
                          value: '${analytics.classAverage.toStringAsFixed(1)}%',
                          icon: Icons.trending_up,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatBigCard(
                          label: isAm ? 'ማለፍ ያለበት' : 'Pass Rate',
                          value: '${analytics.passRate.toStringAsFixed(0)}%',
                          icon: Icons.check_circle,
                          color: AppTheme.info,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _StatBigCard(
                          label: isAm ? 'ከፍተኛ' : 'Highest',
                          value: '${analytics.highestScore.toStringAsFixed(1)}%',
                          icon: Icons.arrow_upward,
                          color: AppTheme.success,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatBigCard(
                          label: isAm ? 'ዝቅተኛ' : 'Lowest',
                          value: '${analytics.lowestScore.toStringAsFixed(1)}%',
                          icon: Icons.arrow_downward,
                          color: AppTheme.primaryRed,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Grade distribution chart
                  Text(
                    isAm ? 'የደረጃ ስርጭት' : 'Grade Distribution',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: _GradeDistributionChart(
                      distribution: analytics.gradeDistribution,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Question difficulty heatmap
                  Text(
                    isAm ? 'ጥያቄ ችግር' : 'Question Difficulty',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isAm
                        ? 'ቀይ = ከባድ, አረንጓዴ = ቀላል'
                        : 'Red = difficult, Green = easy',
                    style: TextStyle(color: AppTheme.lightText, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  _QuestionHeatmap(
                    analytics: analytics.questionAnalytics,
                  ),
                  const SizedBox(height: 24),

                  // Topic scores (if available)
                  if (analytics.topicScores.isNotEmpty) ...[
                    Text(
                      isAm ? 'የርዕስ ውጤት' : 'Topic Scores',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...analytics.topicScores.entries.map((entry) {
                      final score = entry.value;
                      final color = score >= 70
                          ? AppTheme.primaryGreen
                          : score >= 50
                              ? AppTheme.warning
                              : AppTheme.primaryRed;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  entry.key,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500),
                                ),
                                Text(
                                  '${score.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: color,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: score / 100,
                                backgroundColor: Colors.grey.shade200,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(color),
                                minHeight: 8,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],

                  const SizedBox(height: 24),

                  // Insights
                  _InsightsCard(
                    analytics: analytics,
                    isAmharic: isAm,
                  ),
                ],
              ),
            ),
    );
  }
}

class _StatBigCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatBigCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.lightText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GradeDistributionChart extends StatelessWidget {
  final Map<String, int> distribution;
  const _GradeDistributionChart({required this.distribution});

  @override
  Widget build(BuildContext context) {
    if (distribution.isEmpty) {
      return const Center(child: Text('No data'));
    }

    final entries = distribution.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final maxVal = entries.fold<int>(0, (m, e) => e.value > m ? e.value : m);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: (maxVal + 2).toDouble(),
        barTouchData: BarTouchData(enabled: true),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i >= 0 && i < entries.length) {
                  return Text(
                    entries[i].key,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }
                return const SizedBox();
              },
            ),
          ),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: entries.asMap().entries.map((mapEntry) {
          final i = mapEntry.key;
          final entry = mapEntry.value;
          final color = _gradeColor(entry.key);
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: entry.value.toDouble(),
                color: color,
                width: 24,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Color _gradeColor(String grade) {
    if (grade.startsWith('A')) return AppTheme.primaryGreen;
    if (grade.startsWith('B')) return AppTheme.info;
    if (grade.startsWith('C')) return AppTheme.warning;
    if (grade == 'D') return const Color(0xFFED8936);
    return AppTheme.primaryRed;
  }
}

class _QuestionHeatmap extends StatelessWidget {
  final List<QuestionAnalytics> analytics;
  const _QuestionHeatmap({required this.analytics});

  @override
  Widget build(BuildContext context) {
    if (analytics.isEmpty) {
      return const Center(child: Text('No question data'));
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: analytics.map((q) {
        final rate = q.correctRate;
        final color = Color.lerp(
          AppTheme.primaryRed,
          AppTheme.primaryGreen,
          rate,
        )!;

        return Tooltip(
          message: 'Q${q.questionNumber}: ${(rate * 100).toStringAsFixed(0)}%',
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color, width: 1.5),
            ),
            child: Center(
              child: Text(
                '${q.questionNumber}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _InsightsCard extends StatelessWidget {
  final ClassAnalytics analytics;
  final bool isAmharic;

  const _InsightsCard({
    required this.analytics,
    required this.isAmharic,
  });

  @override
  Widget build(BuildContext context) {
    final insights = <String>[];

    // Generate insights
    if (analytics.passRate < 50) {
      insights.add(isAmharic
          ? '⚠️ የማለፍ መጠን ${analytics.passRate.toStringAsFixed(0)}% ነው — ይህ ፈተና ለአብዛኛዎቹ ተማሪዎች ከባድ ነበር'
          : '⚠️ Pass rate is ${analytics.passRate.toStringAsFixed(0)}% — this test was hard for most students');
    }

    final difficultQs = analytics.questionAnalytics
        .where((q) => q.correctRate < 0.4)
        .toList();
    if (difficultQs.isNotEmpty) {
      final qNums = difficultQs.map((q) => 'Q${q.questionNumber}').join(', ');
      insights.add(isAmharic
          ? '🔴 ከባድ ጥያቄዎች: $qNums — እነዚህን ርዕሶች ዳግም ያስተምሩ'
          : '🔴 Difficult questions: $qNums — revisit these topics');
    }

    final easyQs = analytics.questionAnalytics
        .where((q) => q.correctRate > 0.9)
        .toList();
    if (easyQs.length > analytics.questionAnalytics.length * 0.5) {
      insights.add(isAmharic
          ? '🟢 ብዙ ጥያቄዎች ቀላል ነበሩ — ደረጃ ማንሳት ይችላል'
          : '🟢 Many questions were easy — consider raising difficulty');
    }

    if (insights.isEmpty) {
      insights.add(isAmharic
          ? '✅ መደበኛ ውጤት — ተማሪዎች ጥሩ አፈጻጸም አሳይተዋል'
          : '✅ Normal distribution — students performed well');
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb, color: AppTheme.primaryGreen),
              const SizedBox(width: 8),
              Text(
                isAmharic ? 'ግንዛቤዎች' : 'Insights',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...insights.map((insight) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(insight, style: const TextStyle(fontSize: 14)),
          )),
        ],
      ),
    );
  }
}
