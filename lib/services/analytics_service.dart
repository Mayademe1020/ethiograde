import '../models/assessment.dart';
import '../models/scan_result.dart';
import '../models/student.dart';

/// Computed statistics for a single assessment.
class AssessmentStats {
  final String assessmentId;
  final int totalStudents;
  final int gradedCount;
  final double average;
  final double median;
  final double min;
  final double max;
  final double stdDev;
  final Map<String, int> gradeDistribution;

  const AssessmentStats({
    required this.assessmentId,
    required this.totalStudents,
    required this.gradedCount,
    required this.average,
    required this.median,
    required this.min,
    required this.max,
    required this.stdDev,
    required this.gradeDistribution,
  });

  double get passRate =>
      gradedCount == 0 ? 0 : (gradeDistribution['PASS'] ?? 0) / gradedCount;

  String get letterAverage {
    if (average >= 90) return 'A+';
    if (average >= 85) return 'A';
    if (average >= 80) return 'A-';
    if (average >= 75) return 'B+';
    if (average >= 70) return 'B';
    if (average >= 65) return 'B-';
    if (average >= 60) return 'C+';
    if (average >= 55) return 'C';
    if (average >= 50) return 'C-';
    if (average >= 45) return 'D';
    return 'F';
  }
}

/// A single data point in a student's performance trend.
class TrendPoint {
  final String assessmentTitle;
  final DateTime date;
  final double percentage;
  final double maxScore;

  const TrendPoint({
    required this.assessmentTitle,
    required this.date,
    required this.percentage,
    required this.maxScore,
  });
}

/// Trend direction for a student.
enum TrendDirection { improving, declining, stable }

/// Student performance trend across multiple assessments.
class StudentTrend {
  final String studentId;
  final String studentName;
  final List<TrendPoint> points;
  final TrendDirection direction;
  final double slope;

  const StudentTrend({
    required this.studentId,
    required this.studentName,
    required this.points,
    required this.direction,
    required this.slope,
  });
}

/// An at-risk student with reasons.
class AtRiskStudent {
  final Student student;
  final double averagePercentage;
  final int assessmentsBelowThreshold;
  final String reason;

  const AtRiskStudent({
    required this.student,
    required this.averagePercentage,
    required this.assessmentsBelowThreshold,
    required this.reason,
  });
}

/// Subject-wise performance summary.
class SubjectPerformance {
  final String subject;
  final int assessmentCount;
  final double classAverage;
  final int studentCount;

  const SubjectPerformance({
    required this.subject,
    required this.assessmentCount,
    required this.classAverage,
    required this.studentCount,
  });
}

/// Computes analytics from assessment and scan result data.
class AnalyticsService {
  const AnalyticsService();

  /// Compute statistics for a single assessment.
  AssessmentStats computeStats({
    required Assessment assessment,
    required List<ScanResult> results,
  }) {
    final scores = results
        .where((r) => r.assessmentId == assessment.id)
        .map((r) => r.percentage)
        .toList()
      ..sort();

    if (scores.isEmpty) {
      return AssessmentStats(
        assessmentId: assessment.id,
        totalStudents: 0,
        gradedCount: 0,
        average: 0,
        median: 0,
        min: 0,
        max: 0,
        stdDev: 0,
        gradeDistribution: const {},
      );
    }

    final avg = scores.reduce((a, b) => a + b) / scores.length;
    final median = _median(scores);
    final min = scores.first;
    final max = scores.last;
    final stdDev = _stdDev(scores, avg);
    final distribution = _gradeDistribution(scores);

    return AssessmentStats(
      assessmentId: assessment.id,
      totalStudents: scores.length,
      gradedCount: scores.length,
      average: avg,
      median: median,
      min: min,
      max: max,
      stdDev: stdDev,
      gradeDistribution: distribution,
    );
  }

  /// Compute student trend across multiple assessments.
  List<StudentTrend> computeTrends({
    required List<Assessment> assessments,
    required List<ScanResult> allResults,
    required List<Student> students,
    double threshold = 50.0,
  }) {
    final trends = <StudentTrend>[];

    for (final student in students) {
      final points = <TrendPoint>[];

      for (final assessment in assessments) {
        final results = allResults
            .where(
              (r) =>
                  r.assessmentId == assessment.id &&
                  r.studentId == student.id,
            )
            .toList();

        if (results.isNotEmpty) {
          final best = results.reduce(
            (a, b) => a.percentage > b.percentage ? a : b,
          );
          points.add(
            TrendPoint(
              assessmentTitle: assessment.title,
              date: assessment.createdAt,
              percentage: best.percentage,
              maxScore: best.maxScore,
            ),
          );
        }
      }

      if (points.length >= 2) {
        final slope = _linearSlope(points.map((p) => p.percentage).toList());
        final direction = slope > 5
            ? TrendDirection.improving
            : slope < -5
                ? TrendDirection.declining
                : TrendDirection.stable;

        trends.add(
          StudentTrend(
            studentId: student.id,
            studentName: student.fullName,
            points: points,
            direction: direction,
            slope: slope,
          ),
        );
      }
    }

    return trends;
  }

