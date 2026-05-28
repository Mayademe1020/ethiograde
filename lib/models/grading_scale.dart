import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'grading_scale.g.dart';

/// A custom grading scale defined by a teacher or school.
///
/// Example:
/// ```dart
/// GradingScale(
///   name: 'My School Scale',
///   ranges: [
///     GradeRange(grade: 'A+', minScore: 97, maxScore: 100),
///     GradeRange(grade: 'A',  minScore: 93, maxScore: 96),
///     GradeRange(grade: 'B',  minScore: 80, maxScore: 92),
///     GradeRange(grade: 'F',  minScore: 0,  maxScore: 79),
///   ],
/// )
/// ```
@HiveType(typeId: 15)
class GradingScale {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String name;
  @HiveField(3)
  final List<GradeRange> ranges;
  @HiveField(4)
  final DateTime createdAt;

  GradingScale({
    String? id,
    required this.name,
    required this.ranges,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  /// Look up the letter grade for a percentage score.
  String gradeFor(double percentage) {
    for (final range in ranges) {
      if (percentage >= range.minScore && percentage <= range.maxScore) {
        return range.grade;
      }
    }
    return ranges.isNotEmpty ? ranges.last.grade : 'F';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'ranges': ranges.map((r) => r.toMap()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory GradingScale.fromMap(Map<String, dynamic> map) => GradingScale(
        id: map['id'],
        name: map['name'] ?? '',
        ranges: (map['ranges'] as List? ?? [])
            .map((r) => GradeRange.fromMap(r))
            .toList(),
        createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now());

  /// Key used in the rubricType field to reference this custom scale.
  String get rubricKey => 'custom:$id';
}

/// A single grade band within a grading scale.
@HiveType(typeId: 16)
class GradeRange {
  @HiveField(0)
  final String grade; // e.g. 'A+', 'B', 'F'
  @HiveField(1)
  final int minScore; // inclusive, 0-100
  @HiveField(2)
  final int maxScore; // inclusive, 0-100

  const GradeRange({
    required this.grade,
    required this.minScore,
    required this.maxScore,
  });

  Map<String, dynamic> toMap() => {
        'grade': grade,
        'minScore': minScore,
        'maxScore': maxScore,
      };

  factory GradeRange.fromMap(Map<String, dynamic> map) => GradeRange(
        grade: map['grade'] ?? '',
        minScore: map['minScore'] ?? 0,
        maxScore: map['maxScore'] ?? 0);
}
