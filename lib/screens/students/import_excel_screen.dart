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
  final Set<String> _skippedImportIds = {};
  final Set<String> _approvedIssueIds = {};
  bool _isImporting = false;
  String _statusMessage = '';

  @override
  Widget build(BuildContext context) {
    final review = _ImportRosterReview.build(
      imported: _importedStudents,
      existing: context.watch<StudentProvider>().students,
      skippedIds: _skippedImportIds,
      approvedIds: _approvedIssueIds,
    );

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
                        'Instructions',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.info,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '1. Prepare a CSV file (.csv)\n'
                    '2. First row should be headers (Name, Last Name, ID...)\n'
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
                  _isImporting ? ('Importing...') : ('Select CSV File'),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Manual entry button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showManualEntry(),
                icon: const Icon(Icons.person_add),
                label: Text('Add Manually'),
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
              _ImportReviewPanel(
                review: review,
                onSaveReady: review.saveableEntries.isEmpty
                    ? null
                    : () => _saveImportedStudents(review),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${review.visibleEntries.length} ${'Students'}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: review.saveableEntries.isEmpty
                        ? null
                        : () => _saveImportedStudents(review),
                    icon: const Icon(Icons.check),
                    label: Text(
                      review.hasOpenIssues ? 'Save ready' : 'Save All',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: review.visibleEntries.length,
                itemBuilder: (context, index) {
                  final entry = review.visibleEntries[index];
                  final s = entry.student;
                  final rowColor = entry.hasIssues && !entry.approved
                      ? AppTheme.warning
                      : AppTheme.primaryGreen;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: rowColor.withOpacity(0.1),
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: rowColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    title: Text(
                      entry.hasIssues && !entry.approved
                          ? '${s.fullName} - ${entry.issueLabels.join(', ')}'
                          : entry.approved
                          ? '${s.fullName} - approved'
                          : s.fullName,
                    ),
                    subtitle: Text(
                      [
                        if (s.className.isNotEmpty) s.className,
                        if (s.studentId.isNotEmpty) 'ID: ${s.studentId}',
                      ].join(' • '),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            _showEditImportedStudent(entry.student);
                          case 'keep':
                            setState(
                              () => _approvedIssueIds.add(entry.student.id),
                            );
                          case 'skip':
                            setState(() {
                              _skippedImportIds.add(entry.student.id);
                              _approvedIssueIds.remove(entry.student.id);
                            });
                          case 'remove':
                            setState(() {
                              _importedStudents.removeWhere(
                                (student) => student.id == entry.student.id,
                              );
                              _skippedImportIds.remove(entry.student.id);
                              _approvedIssueIds.remove(entry.student.id);
                            });
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        if (entry.hasIssues)
                          const PopupMenuItem(
                            value: 'keep',
                            child: Text('Keep anyway'),
                          ),
                        const PopupMenuItem(
                          value: 'skip',
                          child: Text('Skip for now'),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove'),
                        ),
                      ],
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
      final result = await _import.importStudents(classId: widget.classId);

      if (result.success) {
        setState(() {
          _importedStudents = result.students;
          _skippedImportIds.clear();
          _approvedIssueIds.clear();
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
          top: 24,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'New Student',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),

                // Student ID
                TextFormField(
                  controller: idCtrl,
                  decoration: InputDecoration(
                    labelText: 'Student ID (Roll No.) *',
                    hintText: 'e.g. 001',
                    prefixIcon: const Icon(Icons.badge_outlined),
                  ),
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
                const SizedBox(height: 12),

                // Name (English)
                Text(
                  'Name (English) *',
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
                      child: TextFormField(
                        controller: firstNameCtrl,
                        decoration: InputDecoration(
                          labelText: 'First Name',
                          hintText: 'Abebe',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? ('Required')
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: lastNameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Last Name',
                          hintText: 'Kebede',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? ('Required')
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Gender
                Text(
                  'Gender *',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.lightText,
                  ),
                ),
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
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.male,
                                  size: 18,
                                  color: gender == 'M'
                                      ? Colors.white
                                      : AppTheme.lightText,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Male',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: gender == 'M'
                                        ? Colors.white
                                        : AppTheme.darkText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
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
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.female,
                                  size: 18,
                                  color: gender == 'F'
                                      ? Colors.white
                                      : AppTheme.lightText,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Female',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: gender == 'F'
                                        ? Colors.white
                                        : AppTheme.darkText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
                            prefixIcon: const Icon(Icons.class_outlined),
                          ),
                          items: classes
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.displayName),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setClassState(() => selectedClassId = v ?? ''),
                        ),
                      ),
                    );
                  },
                ),

                // Add button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (!formKey.currentState!.validate()) return;
                      if (gender.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Gender is required'),
                            backgroundColor: AppTheme.primaryRed,
                          ),
                        );
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
                        classIds: classIds,
                      );
                      setState(() => _importedStudents.add(student));
                      Navigator.pop(c);
                    },
                    icon: const Icon(Icons.person_add),
                    label: Text('Add Student'),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(disposeAll);
  }

  void _showEditImportedStudent(Student student) {
    final firstNameCtrl = TextEditingController(text: student.firstName);
    final lastNameCtrl = TextEditingController(text: student.lastName);
    final idCtrl = TextEditingController(text: student.studentId);
    final formKey = GlobalKey<FormState>();
    var gender = student.gender;
    bool disposed = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fix student row',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: idCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Student ID',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: firstNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'First Name',
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: lastNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Last Name',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                StatefulBuilder(
                  builder: (context, setGenderState) => SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: '', label: Text('Skip')),
                      ButtonSegment(value: 'M', label: Text('M')),
                      ButtonSegment(value: 'F', label: Text('F')),
                    ],
                    selected: {gender},
                    onSelectionChanged: (selection) {
                      setGenderState(() => gender = selection.first);
                    },
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      if (!formKey.currentState!.validate()) return;
                      final updated = student.copyWith(
                        studentId: idCtrl.text.trim(),
                        firstName: firstNameCtrl.text.trim(),
                        lastName: lastNameCtrl.text.trim(),
                        gender: gender,
                      );
                      setState(() {
                        final index = _importedStudents.indexWhere(
                          (item) => item.id == student.id,
                        );
                        if (index >= 0) _importedStudents[index] = updated;
                        _approvedIssueIds.remove(student.id);
                      });
                      Navigator.pop(sheetContext);
                    },
                    icon: const Icon(Icons.check),
                    label: const Text('Apply fix'),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      if (disposed) return;
      disposed = true;
      firstNameCtrl.dispose();
      lastNameCtrl.dispose();
      idCtrl.dispose();
    });
  }

  Future<void> _saveImportedStudents(_ImportRosterReview review) async {
    final provider = context.read<StudentProvider>();
    final classProv = context.read<ClassProvider>();
    final studentsToSave = review.saveableEntries
        .map((entry) => entry.student)
        .toList(growable: false);
    if (studentsToSave.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No ready students to save')),
      );
      return;
    }

    final result = await provider.addStudents(studentsToSave);

    // Link to class if provided
    if (widget.classId != null && widget.classId!.isNotEmpty) {
      final studentIds = studentsToSave.map((s) => s.id).toList();
      await classProv.addStudentsToClass(widget.classId!, studentIds);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? '${studentsToSave.length} students saved'
                : result.error ?? 'Could not save students',
          ),
          backgroundColor: result.success
              ? AppTheme.primaryGreen
              : AppTheme.primaryRed,
        ),
      );
      if (result.success) Navigator.pop(context);
    }
  }
}

