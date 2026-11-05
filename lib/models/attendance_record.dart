/// A single student's attendance status for one day.
class AttendanceEntry {
  final String studentId;
  final String status; // AttendanceStatus.*
  final String? note;

  const AttendanceEntry({
    required this.studentId,
    required this.status,
    this.note,
  });

  Map<String, dynamic> toMap() => {
        'studentId': studentId,
        'status': status,
        if (note != null) 'note': note,
      };

  factory AttendanceEntry.fromMap(Map<String, dynamic> map) => AttendanceEntry(
        studentId: map['studentId'] ?? '',
        status: map['status'] ?? AttendanceStatus.present,
        note: map['note'] as String?,
      );

  AttendanceEntry copyWith({String? status, String? note}) => AttendanceEntry(
        studentId: studentId,
        status: status ?? this.status,
        note: note ?? this.note,
      );
}

/// One day's attendance for a whole class.
class AttendanceRecord {
  final String id;
  final String classId;
  final DateTime date;
  final List<AttendanceEntry> entries;
  final DateTime updatedAt;

  const AttendanceRecord({
    required this.id,
    required this.classId,
    required this.date,
    required this.entries,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'classId': classId,
        'date': date.toIso8601String(),
        'entries': entries.map((e) => e.toMap()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory AttendanceRecord.fromMap(Map<String, dynamic> map) =>
      AttendanceRecord(
        id: map['id'] ?? '',
        classId: map['classId'] ?? '',
        date: DateTime.tryParse(map['date'] ?? '') ?? DateTime.now(),
        entries: map['entries'] != null
            ? List<Map<String, dynamic>>.from(map['entries'] as List)
                .map(AttendanceEntry.fromMap)
                .toList()
            : [],
        updatedAt:
            DateTime.tryParse(map['updatedAt'] ?? '') ?? DateTime.now(),
      );

  /// Lookup a student's entry, or null if not recorded yet.
  AttendanceEntry? entryFor(String studentId) => entries
      .where((e) => e.studentId == studentId)
      .cast<AttendanceEntry?>()
      .firstOrNull;
}

/// Attendance status constants and display metadata.
class AttendanceStatus {
  static const String present = 'present';
  static const String absent = 'absent';
  static const String late = 'late';
  static const String excused = 'excused';

  static const List<String> all = [present, absent, late, excused];

  static String label(String status) {
    switch (status) {
      case present:
        return 'Present';
      case absent:
        return 'Absent';
      case late:
        return 'Late';
      case excused:
        return 'Excused';
      default:
        return status;
    }
  }
}
