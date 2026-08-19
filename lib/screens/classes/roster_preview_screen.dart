import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../services/class_provider.dart';
import '../../services/student_provider.dart';
import '../../services/roster_parser.dart';
import '../../models/student.dart';

/// Shows parsed roster results for teacher review before saving.
///
/// The teacher sees "X names found" with each name editable.
/// This is the most important screen — trust is built here.
class RosterPreviewScreen extends StatefulWidget {
  final List<ParsedStudent> parsedStudents;
  final String classId;

  const RosterPreviewScreen({
    super.key,
    required this.parsedStudents,
    required this.classId,
  });

  @override
  State<RosterPreviewScreen> createState() => _RosterPreviewScreenState();
}

class _RosterPreviewScreenState extends State<RosterPreviewScreen> {
  late List<_EditableStudent> _students;

  @override
  void initState() {
    super.initState();
    _students = widget.parsedStudents
        .map(_EditableStudent.fromParsed)
        .toList();
  }

  int get _validCount =>
      _students.where((s) => s.firstName.trim().isNotEmpty).length;

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Roster'),
        actions: [
          TextButton.icon(
            onPressed: _validCount > 0 ? _saveAll : null,
            icon: const Icon(Icons.check),
            label: Text(
              'Save $_validCount',
              style: const TextStyle(fontWeight: FontWeight.bold))),
        ]),
      body: Column(
        children: [
          // Summary banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: context.primaryGreen.withValues(alpha: 0.08),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: context.primaryGreen,
                  size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$_validCount students found — verify and edit below',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: context.primaryGreen))),
              ])),

          // Student list
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _students.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                return _StudentEditCard(
                  student: _students[index],
                  index: index,
                  onChanged: (updated) {
                    setState(() => _students[index] = updated);
                  },
                  onRemove: () {
                    setState(() => _students.removeAt(index));
                  });
              })),

          // Bottom save button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _validCount > 0 ? _saveAll : null,
                icon: const Icon(Icons.save),
                label: Text(
                  'Save $_validCount Students'),
                style: FilledButton.styleFrom(
                  backgroundColor: context.primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size(double.infinity, 0))))),
        ]));
  }

  void _saveAll() async {
    final studentProv = context.read<StudentProvider>();
    final classProv = context.read<ClassProvider>();

    int saved = 0;
    int failed = 0;
    final studentIds = <String>[];

    for (final es in _students) {
      if (es.firstName.trim().isEmpty) continue;

      final student = es.toStudent(classId: widget.classId);
      final result = await studentProv.addStudent(student);
      if (result.success) {
        saved++;
        studentIds.add(student.id);
      } else {
        failed++;
      }
    }

    // Link all saved students to class
    if (studentIds.isNotEmpty) {
      await classProv.addStudentsToClass(widget.classId, studentIds);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "$saved saved${failed > 0 ? ' ($failed failed)' : ''}"),
          backgroundColor: failed > 0
              ? context.primaryYellow
              : context.primaryGreen));
      Navigator.pop(context);
    }
  }
}

class _EditableStudent {
  String studentId;
  String firstName;
  String lastName;
  String gender;
  String rawLine;

  _EditableStudent({
    this.studentId = '',
    required this.firstName,
    this.lastName = '',
    this.gender = '',
    this.rawLine = '',
  });

  factory _EditableStudent.fromParsed(ParsedStudent p) => _EditableStudent(
    studentId: p.studentId,
    firstName: p.firstName,
    lastName: p.lastName,
    gender: p.gender,
    rawLine: p.rawLine);

  Student toStudent({String classId = ''}) => Student(
    studentId: studentId,
    firstName: firstName,
    lastName: lastName,
    gender: gender,
    classIds: classId.isNotEmpty ? [classId] : []);
}

class _StudentEditCard extends StatelessWidget {
  final _EditableStudent student;
  final int index;
  final ValueChanged<_EditableStudent> onChanged;
  final VoidCallback onRemove;

  const _StudentEditCard({
    required this.student,
    required this.index,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: number + raw OCR + remove button
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: context.primaryGreen.withValues(alpha: 0.1),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: context.primaryGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 12))),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    student.rawLine,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.lightText,
                      fontStyle: FontStyle.italic),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
                IconButton(
                  icon: Icon(Icons.close, size: 18, color: context.primaryRed),
                  onPressed: onRemove,
                  tooltip: 'Remove',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints()),
              ]),
            const SizedBox(height: 8),

            // Editable fields
            Row(
              children: [
                // Student ID
                SizedBox(
                  width: 60,
                  child: TextFormField(
                    initialValue: student.studentId,
                    decoration: const InputDecoration(
                      labelText: 'ID',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8)),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (v) => student.studentId = v.trim())),
                const SizedBox(width: 8),
                // First name
                Expanded(
                  child: TextFormField(
                    initialValue: student.firstName,
                    decoration: const InputDecoration(
                      labelText: 'First',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8)),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (v) => student.firstName = v.trim())),
                const SizedBox(width: 8),
                // Last name
                Expanded(
                  child: TextFormField(
                    initialValue: student.lastName,
                    decoration: const InputDecoration(
                      labelText: 'Last',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8)),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (v) => student.lastName = v.trim())),
              ]),
            const SizedBox(height: 8),

            // Gender toggle
            Row(
              children: [
                Text(
                  'Gender:',
                  style: TextStyle(fontSize: 12, color: context.lightText)),
                const SizedBox(width: 8),
                _MiniGenderChip(
                  label: 'M',
                  selected: student.gender == 'M',
                  onTap: () {
                    student.gender = 'M';
                    onChanged(student);
                  }),
                const SizedBox(width: 4),
                _MiniGenderChip(
                  label: 'F',
                  selected: student.gender == 'F',
                  onTap: () {
                    student.gender = 'F';
                    onChanged(student);
                  }),
              ]),
          ])));
  }
}

class _MiniGenderChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MiniGenderChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? context.primaryGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? context.primaryGreen : Colors.grey.shade300)),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? Colors.white : context.lightText))));
  }
}
