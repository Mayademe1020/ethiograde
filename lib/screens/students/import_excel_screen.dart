import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../config/theme.dart';
import '../../models/student.dart';
import '../../services/locale_provider.dart';
import '../../services/student_provider.dart';
import '../../services/excel_service.dart';

class ImportExcelScreen extends StatefulWidget {
  const ImportExcelScreen({super.key});

  @override
  State<ImportExcelScreen> createState() => _ImportExcelScreenState();
}

class _ImportExcelScreenState extends State<ImportExcelScreen> {
  final ExcelService _excel = ExcelService();
  List<Student> _importedStudents = [];
  bool _isImporting = false;
  String _statusMessage = '';

  @override
  Widget build(BuildContext context) {
    final isAm = context.watch<LocaleProvider>().isAmharic;

    return Scaffold(
      appBar: AppBar(
        title: Text(isAm ? 'ተማሪዎች አስገባ' : 'Import Students'),
      ),
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
                border: Border.all(color: AppTheme.info.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppTheme.info),
                      const SizedBox(width: 8),
                      Text(
                        isAm ? 'መመሪያ' : 'Instructions',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.info,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isAm
                        ? '1. Excel ፋይል (.xlsx) ያዘጋጁ\n'
                            '2. የመጀመሪያ ረድፍ ስሞች ይሁኑ (First Name, Last Name, Class...)\n'
                            '3. ፋይሉን ይምረጡ'
                        : '1. Prepare an Excel file (.xlsx)\n'
                            '2. First row should be headers (First Name, Last Name, Class...)\n'
                            '3. Select the file below',
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
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
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.upload_file),
                label: Text(
                  _isImporting
                      ? (isAm ? 'በማስገባት ላይ...' : 'Importing...')
                      : (isAm ? 'Excel ፋይል ይምረጡ' : 'Select Excel File'),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Manual entry button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showManualEntry(isAm),
                icon: const Icon(Icons.person_add),
                label: Text(isAm ? 'በእጅ ያክሉ' : 'Add Manually'),
              ),
            ),

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
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMessage,
                  style: TextStyle(
                    color: _importedStudents.isNotEmpty
                        ? AppTheme.primaryGreen
                        : AppTheme.warning,
                  ),
                ),
              ),

            // Imported students list
            if (_importedStudents.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_importedStudents.length} ${isAm ? 'ተማሪዎች' : 'Students'}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _saveImportedStudents,
                    icon: const Icon(Icons.check),
                    label: Text(isAm ? 'ሁሉን አስቀምጥ' : 'Save All'),
                  ),
                ],
              ),
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
                          fontSize: 12,
                        ),
                      ),
                    ),
                    title: Text(s.fullName),
                    subtitle: Text(
                      [
                        if (s.fullNameAmharic.trim().isNotEmpty) s.fullNameAmharic,
                        if (s.className.isNotEmpty) s.className,
                        if (s.studentId.isNotEmpty) 'ID: ${s.studentId}',
                      ].join(' • '),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        setState(() => _importedStudents.removeAt(index));
                      },
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndImport() async {
    setState(() {
      _isImporting = true;
      _statusMessage = '';
    });

    try {
      final result = await _excel.importStudents();

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

  void _showManualEntry(bool isAm) {
    final firstNameCtrl = TextEditingController();
    final lastNameCtrl = TextEditingController();
    final firstNameAmCtrl = TextEditingController();
    final lastNameAmCtrl = TextEditingController();
    final classCtrl = TextEditingController();
    final sectionCtrl = TextEditingController();
    final idCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(c).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isAm ? 'አዲስ ተማሪ' : 'New Student',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: firstNameCtrl,
                      decoration: InputDecoration(
                        labelText: isAm ? 'ስም' : 'First Name',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: lastNameCtrl,
                      decoration: InputDecoration(
                        labelText: isAm ? 'የአባት ስም' : 'Last Name',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: firstNameAmCtrl,
                      decoration: InputDecoration(
                        labelText: isAm ? 'ስም (አማርኛ)' : 'First Name (Am)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: lastNameAmCtrl,
                      decoration: InputDecoration(
                        labelText: isAm ? 'የአባት ስም (አማርኛ)' : 'Last Name (Am)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: classCtrl,
                      decoration: InputDecoration(
                        labelText: isAm ? 'ክፍል' : 'Class',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: sectionCtrl,
                      decoration: InputDecoration(
                        labelText: isAm ? 'ቡድን' : 'Section',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: idCtrl,
                decoration: InputDecoration(
                  labelText: isAm ? 'የተማሪ መለያ' : 'Student ID',
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (firstNameCtrl.text.isEmpty && lastNameCtrl.text.isEmpty) return;
                    final student = Student(
                      id: const Uuid().v4(),
                      firstName: firstNameCtrl.text,
                      lastName: lastNameCtrl.text,
                      firstNameAmharic: firstNameAmCtrl.text,
                      lastNameAmharic: lastNameAmCtrl.text,
                      className: classCtrl.text,
                      section: sectionCtrl.text,
                      studentId: idCtrl.text,
                    );
                    setState(() => _importedStudents.add(student));
                    Navigator.pop(c);
                  },
                  child: Text(isAm ? 'ጨምር' : 'Add'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveImportedStudents() async {
    final provider = context.read<StudentProvider>();
    await provider.addStudents(_importedStudents);

    if (mounted) {
      final isAm = context.read<LocaleProvider>().isAmharic;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_importedStudents.length} ${isAm ? 'ተማሪዎች ተቀምጠዋል' : 'students saved'}',
          ),
          backgroundColor: AppTheme.primaryGreen,
        ),
      );
      Navigator.pop(context);
    }
  }
}
