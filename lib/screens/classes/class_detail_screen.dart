import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/class_info.dart';
import '../../models/student.dart';
import '../../services/class_provider.dart';
import '../../services/student_provider.dart';
import '../scanning/roster_scan_screen.dart';
import '../students/transfer_dialog.dart';
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
            .map((id) => studentProv.getStudentById(id))
            .whereType<Student>()
            .toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName));

    return Scaffold(
      appBar: AppBar(
        title: Text(currentClass.displayName),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => _editClass(context, currentClass)),
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
                      color: AppTheme.primaryRed,
                      size: 20),
                    const SizedBox(width: 8),
                    Text('Delete Class'),
                  ])),
            ]),
        ]),
      body: Column(
        children: [
          // Class info header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: AppTheme.primaryGreen.withOpacity(0.05),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _InfoChip(
                      icon: Icons.people,
                      label: '${students.length}',
                      sublabel: 'Students'),
                    const SizedBox(width: 12),
                    if (currentClass.grade > 0)
                      _InfoChip(
                        icon: Icons.numbers,
                        label: '${currentClass.grade}',
                        sublabel: 'Grade'),
                    const SizedBox(width: 12),
                    if (currentClass.section.isNotEmpty)
                      _InfoChip(
                        icon: Icons.group,
                        label: currentClass.section,
                        sublabel: 'Section'),
                  ]),

              ])),

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.person_add_outlined,
                    label: 'Add',
                    color: AppTheme.primaryGreen,
                    onTap: () => _addStudentManually(context, currentClass))),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.upload_file,
                    label: 'Import',
                    color: AppTheme.info,
                    onTap: () => _importExcel(context, currentClass))),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.document_scanner_outlined,
                    label: 'Scan',
                    color: AppTheme.primaryYellow,
                    onTap: () => _scanRoster(context, currentClass))),
              ])),

          // Student list
          Expanded(
            child: students.isEmpty
                ? _EmptyClassState()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: students.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final s = students[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primaryGreen.withOpacity(
                            0.1),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: AppTheme.primaryGreen,
                              fontWeight: FontWeight.bold,
                              fontSize: 14))),
                        title: Text(s.fullName),
                        subtitle: Row(
                          children: [
                            if (s.gender.isNotEmpty)
                              Text(
                                s.gender == 'M'
                                    ? ('Male')
                                    : ('Female'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.lightText)),
                            if (s.gender.isNotEmpty && s.studentId.isNotEmpty)
                              Text(
                                ' • ',
                                style: TextStyle(color: AppTheme.lightText)),
                            if (s.studentId.isNotEmpty)
                              Text(
                                '${'ID'}: ${s.studentId}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.lightText)),
                          ]),
                        trailing: PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_vert,
                            size: 20,
                            color: AppTheme.lightText),
                          onSelected: (value) {
                            switch (value) {
                              case 'transfer':
                                _transferStudent(context, s, currentClass);
                              case 'remove':
                                _removeStudent(context, currentClass, s);
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'transfer',
                              child: Row(
                                children: [
                                  Icon(Icons.swap_horiz, size: 18, color: AppTheme.info),
                                  const SizedBox(width: 8),
                                  Text('Transfer'),
                                ])),
                            PopupMenuItem(
                              value: 'remove',
                              child: Row(
                                children: [
                                  Icon(Icons.remove_circle_outline, size: 18, color: AppTheme.primaryRed),
                                  const SizedBox(width: 8),
                                  Text('Remove'),
                                ])),
                          ]));
                    })),
        ]));
  }

  void _addStudentManually(BuildContext context, ClassInfo cls) {
    // Navigate to add student screen with class pre-selected
    Navigator.pushNamed(context, AppRoutes.addStudent, arguments: cls.id);
  }

  void _importExcel(BuildContext context, ClassInfo cls) {
    Navigator.pushNamed(context, AppRoutes.importExcel, arguments: cls.id);
  }

  void _scanRoster(BuildContext context, ClassInfo cls) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RosterScanScreen(classId: cls.id)));
  }

  void _editClass(BuildContext context, ClassInfo cls) async {
    final updated = await CreateClassSheet.show(context, existing: cls);
    if (updated != null && context.mounted) {
      await context.read<ClassProvider>().updateClass(updated);
    }
  }

  void _removeStudent(
    BuildContext context,
    ClassInfo cls,
    Student s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove Student'),
        content: Text(
          "Remove ${s.fullName} from ${cls.displayName}?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryRed),
            child: Text('Remove')),
        ]));
    if (confirmed == true && context.mounted) {
      await context.read<ClassProvider>().removeStudentFromClass(cls.id, s.id);
    }
  }

  void _transferStudent(BuildContext context, Student student, ClassInfo fromClass) async {
    final transferred = await StudentTransferDialog.show(
      context,
      student: student,
      fromClass: fromClass);
    // If transfer was done and undone, the snackbar handles it.
    // If transfer completed, the student list updates via provider.
  }

  void _confirmDelete(BuildContext context, ClassInfo cls) async {
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete Class'),
        content: Text(
          "Delete ${cls.displayName}? Students will not be deleted."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryRed),
            child: Text('Delete')),
        ]));
    if (confirmed == true && context.mounted) {
      await context.read<ClassProvider>().deleteClass(cls.id);
      navigator.pop();
    }
  }
}

// ─── Components ────────────────────────────────────────────────────

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
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryGreen),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
              Text(
                sublabel,
                style: TextStyle(fontSize: 10, color: AppTheme.lightText)),
            ]),
        ]));
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3))),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color)),
          ])));
  }
}

class _EmptyClassState extends StatelessWidget {const _EmptyClassState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No students yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.darkText)),
            const SizedBox(height: 8),
            Text(
              'Import Excel, add manually, or scan a roster',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.lightText)),
          ])));
  }
}
