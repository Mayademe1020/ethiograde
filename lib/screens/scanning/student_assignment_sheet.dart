import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/student.dart';
import '../../models/scan_result.dart';
import '../../services/class_provider.dart';
import '../../services/student_provider.dart';

/// Shows the student picker bottom sheet for assigning a student to a scan result.
/// Returns the selected Student, or null if dismissed.
Future<Student?> showStudentAssignmentSheet({
  required BuildContext context,
  required String classId,
  required List<ScanResult> results,
  required int resultIndex,
}) async {
  final classProv = context.read<ClassProvider>();
  final studentProv = context.read<StudentProvider>();
  final cls = classProv.getClassById(classId);
  if (cls == null) return null;

  final students =
      cls.studentIds
          .map(studentProv.getStudentById)
          .whereType<Student>()
          .toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName));

  if (students.isEmpty) return null;

  return showModalBottomSheet<Student>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Select Student',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: students.length,
              itemBuilder: (_, i) {
                final s = students[i];
                final alreadyAssigned = results.any(
                  (r) =>
                      r.studentId == s.id &&
                      results.indexOf(r) != resultIndex,
                );
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: alreadyAssigned
                        ? Colors.orange.withValues(alpha: 0.2)
                        : AppTheme.primaryGreen.withValues(alpha: 0.1),
                    child: Text(
                      s.studentId.isNotEmpty ? s.studentId : '${i + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        color: alreadyAssigned
                            ? Colors.orange
                            : AppTheme.primaryGreen,
                      ),
                    ),
                  ),
                  title: Text(s.fullName),
                  subtitle: alreadyAssigned
                      ? const Text(
                          'Already assigned',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 11,
                          ),
                        )
                      : null,
                  trailing: alreadyAssigned
                      ? const Icon(
                          Icons.warning_amber,
                          color: Colors.orange,
                          size: 18,
                        )
                      : null,
                  onTap: () => Navigator.pop(ctx, s),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
