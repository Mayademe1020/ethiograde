import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/student.dart';
import '../../models/class_info.dart';
import '../../services/student_transfer_service.dart';
import '../../services/student_provider.dart';
import '../../services/class_provider.dart';

/// Dialog for transferring a student between classes.
///
/// Shows:
/// - Confirmation: "Transfer [Student] from [Class A] to [Class B]?"
/// - Class picker for destination
/// - Optional reason field
/// - Undo snackbar after transfer (10 second window)
///
/// Accessible via long-press on student in class roster.
class StudentTransferDialog extends StatefulWidget {
  final Student student;
  final ClassInfo fromClass;

  const StudentTransferDialog({
    super.key,
    required this.student,
    required this.fromClass,
  });

  /// Show the transfer dialog. Returns true if transfer was completed.
  static Future<bool?> show(
    BuildContext context, {
    required Student student,
    required ClassInfo fromClass,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => StudentTransferDialog(
        student: student,
        fromClass: fromClass));
  }

  @override
  State<StudentTransferDialog> createState() => _StudentTransferDialogState();
}

class _StudentTransferDialogState extends State<StudentTransferDialog> {
  ClassInfo? _selectedClass;
  final _reasonController = TextEditingController();
  bool _isTransferring = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _transfer() async {
    if (_selectedClass == null) return;

    setState(() => _isTransferring = true);

    final result = await StudentTransferService().transferStudent(
      student: widget.student,
      fromClassId: widget.fromClass.id,
      toClassId: _selectedClass!.id,
      reason: _reasonController.text.trim());

    if (!mounted) return;

    if (result.success && result.updatedStudent != null) {
      // Update the student in StudentProvider
      await context.read<StudentProvider>().updateStudent(result.updatedStudent!);

      // Update class rosters — student must be removed from old class and
      // added to new class in ClassProvider, otherwise the roster is stale
      final classProv = context.read<ClassProvider>();
      await classProv.removeStudentFromClass(widget.fromClass.id, widget.student.id);
      await classProv.addStudentToClass(_selectedClass!.id, widget.student.id);

      if (mounted) {
        Navigator.pop(context, true);

        // Show undo snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${widget.student.fullName} transferred to ${_selectedClass!.displayName}'),
            backgroundColor: AppTheme.primaryGreen,
            action: SnackBarAction(
              label: 'UNDO',
              textColor: Colors.white,
              onPressed: () => _undoTransfer(result.updatedStudent!)),
            duration: const Duration(seconds: 10)));
      }
    } else {
      setState(() => _isTransferring = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: AppTheme.error));
      }
    }
  }

  Future<void> _undoTransfer(Student currentStudent) async {
    // Transfer back using the CURRENT student state (not stale widget.student)
    final result = await StudentTransferService().transferStudent(
      student: currentStudent,
      fromClassId: _selectedClass!.id,
      toClassId: widget.fromClass.id,
      reason: 'Undo transfer');

    if (result.success && result.updatedStudent != null && mounted) {
      await context.read<StudentProvider>().updateStudent(result.updatedStudent!);

      // Update class rosters back
      final classProv = context.read<ClassProvider>();
      await classProv.removeStudentFromClass(_selectedClass!.id, widget.student.id);
      await classProv.addStudentToClass(widget.fromClass.id, widget.student.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${widget.student.fullName} restored to ${widget.fromClass.displayName}'),
            backgroundColor: AppTheme.info));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allClasses = context.watch<ClassProvider>().classes;

    // Filter out the current class
    final availableClasses = allClasses
        .where((c) => c.id != widget.fromClass.id)
        .toList();

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.swap_horiz, color: AppTheme.info),
          SizedBox(width: 8),
          Text('Transfer Student'),
        ]),
      content: availableClasses.isEmpty
          ? const Text(
              'No other classes — create one first',
              style: TextStyle(color: AppTheme.lightText))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Student info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppTheme.primaryGreen.withValues(alpha: 0.1),
                          child: Text(
                            widget.student.firstName.isNotEmpty
                                ? widget.student.firstName[0]
                                : '?',
                            style: const TextStyle(color: AppTheme.primaryGreen))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.student.fullName,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                '${"From"}: ${widget.fromClass.displayName}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.lightText)),
                            ])),
                      ])),
                  const SizedBox(height: 16),
                  // Destination class picker
                  const Text(
                    'To (select class)',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: availableClasses.map((cls) {
                      final selected = _selectedClass?.id == cls.id;
                      return ChoiceChip(
                        label: Text(cls.displayName),
                        selected: selected,
                        onSelected: (_) => setState(() => _selectedClass = cls),
                        selectedColor: AppTheme.primaryGreen.withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          color: selected ? AppTheme.primaryGreen : AppTheme.darkText,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal));
                    }).toList()),
                  const SizedBox(height: 16),
                  // Reason field
                  TextField(
                    controller: _reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Reason (optional)',
                      hintText: 'e.g. Moved to different section',
                      isDense: true),
                    maxLines: 2),
                ])),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel')),
        if (availableClasses.isNotEmpty)
          ElevatedButton(
            onPressed: _selectedClass != null && !_isTransferring
                ? _transfer
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen),
            child: _isTransferring
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Transfer')),
      ]);
  }
}
