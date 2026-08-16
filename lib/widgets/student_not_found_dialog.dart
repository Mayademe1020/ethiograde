import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/student.dart';
import '../../services/class_provider.dart';
import '../../services/student_provider.dart';
import '../../services/student_matcher.dart';

/// Shows a dialog when a scanned name doesn't match any student in the class.
/// Offers: "Add now?" (2-tap: confirm → auto-adds with pre-filled name).
class StudentNotFoundDialog extends StatefulWidget {
  final String scannedName;
  final String classId;
  final String? studentId; // Roll number if detected
  final String? gender; // 'M' or 'F' if detected

  const StudentNotFoundDialog({
    super.key,
    required this.scannedName,
    required this.classId,
    this.studentId,
    this.gender,
  });

  /// Show the dialog. Returns the created Student, or null if skipped.
  static Future<Student?> show({
    required BuildContext context,
    required String scannedName,
    required String classId,
    String? studentId,
    String? gender,
  }) {
    return showDialog<Student>(
      context: context,
      builder: (_) => StudentNotFoundDialog(
        scannedName: scannedName,
        classId: classId,
        studentId: studentId,
        gender: gender));
  }

  @override
  State<StudentNotFoundDialog> createState() => _StudentNotFoundDialogState();
}

class _StudentNotFoundDialogState extends State<StudentNotFoundDialog> {
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _idCtrl;
  String _gender = '';
  bool _saving = false;
  List<String> _similarNames = [];

  @override
  void initState() {
    super.initState();
    // Pre-fill from OCR scan
    final parts = widget.scannedName.trim().split(RegExp(r'\s+'));
    _firstNameCtrl = TextEditingController(
      text: parts.isNotEmpty ? parts[0] : '');
    _lastNameCtrl = TextEditingController(
      text: parts.length > 1 ? parts.sublist(1).join(' ') : '');
    _idCtrl = TextEditingController(text: widget.studentId ?? '');
    _gender = widget.gender ?? '';
    _findSimilar();
  }

  void _findSimilar() {
    final classProv = context.read<ClassProvider>();
    final studentProv = context.read<StudentProvider>();
    final cls = classProv.getClassById(widget.classId);
    if (cls == null) return;

    final classStudents = cls.studentIds
        .map(studentProv.getStudentById)
        .whereType<Student>()
        .toList();

    _similarNames = classStudents
        .where(
          (s) => StudentMatcher.similarity(widget.scannedName, s.fullName) > 0.5)
        .map((s) => '${s.fullName} (${s.studentId})')
        .toList();
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.person_search, color: AppTheme.primaryYellow, size: 24),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Student Not Found',
              style: TextStyle(fontSize: 18))),
        ]),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // What OCR read
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(
                    Icons.document_scanner,
                    size: 16,
                    color: AppTheme.lightText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '"${widget.scannedName}"',
                      style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        color: AppTheme.lightText))),
                ])),

            // Similar names warning
            if (_similarNames.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryYellow.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.primaryYellow.withValues(alpha: 0.3))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Similar names in class:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryYellow)),
                    ..._similarNames.map(
                      (n) => Text('• $n', style: const TextStyle(fontSize: 12))),
                  ])),
            ],

            const SizedBox(height: 12),
            const Text(
              'Add as new student?',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.darkText)),
            const SizedBox(height: 12),

            // Editable fields
            TextFormField(
              controller: _firstNameCtrl,
              decoration: const InputDecoration(
                labelText: 'First Name',
                isDense: true)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _lastNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Last Name',
                isDense: true)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _idCtrl,
              decoration: const InputDecoration(
                labelText: 'Student ID',
                isDense: true)),
            const SizedBox(height: 8),

            // Gender
            Row(
              children: [
                const Text(
                  'Gender:',
                  style: TextStyle(fontSize: 13, color: AppTheme.lightText)),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('M'),
                  selected: _gender == 'M',
                  onSelected: (_) => setState(() => _gender = 'M'),
                  selectedColor: AppTheme.primaryGreen,
                  labelStyle: TextStyle(
                    color: _gender == 'M' ? Colors.white : null)),
                const SizedBox(width: 4),
                ChoiceChip(
                  label: const Text('F'),
                  selected: _gender == 'F',
                  onSelected: (_) => setState(() => _gender = 'F'),
                  selectedColor: AppTheme.primaryGreen,
                  labelStyle: TextStyle(
                    color: _gender == 'F' ? Colors.white : null)),
              ]),
          ])),
      actions: [
        // Skip — don't add
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Skip')),
        // Add student
        FilledButton.icon(
          onPressed: _saving ? null : _addStudent,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.person_add, size: 18),
          label: const Text('Add'),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryGreen)),
      ]);
  }

  void _addStudent() async {
    final firstName = _firstNameCtrl.text.trim();
    if (firstName.isEmpty) return;

    setState(() => _saving = true);

    final studentProv = context.read<StudentProvider>();
    final classProv = context.read<ClassProvider>();

    final student = Student(
      studentId: _idCtrl.text.trim(),
      firstName: firstName,
      lastName: _lastNameCtrl.text.trim(),
      gender: _gender,
      classIds: [widget.classId]);

    final result = await studentProv.addStudent(student);
    if (result.success) {
      await classProv.addStudentToClass(widget.classId, student.id);
      if (mounted) Navigator.pop(context, student);
    } else {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Error'),
            backgroundColor: AppTheme.primaryRed));
      }
    }
  }
}
