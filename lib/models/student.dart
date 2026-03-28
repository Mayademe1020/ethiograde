class Student {
  final String id;
  final String firstName;
  final String lastName;
  final String firstNameAmharic;
  final String lastNameAmharic;
  final String studentId; // School-assigned ID
  final String className;
  final String section;
  final int grade; // 1-12 or university year
  final String? photoPath;
  final String? parentPhone;
  final DateTime createdAt;
  final Map<String, dynamic> metadata;

  Student({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.firstNameAmharic = '',
    this.lastNameAmharic = '',
    this.studentId = '',
    this.className = '',
    this.section = '',
    this.grade = 1,
    this.photoPath,
    this.parentPhone,
    DateTime? createdAt,
    this.metadata = const {},
  }) : createdAt = createdAt ?? DateTime.now();

  String get fullName => '$firstName $lastName';
  String get fullNameAmharic => '$firstNameAmharic $lastNameAmharic';

  String getDisplayName(String locale) {
    if (locale == 'am' && fullNameAmharic.trim().isNotEmpty) {
      return fullNameAmharic;
    }
    return fullName;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'firstName': firstName,
    'lastName': lastName,
    'firstNameAmharic': firstNameAmharic,
    'lastNameAmharic': lastNameAmharic,
    'studentId': studentId,
    'className': className,
    'section': section,
    'grade': grade,
    'photoPath': photoPath,
    'parentPhone': parentPhone,
    'createdAt': createdAt.toIso8601String(),
    'metadata': metadata,
  };

  factory Student.fromMap(Map<String, dynamic> map) => Student(
    id: map['id'] ?? '',
    firstName: map['firstName'] ?? '',
    lastName: map['lastName'] ?? '',
    firstNameAmharic: map['firstNameAmharic'] ?? '',
    lastNameAmharic: map['lastNameAmharic'] ?? '',
    studentId: map['studentId'] ?? '',
    className: map['className'] ?? '',
    section: map['section'] ?? '',
    grade: map['grade'] ?? 1,
    photoPath: map['photoPath'],
    parentPhone: map['parentPhone'],
    createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
    metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
  );

  Student copyWith({
    String? firstName,
    String? lastName,
    String? firstNameAmharic,
    String? lastNameAmharic,
    String? studentId,
    String? className,
    String? section,
    int? grade,
    String? photoPath,
    String? parentPhone,
  }) => Student(
    id: id,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    firstNameAmharic: firstNameAmharic ?? this.firstNameAmharic,
    lastNameAmharic: lastNameAmharic ?? this.lastNameAmharic,
    studentId: studentId ?? this.studentId,
    className: className ?? this.className,
    section: section ?? this.section,
    grade: grade ?? this.grade,
    photoPath: photoPath ?? this.photoPath,
    parentPhone: parentPhone ?? this.parentPhone,
    createdAt: createdAt,
    metadata: metadata,
  );
}
