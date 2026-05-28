import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'student.g.dart';

@HiveType(typeId: 0)
class Student {
  @HiveField(0)
  final String id; // UUID (internal)
  @HiveField(1)
  final String studentId; // Roll number (visible, prominent, not optional)
  @HiveField(2)
  final String firstName;
  @HiveField(3)
  final String lastName;  @HiveField(6)
  final String gender; // 'M' or 'F' — required
  @HiveField(7)
  final List<String>
  classIds; // Many-to-many: student can be in multiple classes
  @HiveField(8)
  final String className; // Legacy — kept for backward compat
  @HiveField(9)
  final String section;
  @HiveField(10)
  final int grade;
  @HiveField(11)
  final String? photoPath;
  @HiveField(12)
  final String? parentPhone;
  @HiveField(13)
  final DateTime createdAt;
  @HiveField(14)
  final String? createdBy; // Teacher ID
  @HiveField(15)
  final DateTime? lastModifiedAt;
  @HiveField(16)
  final String? lastModifiedBy;
  @HiveField(17)
  final Map<String, dynamic> metadata;

  Student({
    String? id,
    required this.studentId,
    required this.firstName,
    required this.lastName,    this.gender = '',
    List<String>? classIds,
    this.className = '',
    this.section = '',
    this.grade = 1,
    this.photoPath,
    this.parentPhone,
    DateTime? createdAt,
    this.createdBy,
    this.lastModifiedAt,
    this.lastModifiedBy,
    this.metadata = const {},
  }) : id = id ?? const Uuid().v4(),
       classIds = classIds ?? [],
       createdAt = createdAt ?? DateTime.now();

  String get fullName => '$firstName $lastName';
  bool get hasGender => gender == 'M' || gender == 'F';

  Student copyWith({
    String? id,
    String? studentId,
    String? firstName,
    String? lastName,    String? gender,
    List<String>? classIds,
    String? className,
    String? section,
    int? grade,
    String? photoPath,
    String? parentPhone,
    String? createdBy,
    DateTime? lastModifiedAt,
    String? lastModifiedBy,
    Map<String, dynamic>? metadata,
  }) => Student(
    id: id ?? this.id,
    studentId: studentId ?? this.studentId,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    gender: gender ?? this.gender,
    classIds: classIds ?? this.classIds,
    className: className ?? this.className,
    section: section ?? this.section,
    grade: grade ?? this.grade,
    photoPath: photoPath ?? this.photoPath,
    parentPhone: parentPhone ?? this.parentPhone,
    createdAt: createdAt,
    createdBy: createdBy ?? this.createdBy,
    lastModifiedAt: lastModifiedAt ?? DateTime.now(),
    lastModifiedBy: lastModifiedBy ?? this.lastModifiedBy,
    metadata: metadata ?? this.metadata);

  Map<String, dynamic> toMap() => {
    'id': id,
    'studentId': studentId,
    'firstName': firstName,
    'lastName': lastName,    'gender': gender,
    'classIds': classIds,
    'className': className,
    'section': section,
    'grade': grade,
    'photoPath': photoPath,
    'parentPhone': parentPhone,
    'createdAt': createdAt.toIso8601String(),
    'createdBy': createdBy,
    'lastModifiedAt': lastModifiedAt?.toIso8601String(),
    'lastModifiedBy': lastModifiedBy,
    'metadata': metadata,
  };

  factory Student.fromMap(Map<String, dynamic> map) => Student(
    id: map['id'] ?? '',
    studentId: map['studentId'] ?? '',
    firstName: map['firstName'] ?? '',
    lastName: map['lastName'] ?? '',
    gender: map['gender'] ?? '',
    classIds: map['classIds'] != null ? List<String>.from(map['classIds']) : [],
    className: map['className'] ?? '',
    section: map['section'] ?? '',
    grade: map['grade'] ?? 1,
    photoPath: map['photoPath'],
    parentPhone: map['parentPhone'],
    createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
    createdBy: map['createdBy'],
    lastModifiedAt: map['lastModifiedAt'] != null
        ? DateTime.tryParse(map['lastModifiedAt'])
        : null,
    lastModifiedBy: map['lastModifiedBy'],
    metadata: Map<String, dynamic>.from(map['metadata'] ?? {}));
}
