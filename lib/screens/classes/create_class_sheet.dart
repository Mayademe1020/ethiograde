import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/class_info.dart';
import '../../services/class_provider.dart';
import '../../services/settings_provider.dart';
import '../../services/teacher_provider.dart';

/// Bottom sheet for creating a new class.
/// Simplified: Grade + Section + Subject pickers, auto-generated name.
class CreateClassSheet extends StatefulWidget {
  final ClassInfo? existing;

  const CreateClassSheet({super.key, this.existing});

  static Future<ClassInfo?> show(BuildContext context, {ClassInfo? existing}) {
    return showModalBottomSheet<ClassInfo>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => CreateClassSheet(existing: existing));
  }

  @override
  State<CreateClassSheet> createState() => _CreateClassSheetState();
}

class _CreateClassSheetState extends State<CreateClassSheet> {
  final _formKey = GlobalKey<FormState>();
  int? _selectedGrade;
  String? _selectedSection;
  String? _selectedSubject;
  String? _selectedYear;
  bool _isSaving = false;
  String? _duplicateWarning;
  Timer? _debounceTimer;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _selectedGrade = e.grade > 0 ? e.grade : null;
      _selectedSection = e.section.isNotEmpty ? e.section : null;
      _selectedSubject = e.subject.isNotEmpty ? e.subject : null;
      _selectedYear = e.academicYear.isNotEmpty ? e.academicYear : null;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final settings = context.watch<SettingsProvider>();
    final sections = ['A', 'B', 'C', 'D', 'E', 'F'];

    // Smart defaults
    if (_selectedYear == null && settings.currentAcademicYear.isNotEmpty) {
      _selectedYear = settings.currentAcademicYear;
    }
    if (_selectedSubject == null && settings.subjects.length == 1) {
      _selectedSubject = settings.subjects.first;
    }

    final previewName = _buildPreviewName();

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),

              Text(
                _isEdit ? 'Edit Class' : 'New Class',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),

              // Grade picker
              DropdownButtonFormField<int>(
                value: _selectedGrade,
                decoration: const InputDecoration(
                  labelText: 'Grade *',
                  prefixIcon: Icon(Icons.numbers)),
                items: List.generate(12, (i) => i + 1)
                    .map((g) => DropdownMenuItem(value: g, child: Text('Grade $g')))
                    .toList(),
                onChanged: (v) {
                  setState(() => _selectedGrade = v);
                  _checkDuplicate();
                },
                validator: (v) => v == null ? 'Required' : null),
              const SizedBox(height: 12),

              // Section picker
              DropdownButtonFormField<String>(
                value: _selectedSection,
                decoration: const InputDecoration(
                  labelText: 'Section *',
                  prefixIcon: Icon(Icons.group_outlined)),
                items: sections
                    .map((s) => DropdownMenuItem(value: s, child: Text('Section $s')))
                    .toList(),
                onChanged: (v) {
                  setState(() => _selectedSection = v);
                  _checkDuplicate();
                },
                validator: (v) => v == null ? 'Required' : null),
              const SizedBox(height: 12),

              // Subject picker
              DropdownButtonFormField<String>(
                value: _selectedSubject,
                decoration: const InputDecoration(
                  labelText: 'Subject *',
                  prefixIcon: Icon(Icons.book_outlined)),
                items: settings.subjects
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) {
                  setState(() => _selectedSubject = v);
                  _checkDuplicate();
                },
                validator: (v) => v == null ? 'Required' : null),
              const SizedBox(height: 12),

              // Academic Year picker
              DropdownButtonFormField<String>(
                value: _selectedYear,
                decoration: const InputDecoration(
                  labelText: 'Academic Year *',
                  prefixIcon: Icon(Icons.calendar_today_outlined)),
                items: settings.academicYears
                    .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                    .toList(),
                onChanged: (v) {
                  setState(() => _selectedYear = v);
                  _checkDuplicate();
                },
                validator: (v) => v == null ? 'Required' : null),
              const SizedBox(height: 16),

              // Preview name
              if (previewName.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.2))),
                  child: Row(
                    children: [
                      Icon(Icons.label_outlined, size: 18, color: AppTheme.primaryGreen),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(previewName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryGreen))),
                    ])),
              const SizedBox(height: 8),

              // Duplicate warning
              if (_duplicateWarning != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade300)),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_outlined, size: 18, color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_duplicateWarning!,
                          style: TextStyle(color: Colors.orange.shade800, fontSize: 13))),
                    ])),
              const SizedBox(height: 20),

              // Save button
              FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(_isEdit ? Icons.check : Icons.add),
                label: Text(_isSaving
                    ? 'Saving...'
                    : (_isEdit ? 'Save' : 'Create Class')),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14))),
            ]))));
  }

  String _buildPreviewName() {
    if (_selectedGrade == null || _selectedSection == null) return '';
    final subject = _selectedSubject ?? '';
    if (subject.isEmpty) return 'Grade $_selectedGrade$_selectedSection';
    return 'Grade $_selectedGrade$_selectedSection — $subject';
  }

  void _checkDuplicate() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      if (_selectedGrade == null || _selectedSection == null || _selectedSubject == null || _selectedYear == null) {
        setState(() => _duplicateWarning = null);
        return;
      }
      final classProv = context.read<ClassProvider>();
      final teacherId = context.read<TeacherProvider>().activeTeacher?.id ?? '';
      final isDup = classProv.hasDuplicate(
        grade: _selectedGrade!,
        section: _selectedSection!,
        subject: _selectedSubject!,
        ownerId: teacherId,
        academicYear: _selectedYear!,
        excludeId: widget.existing?.id,
      );
      setState(() {
        _duplicateWarning = isDup
            ? 'Grade $_selectedGrade$_selectedSection — $_selectedSubject already exists for $_selectedYear'
            : null;
      });
    });
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSaving) return;

    setState(() => _isSaving = true);

    final teacherId = context.read<TeacherProvider>().activeTeacher?.id ?? '';
    final name = _buildPreviewName();

    if (_isEdit) {
      final updated = widget.existing!.copyWith(
        name: name,
        grade: _selectedGrade!,
        section: _selectedSection!,
        subject: _selectedSubject!,
        academicYear: _selectedYear!,
      );
      if (mounted) Navigator.pop(context, updated);
    } else {
      final cls = ClassInfo(
        name: name,
        grade: _selectedGrade!,
        section: _selectedSection!,
        subject: _selectedSubject!,
        academicYear: _selectedYear!,
        ownerId: teacherId,
      );
      if (mounted) Navigator.pop(context, cls);
    }
  }
}