class _ImportRosterReview {
  const _ImportRosterReview({
    required this.entries,
    required this.skippedCount,
  });

  final List<_ImportRosterEntry> entries;
  final int skippedCount;

  List<_ImportRosterEntry> get visibleEntries =>
      entries.where((entry) => !entry.isSkipped).toList(growable: false);

  List<_ImportRosterEntry> get saveableEntries => entries
      .where(
        (entry) => !entry.isSkipped && (!entry.hasIssues || entry.approved),
      )
      .toList(growable: false);

  int get readyCount =>
      entries.where((entry) => !entry.isSkipped && !entry.hasIssues).length;

  int get issueCount => entries
      .where((entry) => !entry.isSkipped && entry.hasIssues && !entry.approved)
      .length;

  bool get hasOpenIssues => issueCount > 0;

  factory _ImportRosterReview.build({
    required List<Student> imported,
    required List<Student> existing,
    required Set<String> skippedIds,
    required Set<String> approvedIds,
  }) {
    final importedIdCounts = <String, int>{};
    final importedNameCounts = <String, int>{};
    for (final student in imported) {
      final id = _normalize(student.studentId);
      if (id.isNotEmpty) importedIdCounts[id] = (importedIdCounts[id] ?? 0) + 1;
      final name = _normalize(student.fullName);
      if (name.isNotEmpty) {
        importedNameCounts[name] = (importedNameCounts[name] ?? 0) + 1;
      }
    }

    final existingIds = existing
        .map((student) => _normalize(student.studentId))
        .where((id) => id.isNotEmpty)
        .toSet();
    final existingNames = existing
        .map((student) => _normalize(student.fullName))
        .where((name) => name.isNotEmpty)
        .toSet();

    return _ImportRosterReview(
      skippedCount: skippedIds.length,
      entries: imported
          .map((student) {
            final labels = <String>[];
            final id = _normalize(student.studentId);
            final name = _normalize(student.fullName);
            if (id.isEmpty) labels.add('Needs ID');
            if ((importedIdCounts[id] ?? 0) > 1)
              labels.add('Duplicate ID in file');
            if (existingIds.contains(id)) labels.add('ID already exists');
            if ((importedNameCounts[name] ?? 0) > 1) {
              labels.add('Duplicate name in file');
            }
            if (existingNames.contains(name)) labels.add('Name already exists');

            return _ImportRosterEntry(
              student: student,
              issueLabels: labels,
              isSkipped: skippedIds.contains(student.id),
              approved: approvedIds.contains(student.id),
            );
          })
          .toList(growable: false),
    );
  }

