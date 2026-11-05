import '../models/weighted_grade.dart';
import '../models/scan_result.dart';
import '../models/student.dart';
import 'scoring_service.dart';

/// Pure-Dart service for computing weighted/composite grades.
///
/// Handles the "exam has multiple components" edge case:
/// Quiz (20%) + Midterm (30%) + Final (50%) = Semester Grade.
///
/// Features:
/// - Per-component averaging (multiple quizzes → one quiz score)
/// - Drop lowest N scores per component
/// - Weighted sum → letter grade via ScoringService
/// - Missing component detection (not all exams graded yet)
///
/// No Flutter dependency — testable with plain Dart.
class WeightedGradeService {
  final ScoringService _scoring = const ScoringService();

  const WeightedGradeService();

  /// Compute the composite grade for a single student.
  ///
  /// [studentScores] maps assessmentId → percentage score for this student.
  /// Returns null if no component has any grades.
  CompositeGrade? computeStudentGrade({
    required Student student,
    required WeightedGradeScale scale,
    required Map<String, double> studentScores, // assessmentId → percentage
  }) {
    final componentAverages = <String, double>{};
    final componentAttempts = <String, int>{};

    for (final component in scale.components) {
      // Collect scores for this component's assessments
      final scores = <double>[];
      for (final assessmentId in component.assessmentIds) {
        final score = studentScores[assessmentId];
        if (score != null) {
          scores.add(score);
        }
      }

      componentAttempts[component.name] = scores.length;

      if (scores.isEmpty) {
        componentAverages[component.name] = 0;
        continue;
      }

      // Sort ascending for drop-lowest
      scores.sort();

      // Drop lowest N if configured
      final effectiveScores = component.dropLowest > 0 &&
              scores.length > component.dropLowest
          ? scores.sublist(component.dropLowest)
          : scores;

      if (effectiveScores.isEmpty) {
        componentAverages[component.name] = 0;
        continue;
      }

      final avg =
          effectiveScores.reduce((a, b) => a + b) / effectiveScores.length;
      componentAverages[component.name] = avg;
    }

    // If ALL components have zero attempts, return null
    final totalAttempts =
        componentAttempts.values.fold(0, (sum, a) => sum + a);
    if (totalAttempts == 0) return null;

    // Compute weighted percentage
    double weightedSum = 0;
    double totalWeight = 0;

    for (final component in scale.components) {
      final avg = componentAverages[component.name] ?? 0;
      final attempts = componentAttempts[component.name] ?? 0;

      if (attempts > 0) {
        weightedSum += avg * component.weight;
        totalWeight += component.weight;
      }
    }

    // Normalize: if only some components are graded, compute partial grade
    // (don't penalize for ungraded components)
    final weightedPct =
        totalWeight > 0 ? (weightedSum / totalWeight) : 0.0;

    final letterGrade =
        _scoring.calculateGrade(weightedPct, scale.rubricType);

    return CompositeGrade(
      studentId: student.id,
      studentName: student.fullName,
      componentAverages: componentAverages,
      componentAttempts: componentAttempts,
      weightedPercentage: weightedPct,
      letterGrade: letterGrade,
      rubricType: scale.rubricType);
  }

  /// Compute composite grades for all students in a class.
  ///
  /// [allResults] maps assessmentId → list of ScanResults.
  List<CompositeGrade> computeClassGrades({
    required List<Student> students,
    required WeightedGradeScale scale,
    required Map<String, List<ScanResult>> allResults,
  }) {
    final grades = <CompositeGrade>[];

    for (final student in students) {
      // Build student score map: assessmentId → percentage
      final studentScores = <String, double>{};

      for (final component in scale.components) {
        for (final assessmentId in component.assessmentIds) {
          final results = allResults[assessmentId] ?? [];
          final match = results.where(
            (r) =>
                r.studentId == student.id ||
                r.studentName == student.fullName);
          if (match.isNotEmpty) {
            studentScores[assessmentId] = match.first.percentage;
          }
        }
      }

      final grade = computeStudentGrade(
        student: student,
        scale: scale,
        studentScores: studentScores);

      if (grade != null) {
        grades.add(grade);
      }
    }

    return grades;
  }

  /// Recalculate grades after a grading scale change.
  ///
  /// When a school changes from MoE National to University rubric mid-year,
  /// this recomputes all letter grades with the new scale.
  /// Percentages stay the same — only the letter mapping changes.
  List<CompositeGrade> recalculateWithNewScale({
    required List<CompositeGrade> existingGrades,
    required String newRubricType,
  }) {
    return existingGrades.map((g) {
      return CompositeGrade(
        studentId: g.studentId,
        studentName: g.studentName,
        componentAverages: g.componentAverages,
        componentAttempts: g.componentAttempts,
        weightedPercentage: g.weightedPercentage,
        letterGrade: _scoring.calculateGrade(g.weightedPercentage, newRubricType),
        rubricType: newRubricType);
    }).toList();
  }

  /// Get class statistics from composite grades.
  CompositeClassStats computeClassStats(List<CompositeGrade> grades) {
    if (grades.isEmpty) {
      return CompositeClassStats.empty;
    }

    final percentages = grades.map((g) => g.weightedPercentage).toList()
      ..sort();

    final average =
        percentages.reduce((a, b) => a + b) / percentages.length;
    final passCount = grades.where((g) => g.weightedPercentage >= 50).length;

    final distribution = <String, int>{};
    for (final g in grades) {
      distribution[g.letterGrade] = (distribution[g.letterGrade] ?? 0) + 1;
    }

    return CompositeClassStats(
      studentCount: grades.length,
      average: average,
      highest: percentages.last,
      lowest: percentages.first,
      passRate: passCount / grades.length * 100,
      gradeDistribution: distribution,
      incompleteCount: grades.where((g) => !g.isComplete).length);
  }
}

/// Class-level statistics for composite grades.
class CompositeClassStats {
  final int studentCount;
  final double average;
  final double highest;
  final double lowest;
  final double passRate;
  final Map<String, int> gradeDistribution;
  final int incompleteCount;

  const CompositeClassStats({
    required this.studentCount,
    required this.average,
    required this.highest,
    required this.lowest,
    required this.passRate,
    required this.gradeDistribution,
    required this.incompleteCount,
  });

  static const CompositeClassStats empty = CompositeClassStats(
    studentCount: 0,
    average: 0,
    highest: 0,
    lowest: 0,
    passRate: 0,
    gradeDistribution: {},
    incompleteCount: 0);
}
