import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/student.dart';
import '../../services/class_provider.dart';
import '../../services/student_provider.dart';
import '../../services/teacher_provider.dart';

/// Add or edit a single student. Optionally pre-select a class.
///
/// Pass [existingStudent] to edit. Pass a [preselectedClassId] to auto-link.
class AddStudentScreen extends StatefulWidget {
  final String? preselectedClassId;
  final Student? existingStudent;

  const AddStudentScreen({
    super.key,
    this.preselectedClassId,
    this.existingStudent,
  });

  @override
  State<AddStudentScreen> createState() => _AddStudentScreenState();
}

class _AddStudentScreenState extends State<AddStudentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _studentIdCtrl = TextEditingController();
  final _parentPhoneCtrl = TextEditingController();
  String _gender = '';
  String _selectedClassId = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingStudent;
    if (existing != null) {
      _fullNameCtrl.text = existing.fullName.trim();
      _studentIdCtrl.text = existing.studentId;
      _parentPhoneCtrl.text = existing.parentPhone ?? '';
      _gender = existing.gender;
      _selectedClassId = existing.classIds.isNotEmpty
          ? existing.classIds.first
          : (widget.preselectedClassId ?? '');
    } else {
      _selectedClassId = widget.preselectedClassId ?? '';
    }
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _studentIdCtrl.dispose();
    _parentPhoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final classProv = context.watch<ClassProvider>();
    if (_selectedClassId.isEmpty && classProv.classes.length == 1) {
      _selectedClassId = classProv.classes.single.id;
    }
    // Validate _selectedClassId still exists in available classes
    if (_selectedClassId.isNotEmpty &&
        !classProv.classes.any((c) => c.id == _selectedClassId)) {
      _selectedClassId = '';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingStudent != null ? ('Edit Student') : ('Add Student'),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Only name and roll number are required.',
              style: TextStyle(color: AppTheme.lightText),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _fullNameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Full Name *',
                hintText: 'e.g. Abebe Kebede',
                prefixIcon: const Icon(Icons.person_outline),
              ),
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return 'Full name is required';
                if (value.length > 120) return 'Name is too long';
                return null;
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _studentIdCtrl,
              decoration: InputDecoration(
                labelText: 'Student ID / Roll No. *',
                hintText: 'e.g. 001',
                prefixIcon: const Icon(Icons.badge_outlined),
              ),
              keyboardType: TextInputType.text,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Student ID is required';
                }
                if (v.trim().length > 20) {
                  return 'Max 20 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            Text(
              'Gender (optional)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.lightText,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _GenderChip(
                    label: 'Male',
                    value: 'M',
                    selected: _gender == 'M',
                    onTap: () => setState(() => _gender = 'M'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _GenderChip(
                    label: 'Female',
                    value: 'F',
                    selected: _gender == 'F',
                    onTap: () => setState(() => _gender = 'F'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _GenderChip(
                    label: 'Skip',
                    value: '',
                    selected: _gender.isEmpty,
                    onTap: () => setState(() => _gender = ''),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Class ───────────────────────────────────────────────
            if (classProv.classes.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                value: _selectedClassId.isEmpty ? null : _selectedClassId,
                decoration: InputDecoration(
                  labelText: 'Class',
                  helperText: classProv.classes.length == 1
                      ? 'Selected automatically'
                      : null,
                  prefixIcon: const Icon(Icons.class_outlined),
                ),
                items: classProv.classes
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(c.displayName),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedClassId = v ?? ''),
              ),
              const SizedBox(height: 16),
            ],

            // ── Parent phone (optional) ─────────────────────────────
            TextFormField(
              controller: _parentPhoneCtrl,
              decoration: InputDecoration(
                labelText: 'Parent Phone',
                hintText: '+251...',
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 32),

            // ── Save button ─────────────────────────────────────────
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(
                widget.existingStudent != null
                    ? ('Update Student')
                    : ('Save Student'),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() async {
    // Validate form
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final teacherId = context.read<TeacherProvider>().activeTeacher?.id ?? '';
    final classProv = context.read<ClassProvider>();
    final studentProv = context.read<StudentProvider>();

    // Build student
    final classIds = <String>[];
    if (_selectedClassId.isNotEmpty) classIds.add(_selectedClassId);

    final existing = widget.existingStudent;
    final nameParts = _splitFullName(_fullNameCtrl.text.trim());
    final student = Student(
      id: existing?.id,
      studentId: _studentIdCtrl.text.trim(),
      firstName: nameParts.$1,
      lastName: nameParts.$2,
      gender: _gender,
      classIds: classIds.isNotEmpty ? classIds : (existing?.classIds ?? []),
      className: _selectedClassId.isNotEmpty
          ? (classProv.getClassById(_selectedClassId)?.displayName ?? '')
          : (existing?.className ?? ''),
      parentPhone: _parentPhoneCtrl.text.trim().isEmpty
          ? null
          : _parentPhoneCtrl.text.trim(),
      createdBy: existing?.createdBy ?? teacherId,
      createdAt: existing?.createdAt,
    );

    // Save or update student
    final result = existing != null
        ? await studentProv.updateStudent(student)
        : await studentProv.addStudent(student);

    if (!result.success) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? ('Error')),
            backgroundColor: AppTheme.primaryRed,
          ),
        );
      }
      return;
    }

    // Link to class
    if (_selectedClassId.isNotEmpty) {
      await classProv.addStudentToClass(_selectedClassId, student.id);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${student.fullName} saved'),
          backgroundColor: AppTheme.primaryGreen,
        ),
      );
      Navigator.pop(context);
    }
  }

  (String, String) _splitFullName(String fullName) {
    final parts = fullName.split(RegExp(r'\s+'));
    if (parts.length == 1) return (parts.first, '');
    return (parts.first, parts.sublist(1).join(' '));
  }
}

class _GenderChip extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _GenderChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryGreen : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primaryGreen : Colors.grey.shade300,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              value == 'M'
                  ? Icons.male
                  : value == 'F'
                  ? Icons.female
                  : Icons.remove_circle_outline,
              size: 18,
              color: selected ? Colors.white : AppTheme.lightText,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppTheme.darkText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
