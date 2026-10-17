import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/class_info.dart';
import '../../models/class_note.dart';
import '../../services/class_notes_provider.dart';
import '../../widgets/ui_components.dart';

/// Per-class diary: homework, reminders, observations. Dated notes stored
/// per class, newest first.
class ClassNotesScreen extends StatefulWidget {
  final ClassInfo classInfo;

  const ClassNotesScreen({super.key, required this.classInfo});

  @override
  State<ClassNotesScreen> createState() => _ClassNotesScreenState();
}

class _ClassNotesScreenState extends State<ClassNotesScreen> {
  @override
  Widget build(BuildContext context) {
    final notesProv = context.watch<ClassNotesProvider>();
    final notes = notesProv.notesForClass(widget.classInfo.id);

    return Scaffold(
      appBar: AppBar(title: const Text('Class Notes')),
      body: SafeArea(
        child: notesProv.loadFailed
            ? AppErrorState(
                title: "Couldn't load notes",
                message: 'Your notes could not be read from storage.',
                onRetry: notesProv.reload,
              )
            : notes.isEmpty
                ? AppEmptyState(
                    icon: Icons.note_add_outlined,
                    title: 'No notes yet',
                    message:
                        'Add homework, reminders, or observations for ${widget.classInfo.displayName}.',
                    buttonLabel: 'Add Note',
                    onPressed: () => _editNote(context, null),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: notes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final note = notes[index];
                      return _NoteCard(
                        note: note,
                        onEdit: () => _editNote(context, note),
                        onDelete: () => _confirmDelete(context, note),
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editNote(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Add Note'),
      ),
    );
  }

  void _editNote(BuildContext context, ClassNote? existing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _NoteEditor(
        classInfo: widget.classInfo,
        existing: existing,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, ClassNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete Note'),
        content: Text('Delete "${note.title.isNotEmpty ? note.title : 'this note'}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.primaryRed,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final result =
          await context.read<ClassNotesProvider>().deleteNote(note.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.success ? 'Note deleted' : (result.error ?? 'Delete failed'),
            ),
            backgroundColor: result.success ? null : context.primaryRed,
          ),
        );
      }
    }
  }
}

class _NoteCard extends StatelessWidget {
  final ClassNote note;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _NoteCard({
    required this.note,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  note.title.isNotEmpty ? note.title : 'Untitled',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 18, color: cs.onSurfaceVariant),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline,
                            color: context.primaryRed, size: 18),
                        const SizedBox(width: 8),
                        Text('Delete',
                            style: TextStyle(color: context.primaryRed)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _formatDate(note.date),
            style: TextStyle(fontSize: 12, color: context.lightText),
          ),
          if (note.body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              note.body,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _NoteEditor extends StatefulWidget {
  final ClassInfo classInfo;
  final ClassNote? existing;

  const _NoteEditor({required this.classInfo, this.existing});

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _date = widget.existing?.date ?? DateTime.now();
    _titleController.text = widget.existing?.title ?? '';
    _bodyController.text = widget.existing?.body ?? '';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final note = ClassNote(
      id: widget.existing?.id ?? '',
      classId: widget.classInfo.id,
      date: _date,
      title: _titleController.text.trim(),
      body: _bodyController.text.trim(),
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final result = await context.read<ClassNotesProvider>().saveNote(note);
    if (!mounted) return;
    if (result.success) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Could not save note'),
          backgroundColor: context.primaryRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.existing != null ? 'Edit Note' : 'New Note',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _date = picked);
            },
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 16),
                const SizedBox(width: 8),
                Text(
                  _formatDate(_date),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'e.g. Homework, Exam reminder',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Details',
              hintText: 'Write the note...',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Save Note'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