  static String _normalize(String value) => value.trim().toLowerCase();
}

class _ImportRosterEntry {
  const _ImportRosterEntry({
    required this.student,
    required this.issueLabels,
    required this.isSkipped,
    required this.approved,
  });

  final Student student;
  final List<String> issueLabels;
  final bool isSkipped;
  final bool approved;

  bool get hasIssues => issueLabels.isNotEmpty;
}

class _ImportReviewPanel extends StatelessWidget {
  const _ImportReviewPanel({required this.review, required this.onSaveReady});

  final _ImportRosterReview review;
  final VoidCallback? onSaveReady;

  @override
  Widget build(BuildContext context) {
    final color = review.hasOpenIssues
        ? AppTheme.warning
        : AppTheme.primaryGreen;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rule_folder_outlined, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  review.hasOpenIssues
                      ? 'Clean up roster before saving'
                      : 'Roster import looks ready',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _ImportChip(
                label: '${review.readyCount} ready',
                icon: Icons.check_circle_outline,
                color: AppTheme.primaryGreen,
              ),
              _ImportChip(
                label: '${review.issueCount} need fix',
                icon: Icons.warning_amber_outlined,
                color: review.issueCount > 0
                    ? AppTheme.warning
                    : AppTheme.primaryGreen,
              ),
              if (review.skippedCount > 0)
                _ImportChip(
                  label: '${review.skippedCount} skipped',
                  icon: Icons.block,
                  color: AppTheme.lightText,
                ),
            ],
          ),
          if (review.hasOpenIssues) ...[
            const SizedBox(height: 8),
            Text(
              'Edit rows with missing IDs or duplicates, or save only ready rows.',
              style: TextStyle(color: AppTheme.lightText, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onSaveReady,
              icon: const Icon(Icons.save_outlined),
              label: Text(
                review.hasOpenIssues ? 'Save ready rows' : 'Save all',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportChip extends StatelessWidget {
  const _ImportChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.24)),
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
