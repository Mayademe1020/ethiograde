/// A dated note / diary entry for a class (homework, reminders, observations).
class ClassNote {
  final String id;
  final String classId;
  final DateTime date;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ClassNote({
    required this.id,
    required this.classId,
    required this.date,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
  });

  ClassNote copyWith({
    String? classId,
    DateTime? date,
    String? title,
    String? body,
    DateTime? updatedAt,
  }) =>
      ClassNote(
        id: id,
        classId: classId ?? this.classId,
        date: date ?? this.date,
        title: title ?? this.title,
        body: body ?? this.body,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'classId': classId,
        'date': date.toIso8601String(),
        'title': title,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ClassNote.fromMap(Map<String, dynamic> map) => ClassNote(
        id: map['id'] ?? '',
        classId: map['classId'] ?? '',
        date: DateTime.tryParse(map['date'] ?? '') ?? DateTime.now(),
        title: map['title'] ?? '',
        body: map['body'] ?? '',
        createdAt:
            DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
        updatedAt:
            DateTime.tryParse(map['updatedAt'] ?? '') ?? DateTime.now(),
      );
}
