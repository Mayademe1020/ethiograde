import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'audit_entry.g.dart';

/// Single entry in the grade audit trail.
///
/// Records every change to a ScanResult: who changed it, when,
/// what was old, what is new. Immutable once created.
///
/// This is the answer to "parent disputes a grade":
/// teacher can show exactly who entered/modified the grade and when.
@HiveType(typeId: 13)
class AuditEntry {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String scanResultId;
  @HiveField(2)
  final String action; // 'created', 'score_override', 'grade_change', 'reassigned', 'comment_added'
  @HiveField(3)
  final String teacherId;
  @HiveField(4)
  final String teacherName;
  @HiveField(5)
  final DateTime timestamp;
  @HiveField(6)
  final Map<String, dynamic> previousValues;
  @HiveField(7)
  final Map<String, dynamic> newValues;
  @HiveField(8)
  final String? reason; // Optional: why the change was made

  AuditEntry({
    String? id,
    required this.scanResultId,
    required this.action,
    required this.teacherId,
    required this.teacherName,
    DateTime? timestamp,
    this.previousValues = const {},
    this.newValues = const {},
    this.reason,
  }) : id = id ?? const Uuid().v4(),
       timestamp = timestamp ?? DateTime.now();

  /// Human-readable summary of what changed.
  String get changeDescription {
    switch (action) {
      case 'created':
        return 'Grade created: ${newValues['grade'] ?? ''} (${newValues['percentage']?.toStringAsFixed(1) ?? ''}%)';
      case 'score_override':
        final oldScore = previousValues['totalScore'];
        final newScore = newValues['totalScore'];
        return 'Score changed: $oldScore → $newScore';
      case 'grade_change':
        return 'Grade changed: ${previousValues['grade']} → ${newValues['grade']}';
      case 'reassigned':
        return 'Reassigned: ${previousValues['studentName']} → ${newValues['studentName']}';
      case 'comment_added':
        return 'Comment added';
      default:
        return action;
    }
  }

  String get description => changeDescription;

  Map<String, dynamic> toMap() => {
    'id': id,
    'scanResultId': scanResultId,
    'action': action,
    'teacherId': teacherId,
    'teacherName': teacherName,
    'timestamp': timestamp.toIso8601String(),
    'previousValues': previousValues,
    'newValues': newValues,
    'reason': reason,
  };

  factory AuditEntry.fromMap(Map<String, dynamic> map) => AuditEntry(
    id: map['id'],
    scanResultId: map['scanResultId'] ?? '',
    action: map['action'] ?? '',
    teacherId: map['teacherId'] ?? '',
    teacherName: map['teacherName'] ?? '',
    timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
    previousValues: Map<String, dynamic>.from(map['previousValues'] ?? {}),
    newValues: Map<String, dynamic>.from(map['newValues'] ?? {}),
    reason: map['reason']);
}
