import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/class_note.dart';
import 'hive_box_mixin.dart';
import 'result.dart';

/// Stores per-class diary notes (homework, reminders, observations).
///
/// Notes are stored as plain maps (see [HiveBoxMixin] convention),
/// keyed by their own UUID.
class ClassNotesProvider extends ChangeNotifier with HiveBoxMixin {
  static const _boxName = 'class_notes';

  final List<ClassNote> _notes = [];
  bool _loaded = false;
  bool _loadFailed = false;

  List<ClassNote> get notes => List.unmodifiable(_notes);
  bool get isLoaded => _loaded;
  bool get loadFailed => _loadFailed;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final box = await openBox(_boxName);
      _notes
        ..clear()
        ..addAll(
          box.values
              .map(
                (data) =>
                    ClassNote.fromMap(Map<String, dynamic>.from(data as Map)),
              )
              .toList(),
        )
        ..sort((a, b) => b.date.compareTo(a.date));
      _loaded = true;
      _loadFailed = false;
    } catch (e) {
      debugPrint('ClassNotesProvider: load failed ($e)');
      _notes.clear();
      _loaded = true;
      _loadFailed = true;
    }
    notifyListeners();
  }

  Future<void> reload() async {
    _loaded = false;
    _loadFailed = false;
    await load();
  }

  List<ClassNote> notesForClass(String classId) =>
      _notes.where((n) => n.classId == classId).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  Future<Result<ClassNote>> saveNote(ClassNote note) async {
    if (note.classId.isEmpty) {
      return const Result.failure('Class is required');
    }
    if (note.title.trim().isEmpty && note.body.trim().isEmpty) {
      return const Result.failure('Note is empty');
    }
    try {
      final box = await openBox(_boxName);
      final updated = note.id.isNotEmpty
          ? note.copyWith(updatedAt: DateTime.now())
          : ClassNote(
              id: const Uuid().v4(),
              classId: note.classId,
              date: note.date,
              title: note.title,
              body: note.body,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );
      await box.put(updated.id, updated.toMap());
      final index = _notes.indexWhere((n) => n.id == updated.id);
      if (index >= 0) {
        _notes[index] = updated;
      } else {
        _notes.add(updated);
      }
      _notes.sort((a, b) => b.date.compareTo(a.date));
      notifyListeners();
      return Result.success(updated);
    } catch (e) {
      debugPrint('ClassNotesProvider: saveNote failed ($e)');
      return const Result.failure('Failed to save note');
    }
  }

  Future<Result<void>> deleteNote(String id) async {
    try {
      final box = await openBox(_boxName);
      await box.delete(id);
      _notes.removeWhere((n) => n.id == id);
      notifyListeners();
      return const Result.success(null);
    } catch (e) {
      debugPrint('ClassNotesProvider: deleteNote failed ($e)');
      return const Result.failure('Failed to delete note');
    }
  }
}