  /// Identify at-risk students (below threshold).
  List<AtRiskStudent> findAtRiskStudents({
    required List<Assessment> assessments,
    required List<ScanResult> allResults,
    required List<Student> students,
    double threshold = 50.0,
  }) {
    final atRisk = <AtRiskStudent>[];

    for (final student in students) {
      final percentages = <double>[];

      for (final assessment in assessments) {
        final results = allResults
            .where(
              (r) =>
                  r.assessmentId == assessment.id &&
                  r.studentId == student.id,
            )
            .toList();

        if (results.isNotEmpty) {
          final best = results.reduce(
            (a, b) => a.percentage > b.percentage ? a : b,
          );
          percentages.add(best.percentage);
        }
      }

      if (percentages.isEmpty) continue;

      final avg =
          percentages.reduce((a, b) => a + b) / percentages.length;
      final belowCount =
          percentages.where((p) => p < threshold).length;

      if (avg < threshold || belowCount >= 2) {
        String reason;
        if (avg < threshold) {
          reason =
              'Average ${avg.toStringAsFixed(1)}% below ${threshold.toInt()}%';
        } else {
          reason =
              '$belowCount of ${percentages.length} assessments below ${threshold.toInt()}%';
        }

        atRisk.add(
          AtRiskStudent(
            student: student,
            averagePercentage: avg,
            assessmentsBelowThreshold: belowCount,
            reason: reason,
          ),
        );
      }
    }

    atRisk.sort((a, b) => a.averagePercentage.compareTo(b.averagePercentage));
    return atRisk;
  }

  /// Compute subject-wise class performance.
  List<SubjectPerformance> computeBySubject({
    required List<Assessment> assessments,
    required List<ScanResult> allResults,
  }) {
    final subjectMap = <String, List<double>>{};

    for (final assessment in assessments) {
      final results = allResults.where(
        (r) => r.assessmentId == assessment.id,
      );
      for (final r in results) {
        subjectMap.putIfAbsent(assessment.subject, () => []);
        subjectMap[assessment.subject]!.add(r.percentage);
      }
    }

    return subjectMap.entries.map((entry) {
      final scores = entry.value;
      final avg = scores.reduce((a, b) => a + b) / scores.length;
      return SubjectPerformance(
        subject: entry.key,
        assessmentCount: scores.length,
        classAverage: avg,
        studentCount: scores.length,
      );
    }).toList()
      ..sort((a, b) => b.classAverage.compareTo(a.classAverage));
  }

  // ── Helpers ───────────────────────────────────────────────────────

  double _median(List<double> sorted) {
    final mid = sorted.length ~/ 2;
    if (sorted.length % 2 == 0) {
      return (sorted[mid - 1] + sorted[mid]) / 2;
    }
    return sorted[mid];
  }

  double _stdDev(List<double> values, double mean) {
    final squaredDiffs = values.map((v) => (v - mean) * (v - mean));
    final variance = squaredDiffs.reduce((a, b) => a + b) / values.length;
    return variance;
  }

  Map<String, int> _gradeDistribution(List<double> scores) {
    final dist = <String, int>{'PASS': 0, 'FAIL': 0};
    for (final s in scores) {
      if (s >= 50) {
        dist['PASS'] = dist['PASS']! + 1;
      } else {
        dist['FAIL'] = dist['FAIL']! + 1;
      }
    }
    return dist;
  }

  double _linearSlope(List<double> values) {
    if (values.length < 2) return 0;
    final n = values.length;
    final xMean = (n - 1) / 2;
    final yMean = values.reduce((a, b) => a + b) / n;

    double num = 0;
    double den = 0;
    for (int i = 0; i < n; i++) {
      num += (i - xMean) * (values[i] - yMean);
      den += (i - xMean) * (i - xMean);
    }

    return den == 0 ? 0 : num / den;
  }
}
