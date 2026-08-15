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

  Teacher({
    String? id,
    required this.name,
    this.subject = '',
    this.school = '',
    this.role = 'teacher',
    this.isActive = true,
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'subject': subject,
    'school': school,
    'role': role,
    'isActive': isActive,
    'createdAt': createdAt.toIso8601String(),
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
  );

  Teacher copyWith({
    String? name,
    String? subject,
    String? school,
    String? role,
    bool? isActive,
  }) => Teacher(
    id: id,
    name: name ?? this.name,
    subject: subject ?? this.subject,
    school: school ?? this.school,
    role: role ?? this.role,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt,
  );

  @override
  String toString() => 'Teacher($name, $subject, $role)';
}
