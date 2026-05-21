import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'weighted_grade.g.dart';

/// A weighted component in a composite grade (e.g., Quiz 20%, Midterm 30%, Final 50%).
///
/// Each component maps to an assessment or group of assessments.
/// The final grade is the weighted sum of component averages.
///
/// Example:
/// ```dart
/// final scale = WeightedGradeScale(
///   name: 'Semester 1',
///   components: [
///     GradeComponent(name: 'Quiz', weight: 0.20, assessmentIds: [...]),
///     GradeComponent(name: 'Midterm', weight: 0.30, assessmentIds: [...]),
///     GradeComponent(name: 'Final', weight: 0.50, assessmentIds: [...]),
///   ],
/// );
/// ```
@HiveType(typeId: 22)
class WeightedGradeScale {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String name;
  @HiveField(3)
  final String classId; // Which class this applies to
  @HiveField(4)
  final List<GradeComponent> components;
  @HiveField(5)
  final String rubricType; // moe_national, private_international, university
  @HiveField(6)
  final DateTime createdAt;

  WeightedGradeScale({
    String? id,
    required this.name,
    required this.classId,
    required this.components,
    this.rubricType = 'moe_national',
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  /// Validate that weights sum to 1.0 (100%).
  bool get isValid {
    final sum = components.fold(0.0, (s, c) => s + c.weight);
    return (sum - 1.0).abs() < 0.01;
  }

  /// Total weight as percentage.
  double get totalWeight =>
      components.fold(0.0, (s, c) => s + c.weight) * 100;

  String getDisplayName() =>
      name;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'classId': classId,
    'components': components.map((c) => c.toMap()).toList(),
    'rubricType': rubricType,
    'createdAt': createdAt.toIso8601String(),
  };

  factory WeightedGradeScale.fromMap(Map<String, dynamic> map) =>
      WeightedGradeScale(
        id: map['id'],
        name: map['name'] ?? '',
        classId: map['classId'] ?? '',
        components: (map['components'] as List? ?? [])
            .map((c) => GradeComponent.fromMap(Map<String, dynamic>.from(c)))
            .toList(),
        rubricType: map['rubricType'] ?? 'moe_national',
        createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now());
}

/// One component in a weighted grade (e.g., "Quiz" at 20%).
@HiveType(typeId: 23)
class GradeComponent {
  @HiveField(0)
  final String name;
  @HiveField(2)
  final double weight; // 0.0 to 1.0
  @HiveField(3)
  final List<String> assessmentIds; // Assessments that belong to this component
  @HiveField(4)
  final int dropLowest; // Drop N lowest scores (0 = none)

  const GradeComponent({
    required this.name,
    required this.weight,
    this.assessmentIds = const [],
    this.dropLowest = 0,
  });

  String getDisplayName() =>
      name;

  Map<String, dynamic> toMap() => {
    'name': name,
    'weight': weight,
    'assessmentIds': assessmentIds,
    'dropLowest': dropLowest,
  };

  factory GradeComponent.fromMap(Map<String, dynamic> map) => GradeComponent(
    name: map['name'] ?? '',
    weight: (map['weight'] ?? 0).toDouble(),
    assessmentIds: List<String>.from(map['assessmentIds'] ?? []),
    dropLowest: map['dropLowest'] ?? 0);
}

/// Composite grade result for one student.
class CompositeGrade {
  final String studentId;
  final String studentName;
  final Map<String, double> componentAverages; // componentName → average %
  final Map<String, int> componentAttempts; // componentName → # of assessments graded
  final double weightedPercentage;
  final String letterGrade;
  final String rubricType;

  const CompositeGrade({
    required this.studentId,
    required this.studentName,
    required this.componentAverages,
    required this.componentAttempts,
    required this.weightedPercentage,
    required this.letterGrade,
    required this.rubricType,
  });

  /// Components that have no grades yet.
  List<String> get missingComponents {
    return componentAverages.entries
        .where((e) => componentAttempts[e.key] == 0)
        .map((e) => e.key)
        .toList();
  }

  /// Whether all components have at least one grade.
  bool get isComplete => missingComponents.isEmpty;
}
