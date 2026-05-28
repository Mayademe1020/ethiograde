import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/class_info.dart';
import '../../services/teacher_provider.dart';

/// Bottom sheet for creating a new class.
/// Fields: name, grade, section (required) + subject, school (optional).
/// Goal: under 60 seconds to create.
class CreateClassSheet extends StatefulWidget {
  final ClassInfo? existing; // null = create, non-null = edit

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
  late final TextEditingController _nameCtrl;
  late final TextEditingController _gradeCtrl;
  late final TextEditingController _sectionCtrl;
  late final TextEditingController _subjectCtrl;
  late final TextEditingController _schoolCtrl;
  late final TextEditingController _scheduleCtrl;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _gradeCtrl = TextEditingController(
      text: e != null && e.grade > 0 ? '${e.grade}' : '');
    _sectionCtrl = TextEditingController(text: e?.section ?? '');
    _subjectCtrl = TextEditingController(text: e?.subject ?? '');
    _schoolCtrl = TextEditingController(text: e?.school ?? '');
    _scheduleCtrl = TextEditingController(text: e?.examScheduleNote ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _gradeCtrl.dispose();
    _sectionCtrl.dispose();
    _subjectCtrl.dispose();
    _schoolCtrl.dispose();
    _scheduleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

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
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),

              Text(
                _isEdit
                    ? ('Edit Class')
                    : ('New Class'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),

              // Class name (required)
              TextFormField(
                controller: _nameCtrl,
                autofocus: !_isEdit,
                decoration: InputDecoration(
                  labelText: 'Class Name *',
                  hintText: 'e.g. Grade 5A',
                  prefixIcon: const Icon(Icons.class_outlined)),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Name is required';
                  }
                  return null;
                }),
              const SizedBox(height: 12),

              // Grade + Section row
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _gradeCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Grade *',
                        hintText: '1-12',
                        prefixIcon: const Icon(Icons.numbers)),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Required';
                        }
                        final n = int.tryParse(v.trim());
                        if (n == null || n < 1 || n > 14) {
                          return '1-14';
                        }
                        return null;
                      })),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _sectionCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Section *',
                        hintText: 'A, B, C',
                        prefixIcon: const Icon(Icons.group_outlined)),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Required';
                        }
                        return null;
                      })),
                ]),
              const SizedBox(height: 12),

              // Subject (optional)
              TextFormField(
                controller: _subjectCtrl,
                decoration: InputDecoration(
                  labelText: 'Subject',
                  hintText: 'e.g. Mathematics',
                  prefixIcon: const Icon(Icons.book_outlined))),
              const SizedBox(height: 12),

              // School (optional)
              TextFormField(
                controller: _schoolCtrl,
                decoration: InputDecoration(
                  labelText: 'School',
                  hintText: 'School name',
                  prefixIcon: const Icon(Icons.school_outlined))),
              const SizedBox(height: 12),

              // Exam schedule note (optional)
              TextFormField(
                controller: _scheduleCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Exam Schedule Note',
                  hintText: 'e.g. Final exam June 15',
                  prefixIcon: const Icon(Icons.event_note_outlined))),
              const SizedBox(height: 24),

              // Save button
              FilledButton.icon(
                onPressed: _save,
                icon: Icon(_isEdit ? Icons.check : Icons.add),
                label: Text(
                  _isEdit
                      ? ('Save')
                      : ('Create Class')),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14))),
            ]))));
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final teacherId = context.read<TeacherProvider>().activeTeacher?.id ?? '';
    final grade = int.parse(_gradeCtrl.text.trim());

    if (widget.existing != null) {
      final updated = widget.existing!.copyWith(
        name: _nameCtrl.text.trim(),
        grade: grade,
        section: _sectionCtrl.text.trim().toUpperCase(),
        subject: _subjectCtrl.text.trim(),
        school: _schoolCtrl.text.trim(),
        examScheduleNote: _scheduleCtrl.text.trim().isEmpty
            ? null
            : _scheduleCtrl.text.trim());
      Navigator.pop(context, updated);
    } else {
      final cls = ClassInfo(
        name: _nameCtrl.text.trim(),
        grade: grade,
        section: _sectionCtrl.text.trim().toUpperCase(),
        subject: _subjectCtrl.text.trim(),
        school: _schoolCtrl.text.trim(),
        ownerId: teacherId,
        examScheduleNote: _scheduleCtrl.text.trim().isEmpty
            ? null
            : _scheduleCtrl.text.trim());
      Navigator.pop(context, cls);
    }
  }
}
