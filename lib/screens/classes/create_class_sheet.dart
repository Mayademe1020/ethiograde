import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/class_info.dart';
import '../../services/class_provider.dart';
import '../../services/settings_provider.dart';
import '../../services/teacher_provider.dart';

/// Bottom sheet for creating a new class.
/// Grade + Section dropdowns, Subject autocomplete, Academic Year dropdown.
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
  final _subjectCtrl = TextEditingController();
  final _subjectFocus = FocusNode();
  int? _selectedGrade;
  String? _selectedSection;
  String? _selectedYear;
  bool _isSaving = false;
  String? _duplicateWarning;
  Timer? _debounceTimer;
  List<String> _suggestions = [];
  bool _showSuggestions = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _selectedGrade = e.grade > 0 ? e.grade : null;
      _selectedSection = e.section.isNotEmpty ? e.section : null;
      _subjectCtrl.text = e.subject;
      _selectedYear = e.academicYear.isNotEmpty ? e.academicYear : null;
    }
    _subjectFocus.addListener(() {
      if (!_subjectFocus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) setState(() => _showSuggestions = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _subjectCtrl.dispose();
    _subjectFocus.dispose();
    super.dispose();
  }

  void _filterSuggestions(String query) {
    final settings = context.read<SettingsProvider>();
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = settings.subjects;
        _showSuggestions = true;
      });
      return;
    }
    final lower = query.trim().toLowerCase();
    final matches = settings.subjects
        .where((s) => s.toLowerCase().contains(lower))
        .toList();
    setState(() {
      _suggestions = matches;
      _showSuggestions = true;
    });
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

    // Academic year enforcement
    if (settings.currentAcademicYear.isEmpty && !_isEdit) {
      return Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 24),
            const Icon(Icons.calendar_today_outlined, size: 48, color: AppTheme.primaryGreen),
            const SizedBox(height: 16),
            Text('Set Academic Year First',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Please set your academic year before creating a class.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                // Navigate to settings — caller should handle this
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Go to Settings → Academic Year to set it')));
              },
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Go to Settings'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24))),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ]));
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
                initialValue: _selectedGrade,
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
                initialValue: _selectedSection,
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

              // Subject autocomplete
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _subjectCtrl,
                    focusNode: _subjectFocus,
                    decoration: InputDecoration(
                      labelText: 'Subject *',
                      hintText: 'Type to search or add new',
                      prefixIcon: const Icon(Icons.book_outlined),
                      suffixIcon: _subjectCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                _subjectCtrl.clear();
                                _filterSuggestions('');
                                _checkDuplicate();
                              })
                          : null),
                    onChanged: (v) {
                      _filterSuggestions(v);
                      _checkDuplicate();
                    },
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      return null;
                    }),
                  // Suggestions dropdown
                  if (_showSuggestions && _suggestions.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2))]),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _suggestions.length + (_isNewSubject ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (i < _suggestions.length) {
                            final s = _suggestions[i];
                            final isExactMatch = s.toLowerCase() == _subjectCtrl.text.trim().toLowerCase();
                            return ListTile(
                              dense: true,
                              leading: isExactMatch
                                  ? const Icon(Icons.check, size: 18, color: AppTheme.primaryGreen)
                                  : Icon(Icons.search, size: 18, color: Colors.grey.shade400),
                              title: Text(s, style: TextStyle(
                                fontWeight: isExactMatch ? FontWeight.w600 : FontWeight.normal)),
                              onTap: () {
                                _subjectCtrl.text = s;
                                setState(() => _showSuggestions = false);
                                _subjectFocus.unfocus();
                                _checkDuplicate();
                              });
                          } else {
                            // "Use new subject" option
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.add_circle_outline, size: 18, color: AppTheme.primaryGreen),
                              title: Text('Use "${_subjectCtrl.text.trim()}"',
                                style: const TextStyle(
                                  color: AppTheme.primaryGreen,
                                  fontWeight: FontWeight.w600)),
                              subtitle: const Text('New subject will be added to your list',
                                style: TextStyle(fontSize: 11)),
                              onTap: () {
                                setState(() => _showSuggestions = false);
                                _subjectFocus.unfocus();
                                _checkDuplicate();
                              });
                          }
                        })),
                ]),
              const SizedBox(height: 12),

              // Academic Year picker
              DropdownButtonFormField<String>(
                initialValue: _selectedYear,
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
                    color: AppTheme.primaryGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.2))),
                  child: Row(
                    children: [
                      const Icon(Icons.label_outlined, size: 18, color: AppTheme.primaryGreen),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(previewName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryGreen))),
                    ])),
              const SizedBox(height: 8),

              // New subject indicator
              if (_subjectCtrl.text.trim().isNotEmpty && _isNewSubject)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200)),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('New subject "${_subjectCtrl.text.trim()}" will be added to your list',
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade800))),
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

  bool get _isNewSubject {
    final settings = context.read<SettingsProvider>();
    final typed = _subjectCtrl.text.trim().toLowerCase();
    if (typed.isEmpty) return false;
    return !settings.subjects.any((s) => s.toLowerCase() == typed);
  }

  String _buildPreviewName() {
    if (_selectedGrade == null || _selectedSection == null) return '';
    final subject = _subjectCtrl.text.trim();
    if (subject.isEmpty) return 'Grade $_selectedGrade$_selectedSection';
    return 'Grade $_selectedGrade$_selectedSection — $subject';
  }

  void _checkDuplicate() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final subject = _subjectCtrl.text.trim();
      if (_selectedGrade == null || _selectedSection == null || subject.isEmpty || _selectedYear == null) {
        setState(() => _duplicateWarning = null);
        return;
      }
      final classProv = context.read<ClassProvider>();
      final teacherId = context.read<TeacherProvider>().activeTeacher?.id ?? '';
      final isDup = classProv.hasDuplicate(
        grade: _selectedGrade!,
        section: _selectedSection!,
        subject: subject,
        ownerId: teacherId,
        academicYear: _selectedYear!,
        excludeId: widget.existing?.id,
      );
      setState(() {
        _duplicateWarning = isDup
            ? 'Grade $_selectedGrade$_selectedSection — $subject already exists for $_selectedYear'
            : null;
      });
    });
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSaving) return;

    setState(() => _isSaving = true);

    final settings = context.read<SettingsProvider>();
    final teacherId = context.read<TeacherProvider>().activeTeacher?.id ?? '';
    final subject = _subjectCtrl.text.trim();

    // Auto-add new subject to the list
    if (_isNewSubject) {
      await settings.addSubject(subject);
    }

    final name = _buildPreviewName();

    if (_isEdit) {
      final updated = widget.existing!.copyWith(
        name: name,
        grade: _selectedGrade!,
        section: _selectedSection!,
        subject: subject,
        academicYear: _selectedYear!,
      );
      if (mounted) Navigator.pop(context, updated);
    } else {
      final cls = ClassInfo(
        name: name,
        grade: _selectedGrade!,
        section: _selectedSection!,
        subject: subject,
        academicYear: _selectedYear!,
        ownerId: teacherId,
      );
      if (mounted) Navigator.pop(context, cls);
    }
  }
}
