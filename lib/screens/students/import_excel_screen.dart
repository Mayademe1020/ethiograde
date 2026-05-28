import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../config/theme.dart';
import '../../models/student.dart';
import '../../services/student_provider.dart';
import '../../services/class_provider.dart';
import '../../services/excel_service.dart';

class ImportCsvScreen extends StatefulWidget {
  final String? classId;

  const ImportCsvScreen({super.key, this.classId});

  @override
  State<ImportCsvScreen> createState() => _ImportCsvScreenState();
}

class _ImportCsvScreenState extends State<ImportCsvScreen> {
  final ImportService _import = ImportService();
  List<Student> _importedStudents = [];
  bool _isImporting = false;
  String _statusMessage = '';

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(title: Text('Import Students')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Import instructions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.info.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.info.withOpacity(0.2))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppTheme.info),
                      const SizedBox(width: 8),
                      Text(
                        'Instructions',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.info)),
                    ]),
                  const SizedBox(height: 8),
                  Text(
                    '1. Prepare a CSV file (.csv)\n'
                    '2. First row should be headers (Name, Last Name, ID...)\n'
                    '3. Select the file below',
                    style: const TextStyle(fontSize: 13, height: 1.5)),
                ])),
            const SizedBox(height: 24),

            // Import button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isImporting ? null : _pickAndImport,
                icon: _isImporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white))
                    : const Icon(Icons.upload_file),
                label: Text(
                  _isImporting
                      ? ('Importing...')
                      : ('Select CSV File')))),
            const SizedBox(height: 12),

            // Manual entry button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showManualEntry(),
                icon: const Icon(Icons.person_add),
                label: Text('Add Manually'))),

            const SizedBox(height: 24),

            // Status message
            if (_statusMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: _importedStudents.isNotEmpty
                      ? AppTheme.primaryGreen.withOpacity(0.1)
                      : AppTheme.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
                child: Text(
                  _statusMessage,
                  style: TextStyle(
                    color: _importedStudents.isNotEmpty
                        ? AppTheme.primaryGreen
                        : AppTheme.warning))),

            // Imported students list
            if (_importedStudents.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_importedStudents.length} ${'Students'}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: _saveImportedStudents,
                    icon: const Icon(Icons.check),
                    label: Text('Save All')),
                ]),
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _importedStudents.length,
                itemBuilder: (context, index) {
                  final s = _importedStudents[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primaryGreen.withOpacity(0.1),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: AppTheme.primaryGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 12))),
                    title: Text(s.fullName),
                    subtitle: Text(
                      [
                        if (s.className.isNotEmpty) s.className,
                        if (s.studentId.isNotEmpty) 'ID: ${s.studentId}',
                      ].join(' • ')),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        setState(() => _importedStudents.removeAt(index));
                      }));
                }),
            ],
          ])));
  }

  Future<void> _pickAndImport() async {
    setState(() {
      _isImporting = true;
      _statusMessage = '';
    });

    try {
      final result = await _import.importStudents(classId: widget.classId);

      if (result.success) {
        setState(() {
          _importedStudents = result.students;
          _statusMessage = result.message;
        });
      } else {
        setState(() {
          _statusMessage = result.message;
        });
        if (result.errors.isNotEmpty) {
          debugPrint('Import errors: ${result.errors.join('\n')}');
        }
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
      });
    } finally {
      setState(() => _isImporting = false);
    }
  }

  void _showManualEntry() {
    final firstNameCtrl = TextEditingController();
    final lastNameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String gender = '';
    String selectedClassId = '';

    // Track if controllers were already disposed via Add button.
    bool disposed = false;
    void disposeAll() {
      if (disposed) return;
      disposed = true;
      firstNameCtrl.dispose();
      lastNameCtrl.dispose();
      idCtrl.dispose();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(c).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24),
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'New Student',
                  style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),

                // Student ID
                TextFormField(
                  controller: idCtrl,
                  decoration: InputDecoration(
                    labelText: 'Student ID (Roll No.) *',
                    hintText: 'e.g. 001',
                    prefixIcon: const Icon(Icons.badge_outlined)),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Student ID is required';
                    }
                    if (v.trim().length > 20) {
                      return 'Max 20 characters';
                    }
                    return null;
                  }),
                const SizedBox(height: 12),

                // Name (English)
                Text(
                  'Name (English) *',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.lightText)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: firstNameCtrl,
                        decoration: InputDecoration(
                          labelText: 'First Name',
                          hintText: 'Abebe'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? ('Required')
                            : null)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: lastNameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Last Name',
                          hintText: 'Kebede'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? ('Required')
                            : null)),
                  ]),
                const SizedBox(height: 16),

                // Gender
                Text(
                  'Gender *',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.lightText)),
                const SizedBox(height: 8),
                StatefulBuilder(
                  builder: (context, setGenderState) => Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setGenderState(() => gender = 'M'),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: gender == 'M'
                                  ? AppTheme.primaryGreen
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: gender == 'M'
                                    ? AppTheme.primaryGreen
                                    : Colors.grey.shade300,
                                width: 1.5)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.male,
                                  size: 18,
                                  color: gender == 'M'
                                      ? Colors.white
                                      : AppTheme.lightText),
                                const SizedBox(width: 8),
                                Text(
                                  'Male',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: gender == 'M'
                                        ? Colors.white
                                        : AppTheme.darkText)),
                              ])))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setGenderState(() => gender = 'F'),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: gender == 'F'
                                  ? AppTheme.primaryGreen
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: gender == 'F'
                                    ? AppTheme.primaryGreen
                                    : Colors.grey.shade300,
                                width: 1.5)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.female,
                                  size: 18,
                                  color: gender == 'F'
                                      ? Colors.white
                                      : AppTheme.lightText),
                                const SizedBox(width: 8),
                                Text(
                                  'Female',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: gender == 'F'
                                        ? Colors.white
                                        : AppTheme.darkText)),
                              ])))),
                    ])),
                const SizedBox(height: 16),

                // Class dropdown
                Builder(
                  builder: (context) {
                    final classes = context.watch<ClassProvider>().classes;
                    if (classes.isEmpty) return const SizedBox.shrink();
                    return StatefulBuilder(
                      builder: (context, setClassState) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: DropdownButtonFormField<String>(
                          value: selectedClassId.isEmpty
                              ? null
                              : selectedClassId,
                          decoration: InputDecoration(
                            labelText: 'Class',
                            prefixIcon: const Icon(Icons.class_outlined)),
                          items: classes
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.displayName)))
                              .toList(),
                          onChanged: (v) =>
                              setClassState(() => selectedClassId = v ?? ''))));
                  }),

                // Add button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (!formKey.currentState!.validate()) return;
                      if (gender.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Gender is required'),
                            backgroundColor: AppTheme.primaryRed));
                        return;
                      }

                      final classIds = <String>[];
                      if (selectedClassId.isNotEmpty)
                        classIds.add(selectedClassId);

                      final student = Student(
                        id: const Uuid().v4(),
                        firstName: firstNameCtrl.text.trim(),
                        lastName: lastNameCtrl.text.trim(),
                        className: '',
                        section: '',
                        studentId: idCtrl.text.trim(),
                        gender: gender,
                        classIds: classIds);
                      setState(() => _importedStudents.add(student));
                      disposeAll();
                      Navigator.pop(c);
                    },
                    icon: const Icon(Icons.person_add),
                    label: Text('Add Student'))),
                const SizedBox(height: 24),
              ]))))).whenComplete(disposeAll);
  }

  Future<void> _saveImportedStudents() async {
    final provider = context.read<StudentProvider>();
    final classProv = context.read<ClassProvider>();
    await provider.addStudents(_importedStudents);

    // Link to class if provided
    if (widget.classId != null && widget.classId!.isNotEmpty) {
      final studentIds = _importedStudents.map((s) => s.id).toList();
      await classProv.addStudentsToClass(widget.classId!, studentIds);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_importedStudents.length} ${'students saved'}'),
          backgroundColor: AppTheme.primaryGreen));
      Navigator.pop(context);
    }
  }
}
