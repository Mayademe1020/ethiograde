import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'class_info.g.dart';

/// A class profile — the container for students and assessments.
///
/// Examples: "Grade 5A Math", "Grade 10 Science", "Grade 12 Section B"
/// One teacher can have many classes. One student can be in many classes.
@HiveType(typeId: 1)
class ClassInfo {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String name; // e.g. "Grade 5A" or "Math 5A"
  @HiveField(2)
  final String school;
  @HiveField(3)
  final int grade; // 1-12 or university year
  @HiveField(4)
  final String section; // e.g. "A", "B", "C"
  @HiveField(5)
  final String subject; // e.g. "Mathematics", "English"
  @HiveField(6)
  final List<String> studentIds; // IDs of students in this class
  @HiveField(7)
  final String ownerId; // Teacher ID who owns this class
  @HiveField(8)
  final DateTime createdAt;
  @HiveField(9)
  final DateTime? lastModifiedAt;
  @HiveField(10)
  final String? examScheduleNote; // Free text: "Final exam June 15"
  @HiveField(11)
  final String academicYear; // e.g. "2026-2027"

  const ClassInfo._({
    required this.id,
    required this.name,
    required this.school,
    required this.grade,
    required this.section,
    required this.subject,
    required this.studentIds,
    required this.ownerId,
    required this.createdAt,
    this.lastModifiedAt,
    this.examScheduleNote,
    this.academicYear = '',
  });

  factory ClassInfo({
    String? id,
    required String name,
    String school = '',
    int grade = 1,
    String section = '',
    String subject = '',
    List<String>? studentIds,
    required String ownerId,
    DateTime? createdAt,
    DateTime? lastModifiedAt,
    String? examScheduleNote,
    String academicYear = '',
  }) => ClassInfo._(
    id: id ?? const Uuid().v4(),
    name: name,
    school: school,
    grade: grade,
    section: section,
    subject: subject,
    studentIds: studentIds ?? [],
    ownerId: ownerId,
    createdAt: createdAt ?? DateTime.now(),
    lastModifiedAt: lastModifiedAt,
    examScheduleNote: examScheduleNote,
    academicYear: academicYear);

  int get studentCount => studentIds.length;

  /// Display label: "Grade 5A Math" or just "Grade 5A" if no subject.
  String get displayName {
    final parts = <String>[];
    if (grade > 0) parts.add('Grade $grade');
    if (section.isNotEmpty) parts.add(section);
    if (subject.isNotEmpty) parts.add(subject);
    return parts.isEmpty ? name : parts.join(' ');
  }

  ClassInfo copyWith({
    String? name,
    String? school,
    int? grade,
    String? section,
    String? subject,
    List<String>? studentIds,
    String? ownerId,
    DateTime? lastModifiedAt,
    String? examScheduleNote,
    String? academicYear,
  }) => ClassInfo(
    id: id,
    name: name ?? this.name,
    school: school ?? this.school,
    grade: grade ?? this.grade,
    section: section ?? this.section,
    subject: subject ?? this.subject,
    studentIds: studentIds ?? this.studentIds,
    ownerId: ownerId ?? this.ownerId,
    createdAt: createdAt,
    lastModifiedAt: lastModifiedAt ?? DateTime.now(),
    examScheduleNote: examScheduleNote ?? this.examScheduleNote,
    academicYear: academicYear ?? this.academicYear);

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'school': school,
    'grade': grade,
    'section': section,
    'subject': subject,
    'studentIds': studentIds,
    'ownerId': ownerId,
    'createdAt': createdAt.toIso8601String(),
    'lastModifiedAt': lastModifiedAt?.toIso8601String(),
    'examScheduleNote': examScheduleNote,
    'academicYear': academicYear,
  };

  factory ClassInfo.fromMap(Map<String, dynamic> map) => ClassInfo(
    id: map['id'] ?? '',
    name: map['name'] ?? '',
    school: map['school'] ?? '',
    grade: map['grade'] ?? 1,
    section: map['section'] ?? '',
    subject: map['subject'] ?? '',
    studentIds: map['studentIds'] != null
        ? List<String>.from(map['studentIds'])
        : [],
    ownerId: map['ownerId'] ?? '',
    createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
    lastModifiedAt: map['lastModifiedAt'] != null
        ? DateTime.tryParse(map['lastModifiedAt'])
        : null,
    examScheduleNote: map['examScheduleNote'],
    academicYear: map['academicYear'] ?? '');
}
