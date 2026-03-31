import 'package:uuid/uuid.dart';

/// A school teacher record, used in School Admin mode.
///
/// Persisted in the encrypted `teachers` Hive box.
class Teacher {
  final String id;
  final String name;
  final String nameAmharic;
  final String phone;
  final String email;
  final String subject; // e.g. 'Math', 'English'
  final bool isActive;
  final DateTime createdAt;
  final Map<String, dynamic> metadata;

  Teacher({
    String? id,
    required this.name,
    this.nameAmharic = '',
    this.phone = '',
    this.email = '',
    this.subject = '',
    this.isActive = true,
    DateTime? createdAt,
    this.metadata = const {},
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  String getDisplayName(String locale) {
    if (locale == 'am' && nameAmharic.trim().isNotEmpty) {
      return nameAmharic;
    }
    return name;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'nameAmharic': nameAmharic,
        'phone': phone,
        'email': email,
        'subject': subject,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
        'metadata': metadata,
      };

  factory Teacher.fromMap(Map<String, dynamic> map) => Teacher(
        id: map['id'] ?? '',
        name: map['name'] ?? '',
        nameAmharic: map['nameAmharic'] ?? '',
        phone: map['phone'] ?? '',
        email: map['email'] ?? '',
        subject: map['subject'] ?? '',
        isActive: map['isActive'] ?? true,
        createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
        metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      );

  Teacher copyWith({
    String? name,
    String? nameAmharic,
    String? phone,
    String? email,
    String? subject,
    bool? isActive,
  }) =>
      Teacher(
        id: id,
        name: name ?? this.name,
        nameAmharic: nameAmharic ?? this.nameAmharic,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        subject: subject ?? this.subject,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        metadata: metadata,
      );
}
