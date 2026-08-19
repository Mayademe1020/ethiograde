import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'teacher.g.dart';

@HiveType(typeId: 17)
class Teacher {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String name;
  @HiveField(2)
  final String subject;
  @HiveField(3)
  final String school;
  @HiveField(4)
  final String role; // 'teacher' | 'admin'
  @HiveField(5)
  final bool isActive;
  @HiveField(6)
  final DateTime createdAt;
  @HiveField(7)
  final List<String> subjects;
  @HiveField(8)
  final List<String> classIds;

  Teacher({
    String? id,
    required this.name,
    this.subject = '',
    this.school = '',
    this.role = 'teacher',
    this.isActive = true,
    DateTime? createdAt,
    List<String>? subjects,
    List<String>? classIds,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       subjects = subjects ?? (subject.isEmpty ? const [] : [subject]),
       classIds = classIds ?? const [];

  /// Convenience accessor: the primary subject the teacher teaches.
  String get primarySubject => subject.isNotEmpty ? subject : (subjects.isEmpty ? '' : subjects.first);

  /// All subjects taught, always including the legacy single subject.
  List<String> get allSubjects {
    final set = <String>{...subjects};
    if (subject.isNotEmpty) set.add(subject);
    return set.toList()..sort();
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'subject': subject,
    'school': school,
    'role': role,
    'isActive': isActive,
    'createdAt': createdAt.toIso8601String(),
    'subjects': subjects,
    'classIds': classIds,
  };

  factory Teacher.fromMap(Map<String, dynamic> map) => Teacher(
    id: map['id'] as String?,
    name: map['name'] as String? ?? '',
    subject: map['subject'] as String? ?? '',
    school: map['school'] as String? ?? '',
    role: map['role'] as String? ?? 'teacher',
    isActive: map['isActive'] as bool? ?? true,
    createdAt:
        DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
    subjects: (map['subjects'] as List?)?.cast<String>() ?? const [],
    classIds: (map['classIds'] as List?)?.cast<String>() ?? const [],
  );

  Teacher copyWith({
    String? name,
    String? subject,
    String? school,
    String? role,
    bool? isActive,
    List<String>? subjects,
    List<String>? classIds,
  }) => Teacher(
    id: id,
    name: name ?? this.name,
    subject: subject ?? this.subject,
    school: school ?? this.school,
    role: role ?? this.role,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt,
    subjects: subjects ?? this.subjects,
    classIds: classIds ?? this.classIds,
  );

  @override
  String toString() => 'Teacher($name, $subject, $role)';
}
