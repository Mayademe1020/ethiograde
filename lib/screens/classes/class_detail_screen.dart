import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/responsive.dart';
import '../../config/routes.dart';
import '../../models/class_info.dart';
import '../../models/student.dart';
import '../../services/class_provider.dart';
import '../../services/student_provider.dart';
import '../scanning/roster_scan_screen.dart';
import '../students/transfer_dialog.dart';
import '../../widgets/ui_components.dart';
import 'create_class_sheet.dart';

/// The hub screen for a single class.
/// Shows student list, quick stats, and action buttons (add/import/scan).
class ClassDetailScreen extends StatelessWidget {
  final ClassInfo classInfo;

  const ClassDetailScreen({super.key, required this.classInfo});

  @override
  Widget build(BuildContext context) {
    final classProv = context.watch<ClassProvider>();
    final studentProv = context.watch<StudentProvider>();

    // Get fresh class data (in case it was updated)
    final currentClass = classProv.getClassById(classInfo.id) ?? classInfo;
    final students =
        currentClass.studentIds
            .map(studentProv.getStudentById)
            .whereType<Student>()
            .toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName));
    final rosterHealth = _RosterHealth.fromStudents(students);

    return Scaffold(
      appBar: AppBar(
        title: Text(currentClass.displayName),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => _editClass(context, currentClass),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _confirmDelete(context, currentClass);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      color: context.primaryRed,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text('Delete Class'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Class info header
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(ResponsiveLayout.horizontalPadding(context)),
              color: context.primaryGreen.withValues(alpha: 0.05),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _InfoChip(
                        icon: Icons.people,
                        label: '${students.length}',
                        sublabel: 'Students',
                      ),
                      const SizedBox(width: 12),
                      if (currentClass.grade > 0)
                        _InfoChip(
                          icon: Icons.numbers,
                          label: '${currentClass.grade}',
                          sublabel: 'Grade',
                        ),
                      const SizedBox(width: 12),
                      if (currentClass.section.isNotEmpty)
                        _InfoChip(
                          icon: Icons.group,
                          label: currentClass.section,
                          sublabel: 'Section',
                        ),
                    ],
                  ),
                ],
              ),
            ),

            _ClassSituationPanel(
              classInfo: currentClass,
              students: students,
              rosterHealth: rosterHealth,
              onAddStudent: () => _addStudentManually(context, currentClass),
              onImport: () => _importExcel(context, currentClass),
              onScanRoster: () => _scanRoster(context, currentClass),
            ),

            // Teacher tools — compact row (attendance & class notes).
            // Add / Import / Scan live in the situation panel above so the
            // student list stays the visual focus.
            Padding(
              padding: EdgeInsets.fromLTRB(
                ResponsiveLayout.horizontalPadding(context),
                4,
                ResponsiveLayout.horizontalPadding(context),
                8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pushNamed(
                        context,
                        AppRoutes.classAttendance,
                        arguments: currentClass,
                      ),
                      icon: const Icon(Icons.fact_check_outlined, size: 18),
                      label: const Text('Attendance'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pushNamed(
                        context,
                        AppRoutes.classNotes,
                        arguments: currentClass,
                      ),
                      icon: const Icon(Icons.note_add_outlined, size: 18),
                      label: const Text('Notes'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Student list
            Expanded(
              child: students.isEmpty
                  ? const _EmptyClassState()
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount:
                          students.length + (rosterHealth.hasIssues ? 1 : 0),
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        if (rosterHealth.hasIssues && index == 0) {
                          return _RosterFixPanel(
                            health: rosterHealth,
                            onImport: () => _importExcel(context, currentClass),
                            onAddStudent: () =>
                                _addStudentManually(context, currentClass),
                          );
                        }
                        final studentIndex =
                            index - (rosterHealth.hasIssues ? 1 : 0);
                        final s = students[studentIndex];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: context.primaryGreen.withValues(
                              alpha: 0.1,
                            ),
                            child: Text(
                              '${studentIndex + 1}',
                              style: TextStyle(
                                color: context.primaryGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          title: Text(s.fullName),
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.studentDetail,
                            arguments: s,
                          ),
                          subtitle: Row(
                            children: [
                              if (s.gender.isNotEmpty)
                                Text(
                                  s.gender == 'M' ? ('Male') : ('Female'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.lightText,
                                  ),
                                ),
                              if (s.gender.isNotEmpty && s.studentId.isNotEmpty)
                                Text(
                                  ' • ',
                                  style: TextStyle(color: context.lightText),
                                ),
                              if (s.studentId.isNotEmpty)
                                Text(
                                  '${'ID'}: ${s.studentId}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.lightText,
                                  ),
                                ),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert,
                              size: 20,
                              color: context.lightText,
                            ),
                            onSelected: (value) {
                              switch (value) {
                                case 'edit':
                                  _editStudent(context, s);
                                case 'transfer':
                                  _transferStudent(context, s, currentClass);
                                case 'remove':
                                  _removeStudent(context, currentClass, s);
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                      color: AppTheme.info,
                                    ),
                                    SizedBox(width: 8),
                                    Text('Edit'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'transfer',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.swap_horiz,
                                      size: 18,
                                      color: AppTheme.info,
                                    ),
                                    SizedBox(width: 8),
                                    Text('Transfer'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'remove',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.remove_circle_outline,
                                      size: 18,
                                      color: context.primaryRed,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text('Remove'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _addStudentManually(BuildContext context, ClassInfo cls) {
    // Navigate to add student screen with class pre-selected
    Navigator.pushNamed(context, AppRoutes.addStudent, arguments: cls.id);
  }

  void _importExcel(BuildContext context, ClassInfo cls) {
    Navigator.pushNamed(context, AppRoutes.importExcel, arguments: cls.id);
  }

  void _editStudent(BuildContext context, Student student) {
    Navigator.pushNamed(context, AppRoutes.addStudent, arguments: student);
  }

  void _scanRoster(BuildContext context, ClassInfo cls) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RosterScanScreen(classId: cls.id)),
    );
  }

  void _editClass(BuildContext context, ClassInfo cls) async {
    final updated = await CreateClassSheet.show(context, existing: cls);
    if (updated != null && context.mounted) {
      await context.read<ClassProvider>().updateClass(updated);
    }
  }

  void _removeStudent(BuildContext context, ClassInfo cls, Student s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove Student'),
        content: Text('Remove ${s.fullName} from ${cls.displayName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.primaryRed,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<ClassProvider>().removeStudentFromClass(cls.id, s.id);
    }
  }

  void _transferStudent(
    BuildContext context,
    Student student,
    ClassInfo fromClass,
  ) async {
    await StudentTransferDialog.show(
      context,
      student: student,
      fromClass: fromClass,
    );
    // If transfer was done and undone, the snackbar handles it.
    // If transfer completed, the student list updates via provider.
  }

  void _confirmDelete(BuildContext context, ClassInfo cls) async {
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete Class'),
        content: Text(
          'Delete ${cls.displayName}? Students will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.primaryRed,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<ClassProvider>().deleteClass(cls.id);
      navigator.pop();
    }
  }
}

// ─── Components ────────────────────────────────────────────────────

class _RosterHealth {
  const _RosterHealth({
    required this.missingIds,
    required this.duplicateIds,
    required this.duplicateNames,
  });

  final List<Student> missingIds;
  final List<String> duplicateIds;
  final List<String> duplicateNames;

  bool get hasIssues =>
      missingIds.isNotEmpty ||
      duplicateIds.isNotEmpty ||
      duplicateNames.isNotEmpty;

  int get issueCount =>
      missingIds.length + duplicateIds.length + duplicateNames.length;

  factory _RosterHealth.fromStudents(List<Student> students) {
    final missingIds = students
        .where((student) => student.studentId.trim().isEmpty)
        .toList(growable: false);
    final idCounts = <String, int>{};
    final nameCounts = <String, int>{};
    for (final student in students) {
      final id = student.studentId.trim().toLowerCase();
      if (id.isNotEmpty) idCounts[id] = (idCounts[id] ?? 0) + 1;
      final name = student.fullName.trim().toLowerCase();
      if (name.isNotEmpty) nameCounts[name] = (nameCounts[name] ?? 0) + 1;
    }

    return _RosterHealth(
      missingIds: missingIds,
      duplicateIds: idCounts.entries
          .where((entry) => entry.value > 1)
          .map((entry) => entry.key)
          .toList(growable: false),
      duplicateNames: nameCounts.entries
          .where((entry) => entry.value > 1)
          .map((entry) => entry.key)
          .toList(growable: false),
    );
  }
}

class _ClassSituationPanel extends StatelessWidget {
  const _ClassSituationPanel({
    required this.classInfo,
    required this.students,
    required this.rosterHealth,
    required this.onAddStudent,
    required this.onImport,
    required this.onScanRoster,
  });

  final ClassInfo classInfo;
  final List<Student> students;
  final _RosterHealth rosterHealth;
  final VoidCallback onAddStudent;
  final VoidCallback onImport;
  final VoidCallback onScanRoster;

  @override
  Widget build(BuildContext context) {
    final title = students.isEmpty
        ? 'Build this class list'
        : rosterHealth.hasIssues
        ? 'Fix roster before grading'
        : 'Roster ready for grading';
    final subtitle = students.isEmpty
        ? 'Import a list, add students, or scan a roster.'
        : rosterHealth.hasIssues
        ? '${rosterHealth.issueCount} roster issue(s) could affect paper matching.'
        : '${students.length} students can be matched during scanning.';
    final color = students.isEmpty
        ? AppTheme.info
        : rosterHealth.hasIssues
        ? context.warning
        : context.primaryGreen;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: context.lightText, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _RosterChip(
                icon: Icons.groups_outlined,
                label: '${students.length} students',
                color: AppTheme.info,
              ),
              _RosterChip(
                icon: rosterHealth.missingIds.isEmpty
                    ? Icons.badge_outlined
                    : Icons.warning_amber_outlined,
                label: rosterHealth.missingIds.isEmpty
                    ? 'IDs ready'
                    : '${rosterHealth.missingIds.length} missing IDs',
                color: rosterHealth.missingIds.isEmpty
                    ? context.primaryGreen
                    : context.warning,
              ),
              _RosterChip(
                icon:
                    rosterHealth.duplicateIds.isEmpty &&
                        rosterHealth.duplicateNames.isEmpty
                    ? Icons.verified_outlined
                    : Icons.content_copy_outlined,
                label:
                    rosterHealth.duplicateIds.isEmpty &&
                        rosterHealth.duplicateNames.isEmpty
                    ? 'No duplicates'
                    : 'Duplicates found',
                color:
                    rosterHealth.duplicateIds.isEmpty &&
                        rosterHealth.duplicateNames.isEmpty
                    ? context.primaryGreen
                    : context.warning,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (students.isEmpty || rosterHealth.hasIssues)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: students.isEmpty ? onImport : onAddStudent,
                    icon: Icon(
                      students.isEmpty
                          ? Icons.upload_file
                          : Icons.person_add_outlined,
                    ),
                    label: Text(
                      students.isEmpty ? 'Import list' : 'Add student',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onScanRoster,
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('Scan roster'),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAddStudent,
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Add student'),
              ),
            ),
        ],
      ),
    );
  }
}

class _RosterFixPanel extends StatelessWidget {
  const _RosterFixPanel({
    required this.health,
    required this.onImport,
    required this.onAddStudent,
  });

  final _RosterHealth health;
  final VoidCallback onImport;
  final VoidCallback onAddStudent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.warning.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.warning.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rule_folder_outlined, color: context.warning),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Roster fixes',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (health.missingIds.isNotEmpty)
            Text(
              '${health.missingIds.length} student(s) need an ID for reliable matching.',
              style: TextStyle(color: context.lightText, fontSize: 12),
            ),
          if (health.duplicateIds.isNotEmpty)
            Text(
              '${health.duplicateIds.length} duplicate ID value(s) found.',
              style: TextStyle(color: context.lightText, fontSize: 12),
            ),
          if (health.duplicateNames.isNotEmpty)
            Text(
              '${health.duplicateNames.length} duplicate name value(s) found.',
              style: TextStyle(color: context.lightText, fontSize: 12),
            ),
          const SizedBox(height: 6),
          Text(
            'Use each student menu to edit, transfer, or remove.',
            style: TextStyle(color: context.lightText, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Import fixes'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton.icon(
                  onPressed: onAddStudent,
                  icon: const Icon(Icons.person_add_outlined, size: 18),
                  label: const Text('Add student'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RosterChip extends StatelessWidget {
  const _RosterChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.outlineLight.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: context.primaryGreen),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                sublabel,
                style: TextStyle(fontSize: 10, color: context.lightText),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyClassState extends StatelessWidget {
  const _EmptyClassState();

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.people_outline,
      title: 'No students yet',
      message: 'Import Excel, add manually, or scan a roster',
    );
  }
}
